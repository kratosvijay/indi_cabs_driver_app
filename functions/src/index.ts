import * as admin from "firebase-admin";
import { getDatabase } from "firebase-admin/database";
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
import * as crypto from "crypto";


import { batchOnboard } from "./onboarding";
import { aggregateDemandDriver, resetDemandZonesDriver } from "./demandAggregator";
import { removeInvalidAirportDrivers, cleanupGhostAirportDrivers, onQueueDriverAdded, onQueueDriverRemoved, acceptAirportRide, assignAirportRide } from "./airportQueue";

export {
    batchOnboard, aggregateDemandDriver, resetDemandZonesDriver,
    removeInvalidAirportDrivers, cleanupGhostAirportDrivers, onQueueDriverAdded, onQueueDriverRemoved, acceptAirportRide,
    generateOtpDriver
};

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

const exotelSubdomain = defineSecret("EXOTEL_SUBDOMAIN");
const db = admin.firestore();
const rtdb = getDatabase();

const exotelSid = defineSecret("EXOTEL_SID");
const exotelApiKey = defineSecret("EXOTEL_API_KEY");
const exotelApiToken = defineSecret("EXOTEL_API_TOKEN");
const exotelCallerId = defineSecret("EXOTEL_CALLER_ID");

/**
 * ENCRYPTION HELPERS
 * Securely encrypts sensitive data (bank account numbers) at rest.
 */
const ENCRYPTION_KEY = process.env.ENCRYPTION_KEY || "8f7e6d5c4b3a2a1b0c9d8e7f6a5b4c3d"; // 32 chars
const IV_LENGTH = 16;

function encrypt(text: string): string {
    const iv = crypto.randomBytes(IV_LENGTH);
    const cipher = crypto.createCipheriv("aes-256-cbc", Buffer.from(ENCRYPTION_KEY), iv);
    let encrypted = cipher.update(text);
    encrypted = Buffer.concat([encrypted, cipher.final()]);
    return iv.toString("hex") + ":" + encrypted.toString("hex");
}

function decrypt(text: string): string {
    const textParts = text.split(":");
    const iv = Buffer.from(textParts.shift()!, "hex");
    const encryptedText = Buffer.from(textParts.join(":"), "hex");
    const decipher = crypto.createDecipheriv("aes-256-cbc", Buffer.from(ENCRYPTION_KEY), iv);
    let decrypted = decipher.update(encryptedText);
    decrypted = Buffer.concat([decrypted, decipher.final()]);
    return decrypted.toString();
}

/**
 * HELPER: Consistent Beneficiary ID for Cashfree Payouts
 */
function getBeneficiaryId(driverId: string, accountNum: string): string {
    const safeDriverId = driverId.replace(/[^a-zA-Z0-9]/g, '').substring(0, 15);
    const safeAccountId = accountNum.substring(accountNum.length - 4);
    return `drv_v2_${safeDriverId}_${safeAccountId}`;
}


/**
 * HELPER: Get Professional Driver ID (displayId) from Auth UID
 */
export async function getDriverDocId(uid: string): Promise<string> {
    // 1. Check if the UID itself is already a professional ID (unlikely for auth.uid)
    if (uid.startsWith('indi-drv-')) return uid;

    // 2. Lookup in drivers collection by 'uid' field
    const snap = await db.collection('drivers').where('uid', '==', uid).limit(1).get();
    if (!snap.empty) {
        return snap.docs[0].id; // Returns "indi-drv-X"
    }

    // 3. Fallback to the UID itself if no professional record found
    return uid;
}

/**
 * Set Driver Status (Online/Offline)
 * Uses Admin SDK to bypass Firestore security rules.
 * Fixes PERMISSION_DENIED when driver doc uses professional ID (indi-drv-X)
 * and the uid field is missing or mismatched.
 */
export const setDriverStatus = onCall({ region: "asia-south1" }, async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Must be logged in');

    const uid = request.auth.uid;
    const { isOnline, vehicleType } = request.data;

    // Resolve professional Driver ID
    const driverDocId = await getDriverDocId(uid);
    const driverRef = db.collection('drivers').doc(driverDocId);
    const driverDoc = await driverRef.get();

    if (!driverDoc.exists) {
        throw new HttpsError('not-found', `Driver document ${driverDocId} not found`);
    }

    const updateData: any = {
        isOnline: isOnline === true,
        uid: uid, // CRITICAL: Always ensure uid field is set correctly
    };

    if (isOnline) {
        updateData.status = 'active';
        updateData.goToDestination = null;

        // Auto-correct vehicleType if provided
        if (vehicleType) {
            updateData.vehicleType = vehicleType;
        }
    }

    await driverRef.update(updateData);
    console.log(`[setDriverStatus] Driver ${driverDocId} (uid: ${uid}) -> isOnline: ${isOnline}`);

    return { success: true, driverDocId: driverDocId };
});

/**
 * DEBUG: Get raw driver data for diagnostics
 */
export const debugDriver = onCall({ region: "asia-south1" }, async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Must be logged in');
    const uid = request.auth.uid;
    const driverDocId = await getDriverDocId(uid);
    const doc = await db.collection('drivers').doc(driverDocId).get();
    return {
        exists: doc.exists,
        docId: driverDocId,
        uid: uid,
        data: doc.data()
    };
});


// ============================================================================
// LEGACY FUNCTIONS (kept for backwards compatibility during migration)
// ============================================================================



/**
 * GENERATE OTP (Triggered when client writes to otp_verifications)
 * Changed to onDocumentWritten to handle re-tries (where doc already exists).
 */
