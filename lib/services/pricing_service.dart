import 'package:flutter/foundation.dart';
import 'package:project_taxi_driver_app/widgets/ride_request.dart';

class PricingService {
  /// Local implementation of the pricing logic to avoid unnecessary Cloud Function calls.
  /// Mirrors the logic found in the calculateDynamicPricing Cloud Function.
  static Map<String, dynamic> calculateFareLocally({
    required RideRequest rideRequest,
    required double actualDistanceKm,
    required double actualDurationMins,
    required double waitingCharge,
  }) {
    // 1. RENTAL BILLING LOGIC
    if (rideRequest.rideType == 'rental') {
      final double pkgHours = (rideRequest.durationHours ?? 0).toDouble();
      final double pkgKm = (rideRequest.kmLimit ?? 0).toDouble();
      final double extraHourCharge = (rideRequest.extraHourCharge ?? 0).toDouble();
      final double extraKmCharge = (rideRequest.extraKmCharge ?? 0).toDouble();
      final double baseFare = rideRequest.rideFare;

      double extraHours = 0;
      if ((actualDurationMins / 60.0) > pkgHours) {
        extraHours = ((actualDurationMins / 60.0) - pkgHours).ceilToDouble();
      }

      double extraKm = 0;
      if (actualDistanceKm > pkgKm) {
        extraKm = actualDistanceKm - pkgKm;
      }

      final double extraTimeCost = extraHours * extraHourCharge;
      final double extraDistCost = extraKm * extraKmCharge;

      final double totalFare = baseFare + extraTimeCost + extraDistCost;

      return {
        'finalFare': totalFare,
        'priceUpdated': (extraTimeCost > 0 || extraDistCost > 0),
        'reason': "Local Rental calculation: Base: $baseFare, ExtraKm: $extraDistCost, ExtraTime: $extraTimeCost",
      };
    }

    // 2. DAILY RIDE BILLING LOGIC
    final double estimatedDistanceKm = rideRequest.rideDistance;
    final double distanceDiff = actualDistanceKm - estimatedDistanceKm;

    // Tolerance Logic
    // If distance is nearly identical (within 200 meters), use original quoted fare.
    if (distanceDiff.abs() < 0.2) {
      return {
        'finalFare': rideRequest.rideFare,
        'priceUpdated': false,
        'reason': "Distance matched within 200m tolerance. Using original quoted fare.",
      };
    }

    // For all other cases where the driver significantly deviated (shorter or longer),
    // we perform a full dynamic recalculation based on the actual distance and duration.
    // This ensures fair billing for both the driver and the customer.


    // Recalculate using rules
    // Use createdAt (booking time) for peak/night charges to lock the rate.
    final DateTime refTime = rideRequest.createdAt ?? rideRequest.startedAt ?? DateTime.now();
    
    // Determine Surge Multiplier (1.2x for peak hours)
    double surgeMultiplier = 1.0;
    
    // Get IST Hour (Asia/Kolkata)
    final int hour = refTime.hour;
    final int weekday = refTime.weekday; // 1 = Mon, 7 = Sun
    final bool isWeekend = weekday == DateTime.saturday || weekday == DateTime.sunday;

    if (isWeekend) {
      if (hour >= 15 && hour < 21) surgeMultiplier = 1.20;
    } else {
      final bool isMorningSurge = hour >= 8 && hour < 11;
      final bool isEveningSurge = hour >= 17 && hour < 21;
      if (isMorningSurge || isEveningSurge) surgeMultiplier = 1.20;
    }

    // Night Charge (₹30 for 10 PM - 6 AM)
    double nightCharge = 0.0;
    if (hour >= 22 || hour < 6) {
      nightCharge = 30.0;
    }

    // -------------------------------------------------------------------------
    // 3. APPLY VEHICLE-SPECIFIC PRICING RULES (MATCHING FIRESTORE)
    // -------------------------------------------------------------------------
    // Defaulting to Sedan rates as the primary fallback
    double baseFare = 55.0; 
    double perKm = 22.0;
    double minFare = 170.0;
    double perMinute = 0.0;

    String vType = rideRequest.vehicleType.toLowerCase().trim();
    debugPrint("PricingService: Calculating for VehicleType: '$vType' (Original: '${rideRequest.vehicleType}')");

    if (vType.contains('actingdriver')) {
      baseFare = 150.0;
      minFare = 250.0;
      perKm = 0.0;
      perMinute = 2.0;
    } else if (vType.contains('auto')) {
      baseFare = 30.0;
      minFare = 100.0;
      perKm = 18.0;
      perMinute = 0.0;
    } else if (vType.contains('hatchback')) {
      baseFare = 50.0;
      minFare = 150.0;
      perKm = 20.0;
      perMinute = 0.0;
    } else if (vType.contains('sedan')) {
      baseFare = 55.0;
      minFare = 170.0;
      perKm = 22.0;
      perMinute = 0.0;
    } else if (vType.contains('suv')) {
      baseFare = 70.0;
      minFare = 200.0;
      perKm = 28.0;
      perMinute = 0.0;
    } else {
      debugPrint("PricingService: WARNING - No match for vehicle type '$vType'. Using default Sedan rates.");
    }

    debugPrint("PricingService: Selected Rates - Base: $baseFare, PerKm: $perKm, Min: $minFare, PerMin: $perMinute");

    // -------------------------------------------------------------------------
    // 4. PERFORM RECALCULATION
    // -------------------------------------------------------------------------
    double calculatedFare = baseFare;

    // 1. Distance Charge (Tiered)
    if (actualDistanceKm <= 12) {
      calculatedFare += actualDistanceKm * perKm;
    } else {
      calculatedFare += 12 * perKm;
      // Beyond 12km, use a slightly reduced rate (e.g. -3) unless it's an Acting Driver (0 rate)
      double reducedRate = perKm > 0 ? (perKm - 3.0) : 0;
      calculatedFare += (actualDistanceKm - 12) * reducedRate;
    }

    // 2. Time Charge (₹2 per minute)
    calculatedFare += actualDurationMins * perMinute;

    // 3. Surge
    calculatedFare *= surgeMultiplier;

    // 4. Night Charge
    calculatedFare += nightCharge;

    // 5. Extras (Toll, Geofence, etc. - preserved from estimate)
    double estBase = baseFare;
    if (estimatedDistanceKm <= 12) {
      estBase += estimatedDistanceKm * perKm;
    } else {
      estBase += 12 * perKm + (estimatedDistanceKm - 12) * (perKm - 3.0);
    }
    // Note: We don't include time in estimated base because it's highly variable,
    // we assume the quoted 'rideFare' includes the estimated time cost already.
    estBase *= surgeMultiplier;
    estBase += nightCharge;

    double estimatedExtras = rideRequest.rideFare - estBase;
    if (estimatedExtras < 0) estimatedExtras = 0;

    calculatedFare += estimatedExtras;

    // 6. Minimum Fare Enforcement
    if (calculatedFare < minFare) calculatedFare = minFare;

    return {
      'finalFare': calculatedFare.roundToDouble(),
      'priceUpdated': true,
      'reason': "Dynamic recalculation applied. Surge: ${surgeMultiplier}x, Night: ₹$nightCharge, Extras: ₹${estimatedExtras.toStringAsFixed(0)}",
    };
  }
}
