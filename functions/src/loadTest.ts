import * as admin from "firebase-admin";

// CONFIG
const DRIVER_COUNT = 10;
const RIDE_COUNT = 20;
const TEST_DURATION_MS = 60000; // 60 seconds
const POLL_INTERVAL_MS = 2000;  // 2 seconds
const CENTER_LAT = 13.0827;
const CENTER_LNG = 80.2707;

export async function runLoadTest() {
    if (admin.apps.length === 0) {
        admin.initializeApp();
    }
    const db = admin.firestore();

    console.log("=== STARTING LOAD TEST ===");

    // 1. Create Drivers
    const driverIds: string[] = [];
    const batch = db.batch();

    for (let i = 0; i < DRIVER_COUNT; i++) {
        const driverId = `test_driver_${i}`;
        driverIds.push(driverId);

        const driverRef = db.collection("drivers").doc(driverId);
        batch.set(driverRef, {
            id: driverId,
            name: `Test Driver ${i}`,
            isOnline: true,
            status: "active", // Ready for ride
            vehicleType: "Sedan",
            vehicleClass: "Sedan",
            // Location: tight cluster around center
            currentLocation: new admin.firestore.GeoPoint(CENTER_LAT, CENTER_LNG),
            dutyPreferences: { daily_Sedan: true },
            updatedAt: admin.firestore.FieldValue.serverTimestamp()
        });
    }
    await batch.commit();
    console.log(`Created/Reset ${DRIVER_COUNT} drivers.`);

    // 2. Create Rides
    const rideIds: string[] = [];
    const rideBatch = db.batch(); // Batches limit is 500, we are fine

    for (let i = 0; i < RIDE_COUNT; i++) {
        const rideId = `test_ride_${i}`;
        rideIds.push(rideId);

        const rideRef = db.collection("ride_requests").doc(rideId);
        rideBatch.set(rideRef, {
            rideId: rideId,
            userId: "test_user_load",
            status: "searching",
            pickupLocation: new admin.firestore.GeoPoint(CENTER_LAT, CENTER_LNG),
            vehicleType: "Sedan",
            vehicleClass: "Sedan",
            rideType: "daily",
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            // Clear previous test state
            rejectedBy: [],
            potentialDrivers: []
        });
    }
    await rideBatch.commit();
    console.log(`Created/Reset ${RIDE_COUNT} rides.`);

    // 3. Simulation Loop
    console.log(`Starting simulation loop for ${TEST_DURATION_MS / 1000}s...`);

    const startTime = Date.now();

    while (Date.now() - startTime < TEST_DURATION_MS) {
        // Find assigned rides
        // Note: In real app, each driver listens. Here we query all test rides.

        // Query rides assigned to ANY of our test drivers
        // Firestore 'in' query supports up to 10
        // We have exactly 10 drivers, so we can use 'in' query!

        const assignedSnap = await db.collection("ride_requests")
            .where("driverId", "in", driverIds)
            .get();

        if (!assignedSnap.empty) {
            const updates = db.batch();
            let updateCount = 0;

            assignedSnap.docs.forEach(doc => {
                const data = doc.data();
                const currentDriver = data.driverId;

                // Simulate "Pass"
                console.log(`[SIM] Driver ${currentDriver} REJECTING Ride ${doc.id}`);

                updates.update(doc.ref, {
                    rejectedBy: admin.firestore.FieldValue.arrayUnion(currentDriver),
                    // We don't change status, we just reject. 
                    // The Cloud Function 'handleRideRejection' should pick this up.
                    lastRejectedAt: admin.firestore.FieldValue.serverTimestamp() // Force update trigger
                });
                updateCount++;
            });

            if (updateCount > 0) {
                await updates.commit();
                console.log(`[SIM] Processed ${updateCount} rejections.`);
            }
        } else {
            // console.log("[SIM] No rides assigned to test drivers yet...");
        }

        // Wait
        await new Promise(r => setTimeout(r, POLL_INTERVAL_MS));
    }

    console.log("=== LOAD TEST COMPLETE ===");
}

export async function cleanupTestDrivers() {
    if (admin.apps.length === 0) {
        admin.initializeApp();
    }
    const db = admin.firestore();

    console.log("=== STARTING AGGRESSIVE CLEANUP ===");

    const batch = db.batch();
    let count = 0;

    // 1. Delete ALL drivers starting with "test_driver_"
    // We use the special FieldPath.documentId() to query by Key
    const driversSnap = await db.collection("drivers")
        .where(admin.firestore.FieldPath.documentId(), ">=", "test_driver_")
        .where(admin.firestore.FieldPath.documentId(), "<", "test_driver_\uf8ff")
        .get();

    console.log(`Found ${driversSnap.size} test drivers to delete.`);

    driversSnap.docs.forEach(doc => {
        batch.delete(doc.ref);
        count++;
    });

    // 2. Delete ALL rides starting with "test_ride_"
    const ridesSnap = await db.collection("ride_requests")
        .where(admin.firestore.FieldPath.documentId(), ">=", "test_ride_")
        .where(admin.firestore.FieldPath.documentId(), "<", "test_ride_\uf8ff")
        .get();

    console.log(`Found ${ridesSnap.size} test rides to delete.`);

    ridesSnap.docs.forEach(doc => {
        batch.delete(doc.ref);
        count++;
    });

    if (count > 0) {
        await batch.commit();
    }

    console.log(`Deleted ${count} test documents.`);
    console.log("=== CLEANUP COMPLETE ===");
}
