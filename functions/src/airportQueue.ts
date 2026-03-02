import * as admin from "firebase-admin";
import { onDocumentUpdated, onDocumentCreated, onDocumentDeleted } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";

// ------------------------------------------------------------------
// 1. Invalid Driver Prevention (Remove from queue if offline/on_trip)
// ------------------------------------------------------------------
export const removeInvalidAirportDrivers = onDocumentUpdated(
    { document: "drivers/{driverId}", region: "asia-south1" },
    async (event) => {
        const dData = event.data?.after.data();
        if (!dData) return;

        // If driver is no longer online or is on a trip
        if (dData.status !== "online" || dData.status === "on_trip" || dData.isBusy) {
            const driverId = event.params.driverId;

            const db = getFirestore();
            // Query all airport queues for this driver and remove them
            const snap = await db.collectionGroup('drivers').where('driverId', '==', driverId).get();
            if (snap.empty) return;

            const batch = db.batch();
            snap.docs.forEach(doc => {
                // Ensure we are only deleting from airport_queues
                if (doc.ref.path.includes('airport_queues')) {
                    batch.delete(doc.ref);
                }
            });
            await batch.commit();
        }
    }
);

// ------------------------------------------------------------------
// 2. Auto Heartbeat Cleanup (Ghost drivers)
// ------------------------------------------------------------------
export const cleanupGhostAirportDrivers = onSchedule(
    { schedule: "every 1 minutes", region: "asia-south1", timeoutSeconds: 120 },
    async (event) => {
        // Last heartbeat > 3 minutes ago
        const threshold = admin.firestore.Timestamp.fromMillis(Date.now() - 3 * 60 * 1000);

        // Currently we just have MAA, but this can be queried dynamically or statically listed
        const queues = ['MAA'];

        const db = getFirestore();
        for (const airportId of queues) {
            const driversSnap = await db.collection(`airport_queues/${airportId}/drivers`)
                .where('lastHeartbeat', '<', threshold)
                .get();

            if (driversSnap.empty) continue;

            const batch = db.batch();
            driversSnap.docs.forEach(doc => batch.delete(doc.ref));
            await batch.commit();
            console.log(`Cleaned up ${driversSnap.size} ghost drivers from ${airportId} queue.`);
        }
    }
);

// ------------------------------------------------------------------
// 3. Backend Position Calculator
// ------------------------------------------------------------------
// Whenever a driver joins or leaves the queue, recalculate positions for everyone
const recalculatePositionsForQueue = async (airportId: string) => {
    const db = getFirestore();
    const snap = await db.collection(`airport_queues/${airportId}/drivers`)
        .orderBy("entryTimestamp", "asc")
        .get();

    if (snap.empty) return;

    const batch = db.batch();
    let currentPosition = 1;

    snap.docs.forEach(doc => {
        // Only update if position has changed to save writes
        if (doc.data().position !== currentPosition) {
            batch.update(doc.ref, { position: currentPosition });
        }
        currentPosition++;
    });

    await batch.commit();
    console.log(`Recalculated positions for ${snap.size} drivers in ${airportId} queue.`);
};

export const onQueueDriverAdded = onDocumentCreated(
    { document: "airport_queues/{airportId}/drivers/{driverId}", region: "asia-south1" },
    async (event) => {
        const airportId = event.params.airportId;
        await recalculatePositionsForQueue(airportId);
    }
);

export const onQueueDriverRemoved = onDocumentDeleted(
    { document: "airport_queues/{airportId}/drivers/{driverId}", region: "asia-south1" },
    async (event) => {
        const airportId = event.params.airportId;
        await recalculatePositionsForQueue(airportId);
    }
);