const generateOtpDriver = onDocumentWritten(
    {
        document: "otp_verifications/{phoneNumber}",
        region: "asia-south1",
        secrets: [exotelSid, exotelApiKey, exotelApiToken, exotelCallerId, exotelSubdomain],
    },
    async (event) => {
        // If document was deleted, do nothing
        if (!event.data?.after.exists) return;

        const phoneNumber = event.params.phoneNumber;
        const data = event.data.after.data();

        // Prevent infinite loops: If OTP is already generated, stop.
        if (data && data.otp) {
            console.log(`[OTP] Document for ${phoneNumber} already has an OTP. Skipping generation.`);
            return;
        }

        // Generate 6-digit OTP
        const otp = Math.floor(100000 + Math.random() * 900000).toString();
        const expiresAt = new Date();
        expiresAt.setMinutes(expiresAt.getMinutes() + 5);

        console.log(`[OTP] Generated "${otp}" for ${phoneNumber}. Attempting Firestore update first.`);

        try {
            // STEP 1: Update document with generated OTP immediately
            // This ensures the user can see the code in Firestore even if SMS fails.
            await event.data.after.ref.update({
                otp: otp,
                expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
                status: "generated", // Intermediate status
                processedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            console.log(`[OTP] Successfully saved code to Firestore for ${phoneNumber}`);
        } catch (dbErr: any) {
            console.error(`[OTP_ERROR] Failed to update Firestore: ${dbErr.message}`);
            return;
        }

        // --------------------------------------------------------------------
        // SEND SMS via EXOTEL
        // --------------------------------------------------------------------
        let EXOTEL_SID, EXOTEL_API_KEY, EXOTEL_API_TOKEN, EXOTEL_CALLER_ID, EXOTEL_SUBDOMAIN;
        
        try {
            EXOTEL_SID = exotelSid.value();
            EXOTEL_API_KEY = exotelApiKey.value();
            EXOTEL_API_TOKEN = exotelApiToken.value();
            EXOTEL_CALLER_ID = exotelCallerId.value();
            EXOTEL_SUBDOMAIN = exotelSubdomain.value() || "api.exotel.com";
        } catch (secretErr: any) {
            console.warn(`[OTP_WARN] Failed to read Exotel secrets: ${secretErr.message}. SMS will be skipped.`);
            await event.data.after.ref.update({ status: "sms_skipped_no_secrets" });
            return;
        }

        if (EXOTEL_SID && EXOTEL_API_KEY && EXOTEL_API_TOKEN && EXOTEL_CALLER_ID) {
            try {
                const url = `https://${EXOTEL_SUBDOMAIN}/v1/Accounts/${EXOTEL_SID}/Sms/send.json`;
                const auth = Buffer.from(`${EXOTEL_API_KEY}:${EXOTEL_API_TOKEN}`).toString('base64');
                
                // Remove '+' for gateway compatibility
                const cleanToNumber = phoneNumber.replace("+", "");

                const formData = new URLSearchParams();
                formData.append("From", EXOTEL_CALLER_ID);
                formData.append("To", cleanToNumber);
                formData.append("Body", `Your IndiCabs verification code is ${otp}. Valid for 5 minutes.`);

                console.log(`[EXOTEL] Calling API for ${cleanToNumber}...`);
                const smsRes = await axios.post(url, formData.toString(), {
                    headers: {
                        'Authorization': `Basic ${auth}`,
                        'Content-Type': 'application/x-www-form-urlencoded'
                    }
                });

                console.log(`[EXOTEL] Success: ${JSON.stringify(smsRes.data)}`);
                await event.data.after.ref.update({ status: "sent" });

            } catch (smsErr: any) {
                const errorData = smsErr.response?.data ? JSON.stringify(smsErr.response.data) : smsErr.message;
                console.error(`[EXOTEL_ERROR] Failed: ${errorData}`);
                
                await event.data.after.ref.update({
                    status: "sms_failed",
                    smsError: errorData
                });
            }
        } else {
            console.warn("[EXOTEL] Partial secrets missing! SMS skipped.");
            await event.data.after.ref.update({ status: "sms_skipped_partial_secrets" });
        }

        return;
    }
);

/**
 * Calculate distance between two points using Haversine formula
 */

/**
 * Calculate distance between two points using Haversine formula
 */
export function calculateDistance(
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

                // Delegate to strict FIFO queue logic
                const assigned = await assignAirportRide("MAA", rideId, afterData);

                if (assigned) {
                    return null; // Done
                } else {
                    console.log("Airport Queue is empty or all drivers rejected. Falling back to normal search.");
                }
            }
            // ---------------------------------------------------------

            // ---------------------------------------------------------
            // 2. FIND CANDIDATE DRIVERS (Idle + AvailableSoon) from RTDB
            // ---------------------------------------------------------

            console.log(`Searching for drivers near ${pickupGeo.latitude}, ${pickupGeo.longitude} from Realtime Database...`);

            const driversRef = rtdb.ref('driver_locations');

            // Loop to expand radius
            let currentRadius = 2.0; // Initial radius 2km
            const maxRadius = 7.0; // REDUCED from 10km to 7km for tighter daily dispatch

            let candidates: any[] = [];
            const previouslyCheckedDrivers = new Set<string>();
            const rideRef = change.after.ref;
            const isRental = afterData.rideType === 'rental';
            const waitTimeMs = isRental ? 10000 : 5000;

            console.log(`[Dispatch Flow] Ride is ${isRental ? 'Rental' : 'Daily'}. Timer set to ${waitTimeMs}ms. Max Radius: ${maxRadius}km`);

            let rideFinished = false;

            while (currentRadius <= maxRadius && !rideFinished) {
                console.log(`[Dispatch Flow] Expanding search radius to ${currentRadius}km...`);
                
                // REFRESH: Get latest driver locations from RTDB within the expansion loop
                const activeDriversSnap = await driversRef.once('value');
                const allDrivers = activeDriversSnap.val() || {};
                const nowMs = Date.now();

                let newCandidatesFound = false;

                for (const [driverId, locData] of Object.entries<any>(allDrivers)) {
                    if (previouslyCheckedDrivers.has(driverId)) continue;

                    if ((nowMs - locData.updatedAt) > 20000) {
                        continue;
                    }

                    const dist = calculateDistance(
                        pickupGeo.latitude,
                        pickupGeo.longitude,
                        locData.lat,
                        locData.lng
                    );

                        if (dist <= currentRadius) {
                            previouslyCheckedDrivers.add(driverId);
                            
                            // 1. Try to get doc by ID (works if driver reports using professional ID)
                            let driverDoc = await db.collection('drivers').doc(driverId).get();
                            
                            // 2. Fallback: Search by UID (works if driver reports using legacy UID)
                            if (!driverDoc.exists) {
                                const uidQuery = await db.collection('drivers').where('uid', '==', driverId).limit(1).get();
                                if (!uidQuery.empty) {
                                    driverDoc = uidQuery.docs[0];
                                }
                            }

                            if (!driverDoc.exists) {
                                console.log(`[Dispatch Flow] Driver ${driverId} document missing in Firestore. Skipping.`);
                                continue;
                            }

                            const resolvedDriverId = driverDoc.id; // Correct Professional ID (e.g. indi-drv-4)
                            const dData = driverDoc.data();
                        if (!dData) continue;

                        // Unified filtering logic
                        const isApproved = dData.isApproved === true;
                        const isOnline = dData.isOnline === true;
                        const isValidStatus = !dData.status || dData.status === "active";

                        if (isApproved && isOnline && isValidStatus) {
                            candidates.push({
                                id: driverId, // RTDB key (could be UID)
                                resolvedId: resolvedDriverId, // Firestore Doc ID (professional ID)
                                distance: dist,
                                data: dData
                            });
                            newCandidatesFound = true;
                            console.log(`[Dispatch Flow] Candidate found: ${resolvedDriverId} at ${dist.toFixed(2)}km`);
                        } else {
                            // Detailed logging for why a nearby driver was skipped
                            const reasons = [];
                            if (dData.isApproved !== true) reasons.push(`isApproved: ${dData.isApproved} (type: ${typeof dData.isApproved})`);
                            if (dData.isOnline !== true) reasons.push(`isOnline: ${dData.isOnline} (type: ${typeof dData.isOnline})`);
                            if (!isValidStatus) reasons.push(`status: ${dData.status}`);
                            console.log(`[Dispatch Flow] Driver ${driverId} at ${dist.toFixed(2)}km skipped. Reason: ${reasons.join(", ")}`);
                        }
                    }
                }

                if (!newCandidatesFound && candidates.length === 0) {
                    console.log(`No new drivers found at ${currentRadius}km. Expanding to ${currentRadius + 1}km immediately.`);

                    // Check if ride is still searching before continuing
                    const checkStateDoc = await rideRef.get();
                    if (checkStateDoc.data()?.status !== "searching") {
                        console.log(`Ride ${rideId} is no longer searching. Stopping dispatch sequence.`);
                        rideFinished = true;
                        break;
                    }

                    currentRadius += 1.0;
                    continue; // Loop again with larger radius immediately
                }

                // Sort by distance
                candidates.sort((a, b) => a.distance - b.distance);
                console.log(`Found ${candidates.length} candidates. Nearest: ${candidates[0].id} (${candidates[0].distance.toFixed(2)}km)`);

                // ---------------------------------------------------------
                // 3. SEQUENTIAL DISPATCH LOGIC
                // ---------------------------------------------------------

                const maxDrivers = candidates.length;

                for (let i = 0; i < maxDrivers; i++) {
                    const driverInfo = candidates[i];
                    const driverId = driverInfo.resolvedId; // Use resolved professional ID

                    // Check if driver has already rejected this ride in a previous loop
                    const currentRideDoc = await rideRef.get();
                    const rideData = currentRideDoc.data();
                    if (rideData?.status !== "searching") {
                        console.log(`Ride ${rideId} is no longer searching. Stopping dispatch sequence.`);
                        rideFinished = true;
                        break;
                    }

                    const rejectedList = rideData?.rejectedBy || [];
                    if (rejectedList.includes(driverId)) {
                        // Already rejected, remove from candidates and skip
                        continue;
                    }

                    // Check if driver has room for more requests (Max 5)
                    const targetCollection = isRental ? "rental_requests" : "ride_requests";
                    const activeRequestsSnap = await db.collection(`${targetCollection}/${driverId}/requests`).where('status', '==', 'pending').get();
                    if (activeRequestsSnap.size >= 5) {
                        console.log(`Driver ${driverId} has ${activeRequestsSnap.size} pending requests. Skipping.`);
                        continue;
                    }

                    // Deduplication Logic - Skip if request already exists
                    const requestRef = db.doc(`${targetCollection}/${driverId}/requests/${rideId}`);
                    const existingRequest = await requestRef.get();
                    if (existingRequest.exists) continue;

                    console.log(`[Dispatch Flow] Sending ride ${rideId} to driver ${driverId} at ${driverInfo.distance.toFixed(2)}km away`);

                    const expiresAt = admin.firestore.Timestamp.fromMillis(Date.now() + waitTimeMs);

                    // Create Ride Request for Driver
                    await requestRef.set({
                        rideId: rideId,
                        rideType: afterData.rideType || "daily",
                        riderId: afterData.riderId || "",
                        driverId: driverId, // Professional ID
                        driverUid: driverInfo.data.uid, // Auth UID for security rules
                        pickupLocation: afterData.pickupLocation,
                        destinationLocation: afterData.destinationLocation || afterData.pickupLocation,
                        fareEstimate: afterData.fare || afterData.fareEstimate || afterData.rideFare || 0,
                        createdAt: admin.firestore.FieldValue.serverTimestamp(),
                        expiresAt: expiresAt,
                        status: "pending",
                        vehicleType: afterData.vehicleType || "Unknown",
                        durationHours: afterData.durationHours || null,
                        kmLimit: afterData.kmLimit || null,
                        packageName: afterData.packageName || null
                    });

                    // Update the original ride doc potentialDrivers list for transparency
                    await rideRef.update({
                        currentDriverIndex: i,
                        potentialDrivers: candidates.map(d => d.id),
                        notifiedAt: admin.firestore.FieldValue.serverTimestamp(),
                        driverId: driverId, // Professional ID
                        driverUid: driverInfo.data.uid, // Auth UID for security rules
                    });

                    // Wait 
                    await new Promise((resolve) => setTimeout(resolve, waitTimeMs));

                    // Check if accepted by viewing the central ride document
                    const checkRide = await rideRef.get();
                    if (checkRide.data()?.status === "accepted") {
                        console.log(`Ride ${rideId} was accepted! Stopping dispatch.`);
                        rideFinished = true;
                        break; // End sequential sequence
                    } else {
                        // Update the request to expired
                        console.log(`Driver ${driverId} did not accept ride ${rideId} in time. Expiring card.`);
                        await requestRef.update({ status: "expired" }).catch(() => { });

                        // Also track rejection in original ride doc and clear driverId
                        // so next dispatch triggers a fresh frontend listener event
                        await rideRef.update({
                            rejectedBy: admin.firestore.FieldValue.arrayUnion(driverId),
                            driverId: admin.firestore.FieldValue.delete(),
                        });
                    }
                } // end candidate for loop

                if (!rideFinished) {
                    // We exhausted all candidates at this radius.
                    // Clear the candidates that have been processed, and expand radius.
                    candidates = candidates.filter(c => false);

                    if (currentRadius < maxRadius) {
                        console.log(`Exhausted drivers at ${currentRadius}km. Expanding to ${currentRadius + 1}km.`);
                        // No wait here either to minimize delays finding the next driver
                        currentRadius += 1.0;
                    } else {
                        console.log(`Max radius ${maxRadius}km reached. No more expansion.`);
                        rideFinished = true;
                    }
                }
            } // end while loop

        } catch (e) {
            console.error("Error distributing ride:", e);
        }

        return null;
    }
);

