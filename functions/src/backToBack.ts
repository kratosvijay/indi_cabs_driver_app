import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onDocumentUpdated } from "firebase-functions/v2/firestore";

/**
 * Calculate distance between two points using Haversine formula
 */
function calculateDistance(lat1: number, lon1: number, lat2: number, lon2: number): number {
    const R = 6371; // Radius of the earth in km
    const dLat = deg2rad(lat2 - lat1);
    const dLon = deg2rad(lon2 - lon1);
    const a =
        Math.sin(dLat / 2) * Math.sin(dLat / 2) +
        Math.cos(deg2rad(lat1)) * Math.cos(deg2rad(lat2)) *
        Math.sin(dLon / 2) * Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c; // Distance in km
}

function deg2rad(deg: number): number {
    return deg * (Math.PI / 180);
}

/**
 * 1. Detect AvailableSoon Drivers
 * Triggered on driver status update
 */
export const checkAvailableSoonDrivers = onDocumentUpdated(
    { document: "drivers/{driverId}", region: "asia-south1" },
    async (event) => {
        const driverId = event.params.driverId;
        const driverRef = event.data?.after;
        if (!driverRef || !event.data?.before) return;

        const dData = driverRef.data();
        const beforeData = event.data.before.data();

        // Trigger ONLY when status changes TO "availableSoon"
        if (dData.status !== "availableSoon" || beforeData.status === "availableSoon") {
            return;
        }

        console.log(`[B2B] Driver \${driverId} is now availableSoon. Detecting nearby rides.`);

        const db = admin.firestore();

        // 1. Get driver dropoff location from current ride
        // To find the current ride, we can check ride_requests where status == 'started' for this driver
        const activeRidesSnap = await db.collection("ride_requests")
            .where("driverId", "==", driverId)
            .where("status", "in", ["started", "arrived", "accepted"])
            .get();

        if (activeRidesSnap.empty) {
            console.log(`[B2B] Driver \${driverId} has no active ride to base B2B off of.`);
            return;
        }

        const currentRideDoc = activeRidesSnap.docs[0];
        const currentRideId = currentRideDoc.id;
        const currentRideData = currentRideDoc.data();
        const dropoffLoc = currentRideData.dropoffLocation || currentRideData.destinationLocation;

        if (!dropoffLoc) {
            console.log(`[B2B] Active ride \${currentRideId} has no dropoff location.`);
            return;
        }

        const dLat = dropoffLoc.latitude || dropoffLoc.lat;
        const dLng = dropoffLoc.longitude || dropoffLoc.lng;

        if (!dLat || !dLng) return;

        // 2. Query new rides (status == 'searching')
        // In reality you would use GeoFire. For MVP, fetch searching rides and filter by distance.
        const searchingRidesSnap = await db.collection("ride_requests")
            .where("status", "==", "searching")
            .get();

        const maxSearchRadiusKm = 2.0;
        const candidates: any[] = [];

        for (const rideDoc of searchingRidesSnap.docs) {
            // Skip their own ride just in case it's mislabeled
            if (rideDoc.id === currentRideId) continue;

            const rData = rideDoc.data();
            const pickupLoc = rData.pickupLocation;
            if (!pickupLoc) continue;

            const pLat = pickupLoc.latitude || pickupLoc.lat;
            const pLng = pickupLoc.longitude || pickupLoc.lng;

            if (!pLat || !pLng) continue;

            const dist = calculateDistance(dLat, dLng, pLat, pLng);

            if (dist <= maxSearchRadiusKm) {
                candidates.push({
                    rideId: rideDoc.id,
                    distance: dist,
                    data: rData
                });
            }
        }

        if (candidates.length === 0) {
            console.log(`[B2B] No searching rides within \${maxSearchRadiusKm}km of dropoff.`);
            return;
        }

        // Sort by distance
        candidates.sort((a, b) => a.distance - b.distance);

        // 3. Create B2B Ride Request
        const bestRide = candidates[0];
        console.log(`[B2B] Offering ride \${bestRide.rideId} to driver \${driverId}`);

        // Check if driver can receive more requests (Max 5)
        const activeRequestsSnap = await db.collection(`ride_requests/\${driverId}/requests`).where('status', '==', 'pending').get();
        if (activeRequestsSnap.size >= 5) {
            console.log(`[B2B] Driver \${driverId} already has 5 active requests. Skipping B2B offer.`);
            return;
        }

        const requestRef = db.doc(`ride_requests/\${driverId}/requests/\${bestRide.rideId}`);
        const existingRequest = await requestRef.get();
        if (existingRequest.exists) return; // Deduplicate

        const expiresAt = admin.firestore.Timestamp.fromMillis(Date.now() + 5000);

        await requestRef.set({
            rideId: bestRide.rideId,
            riderId: bestRide.data.riderId || "",
            pickupLocation: bestRide.data.pickupLocation,
            destinationLocation: bestRide.data.destinationLocation || bestRide.data.dropLocation || bestRide.data.pickupLocation,
            fareEstimate: bestRide.data.fare || bestRide.data.fareEstimate || 0,
            vehicleType: bestRide.data.vehicleType || "Unknown",
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            expiresAt: expiresAt,
            status: "pending",
            isBackToBack: true,
            previousRideId: currentRideId
        });

        console.log(`[B2B] Successfully created B2B ride request card for \${driverId}`);
    }
);


/**
 * 2. Accept B2B Ride (Atomic)
 */
export const acceptBackToBackRide = onCall({ region: "asia-south1" }, async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Must be logged in');

    const db = admin.firestore();
    const driverId = request.auth.uid;
    const { rideId, previousRideId } = request.data;

    // Use ride_requests collection as that's what's currently used in this DB structure as central doc
    const rideRef = db.collection('ride_requests').doc(rideId);

    try {
        await db.runTransaction(async (tx) => {
            const rideDoc = await tx.get(rideRef);

            if (!rideDoc.exists) {
                throw new Error("Ride does not exist");
            }

            if (rideDoc.data()?.status !== "searching") {
                throw new Error("Already assigned or no longer searching");
            }

            tx.update(rideRef, {
                status: "accepted",
                driverId: driverId,
                isBackToBack: true,
                previousRideId: previousRideId || null,
                driverOnAnotherRide: true,
                estimatedDelayMinutes: 5,
                acceptedAt: admin.firestore.FieldValue.serverTimestamp()
            });

            const driverRef = db.collection('drivers').doc(driverId);
            tx.update(driverRef, { nextRideId: rideId });
        });

        // Delete other pending requests for this backend driver
        const myRequestsSnap = await db.collection(`ride_requests/\${driverId}/requests`).where('status', '==', 'pending').get();
        const batch = db.batch();
        myRequestsSnap.forEach(doc => {
            if (doc.id !== rideId) {
                batch.delete(doc.ref);
            }
        });
        await batch.commit();

        return { success: true, message: "Back-to-Back Ride accepted successfully" };

    } catch (error: any) {
        console.error("[B2B] Accept failed:", error);
        throw new HttpsError('aborted', error.message || "Ride already taken");
    }
});
