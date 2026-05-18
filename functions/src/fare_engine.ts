import * as admin from "firebase-admin";

export interface FareCalculationResult {
    finalFare: number;
    baseFare: number;
    distanceFare: number;
    timeFare: number;
    waitingCharge: number;
    surgeMultiplier: number;
    nightCharge: number;
    tolls: number;
    taxes: number;
    tip: number;
    totalExcludingTaxes: number;
    reason: string;
}

export async function calculateTripFare(
    rideId: string,
    actualKm: number,
    rideMinutes: number,
    waitingMinutes: number,
    rideType: string = 'daily'
): Promise<FareCalculationResult> {
    const db = admin.firestore();
    const rideRef = db.collection(rideType === 'rental' ? 'rental_requests' : 'ride_requests').doc(rideId);
    const rideSnap = await rideRef.get();

    if (!rideSnap.exists) {
        throw new Error("Ride not found");
    }

    const rideData = rideSnap.data()!;
    let vehicleType = rideData.vehicleType || rideData.vehicleClass || "Sedan";
    
    // Normalize and map common variations to internal rule keys
    const normalized = vehicleType.toString().toLowerCase().trim();
    if (normalized.includes("hatchback") || normalized === "mini") {
        vehicleType = "Hatchback";
    } else if (normalized.includes("sedan")) {
        vehicleType = "Sedan";
    } else if (normalized.includes("suv")) {
        vehicleType = "SUV";
    } else if (normalized.includes("auto")) {
        vehicleType = "Auto";
    } else if (normalized.includes("actingdriver")) {
        vehicleType = "ActingDriver";
    }

    // Fetch pricing rules
    let pricingRules: any = {};
    const pricingDoc = await db.collection("pricing_rules").doc("Chennai").get();
    if (pricingDoc.exists) pricingRules = pricingDoc.data() || {};

    const vRules = (pricingRules.vehicle_types && pricingRules.vehicle_types[vehicleType]) || (({
        ActingDriver: { baseFare: 150, perKilometer: 0, minimumFare: 250, perMinute: 2 },
        Auto: { baseFare: 30, perKilometer: 18, minimumFare: 100 },
        Hatchback: { baseFare: 50, perKilometer: 20, minimumFare: 150 },
        Sedan: { baseFare: 55, perKilometer: 22, minimumFare: 170 },
        SUV: { baseFare: 70, perKilometer: 28, minimumFare: 200 }
    } as Record<string, any>)[vehicleType]) || {
        baseFare: 50,
        perKilometer: 12,
        minimumFare: 100,
        perMinute: 0,
        waitingChargePerMinute: 2
    };

    const baseFare = rideData.baseFare ?? vRules.baseFare ?? 50;
    const perKmRate = rideData.perKilometer ?? vRules.perKilometer ?? 12;
    const perMinuteRate = rideData.perMinute ?? vRules.perMinute ?? 0;
    const waitingRate = rideData.waitingChargePerMinute ?? vRules.waitingChargePerMinute ?? 2;
    const minFare = rideData.minimumFare ?? vRules.minimumFare ?? 100;

    console.log(`[FareEngine] Ride ${rideId}: Vehicle: ${vehicleType} (Original: ${rideData.vehicleType}/${rideData.vehicleClass}), MinFare: ${minFare}`);

    // 1. Distance Calculation (Stick to estimate unless exceeded)
    const estimatedKm = rideData.rideDistance || 0;
    const initialFare = rideData.initialRideFare || rideData.rideFare || 0;
    
    // Lock to estimate as a floor to prevent fare jumping at the start
    const effectiveKm = Math.max(actualKm, estimatedKm);
    
    let distanceFare = 0;
    if (effectiveKm <= 12) {
        distanceFare = effectiveKm * perKmRate;
    } else {
        distanceFare = (12 * perKmRate) + ((effectiveKm - 12) * Math.max(0, perKmRate - 3));
    }

    // 2. Time Fare
    const timeFare = rideMinutes * perMinuteRate;

    // 3. Waiting Charge
    const pickupWaitingCharge = rideData.waitingCharge || 0;
    const midTripWaitingCharge = waitingMinutes * waitingRate;
    const totalWaitingCharge = pickupWaitingCharge + midTripWaitingCharge;

    // 4. Surge
    let surgeMultiplier = rideData.surgeMultiplier || 1.0;

    // 5. Night Charge
    let nightCharge = rideData.nightCharge;
    if (nightCharge === undefined || nightCharge === null) {
        const bookingTime = rideData.createdAt?.toDate() || new Date();
        const hour = bookingTime.getHours();
        nightCharge = (hour >= 22 || hour < 6) ? 30 : 0;
    }

    // 6. Tolls
    const tolls = rideData.tollPrice || 0;

    // 7. Tip
    const tip = rideData.tip || 0;

    // --- Combine ---
    let subtotal = baseFare + distanceFare + timeFare + totalWaitingCharge;
    subtotal *= surgeMultiplier;
    subtotal += nightCharge;

    // 8. Taxes (e.g., 5% GST)
    const taxRate = 0.05;
    const taxes = subtotal * taxRate;
    
    // 9. Final Total & Minimum Fare Enforcement
    // We apply the minimum fare to the final total to ensure it matches the exact target (e.g., 150)
    let finalFare = Math.round(subtotal + taxes + tolls + tip);
    
    if (finalFare < minFare) {
        finalFare = minFare;
    }

    // Baseline protection: Prevents price from dropping below the initially quoted fare
    // UNLESS we are enforcing a minimum fare target that was higher due to a previous bug.
    if (finalFare < initialFare && initialFare > 0) {
        // If the initial fare was 179 (Sedan min + tax) but we are now correctly identifying 
        // a Hatchback min (150), we allow the drop.
        const isCorrection = initialFare > minFare && finalFare === minFare;
        if (!isCorrection) {
            finalFare = initialFare;
        }
    }

    console.log(`[FareEngine] Ride ${rideId} Final: ₹${finalFare} (Subtotal: ${subtotal}, Taxes: ${taxes}, Min: ${minFare})`);

    return {
        finalFare,
        baseFare,
        distanceFare: Math.round(distanceFare),
        timeFare: Math.round(timeFare),
        waitingCharge: Math.round(totalWaitingCharge),
        surgeMultiplier,
        nightCharge,
        tolls,
        taxes: Math.round(taxes),
        tip,
        totalExcludingTaxes: Math.round(subtotal),
        reason: `Distance: ${actualKm.toFixed(2)}km, Time: ${rideMinutes.toFixed(1)}m, Waiting: ${waitingMinutes}m`
    };
}
