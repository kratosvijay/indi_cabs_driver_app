import * as admin from "firebase-admin";
import { setGlobalOptions } from "firebase-functions/v2";

setGlobalOptions({ maxInstances: 1, memory: '256MiB' });

import {
    onDocumentCreated,
    onDocumentWritten,
    onDocumentUpdated,
} from "firebase-functions/v2/firestore";
import { onCall, HttpsError, onRequest } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { defineSecret } from "firebase-functions/params";
import axios from "axios";

import { batchOnboard } from "./onboarding";
import { aggregateDemandDriver, resetDemandZonesDriver } from "./demandAggregator";

export { batchOnboard, aggregateDemandDriver, resetDemandZonesDriver };

/*
export const performLoadTest = onRequest({ timeoutSeconds: 300, maxInstances: 1 }, async (req, res) => {
    try {
        await runLoadTest();
        res.send("Load Test Completed Successfully. Check Cloud Function logs for details.");
    } catch (error) {
        console.error("Load Test Failed:", error);
        res.status(500).send("Load Test Failed: " + error);
    }
});
*/



// ============================================================================
// LEGACY RIDE DISTRIBUTION SYSTEM (RESTORED)
// ============================================================================


if (admin.apps.length === 0) {
    admin.initializeApp();
}

const db = admin.firestore();

const exotelSid = defineSecret("EXOTEL_SID");
const exotelApiKey = defineSecret("EXOTEL_API_KEY");
const exotelApiToken = defineSecret("EXOTEL_API_TOKEN");
const exotelCallerId = defineSecret("EXOTEL_CALLER_ID");
const exotelSubdomain = defineSecret("EXOTEL_SUBDOMAIN");


// ============================================================================
// LEGACY FUNCTIONS (kept for backwards compatibility during migration)
// ============================================================================



/**
 * GENERATE OTP (Triggered when client writes to otp_verifications)
 * Changed to onDocumentWritten to handle re-tries (where doc already exists).
 */