// ------------------------------------------------------------------
// 4. Strict FIFO assignAirportRide (Called passing from index.ts)
// ------------------------------------------------------------------
export const assignAirportRide = async (airportId: string, rideId: string, rideData: any): Promise<boolean> => {
    console.log(`[Queue] Starting strict FIFO assignment for Ride ${rideId} at ${airportId}`);

    const db = getFirestore();
    const queueSnap = await db.collection(`airport_queues/${airportId}/drivers`)
        .orderBy("entryTimestamp", "asc")
        .limit(10)
        .get();

    if (queueSnap.empty) {
        console.log(`[Queue] Airport Queue is empty for ${airportId}.`);
        return false;
    }

    const rideRef = db.collection("rides").doc(rideId);
    // Use rejectedBy to avoid looping over drivers that already rejected or timed out
    const rejectedBy = new Set(rideData.rejectedBy || []);

    let assigned = false;

    // Sequential Loop
    for (const queueDoc of queueSnap.docs) {
        const dId = queueDoc.id;
        const qData = queueDoc.data();

        // Check if driver already rejected
        if (rejectedBy.has(dId)) continue;

        // Verify driver state from profile
        const driverDoc = await db.collection("drivers").doc(dId).get();
        if (!driverDoc.exists) continue;
        const dData = driverDoc.data()!;

        // STRICT FIFO CHECKS
        if (qData.status === "queued" && qData.lockedForRide !== true && dData.status === "online" && !dData.isBusy) {
            console.log(`[Queue] Offering ride to Driver ${dId} in position ${qData.position}`);

            // 1. Lock driver in queue
            await queueDoc.ref.update({
                status: "offered",
                lockedForRide: true,
                currentOfferRideId: rideId
            });

            const expiresAt = admin.firestore.Timestamp.fromMillis(Date.now() + 5000);
            const requestRef = db.doc(`ride_requests/${dId}/requests/${rideId}`);

            // Deduplication - if request already exists somehow, skip
            if ((await requestRef.get()).exists) {
                // Unlock and skip
                await queueDoc.ref.update({ status: "queued", lockedForRide: false, currentOfferRideId: "" });
                continue;
            }

            // 2. Create Ride Request for driver app to see
            await requestRef.set({
                rideId: rideId,
                riderId: rideData.riderId || "",
                pickupLocation: rideData.pickupLocation,
                destinationLocation: rideData.destinationLocation || rideData.pickupLocation,
                fareEstimate: rideData.fare || rideData.fareEstimate || 0,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                expiresAt: expiresAt,
                status: "pending",
                vehicleType: rideData.vehicleType || "Unknown",
                isAirportRide: true
            });

            // Mark central ride doc
            await rideRef.update({
                currentDriverIndex: 0,
                potentialDrivers: [dId],
                notifiedAt: admin.firestore.FieldValue.serverTimestamp(),
                isAirportRide: true
            });

            // 3. WAIT exactly 5 seconds
            await new Promise((resolve) => setTimeout(resolve, 5000));

            // 4. CHECK IF ACCEPTED
            const checkRide = await rideRef.get();
            if (checkRide.data()?.status === "accepted") {
                console.log(`[Queue] Driver ${dId} accepted the airport ride! Terminating FIFO loop.`);
                assigned = true;
                break; // Break loop, mission accomplished
            } else {
                console.log(`[Queue] Driver ${dId} missed/rejected the offer. Unlocking and moving to next.`);
                // Expire request
                await requestRef.update({ status: "expired" }).catch(() => { });

                // Track rejection
                await rideRef.update({
                    rejectedBy: admin.firestore.FieldValue.arrayUnion(dId)
                });

                // Unlock driver in queue, increment skip count
                await queueDoc.ref.update({
                    status: "queued",
                    lockedForRide: false,
                    currentOfferRideId: "",
                    skipCount: admin.firestore.FieldValue.increment(1)
                });
            }
        }
    }

    return assigned;
};

// ------------------------------------------------------------------
// 5. acceptAirportRide (Atomic Transaction)
// ------------------------------------------------------------------
export const acceptAirportRide = onCall({ region: "asia-south1" }, async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Must be logged in');

    const driverId = request.auth.uid;
    const { rideId, airportId = 'MAA' } = request.data;

    if (!rideId) throw new HttpsError('invalid-argument', 'rideId is required');

    const db = getFirestore();
    const rideRef = db.collection('rides').doc(rideId);
    const driverQueueRef = db.collection(`airport_queues/${airportId}/drivers`).doc(driverId);
    const driverRef = db.collection('drivers').doc(driverId);

    try {
        await db.runTransaction(async (tx) => {
            const rideDoc = await tx.get(rideRef);

            if (!rideDoc.exists || rideDoc.data()?.status !== "searching") {
                throw new Error("Ride already taken or cancelled");
            }

            // 1. Mark Ride accepted
            tx.update(rideRef, {
                status: "accepted",
                driverId: driverId,
                acceptedAt: admin.firestore.FieldValue.serverTimestamp(),
                isAirportRide: true
            });

            // 2. Mark Driver busy locally
            tx.update(driverRef, { isBusy: true });

            // 3. Remove driver from Airport Queue (This will trigger position recalculation for everyone else)
            // Or we could verify if he was actually in it first:
            const queueDoc = await tx.get(driverQueueRef);
            if (queueDoc.exists) {
                tx.delete(driverQueueRef);
            }
        });

        // Async cleanup: Clear local pending ride requests for this driver
        const myRequestsSnap = await db.collection(`ride_requests/${driverId}/requests`).where('status', '==', 'pending').get();
        const batch = db.batch();
        myRequestsSnap.docs.forEach(doc => {
            if (doc.id !== rideId) batch.delete(doc.ref);
        });
        await batch.commit();

        return { success: true };
    } catch (e: any) {
        console.error("Airport Accept failed:", e);
        throw new HttpsError('aborted', e.message || "Ride already taken");
    }
});