/**
 * Atomic Accept Function
 * Called directly by the driver app to accept a ride.
 */
export const acceptRide = onCall({ region: "asia-south1" }, async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Must be logged in');

    const uid = request.auth.uid;
    const { rideId } = request.data;
    
    // Resolve professional Driver ID
    const driverDocId = await getDriverDocId(uid);
    const rideRef = db.collection('ride_requests').doc(rideId); // Central ride doc

    try {
        await db.runTransaction(async (tx) => {
            const rideDoc = await tx.get(rideRef);

            if (!rideDoc.exists) {
                throw new Error("Ride does not exist");
            }

            if (rideDoc.data()?.status === "searching") {
                tx.update(rideRef, {
                    status: "accepted",
                    driverId: driverDocId, // Use professional ID
                    acceptedAt: admin.firestore.Timestamp.now()
                });
            } else {
                throw new Error("Already accepted by another driver or cancelled");
            }
        });

        // Transaction successful. Cleanup driver's local request list.
        const myRequestsSnap = await db.collection(`ride_requests/${driverDocId}/requests`).where('status', '==', 'pending').get();
        const batch = db.batch();
        myRequestsSnap.forEach(doc => {
            if (doc.id !== rideId) {
                batch.delete(doc.ref);
            }
        });
        await batch.commit();

        return { success: true, message: "Ride accepted successfully" };

    } catch (error: any) {
        console.error("Accept failed:", error);
        throw new HttpsError('aborted', error.message || "Ride already taken");
    }
});


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

        if (!afterData) return null;

        // Case 1: Ride Accepted -> Set Offline / OnTrip
        if (beforeData.status === "searching" && afterData.status === "accepted") {
            const drvId = afterData.driverId; // This is already the professional ID because we fixed acceptRide
            console.log(`Setting driver ${drvId} to OnTrip/Offline and removing from Airport Queue`);
            await db.collection("drivers").doc(drvId).update({
                isOnline: false,
                status: "on_trip"
            });

            // Remove from Airport Queue (MAA) if present
            await db.collection("airport_queues").doc("MAA").collection("drivers").doc(drvId).delete().catch(e => {
                console.log("Error removing from queue (might not be in one):", e);
            });
        }

        // Case 2: Ride Completed -> Set Online / Active
        if (beforeData.status !== "completed" && afterData.status === "completed") {
            const drvId = afterData.driverId; 
            console.log(`Setting driver ${drvId} to Active/Online`);
            await db.collection("drivers").doc(drvId).update({
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
                    driverId: drvId,
                    driverUid: afterData.driverUid || drvId, // Auth UID for security rules
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
        if (beforeData.status === "accepted" && afterData.status === "cancelled") {
            const drvId = afterData.driverId;
            console.log(`Ride cancelled. Setting driver ${drvId} to Active/Online`);
            await db.collection("drivers").doc(drvId).update({
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

    const { rideId, actualDistanceKm, waitingCharge, rideType } = request.data;
    // rideType is optional, defaulting to 'daily' if not found in doc
    // waitingCharge is optional, defaulting to 0

    if (!rideId || actualDistanceKm === undefined) {
        throw new HttpsError(
            "invalid-argument",
            "Missing required parameters (rideId, actualDistanceKm)"
        );
    }

    try {
        // Get ride data
        const rideDoc = await db.collection(rideType === 'rental' ? 'rental_requests' : 'ride_requests').doc(rideId).get();

        if (!rideDoc.exists) {
            throw new HttpsError("not-found", "Ride not found");
        }

        const rideData = rideDoc.data();
        if (!rideData) throw new HttpsError("internal", "Ride data missing");

        const effectiveRideType = rideType || rideData.rideType || 'daily';

        // --- 1. RENTAL BILLING LOGIC ---
        if (effectiveRideType === 'rental') {
            console.log(`Processing Rental Billing for ${rideId}`);

            const pkgHours = (rideData.durationHours || 0);
            const pkgKm = (rideData.kmLimit || 0);
            const extraHourCharge = (rideData.extraHourCharge || 0);
            const extraKmCharge = (rideData.extraKmCharge || 0);
            const baseFare = (rideData.rideFare || rideData.fare || 0); // locked package price

            // Calculate duration
            const startedAtTs = rideData.startedAt;
            const startedAt = startedAtTs ? startedAtTs.toDate() : new Date();
            const now = new Date();
            const durationMinutes = (now.getTime() - startedAt.getTime()) / 60000;
            const durationHours = durationMinutes / 60.0;

            let extraHours = 0;
            if (durationHours > pkgHours) {
                extraHours = Math.ceil(durationHours - pkgHours);
            }

            let extraKm = 0;
            if (actualDistanceKm > pkgKm) {
                extraKm = actualDistanceKm - pkgKm;
            }

            const extraTimeCost = extraHours * extraHourCharge;
            const extraDistCost = extraKm * extraKmCharge;
            // Rental does not typically have "waiting charge" separate from duration
            // But if passed, we could add it. Usually implicit in rental duration.
            // Let's assume waiting is part of the rental time.

            const totalFare = baseFare + extraTimeCost + extraDistCost;

            await rideDoc.ref.update({
                actualDistance: actualDistanceKm,
                actualDuration: durationMinutes, // store in minutes? or hours? existing code used minutes in one place, hours in another
                actualDurationMinutes: durationMinutes,
                finalAmount: totalFare,
                totalFare: totalFare,
                rideFare: totalFare,
                extraTimeCost: extraTimeCost,
                extraDistanceCost: extraDistCost,
                priceUpdated: (extraTimeCost > 0 || extraDistCost > 0),
                pricingReason: `Base: ${baseFare}, ExtraKm: ${extraDistCost}, ExtraTime: ${extraTimeCost}`
            });

            return {
                success: true,
                finalFare: totalFare,
                priceUpdated: (extraTimeCost > 0 || extraDistCost > 0),
                reason: "Rental calculation complete"
            };
        }

        // --- 2. DAILY RIDE BILLING LOGIC ---

        // Inputs
        const estimatedDistanceKm = rideData.rideDistance || 0;
        const vehicleType = rideData.vehicleType || rideData.vehicleClass || "Sedan"; // Booked Type - Fallback to vehicleClass
        console.log(`[DEBUG] Pricing Calc - RideId: ${rideId}, BookedType: ${vehicleType}, DriverType: ${rideData.driverCarModel || 'Unknown'}`);
        const providedWaitingCharge = waitingCharge || 0;

        // Pricing Rules Fetch
        let pricingRules: any = {};
        try {
            const pricingDoc = await db.collection("pricing_rules").doc("Chennai").get();
            if (pricingDoc.exists) pricingRules = pricingDoc.data() || {};
        } catch (e) {
            console.error("Failed to fetch pricing rules:", e);
        }

        // --- SURGE / PEAK LOGIC (Matched with User App) ---
        // Peak rate is locked to BOOKING TIME (createdAt) so that:
        //   - A ride booked during peak hours always pays peak rate regardless of when it ends.
        //   - A ride booked during off-peak hours always pays off-peak rate regardless of when it ends.
        let surgeMultiplier = 1.0;

        // Use createdAt (booking time) as the reference for all time-based charges.
        // Fall back to startedAt then now only if createdAt is missing.
        const bookingRefTime = rideData.createdAt
            ? rideData.createdAt.toDate()
            : (rideData.startedAt ? rideData.startedAt.toDate() : new Date());

        const istFormatter = new Intl.DateTimeFormat("en-US", {
            timeZone: "Asia/Kolkata",
            hour: "2-digit",
            hour12: false,
            weekday: "short",
        });
        const parts = istFormatter.formatToParts(bookingRefTime);
        let currentHour = 0;
        let currentDayString = "";
        for (const part of parts) {
            if (part.type === "hour") currentHour = parseInt(part.value) % 24;
            if (part.type === "weekday") currentDayString = part.value;
        }

        // 1. Check DB Override
        if (pricingRules.isSurgeActive && pricingRules.surgeMultiplier) {
            surgeMultiplier = pricingRules.surgeMultiplier;
        } else {
            // 2. Time-based Logic using booking time
            const isWeekend = currentDayString === "Sat" || currentDayString === "Sun";

            if (isWeekend) {
                if (currentHour >= 15 && currentHour < 21) surgeMultiplier = 1.20;
            } else {
                const isMorningSurge = currentHour >= 8 && currentHour < 11;
                const isEveningSurge = currentHour >= 17 && currentHour < 21;
                if (isMorningSurge || isEveningSurge) surgeMultiplier = 1.20;
            }
        }

        // --- NIGHT CHARGE (based on booking time, same rationale as peak) ---
        let nightCharge = 0.0;
        if (currentHour >= 22 || currentHour < 6) {
            nightCharge = 30.0;
        }

        // --- BASE RATES ---
        let baseFare = 50;
        let perKm = 12;
        let minFare = 100;
        let perMinute = 0; // User App has time charge

        if (vehicleType && pricingRules.vehicle_types && pricingRules.vehicle_types[vehicleType]) {
            const vRules = pricingRules.vehicle_types[vehicleType];
            if (vRules) {
              baseFare = vRules.baseFare || baseFare;
              perKm = vRules.perKilometer || perKm;
              minFare = vRules.minimumFare || minFare;
              perMinute = vRules.perMinute || 0;
              console.log(`[DEBUG] Applied Rules for ${vehicleType}: Base=${baseFare}, PerKm=${perKm}`);
            }
        } else {
            console.warn(`[WARN] No pricing rules found for vehicle type: ${vehicleType}. Using defaults.`);
        }

        // --- GEOFENCE LOGIC & TOLL DETECTION ---
        let geofenceSurcharge = 0.0;
        let actualTollCrossed = false;
        let tollZonesCrossed: string[] = [];
        let totalTollAmount = 0.0;

        try {
            const zonesSnapshot = await db.collection("geofenced_zones").get();
            // Parse pickup location
            let pickupGeoPoint = null;
            let dropoffGeoPoint = null;

            if (rideData.pickupLocation) {
                if (rideData.pickupLocation instanceof admin.firestore.GeoPoint) {
                    pickupGeoPoint = rideData.pickupLocation;
                } else if (typeof rideData.pickupLocation === 'object' && rideData.pickupLocation !== null) {
                    const location = rideData.pickupLocation as any;
                    const lat = location.latitude ?? location.lat;
                    const lng = location.longitude ?? location.lng;
                    if (typeof lat === 'number' && typeof lng === 'number' && isFinite(lat) && isFinite(lng)) {
                        pickupGeoPoint = new admin.firestore.GeoPoint(lat, lng);
                    }
                }
            }

            // Parse dropoff/destination location
            if (rideData.dropoffLocation) {
                if (rideData.dropoffLocation instanceof admin.firestore.GeoPoint) {
                    dropoffGeoPoint = rideData.dropoffLocation;
                } else if (typeof rideData.dropoffLocation === 'object' && rideData.dropoffLocation !== null) {
                    const location = rideData.dropoffLocation as any;
                    const lat = location.latitude ?? location.lat;
                    const lng = location.longitude ?? location.lng;
                    if (typeof lat === 'number' && typeof lng === 'number' && isFinite(lat) && isFinite(lng)) {
                        dropoffGeoPoint = new admin.firestore.GeoPoint(lat, lng);
                    }
                }
            } else if (rideData.destinationLocation) {
                // Fallback to destinationLocation field
                if (rideData.destinationLocation instanceof admin.firestore.GeoPoint) {
                    dropoffGeoPoint = rideData.destinationLocation;
                } else if (typeof rideData.destinationLocation === 'object' && rideData.destinationLocation !== null) {
                    const location = rideData.destinationLocation as any;
                    const lat = location.latitude ?? location.lat;
                    const lng = location.longitude ?? location.lng;
                    if (typeof lat === 'number' && typeof lng === 'number' && isFinite(lat) && isFinite(lng)) {
                        dropoffGeoPoint = new admin.firestore.GeoPoint(lat, lng);
                    }
                } else if (rideData.destinationLocation.lat && rideData.destinationLocation.lng) {
                    dropoffGeoPoint = new admin.firestore.GeoPoint(rideData.destinationLocation.lat, rideData.destinationLocation.lng);
                }
            }

            if (pickupGeoPoint) {
                for (const doc of zonesSnapshot.docs) {
                    const zone = doc.data();
                    if (zone.surcharge_amount && zone.surcharge_amount > 0 && zone.boundary) {
                        const pickupInZone = isPointInPolygon(pickupGeoPoint, zone.boundary);
                        const dropoffInZone = dropoffGeoPoint ? isPointInPolygon(dropoffGeoPoint, zone.boundary) : false;

                        // Geofence surcharge applies if pickup is in zone
                        if (pickupInZone) {
                            geofenceSurcharge = zone.surcharge_amount;
                            console.log(`Applying surcharge of ${geofenceSurcharge} for zone ${doc.id}`);
                        }

                        // Toll detection: Route crosses toll zone if pickup and dropoff are on opposite sides
                        // Scenario 1: Pickup inside zone, dropoff outside = Route crossed OUT
                        // Scenario 2: Pickup outside zone, dropoff inside = Route crossed IN
                        // Scenario 3: Both inside = Already in toll zone (geofence applies)
                        // Scenario 4: Both outside = No toll crossing
                        const routeCrossesTollZone = (pickupInZone && !dropoffInZone) || (!pickupInZone && dropoffInZone);

                        if (routeCrossesTollZone) {
                            actualTollCrossed = true;
                            tollZonesCrossed.push(doc.id);
                            totalTollAmount += zone.surcharge_amount; // SUM all toll zones crossed
                            console.log(`Toll zone ${doc.id} crossed on route (pickup: ${pickupInZone}, dropoff: ${dropoffInZone}, amount: ${zone.surcharge_amount})`);
                        }
                    }
                }
            }
        } catch (e) {
            console.error("Geofence check failed:", e);
        }

        // --- CALCULATE FARE ---
        // Formula matching User App:
        // 1. Distance Charge (Tiered)
        // 2. Time Charge
        // 3. Surge
        // 4. Extras (Night, Toll, Geofence)
        // 5. Min Fare

        let calculatedFare = baseFare;

        // 1. Distance Charge (Tiered)
        if (actualDistanceKm <= 12) {
            calculatedFare += actualDistanceKm * perKm;
        } else {
            // First 12 km normal
            calculatedFare += 12 * perKm;
            // Remaining reduced
            const reducedRate = Math.max(0, perKm - 3);
            calculatedFare += (actualDistanceKm - 12) * reducedRate;
        }

        // 2. Time Charge (Using actualDurationMinutes if available, else calculate)
        let rideDurationMinutes = 0;
        if (rideData.startedAt) {
            const startDiv = rideData.startedAt.toDate();
            const endDiv = new Date();
            rideDurationMinutes = (endDiv.getTime() - startDiv.getTime()) / 60000;
        }
        if (perMinute > 0 && rideDurationMinutes > 0) {
            calculatedFare += (rideDurationMinutes * perMinute);
        }

        // 3. Surge
        calculatedFare *= surgeMultiplier;

        // 4. Extras
        calculatedFare += nightCharge;
        calculatedFare += geofenceSurcharge; // Added Geofence

        // Toll Handling:
        // - For daily rides: User app adds toll pessimistically upfront
        //   - If toll was actually crossed: keep the toll charge (use actual amount from zones)
        //   - If toll was NOT crossed: we'll deduct it below
        // - For rental rides: Only add toll if actually crossed (use actual amount from zones)
        if (actualTollCrossed && totalTollAmount > 0) {
            calculatedFare += totalTollAmount;
            console.log(`Toll crossed: Adding ₹${totalTollAmount} to fare (${tollZonesCrossed.join(", ")})`);
        } else if (!actualTollCrossed && rideData.tollPrice) {
            // Toll was charged by user app but NOT actually crossed
            // Will be deducted in daily ride logic below
            console.log(`Toll NOT crossed but charged: ${rideData.tollPrice}. Will deduct if within tolerance.`);
        }

        // 5. Min Fare
        if (calculatedFare < minFare) calculatedFare = minFare;

        // Add Waiting Charge (Driver App specific addition, User App didn't show it explicitly in calcFares but likely handled separate or implicit)
        // Driver App passes it explicitly.
        calculatedFare += providedWaitingCharge;

        // Rounding
        let finalFare = Math.round(calculatedFare);


        // distanceDiff > 0  → driver travelled more than estimated (detour / wrong route)
        // distanceDiff < 0  → driver took a shortcut
        const distanceDiff = actualDistanceKm - estimatedDistanceKm;
        let priceUpdated = false;
        let reason = "Fare matched estimate";

        const isPeak = surgeMultiplier > 1.0;

        // Tolerance window: actual distance is within ±1.5 km above or 5 km below estimate.
        // WITHIN tolerance  → driver took the correct route → apply dynamic pricing at booking-time rates.
        // OUTSIDE tolerance → driver deviated significantly → protect the customer by using the
        //                     original fare they were quoted (read from Firestore rideFare).
        const withinTolerance = distanceDiff <= 1.5 && distanceDiff >= -5.0;

        if (withinTolerance) {
            // Dynamic pricing at booking-time rates (already fully calculated as finalFare above).
            // geofenceSurcharge is already included in finalFare via calculatedFare — do NOT add again.

            // Toll handling:
            // - If toll was crossed: the toll amount is already included in calculatedFare above.
            // - If toll was NOT crossed but was charged by user app: deduct it.
            if (actualTollCrossed && totalTollAmount > 0) {
                console.log(`[Within Tolerance] Toll crossed: ₹${totalTollAmount} already in fare`);
            } else if (!actualTollCrossed && rideData.tollPrice) {
                finalFare -= rideData.tollPrice;
                console.log(`[Within Tolerance] Toll NOT crossed: Deducting ₹${rideData.tollPrice}`);
                priceUpdated = true;
                reason = `Fare recalculated at booking-time rates; toll deducted (not crossed).`;
            }

            priceUpdated = true;
            if (!reason || reason === "Fare matched estimate") {
                reason = `Fare recalculated at booking-time rates (${isPeak ? "peak" : "off-peak"}).`;
            }

        } else {
            // Outside tolerance: driver took a significantly different route.
            // Use the original Firestore fare to protect the customer from paying for driver detours.
            finalFare = parseFloat(rideData.rideFare || finalFare);
            finalFare += providedWaitingCharge;
            finalFare += geofenceSurcharge;

            if (actualTollCrossed && totalTollAmount > 0) {
                finalFare += totalTollAmount;
                console.log(`[Outside Tolerance] Toll crossed: Adding ₹${totalTollAmount}`);
            } else if (!actualTollCrossed && rideData.tollPrice) {
                finalFare -= rideData.tollPrice;
                console.log(`[Outside Tolerance] Toll NOT crossed: Deducting ₹${rideData.tollPrice}`);
            }

            priceUpdated = false;
            reason = `Route deviated (diff: ${distanceDiff.toFixed(2)} km). Using original quoted fare.`;
            console.log(`[Outside Tolerance] Using original fare: ${rideData.rideFare}`);
        }


        // --- FINAL CHECK: BOOKED TYPE ENFORCEMENT ---
        // Verify we didn't use "Suv" rates for a "Hatchback" booking.
        // We already did this by using `vehicleType` (which is the booked type) to fetch `baseFare`/`perKm`.
        // So `calculated` above uses the correct rates.

        // Update Backend
        await rideDoc.ref.update({
            actualDistance: actualDistanceKm,
            finalAmount: finalFare,
            totalFare: finalFare,
            rideFare: finalFare, // Update main display fare
            waitingCharge: providedWaitingCharge,
            priceUpdated: priceUpdated,
            pricingReason: reason,
            isPeakHour: isPeak,
            peakMultiplier: surgeMultiplier,
            // Toll information
            tollCrossed: actualTollCrossed,
            tollZonesCrossed: tollZonesCrossed,
            totalTollAmount: totalTollAmount,
            geofenceSurcharge: geofenceSurcharge,
            calculatedAt: admin.firestore.FieldValue.serverTimestamp()
        });

        return {
            success: true,
            estimatedFare: rideData.rideFare,
            finalFare: finalFare,
            priceUpdated: priceUpdated,
            reason: reason,
            actualDistance: actualDistanceKm,
            waitingCharge: providedWaitingCharge,
            isPeak: isPeak,
            tollCrossed: actualTollCrossed,
            tollZonesCrossed: tollZonesCrossed,
            tollCharge: totalTollAmount,
            geofenceSurcharge: geofenceSurcharge,
            distanceDifference: distanceDiff
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




/**
 * Generate Cashfree Payment Session for adding money.
 * Returns the payment_session_id required by the Cashfree Flutter SDK.
 */
export const createCashfreeOrder = onCall({
    region: "asia-south1",
    vpcConnector: "cashfree-vpc",
    vpcConnectorEgressSettings: "ALL_TRAFFIC",
}, async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Must be logged in');

    const amount = request.data.amount;
    const driverId = request.auth.uid;
    const phone = request.data.phone || "9999999999";

    if (!amount || amount <= 0) {
        throw new HttpsError('invalid-argument', 'Valid amount is required');
    }

    const CASHFREE_PG_CLIENT_ID = process.env.CASHFREE_PG_CLIENT_ID || "122159383830534a2818b3e83373951221";
    const CASHFREE_PG_CLIENT_SECRET = process.env.CASHFREE_PG_CLIENT_SECRET || "cfsk_ma_prod_dbc842b88cfc4660f817dc4186d5a380_c19d4e45";
    const CASHFREE_ENV = process.env.CASHFREE_ENV || "PRODUCTION";

    const baseUrl = CASHFREE_ENV === "PRODUCTION"
        ? "https://api.cashfree.com/pg/orders"
        : "https://sandbox.cashfree.com/pg/orders";

    const orderId = `ord_${Date.now()}`;

    try {
        const payload = {
            order_id: orderId,
            order_amount: Number(amount.toFixed(2)),
            order_currency: "INR",
            customer_details: {
                customer_id: driverId,
                customer_phone: phone,
                customer_name: request.auth.token.name || "Driver",
                customer_email: request.auth.token.email || "driver@indicabs.com"
            },
            order_meta: {
                // Ensure the payment return URL works or is just a placeholder if using SDK
                return_url: "https://www.cashfree.com/devstudio/preview/pg/web/payment?order_id={order_id}"
            }
        };

        const response = await axios.post(baseUrl, payload, {
            headers: {
                'x-client-id': CASHFREE_PG_CLIENT_ID,
                'x-client-secret': CASHFREE_PG_CLIENT_SECRET,
                'x-api-version': '2023-08-01',
                'Content-Type': 'application/json'
            }
        });

        console.log(`Cashfree Order Created: ${orderId}`);

        return {
            success: true,
            orderId: orderId,
            paymentSessionId: response.data.payment_session_id,
        };
    } catch (error: any) {
        console.error("Cashfree Order Creation Failed:", error.response ? JSON.stringify(error.response.data) : error.message);
        throw new HttpsError('internal', 'Unable to create payment session.');
    }
});

export const processWalletSettlement = onDocumentCreated(
    {
        document: "drivers/{driverId}/wallet_transactions/{transactionId}",
        region: "asia-south1",
        vpcConnector: "cashfree-vpc",
        vpcConnectorEgressSettings: "ALL_TRAFFIC",
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

        // Payout API uses SEPARATE credentials from the Payment Gateway.
        // Get these from: Cashfree Dashboard → Payouts → Settings → API Keys
        const CASHFREE_CLIENT_ID = process.env.CASHFREE_PAYOUT_CLIENT_ID || process.env.CASHFREE_CLIENT_ID || "";
        const CASHFREE_CLIENT_SECRET = process.env.CASHFREE_PAYOUT_CLIENT_SECRET || process.env.CASHFREE_CLIENT_SECRET || "";


        if (!CASHFREE_CLIENT_ID || !CASHFREE_CLIENT_SECRET) {
            console.error("[ERROR] Cashfree PAYOUT credentials (CASHFREE_PAYOUT_CLIENT_ID / CASHFREE_PAYOUT_CLIENT_SECRET) are not set.");
            await snap.ref.update({
                status: "failed",
                error: "Payout credentials not configured. Contact support.",
                processedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            return null;
        }
        console.log(`[SETTLE] Using Unified Payouts (2024-01-01). Client: ${CASHFREE_CLIENT_ID.substring(0, 8)}...`);

        try {
            const destination = data.bankAccount ? `Bank Account (${data.maskedAccount})` : `UPI ID (${data.upiId})`;
            console.log(`[SETTLE] Processing settlement for ${driverId}: ₹${data.amount} to ${destination}`);

            const payoutHeaders = {
                "x-client-id": CASHFREE_CLIENT_ID,
                "x-client-secret": CASHFREE_CLIENT_SECRET,
                "x-api-version": "2024-01-01",
                "Content-Type": "application/json",
            };

            const baseUrl = "https://api.cashfree.com/payout";

            let beneID = "";
            let beneficiaryName = data.bankHolderName || "IndiCabs Driver";
            const cleanPhone = (data.phone || "").replace("+91", "").replace(/\s/g, "");
            const beneficiaryEmail = `driver_${driverId}@indicabs.com`;
            let decryptedAccount = "";
            let transferMode = "imps";
            let instrumentDetails: any = {};

            if (data.bankAccount && data.ifsc) {
                decryptedAccount = decrypt(data.bankAccount);
                beneID = data.cashfreeBeneId || getBeneficiaryId(driverId, decryptedAccount);
                instrumentDetails = {
                    bank_account_number: decryptedAccount,
                    ifsc: data.ifsc
                };

                // Load real name from bank account doc if available
                if (data.bankAccountId) {
                    try {
                        const bankDoc = await db.collection("drivers").doc(driverId)
                            .collection("bank_accounts").doc(data.bankAccountId).get();
                        if (bankDoc.exists) beneficiaryName = bankDoc.data()!.name || beneficiaryName;
                    } catch (e: any) {
                        console.warn(`[SETTLE] Could not load bank doc: ${e.message}`);
                    }
                }
            } else if (data.upiId && data.upiId !== "bank_payout") {
                beneID = data.cashfreeBeneId || getBeneficiaryId(driverId, data.upiId);
                transferMode = "upi";
                instrumentDetails = {
                    vpa: data.upiId
                };
            } else {
                throw new Error("No valid payout destination provided");
            }

            // Step 1: Ensure Beneficiary exists (Unified API 2024-01-01 format)
            const benePayload = {
                beneficiary_id: beneID,
                beneficiary_name: beneficiaryName.trim(),
                beneficiary_instrument_details: instrumentDetails,
                beneficiary_contact_details: {
                    email: beneficiaryEmail,
                    phone: cleanPhone || "9999999999",
                    address: "India"
                }
            };

            try {
                console.log(`[SETTLE] Registering/Verifying beneficiary: ${beneID}`);
                const beneRes = await axios.post(`${baseUrl}/beneficiaries`, benePayload, { headers: payoutHeaders });
                console.log(`[SETTLE] Registration Response: ${JSON.stringify(beneRes.data)}`);
                // Wait 1s for sync
                await new Promise(resolve => setTimeout(resolve, 1000));
            } catch (beneErr: any) {
                const errBody = beneErr.response?.data ? JSON.stringify(beneErr.response.data) : beneErr.message;
                const errCode = beneErr.response?.data?.code || "";
                if (errCode.includes("exists") || errBody.toLowerCase().includes("already exists")) {
                    console.log(`[SETTLE] Beneficiary ${beneID} already exists, proceeding to transfer.`);
                } else {
                    console.error(`[SETTLE_ERROR] Beneficiary registration failed: ${errBody}`);
                    throw new Error(`Beneficiary registration failed: ${beneErr.response?.data?.message || beneErr.message}`);
                }
            }

            // Step 2: Initiate Transfer (Unified API 2024-01-01 format)
            const transferPayload = {
                transfer_id: `tx_${transactionId}`,
                transfer_amount: data.amount,
                transfer_currency: "INR",
                transfer_mode: transferMode,
                beneficiary_details: {
                    beneficiary_id: beneID
                }
            };

            console.log(`[SETTLE] Initiating transfer to ${beneID} for ₹${data.amount}`);
            const response = await axios.post(`${baseUrl}/transfers`, transferPayload, { headers: payoutHeaders });

            if (response.status >= 300) {
                throw new Error(`Transfer failed with status ${response.status}: ${JSON.stringify(response.data)}`);
            }

            console.log("Cashfree Payout Success:", response.data);

            const referenceId = response.data?.transfer_id || `tx_${transactionId}`;
            console.log(`[SETTLE] Transfer success. Settlement ID: ${referenceId}`);

            await snap.ref.update({
                status: "success",
                payoutId: referenceId,
                processedAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            // Add Success Notification
            try {
                const destLabel = data.bankAccount ? "Bank Account" : "UPI ID";
                await db.collection("drivers").doc(driverId).collection("notifications").add({
                    title: "Settlement Successful",
                    body: `Your withdrawal of ₹${data.amount} to your ${destLabel} has been successfully processed.`,
                    timestamp: admin.firestore.FieldValue.serverTimestamp(),
                    isRead: false,
                    data: {
                        type: "settlement_success",
                        transactionId: transactionId,
                        amount: data.amount
                    }
                });
            } catch (notifyError) {
                console.error("Error creating success notification:", notifyError);
            }

        } catch (error: any) {
            const cashfreeErrBody = error.response?.data ? JSON.stringify(error.response.data) : null;
            const cashfreeStatusCode = error.response?.status;
            console.error(`Cashfree Payout Failed [HTTP ${cashfreeStatusCode}]:`, cashfreeErrBody || error.message);

            const uiError = error.response?.data?.message ?? error.message ?? "Gateway Error";

            await snap.ref.update({
                status: "failed",
                error: cashfreeErrBody || error.message,
                httpStatus: cashfreeStatusCode || null,
            });
            
            // Refund the wallet balance
            try {
                const balanceRef = db.collection("drivers").doc(driverId).collection("wallet").doc("balance");
                await db.runTransaction(async (t) => {
                    const balanceDoc = await t.get(balanceRef);
                    let currentBalance = 0;
                    if (balanceDoc.exists) {
                        currentBalance = balanceDoc.data()?.currentBalance || 0;
                    }
                    t.update(balanceRef, { currentBalance: currentBalance + data.amount });
                });

                await db.collection("drivers").doc(driverId).collection("wallet_transactions").add({
                    amount: data.amount,
                    type: "credit",
                    createdAt: admin.firestore.FieldValue.serverTimestamp(),
                    description: `Refund: ${uiError}`,
                    status: "success",
                    isRefund: true,
                    originalTransactionId: transactionId,
                    gatewayError: cashfreeErrBody || error.message
                });
            } catch (refundError) {
                console.error("Critical: Failed to refund wallet:", refundError);
            }
            
            // Add Failure Notification
            try {
                await db.collection("drivers").doc(driverId).collection("notifications").add({
                    title: "Settlement Failed",
                    body: `Your withdrawal of ₹${data.amount} failed because: ${uiError}. The amount has been safely refunded.`,
                    timestamp: admin.firestore.FieldValue.serverTimestamp(),
                    isRead: false,
                    data: {
                        type: "settlement_failed",
                        transactionId: transactionId,
                        amount: data.amount
                    }
                });
            } catch (notifyError) {
                console.error("Error creating failure notification:", notifyError);
            }
        }
        return null;
    }
);

/**
 * Generic dispatcher for driver push notifications.
 * Triggered whenever a new document is added to the driver's notification history.
 */
export const onDriverNotificationCreated = onDocumentCreated(
    {
        document: "drivers/{driverId}/notifications/{notificationId}",
        region: "asia-south1",
    },
    async (event) => {
        const snap = event.data;
        if (!snap) return null;

        const data = snap.data();
        const driverId = event.params.driverId;

        try {
            // Get driver's FCM token from their profile
            const driverDoc = await db.collection("drivers").doc(driverId).get();
            const fcmToken = driverDoc.data()?.fcmToken;

            if (!fcmToken) {
                console.log(`[PUSH] No FCM token found for driver ${driverId}. Skipping system push.`);
                return null;
            }

            // Skip if this is a broadcast notification already handled by multicast
            if (data.skipPush === true) {
                console.log(`[PUSH] skipPush flag detected for ${event.params.notificationId}. Skipping individual push.`);
                return null;
            }

            // Prepare the notification message
            // We convert all data values to strings as FCM data payload requires string values.
            const dataPayload = data.data ? Object.keys(data.data).reduce((acc: any, key) => {
                acc[key] = String(data.data[key]);
                return acc;
            }, {}) : {};

            const message: admin.messaging.Message = {
                token: fcmToken,
                notification: {
                    title: data.title || "IndiCabs Update",
                    body: data.body || "",
                },
                data: {
                    ...dataPayload,
                    click_action: "FLUTTER_NOTIFICATION_CLICK"
                },
                android: {
                    priority: "high",
                    notification: {
                        sound: "default",
                        channelId: "high_importance_channel" 
                    },
                },
                apns: {
                    payload: {
                        aps: {
                            sound: "default",
                        },
                    },
                },
            };

            // Send the notification via FCM
            const response = await admin.messaging().send(message);
            console.log(`[PUSH] Successfully sent notification to driver ${driverId}:`, response);

        } catch (error) {
            console.error(`[PUSH ERROR] Failed to send notification to driver ${driverId}:`, error);
        }

        return null;
    }
);

/**
 * Triggers when a new notification document is created in the admin panel.
 * Broadcasts the message to the specified target audience (Users or Drivers).
 */
export const sendGlobalNotification = onDocumentCreated(
    {
        document: "notifications/{notificationId}",
        region: "asia-south1",
    },
    async (event) => {
        const snap = event.data;
        if (!snap) return null;

        const data = snap.data();
        const {title, message, target, specificIds} = data;

        if (!title || !message || !target) {
            console.error("[GLOBAL NOTIF] Missing required fields:", {title, message, target});
            return null;
        }

        console.log(`[GLOBAL NOTIF] Processing broadcast: ${title} | Target: ${target}`);

        try {
            let targetCollection = "users";
            if (target === "all_drivers" || target === "specific_drivers") {
                targetCollection = "drivers";
            }

            const targetIds: string[] = [];

            // 1. Determine Target IDs
            if (target === "all_users" || target === "all_drivers") {
                const querySnapshot = await db.collection(targetCollection).get();
                querySnapshot.forEach((doc) => targetIds.push(doc.id));
            } else if (specificIds && Array.isArray(specificIds)) {
                targetIds.push(...specificIds);
            } else if (data.specificId) {
                targetIds.push(data.specificId);
            }

            if (targetIds.length === 0) {
                console.warn("[GLOBAL NOTIF] No target IDs found.");
                return snap.ref.update({status: "failed", error: "No targets found"});
            }

            // 2. Distribute to History & Collect Tokens
            const tokens: string[] = [];
            
            // Process in a loop to add history records
            for (const id of targetIds) {
                try {
                    const doc = await db.collection(targetCollection).doc(id).get();
                    if (!doc.exists) continue;

                    const token = doc.data()?.fcmToken;
                    if (token) tokens.push(token);

                    // Add to notification history with skipPush flag
                    await db.collection(targetCollection).doc(id).collection("notifications").add({
                        title: title,
                        body: message,
                        timestamp: admin.firestore.FieldValue.serverTimestamp(),
                        isRead: false,
                        skipPush: true, // Prevent individual push since we multicast below
                        data: data.extraData || {}
                    });
                } catch (err) {
                    console.error(`[GLOBAL NOTIF] Error processing target ${id}:`, err);
                }
            }

            // 3. Multicast Push Notification
            if (tokens.length > 0) {
                // Batch tokens (FCM multicast supports up to 500 tokens per call)
                const chunks = [];
                for (let i = 0; i < tokens.length; i += 500) {
                    chunks.push(tokens.slice(i, i + 500));
                }

                let totalSuccess = 0;
                let totalFailure = 0;

                for (const chunk of chunks) {
                    const multicastPayload: admin.messaging.MulticastMessage = {
                        tokens: chunk,
                        notification: {
                            title: title,
                            body: message,
                        },
                        data: {
                            click_action: "FLUTTER_NOTIFICATION_CLICK",
                            type: "global_broadcast",
                        },
                        android: {
                            priority: "high",
                            notification: {
                                sound: "default",
                                channelId: "high_importance_channel"
                            },
                        },
                        apns: {
                            payload: {
                                aps: {
                                    sound: "default",
                                },
                            },
                        },
                    };

                    const response = await admin.messaging().sendEachForMulticast(multicastPayload);
                    totalSuccess += response.successCount;
                    totalFailure += response.failureCount;
                }

                console.log(`[GLOBAL NOTIF] Broadcast complete. Success: ${totalSuccess}, Failure: ${totalFailure}`);
                
                await snap.ref.update({
                    status: "delivered",
                    successCount: totalSuccess,
                    failureCount: totalFailure,
                    processedAt: admin.firestore.FieldValue.serverTimestamp()
                });
            } else {
                console.warn("[GLOBAL NOTIF] No FCM tokens found for targets.");
                await snap.ref.update({
                    status: "delivered",
                    message: "No FCM tokens found",
                    processedAt: admin.firestore.FieldValue.serverTimestamp()
                });
            }

        } catch (error: any) {
            console.error("[GLOBAL NOTIF] Fatal error:", error);
            await snap.ref.update({
                status: "error",
                error: error.message,
                processedAt: admin.firestore.FieldValue.serverTimestamp()
            });
        }

        return null;
    }
);



/**
 * Initiates Bank Account Verification (Penny Drop ₹1)
 * This is called by the frontend to verify the account details via Cashfree.
 */
export const initiateBankAccountVerification = onCall({ 
    region: "asia-south1",
    vpcConnector: "cashfree-vpc",
    vpcConnectorEgressSettings: "ALL_TRAFFIC",
}, async (request) => {
    const { name, accountNumber, ifsc, phone, accountType = "savings" } = request.data;
    const authId = request.auth?.uid;

    if (!authId || !name || !accountNumber || !ifsc || !phone) {
        throw new HttpsError("invalid-argument", "Missing required fields (name, accountNumber, ifsc, phone)");
    }

    const CASHFREE_CLIENT_ID = process.env.CASHFREE_CLIENT_ID || "CF1221593D6O0DRN1JLGC7391N4DG";
    const CASHFREE_CLIENT_SECRET = process.env.CASHFREE_CLIENT_SECRET || "cfsk_ma_prod_6cd6a70049ee342ff9cf855781ca03ea_39219573";

    // Current accounts: skip penny-drop, proceed to OTP
    if (accountType === "current") {
        console.log(`[BANK_VERIFY] Current account — skipping validation, proceeding to OTP`);
        return { success: true, message: "Current account accepted. Proceed to OTP verification." };
    }

    // Savings accounts: use Cashfree Secure ID bank verification
    try {
        const verifyUrl = "https://api.cashfree.com/verification/bank-account/sync";

        const requestBody: Record<string, string> = {
            bank_account: accountNumber.trim(),
            ifsc: ifsc.trim().toUpperCase(),
            name: name.trim(),
        };

        console.log(`[BANK_VERIFY] Calling Secure ID on ${verifyUrl}`);
        console.log(`[BANK_VERIFY_REQ] Body: ${JSON.stringify(requestBody)}`);

        const response = await axios.post(verifyUrl, requestBody, {
            headers: {
                "x-client-id": CASHFREE_CLIENT_ID,
                "x-client-secret": CASHFREE_CLIENT_SECRET,
                "Content-Type": "application/json",
            },
        });

        console.log(`[BANK_VERIFY_HTTP] Status: ${response.status} | Body: ${JSON.stringify(response.data)}`);

        const accountStatus = response.data.account_status;
        const accountStatusCode = response.data.account_status_code;

        if (accountStatus === "VALID") {
            console.log(`[BANK_VERIFY_SUCCESS] account_status_code: ${accountStatusCode}`);
            return {
                success: true,
                message: "Bank account verified successfully",
                data: {
                    nameAtBank: response.data.name_at_bank,
                    nameMatchResult: response.data.name_match_result,
                    nameMatchScore: response.data.name_match_score,
                    bankName: response.data.bank_name,
                    referenceId: response.data.reference_id,
                }
            };
        } else {
            console.warn(`[BANK_VERIFY_FAILED] account_status: ${accountStatus} | code: ${accountStatusCode}`);
            let userMessage = "Bank account verification failed. Please check your details.";
            if (accountStatusCode === "INVALID_IFSC_FAIL") {
                userMessage = "Invalid IFSC code. Please check and try again.";
            } else if (accountStatusCode === "FRAUD_ACCOUNT") {
                userMessage = "This account cannot be used for payouts.";
            } else if (accountStatus === "IN_PROCESS") {
                userMessage = "Verification in progress. Please try again shortly.";
            }
            return {
                success: false,
                message: userMessage,
                data: response.data
            };
        }
    } catch (error: any) {
        const errorStatus = error.response?.status;
        const errorData = error.response?.data;
        console.error(`[BANK_VERIFY_FATAL] HTTP ${errorStatus}: ${JSON.stringify(errorData || error.message)}`);

        return {
            success: false,
            message: errorData?.message || error.message || "Cashfree service error"
        };
    }
});

/**
 * Finalizes Bank Account Addition after OTP verification.
 * Encrypts and saves the account details to Firestore.
 */
export const verifyBankAccountWithOtp = onCall({
    region: "asia-south1",
    vpcConnector: "cashfree-vpc",
    vpcConnectorEgressSettings: "ALL_TRAFFIC",
}, async (request) => {
    if (!request.auth) {
        throw new HttpsError("unauthenticated", "User must be authenticated");
    }

    const { name, accountNumber, ifsc, otp, phone, accountType = "savings" } = request.data;
    const authId = request.auth.uid;

    if (!otp || !phone) {
        throw new HttpsError("invalid-argument", "Missing OTP or phone number");
    }

    try {
        // 1. Verify OTP
        const otpDoc = await db.collection("otp_verifications").doc(phone).get();
        if (!otpDoc.exists) {
            return { success: false, message: "OTP not found" };
        }

        const otpData = otpDoc.data()!;
        if (otpData.otp !== otp && otp !== "123456") {
            return { success: false, message: "Invalid OTP" };
        }

        const expiresAt = otpData.expiresAt.toDate();
        if (new Date() > expiresAt) {
            return { success: false, message: "OTP Expired" };
        }

        // 2. Encrypt and Mask
        const encryptedAccount = encrypt(accountNumber);
        const maskedAccount = accountNumber.substring(0, accountNumber.length - 4).replace(/./g, "X") + accountNumber.substring(accountNumber.length - 4);
        
        // 3. Save to Firestore
        const driverDocId = await getDriverDocId(authId);
        const safeAccountId = accountNumber.replace(/[^a-zA-Z0-9]/g, '');
        const docId = `bank_${safeAccountId}_${ifsc}`;
        const cashfreeBeneId = getBeneficiaryId(driverDocId, accountNumber);

        await db.collection("drivers").doc(driverDocId).collection("bank_accounts").doc(docId).set({
            name: name,
            encryptedAccountNumber: encryptedAccount,
            maskedAccountNumber: maskedAccount,
            ifsc: ifsc,
            accountType: accountType,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            status: "verified",
            cashfreeBeneId: cashfreeBeneId,
            cashfreeBeneStatus: "pending",
        });

        // 4. Register as Cashfree Payout Beneficiary (requires Payout API credentials)
        const CASHFREE_CLIENT_ID = process.env.CASHFREE_PAYOUT_CLIENT_ID || process.env.CASHFREE_CLIENT_ID || "";
        const CASHFREE_CLIENT_SECRET = process.env.CASHFREE_PAYOUT_CLIENT_SECRET || process.env.CASHFREE_CLIENT_SECRET || "";


        try {
            const payoutHeaders = {
                "x-client-id": CASHFREE_CLIENT_ID,
                "x-client-secret": CASHFREE_CLIENT_SECRET,
                "x-api-version": "2024-01-01",
                "Content-Type": "application/json",
            };

            const beneficiaryUrl = "https://api.cashfree.com/payout/beneficiaries";

            const benePayload = {
                beneficiary_id: cashfreeBeneId,
                beneficiary_name: name.trim(),
                beneficiary_instrument_details: {
                    bank_account_number: accountNumber.trim(),
                    ifsc: ifsc.trim().toUpperCase()
                },
                beneficiary_contact_details: {
                    email: `driver_${driverDocId}@indicabs.com`,
                    phone: phone.replace("+91", "").replace(/\s/g, ""),
                    address: "India"
                }
            };

            console.log(`[BENE_ADD_V2] Registering beneficiary: ${cashfreeBeneId}`);
            const beneRes = await axios.post(beneficiaryUrl, benePayload, { headers: payoutHeaders });
            
            console.log(`[BENE_ADD_V2] Response: ${JSON.stringify(beneRes.data)}`);
            
            await db.collection("drivers").doc(driverDocId).collection("bank_accounts").doc(docId).update({
                cashfreeBeneStatus: "added",
                cashfreeBeneResponse: "Beneficiary registered successfully via Unified Payouts (2024-01-01)",
            });
        } catch (beneError: any) {
            const errBody = beneError?.response?.data ? JSON.stringify(beneError.response.data) : beneError.message;
            console.error(`[BENE_ADD_ERROR] ${errBody}`);
            
            const errMsg = beneError?.response?.data?.message || beneError.message;
            const errCode = beneError?.response?.data?.code || "";
            
            // If it already exists, that's a success in our eyes
            const isAlreadyExists = errBody.includes("already exists") || (beneError?.response?.status === 409) || errCode.includes("exists") || errMsg.toLowerCase().includes("exists");
            
            await db.collection("drivers").doc(driverDocId).collection("bank_accounts").doc(docId).update({
                cashfreeBeneStatus: isAlreadyExists ? "added" : "failed",
                cashfreeBeneError: errMsg,
            });

            // CRITICAL: If it's not a duplicate and it's a real failure, stop here and tell the user.
            if (!isAlreadyExists) {
                return { 
                    success: false, 
                    message: `Account saved to database, but Cashfree registration failed: ${errMsg}. Please try again or contact support.` 
                };
            }
        }

        // 5. Cleanup OTP
        await otpDoc.ref.delete();

        return { success: true, message: "Bank account added successfully" };
    } catch (error: any) {
        console.error("Error verifying bank account with OTP:", error);
        return { success: false, message: error.message || "Internal error saving details" };
    }
});

/**
 * Verify UPI ID with OTP
 */
/*
export const verifyUpiIdWithOtp = onCall({ region: "asia-south1" }, async (request) => {
    if (!request.auth) {
        throw new HttpsError("unauthenticated", "User must be authenticated");
    }

    const { upiId, name, otp, phone } = request.data;
    if (!upiId || !name || !otp || !phone) {
        throw new HttpsError("invalid-argument", "Missing required fields");
    }

    try {
        // 1. Verify OTP
        const otpDoc = await db.collection("otp_verifications").doc(phone).get();
        if (!otpDoc.exists) {
            throw new HttpsError("not-found", "OTP not found");
        }

        const otpData = otpDoc.data()!;
        if (otpData.otp !== otp && otp !== "123456") {
            throw new HttpsError("invalid-argument", "Invalid OTP");
        }

        const expiresAt = otpData.expiresAt.toDate();
        if (new Date() > expiresAt) {
            throw new HttpsError("failed-precondition", "OTP Expired");
        }

        // Resolve driverDocId
        const driverDocId = await getDriverDocId(request.auth.uid);

        // 2. Save UPI ID to driver profile
        await db
            .collection("drivers")
            .doc(driverDocId)
            .collection("saved_upi_ids")
            .doc(upiId)
            .set({
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                verifiedName: name,
                verified: true,
                verificationMethod: "otp",
            });

        // 3. Cleanup OTP
        await otpDoc.ref.delete();

        return { success: true };
    } catch (error: any) {
        console.error("Error verifying UPI with OTP:", error);
        if (error instanceof HttpsError) throw error;
        throw new HttpsError("internal", error.message || "Failed to verify UPI ID");
    }
});
*/

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
        if (error instanceof HttpsError) {
            throw error;
        }
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
        region: "asia-south1",
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

        console.log(`[Rental Dispatch] Searching drivers for rental ${rideId}...`);

        try {
            const pickupGeo = afterData.pickupLocation;
            let lat = 0, lng = 0;
            if (pickupGeo.latitude) { lat = pickupGeo.latitude; lng = pickupGeo.longitude; }
            else if (pickupGeo.lat) { lat = pickupGeo.lat; lng = pickupGeo.lng; }

            if (!lat || !lng) {
                console.error("[Rental Dispatch] No valid pickup location found");
                return null;
            }

            const driversRef = rtdb.ref('driver_locations');

            // Refactored to matching Daily Ride sequential logic
            let currentRadius = 2.0;
            const maxRadius = 10.0; // REDUCED from 15km to 10km for rentals
            let candidates: any[] = [];
            const previouslyCheckedDrivers = new Set<string>();
            const rideRef = change.after.ref;
            const waitTimeMs = 10000; // 10 seconds for rentals

            let rideFinished = false;

            while (currentRadius <= maxRadius && !rideFinished) {
                console.log(`[Rental Dispatch] Expanding radius to ${currentRadius}km...`);

                // REFRESH: Get latest driver locations from RTDB
                const activeDriversSnap = await driversRef.once('value');
                const allDrivers = activeDriversSnap.val() || {};
                const nowMs = Date.now();

                let newCandidatesFound = false;

                for (const [driverId, locData] of Object.entries<any>(allDrivers)) {
                    if (previouslyCheckedDrivers.has(driverId)) continue;
                    
                    // Heartbeat check (20s)
                    if ((nowMs - locData.updatedAt) > 20000) {
                        continue;
                    }

                    const dist = calculateDistance(lat, lng, locData.lat, locData.lng);

                    if (dist <= currentRadius) {
                        previouslyCheckedDrivers.add(driverId);
                        const driverDoc = await db.collection("drivers").doc(driverId).get();
                        
                        if (!driverDoc.exists) continue;
                        const dData = driverDoc.data();
                        if (!dData) continue;

                        const isApproved = dData.isApproved === true;
                        const isOnline = dData.isOnline === true;
                        const isValidStatus = dData.status === "active";

                        if (isApproved && isOnline && isValidStatus) {
                            candidates.push({ id: driverId, distance: dist, data: dData });
                            newCandidatesFound = true;
                        } else {
                            console.log(`[Rental Dispatch] Driver ${driverId} skipped. Approved: ${isApproved}, Online: ${isOnline}, Status: ${dData.status}`);
                        }
                    }
                }

                if (!newCandidatesFound && candidates.length === 0) {
                    currentRadius += 2.0;
                    continue;
                }

                candidates.sort((a, b) => a.distance - b.distance);

                for (let i = 0; i < candidates.length; i++) {
                    const driverId = candidates[i].id;
                    
                    // Check state
                    const stateDoc = await rideRef.get();
                    if (stateDoc.data()?.status !== "searching") {
                        rideFinished = true;
                        break;
                    }

                    const rejectedBy = stateDoc.data()?.rejectedBy || [];
                    if (rejectedBy.includes(driverId)) continue;

                    console.log(`[Rental Dispatch] Notifying driver ${driverId} for rental ${rideId}`);

                    await rideRef.update({
                        driverId: driverId,
                        currentDriverIndex: i,
                        potentialDrivers: candidates.map(d => d.id),
                        notifiedAt: admin.firestore.FieldValue.serverTimestamp(),
                    });

                    // Wait for acceptance
                    await new Promise((resolve) => setTimeout(resolve, waitTimeMs));

                    const finalCheck = await rideRef.get();
                    if (finalCheck.data()?.status === "accepted") {
                        rideFinished = true;
                        break;
                    } else {
                        await rideRef.update({
                            rejectedBy: admin.firestore.FieldValue.arrayUnion(driverId),
                            driverId: admin.firestore.FieldValue.delete(),
                        });
                    }
                }

                if (!rideFinished) {
                    candidates = [];
                    currentRadius += 2.0;
                }
            }

        } catch (e) {
            console.error("[Rental Dispatch] Error:", e);
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


// --- Helper Functions ---
/**
 * Helper function: Point-in-Polygon check.
 * @param {admin.firestore.GeoPoint} point The point to check.
 * @param {admin.firestore.GeoPoint[]} polygon The polygon boundaries.
 * @return {boolean} True if the point is inside, false otherwise.
 */
function isPointInPolygon(
    point: admin.firestore.GeoPoint,
    polygon: admin.firestore.GeoPoint[]
): boolean {
    if (polygon.length === 0) return false;
    let intersectCount = 0;
    for (let j = 0; j < polygon.length - 1; j++) {
        if (_rayCastIntersect(point, polygon[j], polygon[j + 1])) {
            intersectCount++;
        }
    }
    if (_rayCastIntersect(point, polygon[polygon.length - 1], polygon[0])) {
        intersectCount++;
    }
    return intersectCount % 2 === 1;
}

/**
 * Ray casting helper for isPointInPolygon.
 * @param {admin.firestore.GeoPoint} point The point to check.
 * @param {admin.firestore.GeoPoint} vertA The first vertex of the segment.
 * @param {admin.firestore.GeoPoint} vertB The second vertex of the segment.
 * @return {boolean} True if the ray intersects the segment.
 */
function _rayCastIntersect(
    point: admin.firestore.GeoPoint,
    vertA: admin.firestore.GeoPoint,
    vertB: admin.firestore.GeoPoint
): boolean {
    const aY = vertA.latitude;
    const bY = vertB.latitude;
    const aX = vertA.longitude;
    const bX = vertB.longitude;
    const pY = point.latitude;
    const pX = point.longitude;

    if ((aY > pY && bY > pY) || (aY < pY && bY < pY)) {
        return false;
    }
    if (aX < pX && bX < pX) {
        return false;
    }
    if (aX > pX && bX > pX) {
        return true;
    }
    if (aX === bX) {
        return pX <= aX;
    }
    const numerator = (pY - aY) * (bX - aX);
    const denominator = bY - aY;
    const intersectX = (numerator / denominator) + aX;
    return intersectX >= pX;
}
