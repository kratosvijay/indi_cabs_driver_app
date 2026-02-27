import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";


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
    const d = R * c; // Distance in km
    return d;
}

function deg2rad(deg: number): number {
    return deg * (Math.PI / 180);
}


/**
 * Find Back-to-Back Drivers
 * 
 * Logic:
 * 1. Find drivers who are 'in_ride'.
 * 2. Check their current dropoff location (from their active ride).
 * 3. If they are close to the dropoff (e.g. < 3km or < 5 mins), AND
 * 4. Structurally ensure the new pickup is close to that dropoff.
 * 
 * Note: Real-time "time to dropoff" requires live traffic data (Google Routes API).
 * For this MVP, we will use straight-line distance to dropoff < 2km as a proxy for "about to finish".
 */
export const findBackToBackDrivers = onCall(async (request) => {
    const db = admin.firestore(); // Init DB here to ensure App is initialized

    const rideId = request.data.rideId;
    const pickupLat = request.data.pickupLat;
    const pickupLng = request.data.pickupLng;

    if (!rideId || !pickupLat || !pickupLng) {
        throw new HttpsError('invalid-argument', 'Missing rideId or pickup location');
    }

    console.log(`[BackToBack] Searching for drivers near ${pickupLat}, ${pickupLng} for ride ${rideId}`);

    // 1. Get all drivers who are currently in a ride
    // In a real app, you would use GeoFire or geospatial queries on 'driver_locations' 
    // filtered by status. Here we might have to scan or rely on a known list.
    // Optimization: query 'drivers' where status == 'on_trip' (if maintained).

    // For MVP efficiency: We'll query `ride_requests` where status == 'accepted' or 'arrived' or 'started'
    // Actually, 'started' is the phase where they are moving to dropoff.

    const activeRidesSnapshot = await db.collection("ride_requests")
        .where("status", "==", "started")
        .get();

    const potentialDrivers: any[] = [];

    for (const doc of activeRidesSnapshot.docs) {
        const rideData = doc.data();
        const driverId = rideData.driverId;
        const dropoffLoc = rideData.dropoffLocation; // Map or GeoPoint

        if (!dropoffLoc) continue;

        let dLat = 0;
        let dLng = 0;

        if (dropoffLoc.latitude) {
            dLat = dropoffLoc.latitude;
            dLng = dropoffLoc.longitude;
        } else if (dropoffLoc.lat) {
            dLat = dropoffLoc.lat;
            dLng = dropoffLoc.lng;
        }

        // 2. Check distance between Active Ride Dropoff AND New Ride Pickup
        // This ensures the driver finishes near where the new ride starts.
        const distanceToNewPickup = calculateDistance(dLat, dLng, pickupLat, pickupLng);

        // Threshold: 50km (DEBUGGING)
        if (distanceToNewPickup <= 50.0) {
            // 3. (Optional) Check if driver is ALREADY actually close to the dropoff?
            // This requires the driver's current live location. 
            // We can fetch driver's latest location from 'drivers/{driverId}'

            const driverDoc = await db.collection("drivers").doc(driverId).get();
            const driverLoc = driverDoc.data()?.currentLocation; // Assuming this is updated

            if (driverLoc) {
                const currentLat = driverLoc.latitude || driverLoc.lat;
                const currentLng = driverLoc.longitude || driverLoc.lng;

                // Distance from Driver to HIS Dropoff
                const distToDropoff = calculateDistance(currentLat, currentLng, dLat, dLng);

                // If he is within 50km of his dropoff, he is a candidate.
                if (distToDropoff <= 50.0) {
                    potentialDrivers.push({
                        driverId: driverId,
                        distance: distanceToNewPickup, // Priority metric
                        currentRideId: doc.id
                    });
                }
            }
        }
    }

    // Sort by proximity
    potentialDrivers.sort((a, b) => a.distance - b.distance);

    if (potentialDrivers.length > 0) {
        const bestDriver = potentialDrivers[0];
        console.log(`[BackToBack] Found driver ${bestDriver.driverId} ending ride ${bestDriver.currentRideId}`);

        // Update the ride request to assign this driver
        // This triggers the driver's listener (standard or back-to-back)
        await db.collection('ride_requests').doc(rideId).update({
            driverId: bestDriver.driverId,
            status: 'searching', // Ensure it is 'searching' so it appears in their list
            isBackToBack: true,   // Flag for analytics/UI
            backToBackPreviousRideId: bestDriver.currentRideId
        });

        return {
            found: true,
            driverId: bestDriver.driverId,
            currentRideId: bestDriver.currentRideId
        };
    }

    return { found: false };
});
