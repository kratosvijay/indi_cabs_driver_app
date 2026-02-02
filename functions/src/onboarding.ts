import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";





/**
 * Batch Onboard Drivers and Vehicles from Excel Data
 * - Creates Firebase Auth User
 * - Creates Driver Document (Approved)
 * - Creates Vehicle Document (Approved)
 * - Links Driver and Vehicle
 */
// Rename to batchOnboard for clarity, or keep name but change logic.
// Changing export requires updating index.ts too. Let's keep export name 'batchOnboardDrivers' for now to avoid index.ts edit if possible, 
// OR just update index.ts as well. Updating index.ts is cleaner.

export const batchOnboard = onCall({ timeoutSeconds: 540, memory: '512MiB', region: 'us-central1' }, async (request) => {
    // 1. Authentication Check
    if (!request.auth) {
        throw new HttpsError("unauthenticated", "User must be authenticated.");
    }

    const db = admin.firestore();
    const auth = admin.auth();

    const type: 'driver' | 'vehicle' = request.data.type; // 'driver' or 'vehicle'
    const data: any[] = request.data.data;

    if (!type || !data || !Array.isArray(data) || data.length === 0) {
        throw new HttpsError("invalid-argument", "Invalid arguments. Provide 'type' and 'data'.");
    }

    const results = {
        success: 0,
        failed: 0,
        errors: [] as string[]
    };

    console.log(`Starting batch import for ${type}: ${data.length} items...`);

    for (let i = 0; i < data.length; i++) {
        const row = data[i];
        const rowIndex = i + 2;

        try {
            if (type === 'driver') {
                // DRIVER UPLOAD LOGIC
                if (!row.email || !row.phone || !row.name) {
                    throw new Error("Missing required fields (Email, Phone, Name)");
                }

                // 1. Create or Get User (Auth)
                let uid = "";
                try {
                    const userRecord = await auth.getUserByEmail(row.email);
                    uid = userRecord.uid;
                } catch (e: any) {
                    if (e.code === 'auth/user-not-found') {
                        // Default password logic if not provided (removed from template)
                        const password = row.phone.replace('+', '') || "123456";
                        const newUser = await auth.createUser({
                            email: row.email,
                            phoneNumber: row.phone.startsWith('+') ? row.phone : `+91${row.phone}`,
                            password: password,
                            displayName: row.name,
                            emailVerified: true
                        });
                        uid = newUser.uid;
                    } else {
                        throw e;
                    }
                }

                // 2. Create Driver Document
                await db.collection("drivers").doc(uid).set({
                    name: row.name,
                    email: row.email,
                    phoneNumber: row.phone,
                    licenseNumber: row.licenseNumber ?? "",
                    aadharNumber: row.aadharNumber ?? "", // Added Aadhar
                    status: "active",
                    isOnline: false,
                    isApproved: true,
                    joinedDate: admin.firestore.FieldValue.serverTimestamp(),
                    rating: 5.0,
                    totalRides: 0,
                    earnings: 0,
                    createdAt: admin.firestore.FieldValue.serverTimestamp(),
                }, { merge: true });

            } else if (type === 'vehicle') {
                // VEHICLE UPLOAD LOGIC
                if (!row.vehiclePlate || !row.vehicleModel || !row.vehicleType) {
                    throw new Error("Missing fields (Plate, Model, Type)");
                }

                // Check for existing vehicle
                const vehicleQuery = await db.collection("vehicles").where("plateNumber", "==", row.vehiclePlate).limit(1).get();

                if (!vehicleQuery.empty) {
                    // Update
                    const vehicleId = vehicleQuery.docs[0].id;
                    await db.collection("vehicles").doc(vehicleId).update({
                        model: row.vehicleModel,
                        brand: row.vehicleBrand ?? "Unknown", // Added Brand
                        type: row.vehicleType,
                        color: row.color ?? "Unknown",
                        fuelType: row.fuelType ?? "Petrol",
                        status: 'Active',
                        isApproved: true
                    });
                } else {
                    // Create
                    await db.collection("vehicles").add({
                        plateNumber: row.vehiclePlate,
                        model: row.vehicleModel,
                        brand: row.vehicleBrand ?? "Unknown", // Added Brand
                        type: row.vehicleType,
                        color: row.color ?? "Unknown",
                        fuelType: row.fuelType ?? "Petrol",
                        status: "Active",
                        isApproved: true,
                        assignedDriverId: null,
                        createdAt: admin.firestore.FieldValue.serverTimestamp(),
                        fuelLevel: 100,
                        lastMaintenanceDate: admin.firestore.FieldValue.serverTimestamp(),
                    });
                }
            } else {
                throw new Error("Invalid type specified.");
            }

            results.success++;

        } catch (error: any) {
            console.error(`Error processing row ${rowIndex}:`, error);
            results.failed++;
            const id = type === 'driver' ? row.email : row.vehiclePlate;
            results.errors.push(`Row ${rowIndex} (${id ?? 'Unknown'}): ${error.message}`);
        }
    }

    return results;
});