export const generateOtpDriver = onDocumentWritten(
    {
        document: "otp_verifications/{phoneNumber}",
        region: "asia-south1",
    },
    async (event) => {
        // If document was deleted, do nothing
        if (!event.data?.after.exists) return;

        const phoneNumber = event.params.phoneNumber;
        const data = event.data.after.data();

        // Prevent infinite loops: If OTP is already generated, stop.
        if (data && data.otp) return;

        // Generate 6-digit OTP
        const otp = Math.floor(100000 + Math.random() * 900000).toString();
        const expiresAt = new Date();
        expiresAt.setMinutes(expiresAt.getMinutes() + 5);

        console.log(`Generating OTP for ${phoneNumber}: ${otp}`);

        // Update document with generated OTP
        return event.data.after.ref.update({
            otp: otp,
            expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
            status: "sent",
            processedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    }
);

/**
 * Calculate distance between two points using Haversine formula
 */

/**
 * Calculate distance between two points using Haversine formula
 */
function calculateDistance(
    lat1: number,
    lon1: number,
    lat2: number,
    lon2: number
): number {
    const R = 6371; // Radius of the Earth in km
    const dLat = ((lat2 - lat1) * Math.PI) / 180;
    const dLon = ((lon2 - lon1) * Math.PI) / 180;
    const a =
        Math.sin(dLat / 2) * Math.sin(dLat / 2) +
        Math.cos((lat1 * Math.PI) / 180) *
        Math.cos((lat2 * Math.PI) / 180) *
        Math.sin(dLon / 2) *
        Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c;
}



/**
 * Distribute ride to nearby drivers sequentially
 */
/**
 * Distribute ride to nearby drivers sequentially
 */
/**
 * Distribute ride to nearby drivers with expanding radius (1km -> 10km)
 * Triggered when a ride is created or reset to 'searching'
 */

/**
 * Distribute ride to nearby drivers sequentially
 */
export const distributeRideToDrivers = onDocumentWritten(
    {
        document: "ride_requests/{rideId}",
        timeoutSeconds: 300, // Allow running for 5 minutes
        region: "asia-south1",
    },
    async (event) => {
        const change = event.data;
        if (!change) return null; // Deleted

        const afterData = change.after.data();
        if (!afterData) return null;

        const beforeData = change.before.exists ? change.before.data() : null;
        const rideId = event.params.rideId;

        // Trigger only if:
        // 1. New ride created with status 'searching'
        // 2. Status changed to 'searching' (e.g. from cancelled/rejected)
        // 3. NOT if just 'driverId' or other fields changed while already searching (to avoid loops)

        const isNew = !beforeData;
        const isStatusChange = beforeData && beforeData.status !== "searching" && afterData.status === "searching";

        // Logic to avoid infinite loops when we update driverId ourselves
        // If status was already searching and we are just updating internal fields, stop.
        if (!isNew && !isStatusChange && afterData.status === "searching") {
            return null;
        }

        if (afterData.status !== "searching") {
            return null;
        }

        console.log(`Searching drivers for ride ${rideId}...`);

        try {
            // Get Pickup Location
            const pickupGeo = afterData.pickupLocation; // GeoPoint
            if (!pickupGeo) {
                console.error("No pickup location found");
                return null;
            }

            // ---------------------------------------------------------
            // 1. CHECK FOR AIRPORT QUEUE (MAA) - POLYGON CHECK
            // ---------------------------------------------------------

            // Get Chennai Airport Polygon
            const geoZoneDoc = await db.collection("geofenced_zones").doc("Chennai_Airport").get();
            let isInsideAirport = false;

            if (geoZoneDoc.exists) {
                const boundary = geoZoneDoc.data()?.boundary || []; // Array of GeoPoints
                if (boundary.length > 0) {
                    // Ray-Casting Algorithm
                    let inside = false;
                    const x = pickupGeo.latitude, y = pickupGeo.longitude;

                    for (let i = 0, j = boundary.length - 1; i < boundary.length; j = i++) {
                        const xi = boundary[i].latitude, yi = boundary[i].longitude;
                        const xj = boundary[j].latitude, yj = boundary[j].longitude;

                        const intersect = ((yi > y) !== (yj > y)) &&
                            (x < (xj - xi) * (y - yi) / (yj - yi) + xi);
                        if (intersect) inside = !inside;
                    }
                    isInsideAirport = inside;
                }
            } else {
                // Fallback to Radius if polygon missing
                const airportCenter = { lat: 12.994112, lng: 80.170866 }; // Chennai Airport
                const distToAirport = calculateDistance(
                    pickupGeo.latitude,
                    pickupGeo.longitude,
                    airportCenter.lat,
                    airportCenter.lng
                );
                if (distToAirport <= 2.5) isInsideAirport = true;
            }

            if (isInsideAirport) {
                console.log(`Ride ${rideId} is INSIDE Airport Polygon. Checking Queue...`);

                const queueSnap = await db.collection("airport_queues")
                    .doc("MAA")
                    .collection("drivers")
                    .orderBy("entryTimestamp", "asc")
                    .limit(10) // Get top 10
                    .get();

                if (!queueSnap.empty) {
                    // Check availability via rejection history
                    const rejectedBy = new Set(afterData.rejectedBy || []);
                    let selectedDriverId = null;

                    for (const doc of queueSnap.docs) {
                        const dId = doc.id;
                        // Skip if already rejected this specific ride
                        if (!rejectedBy.has(dId)) {
                            selectedDriverId = dId;
                            break;
                        }
                    }

                    if (selectedDriverId) {
                        console.log(`Assigning Airport Ride ${rideId} to Queued Driver: ${selectedDriverId}`);

                        await change.after.ref.update({
                            driverId: selectedDriverId,
                            currentDriverIndex: 0,
                            potentialDrivers: [selectedDriverId], // Only him for now
                            notifiedAt: admin.firestore.FieldValue.serverTimestamp(),
                            isAirportRide: true
                        });

                        // Verify if we should update queue status to 'offered_ride'
                        await db.collection("airport_queues")
                            .doc("MAA")
                            .collection("drivers")
                            .doc(selectedDriverId)
                            .update({ status: 'offered_ride' });

                        return null; // Done
                    } else {
                        console.log("All top 10 queued drivers have rejected this ride. Falling back to normal search.");
                    }
                } else {
                    console.log("Airport Queue is empty. Falling back to normal search.");
                }
            }
            // ---------------------------------------------------------

            // Find Online Drivers
            // Filter by: isOnline: true, status: active (or null?)
            // We also need to match vehicle type if needed
            const driversSnap = await db.collection("drivers")
                .where("isOnline", "==", true)
                .where("status", "==", "active")
                // .where("vehicleClass", "==", afterData.vehicleClass) // Optional: strict matching
                .get();

            const drivers: any[] = [];

            driversSnap.forEach(doc => {
                const dData = doc.data();
                if (dData.currentLocation) {
                    const dist = calculateDistance(
                        pickupGeo.latitude,
                        pickupGeo.longitude,
                        dData.currentLocation.latitude,
                        dData.currentLocation.longitude
                    );

                    // Radius Check (e.g. 50km max)
                    if (dist <= 50) {
                        drivers.push({ id: doc.id, distance: dist, data: dData });
                    }
                }
            });

            if (drivers.length === 0) {
                console.log("No drivers found nearby.");
                // Ensure we don't leave it securely assigned if it was
                return null;
            }

            // Sort by distance
            drivers.sort((a, b) => a.distance - b.distance);

            console.log(`Found ${drivers.length} drivers. Nearest: ${drivers[0].id} (${drivers[0].distance.toFixed(2)}km)`);

            // Assign to first driver
            const firstDriver = drivers[0];
            const potentialDriverIds = drivers.map(d => d.id);

            await change.after.ref.update({
                driverId: firstDriver.id,
                currentDriverIndex: 0,
                potentialDrivers: potentialDriverIds,
                notifiedAt: admin.firestore.FieldValue.serverTimestamp(),
                // Keep status as searching, the driver app listens for 'searching' + 'driverId == me'
            });

            console.log(`Assigned ride ${rideId} to ${firstDriver.id}`);

        } catch (e) {
            console.error("Error distributing ride:", e);
        }

        return null;
    }
);


/**
 * Handle ride rejection/timeout and re-assign to next driver
 * Triggered on Update
 */
export const handleRideRejection = onDocumentUpdated(
    {
        document: "ride_requests/{rideId}",
        region: "asia-south1",
    },
    async (event) => {
        const change = event.data;
        if (!change) return null;

        const beforeData = change.before.data();
        const afterData = change.after.data();
        const rideId = event.params.rideId;

        // 1. Handle Cancellation by Driver (after acceptance)
        // User: "if a driver accepts and cancels the ride immedialty then the status of the user nust turn back to searching"
        if (
            beforeData.status !== "cancelled" &&
            afterData.status === "cancelled" &&
            afterData.cancelledBy === "driver"
        ) {
            const driverId = beforeData.driverId; // The driver who cancelled

            console.log(`Driver ${driverId} cancelled ride ${rideId}. Resetting to searching.`);

            // Block driver (optional: 24h block)
            if (beforeData.status === "accepted") {
                const blockUntil = new Date();
                blockUntil.setHours(blockUntil.getHours() + 24);
                await db.collection("ride_requests").doc(rideId).collection("blocked_drivers").doc(driverId).set({
                    blockedUntil: admin.firestore.Timestamp.fromDate(blockUntil),
                    reason: "Cancelled before arrival",
                });
            }

            // Reset to searching to trigger 'distributeRideToDrivers' again
            // We also add the driver to 'rejectedBy' so they aren't picked again immediately
            await change.after.ref.update({
                status: "searching",
                driverId: admin.firestore.FieldValue.delete(),
                cancelledBy: admin.firestore.FieldValue.delete(),
                cancellationReason: admin.firestore.FieldValue.delete(),
                rejectedBy: admin.firestore.FieldValue.arrayUnion(driverId),
                // We might want to clear potentialDrivers to force a fresh radius search?
                // User said "reoffered for search radius atart with 1 km"
                // So yes, let's clear potentialDrivers so the loop starts fresh
                potentialDrivers: [],
                currentDriverIndex: 0
            });
            return null;
        }

        // 2. Handle Rejection / Timeout (Status is still 'searching')
        // Used when the app reports a rejection or timeout
        if (afterData.status === "searching") {
            const oldRejected = beforeData.rejectedBy || [];
            const newRejected = afterData.rejectedBy || [];

            // If rejected list grew, we need to pick next driver
            if (newRejected.length > oldRejected.length) {

                // TRACK METRICS: Increment ridesRejected for newly rejected drivers
                const newlyRejected = newRejected.filter((id: string) => !oldRejected.includes(id));
                newlyRejected.forEach((dId: string) => {
                    db.collection("drivers").doc(dId).update({
                        "metrics.ridesRejected": admin.firestore.FieldValue.increment(1)
                        // defined as: user rejects or timeout
                    }).catch(err => console.error(`Failed to update stats for ${dId}:`, err));
                });

                const potentialDrivers = afterData.potentialDrivers || [];
                const allRejected = new Set(newRejected);

                let nextDriverId = null;
                let nextIndex = 0;

                // Find next eligible driver
                // We try to pick the one AFTER the current index if possible
                let startIndex = (afterData.currentDriverIndex || 0) + 1;

                // Simple search for next available
                for (let i = 0; i < potentialDrivers.length; i++) {
                    // Wrap around logic? User said "until one of them accepts". 
                    // Usually linear is better unless we run out.
                    const idx = (startIndex + i) % potentialDrivers.length;
                    const dId = potentialDrivers[idx];

                    if (!allRejected.has(dId)) {
                        nextDriverId = dId;
                        nextIndex = idx;
                        break;
                    }
                }

                if (nextDriverId) {
                    console.log(`Re-assigning ride ${rideId} to next driver ${nextDriverId}`);
                    await change.after.ref.update({
                        driverId: nextDriverId,
                        currentDriverIndex: nextIndex,
                        notifiedAt: admin.firestore.FieldValue.serverTimestamp(),
                    });
                } else {
                    console.log("No more drivers available in current pool. Checking for cycle reset...");

                    if (potentialDrivers.length > 0) {
                        // Reset the cycle! 
                        // User requirement: "if it is stll available then the ride should be offered to the same driver"
                        // This implies circular assignment.

                        const firstDriver = potentialDrivers[0];
                        console.log(`Cycle reset: Clearing rejections and re-assigning ride ${rideId} to first driver ${firstDriver}`);

                        await change.after.ref.update({
                            rejectedBy: [], // Clear history so they can accept again
                            driverId: firstDriver,
                            currentDriverIndex: 0,
                            notifiedAt: admin.firestore.FieldValue.serverTimestamp(),
                        });
                    } else {
                        console.log("Potential drivers list empty. Cannot cycle.");
                    }
                }
            }
        }
        return null;
    }
);

/**
 * Manage Driver Status (Online/Offline) based on Ride Status
 * User: "if a driver accepts a ride make him offline when he completes the make him onlune again"
 */
export const manageDriverStatus = onDocumentUpdated(
    {
        document: "ride_requests/{rideId}",
        region: "asia-south1",
    },
    async (event) => {
        const change = event.data;
        const rideId = event.params.rideId;
        if (!change) return null;

        const beforeData = change.before.data();
        const afterData = change.after.data();

        const driverId = afterData.driverId;
        if (!driverId) return null;

        const driverRef = db.collection("drivers").doc(driverId);

        // Case 1: Ride Accepted -> Set Offline / OnTrip
        if (beforeData.status === "searching" && afterData.status === "accepted") {
            console.log(`Setting driver ${driverId} to OnTrip/Offline and removing from Airport Queue`);
            await driverRef.update({
                isOnline: false,
                status: "on_trip"
            });

            // Remove from Airport Queue (MAA) if present
            // This ensures the queue shifts up (1->0, 2->1, etc.)
            await db.collection("airport_queues").doc("MAA").collection("drivers").doc(driverId).delete().catch(e => {
                console.log("Error removing from queue (might not be in one):", e);
            });
        }

        // Case 2: Ride Completed -> Set Online / Active
        if (beforeData.status !== "completed" && afterData.status === "completed") {
            console.log(`Setting driver ${driverId} to Active/Online`);
            await driverRef.update({
                isOnline: true,
                status: "active"
            });

            // ---------------------------------------------------------
            // CREATE EARNINGS RECORD
            // ---------------------------------------------------------
            try {
                const amount = afterData.fare || 0;
                const earningsData = {
                    amount: amount,
                    createdAt: admin.firestore.FieldValue.serverTimestamp(),
                    driverId: driverId,
                    rideId: rideId,
                    status: "completed",
                    type: "ride_fare",
                    details: {
                        baseFare: afterData.baseFare || amount, // Fallback if baseFare specific field missing
                        distance: afterData.distance || 0,
                        rideType: afterData.rideType || "daily",
                        waitingCharge: afterData.waitingCharge || 0
                    }
                };

                await db.collection("earnings").add(earningsData);
                console.log(`Earnings record created for ride ${rideId}: ${amount}`);
            } catch (err) {
                console.error(`Failed to create earnings record for ${rideId}:`, err);
            }
            // ---------------------------------------------------------
        }

        // Case 3: Ride Cancelled (after acceptance) -> Set Online / Active
        // (If driver cancelled it, they might be blocked, but they should be conceptually 'available' for other things unless blocked logic overrides)
        // But if USER cancels, driver should go back online.
        if (beforeData.status === "accepted" && afterData.status === "cancelled") {
            console.log(`Ride cancelled. Setting driver ${driverId} to Active/Online`);
            await driverRef.update({
                isOnline: true,
                status: "active"
            });
        }
        return null;
    }
);

/**
 * Calculate dynamic pricing based on actual distance traveled
 */
export const calculateDynamicPricing = onCall({ region: "asia-south1" }, async (request) => {
    if (!request.auth) {
        throw new HttpsError(
            "unauthenticated",
            "User must be authenticated"
        );
    }

    const { rideId, actualDistanceKm } = request.data;

    if (!rideId || actualDistanceKm === undefined) {
        throw new HttpsError(
            "invalid-argument",
            "Missing required parameters"
        );
    }

    try {
        // Get ride data
        const rideDoc = await db.collection("ride_requests").doc(rideId).get();

        if (!rideDoc.exists) {
            throw new HttpsError("not-found", "Ride not found");
        }

        const rideData = rideDoc.data();
        if (!rideData) throw new HttpsError("internal", "Ride data missing");

        const estimatedDistanceKm = rideData.rideDistance || 0;
        const estimatedFare = rideData.rideFare || 0;
        // Fix: Use the vehicle type requested by user, not driver's vehicle
        const vehicleType = rideData.vehicleType || "Sedan";

        // Fix: Logic to LOCK rates at time of booking.
        // Check if rate variables are stored in the ride document itself.
        // If they are (e.g. from createRide function), use them.
        // Otherwise, fetch from pricing rules and fallback to defaults.

        let baseFare = rideData.baseFare;
        let perKmRate = rideData.perKilometer; // Check for perKilometer or perKmRate
        let minimumFare = rideData.minimumFare;

        // If any rate is missing, fetch from Pricing Rules (Legacy/Fallback behavior)
        if (baseFare === undefined || perKmRate === undefined || minimumFare === undefined) {
            console.log("Rates not found in ride doc. Fetching current pricing rules...");

            // Set defaults if fetch fails
            if (baseFare === undefined) baseFare = 50;
            if (perKmRate === undefined) perKmRate = 10;
            if (minimumFare === undefined) minimumFare = 150;

            try {
                // Get Chennai pricing document
                const pricingDoc = await db
                    .collection("pricing_rules")
                    .doc("Chennai")
                    .get();

                if (pricingDoc.exists) {
                    const pricingData = pricingDoc.data();
                    if (pricingData && pricingData.vehicle_types) {
                        const vehicleTypeData = pricingData.vehicle_types[vehicleType];
                        if (vehicleTypeData) {
                            // Only overwrite if undefined in rideData
                            if (rideData.baseFare === undefined) baseFare = vehicleTypeData.baseFare || baseFare;
                            if (rideData.perKilometer === undefined) perKmRate = vehicleTypeData.perKilometer || perKmRate;
                            if (rideData.minimumFare === undefined) minimumFare = vehicleTypeData.minimumFare || minimumFare;
                        } else {
                            console.log(
                                `No pricing rules found for ${vehicleType}, using defaults`
                            );
                        }
                    } else {
                        console.log(
                            "No vehicle_types found in pricing rules, using defaults"
                        );
                    }
                } else {
                    console.log("No Chennai pricing doc found, using defaults");
                }
            } catch (error) {
                console.log(
                    `Error fetching pricing rules: ${error}, using defaults`
                );
            }
        } else {
            console.log(`Using LOCKED rates from ride doc: Base=${baseFare}, PerKm=${perKmRate}, Min=${minimumFare}`);
        }

        // Calculate distance difference
        const distanceDiff = actualDistanceKm - estimatedDistanceKm;

        let finalFare = estimatedFare;
        let priceUpdated = false;
        let reason = "";

        // Check if distance is extra
        if (distanceDiff > 0) {
            // Extra distance traveled
            if (distanceDiff > 1.5) {
                // Exceeds tolerance, update price
                const extraCharge = distanceDiff * perKmRate;
                finalFare = estimatedFare + extraCharge;
                priceUpdated = true;
                reason = `Extra ${distanceDiff.toFixed(2)}km traveled`;
            } else {
                // Within tolerance, no update
                reason = `Extra distance in tolerance (${distanceDiff.toFixed(2)}km)`;
            }
        } else if (distanceDiff < 0) {
            // Less distance traveled
            const lessDistance = Math.abs(distanceDiff);

            if (lessDistance > 5) {
                // Exceeds tolerance, recalculate price
                finalFare = baseFare + actualDistanceKm * perKmRate;
                priceUpdated = true;
                reason = `Ride ended ${lessDistance.toFixed(2)}km early`;
            } else {
                // Within tolerance, no update
                reason = `Early end within tolerance (${lessDistance.toFixed(2)}km)`;
            }
        }

        // Enforce minimum fare
        if (finalFare < minimumFare) {
            finalFare = minimumFare;
            priceUpdated = true;
            if (!reason) {
                reason = `Minimum fare applied (${actualDistanceKm.toFixed(2)}km traveled)`;
            } else {
                reason += ` | Minimum fare enforced`;
            }
        }

        // Update ride document with final fare
        await rideDoc.ref.update({
            actualDistance: actualDistanceKm,
            finalAmount: finalFare,
            totalFare: finalFare,
            priceUpdated: priceUpdated,
            pricingReason: reason,
        });

        return {
            success: true,
            estimatedFare: estimatedFare,
            finalFare: finalFare,
            priceUpdated: priceUpdated,
            reason: reason,
            actualDistance: actualDistanceKm,
            estimatedDistance: estimatedDistanceKm,
        };
    } catch (error) {
        console.error("Error calculating dynamic pricing:", error);
        throw new HttpsError(
            "internal",
            "Failed to calculate pricing"
        );
    }
});

/**
 * Cleanup expired blocked drivers (runs daily)
 */
export const cleanupBlockedDrivers = onSchedule("every 24 hours",
    async (_event) => {
        const now = admin.firestore.Timestamp.now();

        try {
            // Get all ride requests
            const ridesSnapshot = await db.collection("ride_requests").get();

            for (const rideDoc of ridesSnapshot.docs) {
                const blockedDriversSnapshot = await rideDoc.ref
                    .collection("blocked_drivers")
                    .where("blockedUntil", "<=", now)
                    .get();

                // Delete expired blocks
                const batch = db.batch();
                blockedDriversSnapshot.docs.forEach((doc) => {
                    batch.delete(doc.ref);
                });

                await batch.commit();

                if (blockedDriversSnapshot.size > 0) {
                    console.log(
                        `Cleaned ${blockedDriversSnapshot.size} blocks for ${rideDoc.id}`
                    );
                }
            }

            return;
        } catch (error) {
            console.error("Error cleaning up blocked drivers:", error);
            return;
        }
    }
);


// Razorpay Config via firebase functions:config:set razorpay.key_id="" razorpay.key_secret=""
// These are securely stored in the Google Cloud environment.


/**
 * Fetch Razorpay Key ID for the Client App
 * This allows the app to get the key without hardcoding it.
 */
export const getRazorpayKey = onCall(async (_request) => {
    // Return only the KEY_ID (public), never the SECRET
    // Using process.env from .env file (standard for Gen 2)
    const keyId = process.env.RAZORPAY_KEY_ID || "";
    if (!keyId) {
        console.error("Razorpay Key ID not configured in .env");
    }
    return { keyId: keyId };
});

export const processWalletSettlement = onDocumentCreated(
    {
        document: "drivers/{driverId}/wallet_transactions/{transactionId}",
        region: "asia-south1",
    },
    async (event) => {
        const snap = event.data;
        if (!snap) return null;

        const data = snap.data();
        const driverId = event.params.driverId;
        const transactionId = event.params.transactionId;

        // Only process pending debit transactions
        if (data.type !== "debit" || data.status !== "pending") {
            return null;
        }

        const RAZORPAY_KEY = process.env.RAZORPAY_KEY_ID || "";
        const RAZORPAY_SECRET = process.env.RAZORPAY_KEY_SECRET || "";

        if (!RAZORPAY_KEY || !RAZORPAY_SECRET) {
            console.error("Razorpay keys are not configured in .env");
            return null;
        }

        try {
            console.log(`Processing settlement for ${driverId}: ₹${data.amount} to ${data.upiId}`);

            const payoutRequest = {
                account_number: "2323230041624855", // Using Demo or Configured Account
                amount: Math.round(data.amount * 100), // Amount in paise
                currency: "INR",
                mode: "UPI",
                purpose: "payout",
                fund_account: {
                    account_type: "vpa",
                    vpa: {
                        address: data.upiId
                    },
                    contact: {
                        name: "Driver Settlement",
                        type: "self",
                        reference_id: driverId,
                    }
                },
                queue_if_low_balance: true,
                reference_id: transactionId,
                narration: "Driver Wallet Settlement"
            };

            const response = await axios.post(
                "https://api.razorpay.com/v1/payouts",
                payoutRequest,
                {
                    auth: {
                        username: RAZORPAY_KEY,
                        password: RAZORPAY_SECRET,
                    },
                    headers: {
                        "Content-Type": "application/json",
                    },
                }
            );

            console.log("Payout Successful:", response.data);

            // Update Transaction to Success
            await snap.ref.update({
                status: "success",
                payoutId: response.data.id,
                processedAt: admin.firestore.FieldValue.serverTimestamp(),
            });

        } catch (error: any) {
            console.error("Payout Failed:", error.response ? error.response.data : error.message);

            // Refund Balance on Failure
            await db.runTransaction(async (t) => {
                const balanceRef = db.doc(`drivers/${driverId}/wallet/balance`);
                const balanceDoc = await t.get(balanceRef);
                const currentBalance = balanceDoc.data()?.currentBalance || 0;

                t.update(balanceRef, {
                    currentBalance: currentBalance + data.amount
                });

                t.update(snap.ref, {
                    status: "failed",
                    error: error.response ? JSON.stringify(error.response.data) : error.message,
                    refundedAt: admin.firestore.FieldValue.serverTimestamp()
                });
            });
        }
        return null;
    }
);

export const autoSettleWallets = onSchedule("every day 00:00", async (event) => {
    console.log("Starting midnight auto-settlement...");

    try {
        const driversSnapshot = await db.collection("drivers")
            .where("autoSettleEnabled", "==", true)
            .get();

        if (driversSnapshot.empty) {
            console.log("No drivers with auto-settle enabled.");
            return;
        }

        let batch = db.batch();
        let operationCount = 0;

        for (const driverDoc of driversSnapshot.docs) {
            const data = driverDoc.data();
            const upiId = data.autoSettleUpiId;

            if (!upiId) {
                console.log(`Skipping driver ${driverDoc.id}: No autoSettleUpiId`);
                continue;
            }

            // Get balance
            const balanceRef = driverDoc.ref.collection("wallet").doc("balance");
            const balanceDoc = await balanceRef.get();
            const currentBalance = balanceDoc.data()?.currentBalance || 0;

            if (currentBalance > 0) {
                console.log(`Settling driver ${driverDoc.id}: ${currentBalance}`);

                // Debit Balance
                batch.set(balanceRef, { currentBalance: 0 }, { merge: true });

                // Create Transaction
                const transactionRef = driverDoc.ref.collection("wallet_transactions").doc();
                batch.set(transactionRef, {
                    amount: currentBalance,
                    type: "debit",
                    createdAt: admin.firestore.FieldValue.serverTimestamp(),
                    description: `Auto-Settled to UPI: ${upiId}`,
                    upiId: upiId,
                    status: "pending", // processSettlement will pick this up
                    isAutoSettlement: true
                });

                operationCount += 2; // 2 writes per driver

                if (operationCount >= 400) {
                    console.log("Committing batch chunk...");
                    await batch.commit();
                    batch = db.batch(); // Re-initialize batch
                    operationCount = 0;
                }
            }
        }

        if (operationCount > 0) {
            await batch.commit();
        }

        console.log(`Auto-settlement completed.`);

        console.log(`Auto-settlement completed.`);

    } catch (error) {
        console.error("Error in auto-settlement:", error);
    }
});

/**
 * Verify UPI ID using Razorpay Fund Account Validation
 * Performed strictly via Cloud Function to keep secrets safe.
 */
export const verifyUpiId = onCall({ region: "asia-south1" }, async (request) => {
    if (!request.auth) {
        throw new HttpsError("unauthenticated", "User must be authenticated");
    }

    const { upiId, name } = request.data;
    if (!upiId || !name) {
        throw new HttpsError("invalid-argument", "Missing UPI ID or Name");
    }

    const RAZORPAY_KEY = process.env.RAZORPAY_KEY_ID || "";
    const RAZORPAY_SECRET = process.env.RAZORPAY_KEY_SECRET || "";

    if (!RAZORPAY_KEY || !RAZORPAY_SECRET) {
        throw new HttpsError("failed-precondition", "Razorpay not configured");
    }

    try {
        const authHeader = {
            username: RAZORPAY_KEY,
            password: RAZORPAY_SECRET,
        };

        // 1. Create Contact
        console.log(`Creating contact for ${name}...`);
        const contactResponse = await axios.post(
            "https://api.razorpay.com/v1/contacts",
            {
                name: name,
                type: "vendor", // or 'employee', 'self'
                reference_id: request.auth.uid,
            },
            { auth: authHeader }
        );
        const contactId = contactResponse.data.id;

        // 2. Create Fund Account (UPI)
        console.log(`Creating fund account for ${upiId}...`);
        const fundAccountResponse = await axios.post(
            "https://api.razorpay.com/v1/fund_accounts",
            {
                contact_id: contactId,
                account_type: "vpa",
                vpa: { address: upiId },
            },
            { auth: authHeader }
        );
        const fundAccountId = fundAccountResponse.data.id;

        // 3. Validate Fund Account (Penny Drop rule: ~₹1.18 cost)
        console.log(`Validating fund account ${fundAccountId}...`);
        const validationResponse = await axios.post(
            "https://api.razorpay.com/v1/fund_accounts/validations",
            {
                fund_account_id: fundAccountId,
                amount: 100, // 1.00 INR
                currency: "INR",
                notes: {
                    driver_id: request.auth.uid,
                    reason: "UPI Verification"
                }
            },
            { auth: authHeader }
        );

        const status = validationResponse.data.status; // 'created', 'completed', 'failed'

        // Sometimes validation is async, but usually instant for UPI.
        // If status is 'created', we might assume pending.
        // For strict check, we want 'active' or 'completed'?
        // Razorpay docs: status 'completed' means success.

        if (status === "completed" || status === "active") { // 'active' might be for fund_account itself? Validation status is usually different.
            // Actually validation status: 'created', 'pending', 'completed', 'failed'
            return {
                success: true,
                registeredName: validationResponse.data.results?.registered_name || name,
                status: status
            };
        } else if (status === "failed") {
            throw new HttpsError("aborted", "UPI Verification Failed: Invalid Account");
        } else {
            // Pending?
            return {
                success: true, // Optimistic or ask user to wait?
                message: "Verification Pending",
                status: status
            };
        }

    } catch (error: any) {
        console.error("Error validating UPI:", error.response ? error.response.data : error.message);
        throw new HttpsError(
            "internal",
            error.response?.data?.error?.description || "Verification Failed"
        );
    }
});

/**
 * VERIFY OTP AND CREATE DRIVER (Callable)
 * Replaces client-side driver creation for security.
 */
export const verifyOtpAndCreateDriver = onCall({ region: "asia-south1" }, async (request) => {
    // Note: Request.auth might be null if user is not logged in yet (Self-Registration)
    // Or it might be the Fleet Operator's auth. 

    const { phone, otp, driverData, targetUid } = request.data;

    if (!phone || !otp || !driverData) {
        throw new HttpsError("invalid-argument", "Missing phone, otp, or driver details");
    }

    try {
        // 1. Validate OTP
        const verificationDoc = await db.collection("otp_verifications").doc(phone).get();
        if (!verificationDoc.exists) {
            throw new HttpsError("not-found", "OTP request not found");
        }

        const verData = verificationDoc.data()!;
        if (!verData.otp) { // OTP not generated yet
            throw new HttpsError("failed-precondition", "OTP not generated yet");
        }

        if (verData.otp !== otp) {
            throw new HttpsError("invalid-argument", "Invalid OTP");
        }

        const expiresAt = verData.expiresAt.toDate();
        if (new Date() > expiresAt) {
            throw new HttpsError("failed-precondition", "OTP Expired");
        }

        // 2. Create Driver in Firestore
        // Use provided targetUid or generate one
        const newUid = targetUid || `driver_${Date.now()}`;

        await db.collection("drivers").doc(newUid).set({
            ...driverData,
            uid: newUid,
            phoneNumber: phone,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            isApproved: false,
            documentsSubmitted: false, // Will be updated by next steps
            // If logged in as operator, we can add that tracking field
            fleetOperatorId: request.auth ? request.auth.uid : null,
            vehicleType: driverData.vehicleType || "Select Vehicle",
        });

        // 3. Cleanup OTP
        await verificationDoc.ref.delete();

        return { success: true, uid: newUid };

    } catch (error: any) {
        console.error("Error creating driver:", error);
        throw new HttpsError("internal", `Failed to create driver: ${error.message || error}`);
    }
});

/**
 * Initiate Exotel Click-to-Call
 */
export const initiateCall = onCall({
    secrets: [exotelSid, exotelApiKey, exotelApiToken, exotelCallerId, exotelSubdomain],
    region: "asia-south1",
}, async (request) => {
    if (!request.auth) {
        throw new HttpsError("unauthenticated", "User must be authenticated");
    }

    const { rideId } = request.data;
    if (!rideId) {
        throw new HttpsError("invalid-argument", "Missing rideId");
    }

    const EXOTEL_SID = exotelSid.value();
    const EXOTEL_API_KEY = exotelApiKey.value();
    const EXOTEL_API_TOKEN = exotelApiToken.value();
    const EXOTEL_CALLER_ID = exotelCallerId.value();
    const EXOTEL_SUBDOMAIN = exotelSubdomain.value() || "api.exotel.com";

    if (!EXOTEL_SID || !EXOTEL_API_KEY || !EXOTEL_API_TOKEN || !EXOTEL_CALLER_ID) {
        console.error("Exotel credentials missing in secrets");
        throw new HttpsError("failed-precondition", "Call service not configured");
    }

    try {
        // 1. Fetch Ride Data
        const rideDoc = await db.collection("ride_requests").doc(rideId).get();
        if (!rideDoc.exists) {
            throw new HttpsError("not-found", "Ride not found");
        }
        const rideData = rideDoc.data();
        if (!rideData) throw new HttpsError("internal", "Ride data empty");

        const driverId = request.auth.uid;
        const userId = rideData.userId;

        // 2. Fetch Phone Numbers
        const driverDoc = await db.collection("drivers").doc(driverId).get();
        const userDoc = await db.collection("users").doc(userId).get();

        if (!driverDoc.exists || !userDoc.exists) {
            throw new HttpsError("not-found", "Driver or User not found");
        }

        const driverPhone = driverDoc.data()?.phoneNumber; // E.g., +919000000000
        const userPhone = userDoc.data()?.phoneNumber;

        if (!driverPhone || !userPhone) {
            throw new HttpsError("failed-precondition", "Phone numbers missing");
        }

        // 3. Call Exotel
        // https://developer.exotel.com/api/#call-agent
        // From: Driver (Agent), To: User (Customer), CallerId: ExoPhone

        const url = `https://${EXOTEL_API_KEY}:${EXOTEL_API_TOKEN}@${EXOTEL_SUBDOMAIN}/v1/Accounts/${EXOTEL_SID}/Calls/connect.json`;

        const formData = new URLSearchParams();
        formData.append("From", driverPhone); // Agent (Driver)
        formData.append("To", userPhone);     // Customer (User)
        formData.append("CallerId", EXOTEL_CALLER_ID); // Virtual Number
        formData.append("Record", "true"); // Optional

        // Exotel expects x-www-form-urlencoded
        const response = await axios.post(url, formData.toString(), {
            headers: {
                'Content-Type': 'application/x-www-form-urlencoded'
            }
        });

        console.log(`Exotel Call Initiated: ${response.status} - ${JSON.stringify(response.data)}`);

        return { success: true, sid: response.data?.Call?.Sid };

    } catch (error: any) {
        console.error("Error initiating call:", error.response ? error.response.data : error.message);
        throw new HttpsError("internal", "Failed to initiate call");
    }
});
// ----------------------------------------------------------------------------
/**
 * Update Driver Metrics (Acceptance, Cancellation, Rating)
 * Triggered on changes to ride_requests
 */
export const updateDriverMetrics = onDocumentUpdated(
    "ride_requests/{rideId}",
    async (event) => {
        const change = event.data;
        if (!change) return null;

        const before = change.before.data();
        const after = change.after.data();
        // Determine driverId: Use after for acceptance, before for cancellation/rating if missing
        const driverId = after.driverId || before.driverId;

        if (!driverId) return null;

        const driverRef = db.collection("drivers").doc(driverId);

        // 1. Accepted Ride (Searching -> Accepted)
        if (before.status === "searching" && after.status === "accepted" && after.driverId === driverId) {
            try {
                await db.runTransaction(async (t) => {
                    const doc = await t.get(driverRef);
                    if (!doc.exists) return;

                    const data = doc.data() || {};
                    const metrics = data.metrics || {};

                    const newAccepted = (metrics.ridesAccepted || 0) + 1;
                    const rejected = metrics.ridesRejected || 0;
                    const totalOffers = newAccepted + rejected;

                    // Acceptance Rate = Accepted / (Accepted + Rejected)
                    const acceptanceRate = totalOffers > 0 ? (newAccepted / totalOffers) * 100 : 0;

                    t.update(driverRef, {
                        "metrics.ridesAccepted": newAccepted,
                        "acceptanceRate": parseFloat(acceptanceRate.toFixed(2))
                    });
                });
                console.log(`Updated Acceptance Rate for ${driverId}`);
            } catch (error) {
                console.error("Failed to update acceptance stats:", error);
            }
        }

        // 2. Cancelled Ride (Accepted -> Cancelled by Driver)
        if (before.status === "accepted" && after.status === "cancelled" && after.cancelledBy === "driver") {
            try {
                await db.runTransaction(async (t) => {
                    const doc = await t.get(driverRef);
                    if (!doc.exists) return;

                    const data = doc.data() || {};
                    const metrics = data.metrics || {};

                    const newCancelled = (metrics.ridesCancelled || 0) + 1;
                    const ridesAccepted = metrics.ridesAccepted || 1; // Default to 1 to avoid DBZ if data missing

                    // Cancellation Rate = Cancelled / Accepted
                    const cancellationRate = ridesAccepted > 0 ? (newCancelled / ridesAccepted) * 100 : 0;

                    t.update(driverRef, {
                        "metrics.ridesCancelled": newCancelled,
                        "cancellationRate": parseFloat(cancellationRate.toFixed(2))
                    });
                });
                console.log(`Updated Cancellation Rate for ${driverId}`);
            } catch (error) {
                console.error("Failed to update cancellation stats:", error);
            }
        }

        // 3. Rating Update (User rates the ride)
        const oldRating = before.rating;
        const newRating = after.rating;

        // Update only if rating is newly added
        if (!oldRating && newRating && typeof newRating === 'number' && newRating > 0) {
            try {
                await db.runTransaction(async (t) => {
                    const doc = await t.get(driverRef);
                    if (!doc.exists) return;

                    const data = doc.data() || {};
                    const metrics = data.metrics || {};

                    const newSum = (metrics.ratingSum || 0) + newRating;
                    const newCount = (metrics.ratingCount || 0) + 1;
                    const avgRating = newCount > 0 ? newSum / newCount : 0;

                    t.update(driverRef, {
                        "metrics.ratingSum": newSum,
                        "metrics.ratingCount": newCount,
                        "rating": parseFloat(avgRating.toFixed(1))
                    });
                });
                console.log(`Updated Rating for ${driverId}: ${newRating}`);
            } catch (error) {
                console.error("Failed to update rating stats:", error);
            }
        }

        return null;
    }
);

// ----------------------------------------------------------------------------
/**
 * Handle Cancellation Fees
 * automated wallet credits for drivers
 */
export const manageCancellationFees = onDocumentUpdated(
    "ride_requests/{rideId}",
    async (event) => {
        const change = event.data;
        if (!change) return null;

        const before = change.before.data();
        const after = change.after.data();
        const rideId = event.params.rideId;

        // Only trigger if status changed to 'cancelled'
        if (before.status === "cancelled" || after.status !== "cancelled") {
            return null;
        }

        const driverId = after.driverId || before.driverId;
        if (!driverId) return null;

        const driverRef = db.collection("drivers").doc(driverId);
        const walletRef = driverRef.collection("wallet_transactions");
        const balanceRef = driverRef.collection("wallet").doc("balance");

        let creditAmount = 0;
        let reason = "";

        // Scenario 1: Driver Cancelled after waiting > 3 mins
        if (after.cancelledBy === "driver" && after.arrivedAt) {
            // Ensure arrivedAt is a Timestamp
            const arrivedAt = after.arrivedAt.toDate ? after.arrivedAt.toDate().getTime() : new Date(after.arrivedAt).getTime();
            const cancelledAt = after.cancelledAt ? (after.cancelledAt.toDate ? after.cancelledAt.toDate().getTime() : new Date(after.cancelledAt).getTime()) : Date.now();

            const durationSeconds = (cancelledAt - arrivedAt) / 1000;

            if (durationSeconds > 180) { // 3 minutes
                creditAmount = 20;
                reason = "Cancellation Fee (Waited > 3 mins)";
            }
        }

        // Scenario 2: User Cancelled after Driver Arrived
        // (If user cancelled, cancelledBy might be 'user')
        if ((after.cancelledBy === "user" || after.cancelledBy === "customer") && (before.status === "arrived" || after.arrivedAt)) {
            creditAmount = 20;
            reason = "Cancellation Fee (User Cancelled after Arrival)";
        }

        if (creditAmount > 0) {
            console.log(`Crediting ₹${creditAmount} to driver ${driverId} for ride ${rideId}. Reason: ${reason}`);

            try {
                await db.runTransaction(async (t) => {
                    // Get current balance
                    const balanceDoc = await t.get(balanceRef);
                    const currentBalance = balanceDoc.exists ? (balanceDoc.data()?.currentBalance || 0) : 0;
                    const newBalance = currentBalance + creditAmount;

                    // Update Balance
                    t.set(balanceRef, {
                        currentBalance: newBalance,
                        updatedAt: admin.firestore.FieldValue.serverTimestamp()
                    }, { merge: true });

                    // Add Transaction Record
                    const newTxRef = walletRef.doc();
                    t.set(newTxRef, {
                        amount: creditAmount,
                        type: "credit",
                        description: reason,
                        rideId: rideId,
                        status: "success",
                        timestamp: admin.firestore.FieldValue.serverTimestamp(),
                        category: "cancellation_fee"
                    });
                });
                console.log("Credit Transaction Successful");
            } catch (error) {
                console.error("Failed to credit cancellation fee:", error);
            }
        }

        return null;
    }
);

/**
 * RESET ALL DRIVERS (Admin/Debug Tool)
 * Sets all drivers to offline to clear "Ghost Drivers"
 */
export const resetAllDrivers = onRequest({ timeoutSeconds: 60, maxInstances: 1 }, async (req, res) => {
    try {
        const driversSnap = await db.collection("drivers").where("isOnline", "==", true).get();
        if (driversSnap.empty) {
            res.send("No online drivers found to reset.");
            return;
        }

        const batch = db.batch();
        let count = 0;

        driversSnap.docs.forEach(doc => {
            batch.update(doc.ref, {
                isOnline: false,
                status: "offline",
                lastSeen: admin.firestore.FieldValue.serverTimestamp()
            });
            count++;
        });

        await batch.commit();
        res.send(`Successfully reset ${count} drivers to OFFLINE. Please ask all real drivers to re-login.`);
    } catch (error) {
        console.error("Reset Failed:", error);
        res.status(500).send("Reset Failed: " + error);
    }
});

/**
 * DISTRIBUTE RENTAL TO DRIVERS
 * Identical logic to distributeRideToDrivers but for 'rental_requests'
 */
export const distributeRentalToDrivers = onDocumentWritten(
    {
        document: "rental_requests/{rideId}",
        timeoutSeconds: 300,
    },
    async (event) => {
        const change = event.data;
        if (!change) return null;

        const afterData = change.after.data();
        if (!afterData) return null;

        const beforeData = change.before.exists ? change.before.data() : null;
        const rideId = event.params.rideId;

        const isNew = !beforeData;
        const isStatusChange = beforeData && beforeData.status !== "searching" && afterData.status === "searching";

        if (!isNew && !isStatusChange && afterData.status === "searching") {
            return null;
        }

        if (afterData.status !== "searching") {
            return null;
        }

        console.log(`Searching drivers for rental ${rideId}...`);

        try {
            const pickupGeo = afterData.pickupLocation;
            // Handle both GeoPoint and Map (User Request schema variation)
            let lat = 0, lng = 0;
            if (pickupGeo.latitude) { lat = pickupGeo.latitude; lng = pickupGeo.longitude; }
            else if (pickupGeo.lat) { lat = pickupGeo.lat; lng = pickupGeo.lng; }

            if (!lat || !lng) {
                console.error("No valid pickup location found");
                return null;
            }

            const driversSnap = await db.collection("drivers")
                .where("isOnline", "==", true)
                .where("status", "==", "active")
                .get();

            const drivers: any[] = [];

            driversSnap.forEach(doc => {
                const dData = doc.data();
                if (dData.currentLocation) {
                    const dist = calculateDistance(
                        lat, lng,
                        dData.currentLocation.latitude,
                        dData.currentLocation.longitude
                    );
                    if (dist <= 50) {
                        drivers.push({ id: doc.id, distance: dist, data: dData });
                    }
                }
            });

            if (drivers.length === 0) {
                console.log("No drivers found nearby for rental.");
                return null;
            }

            drivers.sort((a, b) => a.distance - b.distance);
            console.log(`Found ${drivers.length} drivers for rental. Nearest: ${drivers[0].id}`);

            const firstDriver = drivers[0];
            const potentialDriverIds = drivers.map(d => d.id);

            await change.after.ref.update({
                driverId: firstDriver.id,
                currentDriverIndex: 0,
                potentialDrivers: potentialDriverIds,
                notifiedAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            console.log(`Assigned rental ${rideId} to ${firstDriver.id}`);

        } catch (e) {
            console.error("Error distributing rental:", e);
        }
        return null;
    }
);

/**
 * HANDLE RENTAL REJECTION
 * Identical logic to handleRideRejection but for 'rental_requests'
 */
export const handleRentalRejection = onDocumentUpdated(
    "rental_requests/{rideId}",
    async (event) => {
        const change = event.data;
        if (!change) return null;

        const beforeData = change.before.data();
        const afterData = change.after.data();
        const rideId = event.params.rideId;

        if (afterData.status === "searching") {
            const oldRejected = beforeData.rejectedBy || [];
            const newRejected = afterData.rejectedBy || [];

            if (newRejected.length > oldRejected.length) {
                const potentialDrivers = afterData.potentialDrivers || [];
                const allRejected = new Set(newRejected);

                let nextDriverId = null;
                let nextIndex = 0;
                let startIndex = (afterData.currentDriverIndex || 0) + 1;

                for (let i = 0; i < potentialDrivers.length; i++) {
                    const idx = (startIndex + i) % potentialDrivers.length;
                    const dId = potentialDrivers[idx];

                    if (!allRejected.has(dId)) {
                        nextDriverId = dId;
                        nextIndex = idx;
                        break;
                    }
                }

                if (nextDriverId) {
                    console.log(`Re-assigning rental ${rideId} to next driver ${nextDriverId}`);
                    await change.after.ref.update({
                        driverId: nextDriverId,
                        currentDriverIndex: nextIndex,
                        notifiedAt: admin.firestore.FieldValue.serverTimestamp(),
                    });
                } else {
                    console.log("No more drivers available for rental. Checking for cycle reset...");
                    if (potentialDrivers.length > 0) {
                        const firstDriver = potentialDrivers[0];
                        console.log(`Rental Cycle reset: Re-assigning ${rideId} to ${firstDriver}`);

                        await change.after.ref.update({
                            rejectedBy: [],
                            driverId: firstDriver,
                            currentDriverIndex: 0,
                            notifiedAt: admin.firestore.FieldValue.serverTimestamp(),
                        });
                    }
                }
            }
        }
        return null;
    }
);

/**
 * Seed Chennai Airport Geofence
 * HTTP Trigger to manually populate the database
 */

