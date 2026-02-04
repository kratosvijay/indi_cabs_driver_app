import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

class GoToTimerService extends GetxService {
  static GoToTimerService get instance => Get.find<GoToTimerService>();

  // GoTo state
  final Rxn<Map<String, dynamic>> goToDestination = Rxn<Map<String, dynamic>>();
  final RxBool isGoToActive = false.obs;
  final Rx<DateTime?> goToStartTime = Rx<DateTime?>(null);
  final Rx<DateTime?> goToEndTime = Rx<DateTime?>(null);
  final RxInt remainingMinutes = 0.obs;

  // Timer for countdown and auto-disable
  Timer? _countdownTimer;
  Timer? _autoDisableTimer;

  // Default GoTo duration (1 hour)
  final Duration goToDuration = const Duration(hours: 1);

  // Maximum distance from destination to consider a request "towards" it (in km)
  final double maxDestinationDistance = 15.0;

  // Callbacks
  Function()? onGoToExpired;

  @override
  void onClose() {
    _countdownTimer?.cancel();
    _autoDisableTimer?.cancel();
    super.onClose();
  }

  /// Activate GoTo mode with a destination
  Future<void> activateGoTo(
    Map<String, dynamic> destination, {
    Duration? customDuration,
  }) async {
    debugPrint('GoToTimerService: Activating GoTo mode');

    final duration = customDuration ?? goToDuration;
    final now = DateTime.now();

    goToDestination.value = destination;
    goToStartTime.value = now;
    goToEndTime.value = now.add(duration);
    isGoToActive.value = true;

    // Calculate remaining minutes
    _updateRemainingTime();

    // Start countdown timer (updates every minute)
    _startCountdownTimer();

    // Start auto-disable timer
    _startAutoDisableTimer(duration);

    debugPrint(
      'GoToTimerService: GoTo activated until ${goToEndTime.value}',
    );
  }

  /// Deactivate GoTo mode manually
  void deactivateGoTo({bool expired = false}) {
    debugPrint(
      'GoToTimerService: Deactivating GoTo mode (expired: $expired)',
    );

    _countdownTimer?.cancel();
    _autoDisableTimer?.cancel();

    goToDestination.value = null;
    goToStartTime.value = null;
    goToEndTime.value = null;
    isGoToActive.value = false;
    remainingMinutes.value = 0;

    if (expired && onGoToExpired != null) {
      onGoToExpired!();
    }
  }

  /// Extend GoTo by additional time
  void extendGoTo(Duration additionalTime) {
    if (!isGoToActive.value || goToEndTime.value == null) return;

    final newEndTime = goToEndTime.value!.add(additionalTime);
    goToEndTime.value = newEndTime;

    // Restart timers with new duration
    final remainingDuration = newEndTime.difference(DateTime.now());
    _countdownTimer?.cancel();
    _autoDisableTimer?.cancel();
    _startCountdownTimer();
    _startAutoDisableTimer(remainingDuration);

    debugPrint('GoToTimerService: GoTo extended until $newEndTime');
  }

  /// Check if a ride request is towards the GoTo destination
  bool isRequestTowardsDestination(
    LatLng pickupLocation,
    LatLng dropoffLocation,
  ) {
    if (!isGoToActive.value || goToDestination.value == null) {
      return true; // If GoTo not active, all requests are valid
    }

    final destLat = goToDestination.value!['lat'] as double;
    final destLng = goToDestination.value!['lng'] as double;
    final destination = LatLng(destLat, destLng);

    // Calculate distance from dropoff to GoTo destination
    final distanceToDestination = Geolocator.distanceBetween(
          dropoffLocation.latitude,
          dropoffLocation.longitude,
          destination.latitude,
          destination.longitude,
        ) /
        1000; // Convert to km

    debugPrint(
      'GoToTimerService: Distance from dropoff to destination: ${distanceToDestination.toStringAsFixed(2)} km',
    );

    // Also check if dropoff is generally in the direction of destination
    // by comparing if dropoff is closer to destination than pickup
    final pickupToDestDist = Geolocator.distanceBetween(
          pickupLocation.latitude,
          pickupLocation.longitude,
          destination.latitude,
          destination.longitude,
        ) /
        1000;

    final isMovingTowardsDestination = distanceToDestination < pickupToDestDist;

    // Request is valid if:
    // 1. Dropoff is within max distance from destination, OR
    // 2. Ride is moving towards the destination (even if not reaching it)
    final isValid = distanceToDestination <= maxDestinationDistance ||
        (isMovingTowardsDestination &&
            distanceToDestination <= maxDestinationDistance * 2);

    debugPrint('GoToTimerService: Request towards destination: $isValid');
    return isValid;
  }

  /// Get remaining time as formatted string
  String getRemainingTimeFormatted() {
    if (!isGoToActive.value || goToEndTime.value == null) {
      return '';
    }

    final remaining = goToEndTime.value!.difference(DateTime.now());
    if (remaining.isNegative) {
      return 'Expired';
    }

    final hours = remaining.inHours;
    final minutes = remaining.inMinutes.remainder(60);

    if (hours > 0) {
      return '$hours hr ${minutes} min';
    } else {
      return '$minutes min';
    }
  }

  /// Private: Start countdown timer
  void _startCountdownTimer() {
    _countdownTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _updateRemainingTime();

      if (remainingMinutes.value <= 0) {
        timer.cancel();
      }
    });
  }

  /// Private: Start auto-disable timer
  void _startAutoDisableTimer(Duration duration) {
    _autoDisableTimer = Timer(duration, () {
      debugPrint('GoToTimerService: GoTo time expired, auto-disabling');
      deactivateGoTo(expired: true);
    });
  }

  /// Private: Update remaining time
  void _updateRemainingTime() {
    if (goToEndTime.value == null) {
      remainingMinutes.value = 0;
      return;
    }

    final remaining = goToEndTime.value!.difference(DateTime.now());
    remainingMinutes.value = remaining.inMinutes;

    if (remainingMinutes.value < 0) {
      remainingMinutes.value = 0;
    }
  }

  /// Get destination address
  String? getDestinationAddress() {
    return goToDestination.value?['address'] as String?;
  }

  /// Get destination location
  LatLng? getDestinationLocation() {
    if (goToDestination.value == null) return null;
    final lat = goToDestination.value!['lat'] as double;
    final lng = goToDestination.value!['lng'] as double;
    return LatLng(lat, lng);
  }
}
