import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import { calculateDistance, isValidPoint } from "./utils/geo";
import axios from "axios";
import { calculateTripFare } from "./fare_engine";


/**
 * Triggered when a new GPS point is added to a driver's trip in RTDB.
 * Path: driver_trips/{rideId}/points/{pointId}
 */
export const onGPSUpdate = functions.region("asia-south1")
    .runWith({ secrets: ["GOOGLE_MAPS_API_KEY"] })
    .database.ref("driver_trips/{rideId}/points/{pointId}")
    .onCreate(async (snapshot: functions.database.DataSnapshot, context: functions.EventContext) => {
        const rideId = context.params.rideId;
        const newPoint = snapshot.val();
        
        if (!newPoint || !newPoint.lat || !newPoint.lng) return;

        const db = admin.firestore();
        const rideRef = db.collection("ride_requests").doc(rideId);
        const rideSnap = await rideRef.get();

        if (!rideSnap.exists) return;
        const rideData = rideSnap.data()!;

        // Only process if trip is STARTED or RESUMED
        const activeStatuses = ["started", "resumed"];
        if (!activeStatuses.includes(rideData.status)) return;

        const lastPoint = rideData.lastProcessedPoint; // { lat, lng, timestamp }
        let accumulatedDistance = rideData.accumulatedDistanceMeters || 0;

        if (lastPoint) {
            const isValid = isValidPoint(
                { lat: lastPoint.lat, lng: lastPoint.lng, timestamp: lastPoint.timestamp },
                { lat: newPoint.lat, lng: newPoint.lng, timestamp: newPoint.timestamp, accuracy: newPoint.accuracy }
            );

            if (isValid) {
                const segmentKm = calculateDistance(lastPoint.lat, lastPoint.lng, newPoint.lat, newPoint.lng);
                accumulatedDistance += (segmentKm * 1000);

                // Periodic Snapping to Road (e.g., every 5 points or every 500m)
                // For now, we'll just accumulate raw (but filtered) distance
                // and implement snapping in a separate batch function or at the end.
            } else {
                console.log(`[TripEngine] Point rejected for ride ${rideId}`);
                return;
            }
        }

        // Update ride doc with new distance and last point
        const actualDistanceKm = accumulatedDistance / 1000.0;
        
        // Real-time Fare Calculation
        const startedAt = rideData.startedAt?.toDate() || new Date();
        const rideDurationMinutes = (Date.now() - startedAt.getTime()) / 60000;
        const waitingMinutes = rideData.waitingMinutes || 0;

        const fareResult = await calculateTripFare(
            rideId,
            actualDistanceKm,
            rideDurationMinutes,
            waitingMinutes
        );

        await rideRef.update({
            accumulatedDistanceMeters: accumulatedDistance,
            actualDistance: actualDistanceKm,
            actualDuration: Math.round(rideDurationMinutes),
            totalFare: fareResult.finalFare,
            rideFare: fareResult.finalFare,
            fare: fareResult.finalFare,
            lastProcessedPoint: {
                lat: newPoint.lat,
                lng: newPoint.lng,
                timestamp: newPoint.timestamp
            },
            currentLatLng: new admin.firestore.GeoPoint(newPoint.lat, newPoint.lng)
        });

        console.log(`[TripEngine] Ride ${rideId} updated. Distance: ${actualDistanceKm.toFixed(2)}km, Fare: ₹${fareResult.finalFare}`);
    }
);

/**
 * Snap a list of points to the road network using Google Roads API.
 */
export async function snapToRoads(points: { lat: number, lng: number }[]): Promise<{ lat: number, lng: number }[]> {
    if (points.length < 2) return points;

    try {
        const apiKey = process.env.GOOGLE_MAPS_API_KEY;
        const path = points.map(p => `${p.lat},${p.lng}`).join("|");
        const url = `https://roads.googleapis.com/v1/snapToRoads?path=${path}&interpolate=true&key=${apiKey}`;

        const response = await axios.get(url);
        if (response.data && response.data.snappedPoints) {
            return response.data.snappedPoints.map((p: any) => ({
                lat: p.location.latitude,
                lng: p.location.longitude
            }));
        }
    } catch (e) {
        console.error("[TripEngine] Roads API Error:", e);
    }
    return points;
}

/**
 * Calculate the total distance of a polyline/path.
 */
export function calculatePathDistance(points: { lat: number, lng: number }[]): number {
    let total = 0;
    for (let i = 0; i < points.length - 1; i++) {
        total += calculateDistance(points[i].lat, points[i].lng, points[i+1].lat, points[i+1].lng);
    }
    return total;
}
