import * as admin from "firebase-admin";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import * as geohash from "./utils/geohash";

// Region configuration for better quota management
const REGION = "us-central1";

// 1. Trigger on New Ride Request
export const aggregateDemandDriver = onDocumentCreated(
    {
        document: "ride_requests/{rideId}",
        region: REGION,
    },
    async (event) => {
        const snapshot = event.data;
        if (!snapshot) return;

        const db = admin.firestore(); // Get Firestore inside handler

        const rideData = snapshot.data();
        const pickup = rideData.pickupLocation; // { lat: ..., lng: ... } or GeoPoint

        if (!pickup) return;

        let lat, lng;
        if (pickup.latitude && pickup.longitude) {
            // GeoPoint or similar object
            lat = pickup.latitude;
            lng = pickup.longitude;
        } else if (pickup.lat && pickup.lng) {
            // Map
            lat = pickup.lat;
            lng = pickup.lng;
        } else {
            return;
        }

        // Encode to precision 6 (~1.2km x 0.6km)
        const gHash = geohash.encode(lat, lng, 6);
        const zoneRef = db.collection("demand_zones").doc(gHash);

        // Get center for visualization if needed
        const center = geohash.decode(gHash);

        // Transactional update or simple increment
        await zoneRef.set({
            geohash: gHash,
            lat: center.lat,
            lng: center.lon,
            count: admin.firestore.FieldValue.increment(1),
            lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });

        console.log(`Demand Aggregated for ${gHash}: +1`);
    }
);

// 2. Cleanup Old Demand (Hourly Reset)
export const resetDemandZonesDriver = onSchedule(
    {
        schedule: "every 60 minutes",
        region: REGION,
    },
    async (event) => {
        const db = admin.firestore(); // Get Firestore inside handler
        const cutoff = new Date(Date.now() - 60 * 60 * 1000); // 1 hour ago

        // Find zones updated before cutoff
        const snapshot = await db.collection("demand_zones")
            .where("lastUpdated", "<", cutoff)
            .get();

        if (snapshot.empty) {
            console.log("No old demand zones to clean.");
            return;
        }

        const batch = db.batch();
        snapshot.docs.forEach((doc) => {
            // Option A: Delete entirely
            batch.delete(doc.ref);
        });

        await batch.commit();
        console.log(`Cleaned up ${snapshot.size} old demand zones.`);
    });
