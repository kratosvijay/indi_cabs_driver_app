import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:project_taxi_driver_app/widgets/ride_request.dart';

enum SortType {
  priceHighToLow,
  distanceLowToHigh,
  timeNewest,
  priorityScore,
  smartAI,
}

enum FilterType {
  all,
  cashOnly,
  digitalOnly,
  dailyOnly,
  rentalOnly,
  multiStopOnly,
  distanceNearby, // Within 5km
  distanceMedium, // 5-15km
  distanceFar, // 15km+
}

class RequestQueueService extends GetxService {
  static RequestQueueService get instance => Get.find<RequestQueueService>();

  // Separate queues for daily and rental requests
  final RxList<RideRequest> dailyRequests = <RideRequest>[].obs;
  final RxList<RideRequest> rentalRequests = <RideRequest>[].obs;

  // Current sorting preference
  final Rx<SortType> currentSortType = SortType.timeNewest.obs;

  // Current filter
  final Rx<FilterType> currentFilter = FilterType.all.obs;

  // Priority weights for smart sorting (can be adjusted based on ML/driver preferences)
  final RxDouble fareWeight = 0.5.obs; // 50% weight on fare
  final RxDouble distanceWeight = 0.3.obs; // 30% weight on distance
  final RxDouble timeWeight = 0.2.obs; // 20% weight on time

  // Maximum number of requests to keep in queue
  final int maxQueueSize = 10;

  // Request timeout tracking
  final Map<String, Timer> _requestTimers = {};

  // Driver preference learning (for ML-based sorting)
  final Map<String, dynamic> driverPreferences = {
    'preferredPaymentMethod': 'all', // cash, digital, all
    'preferredDistance': 'medium', // nearby, medium, far, all
    'preferredRideType': 'all', // daily, rental, all
    'avgAcceptedFare': 0.0,
    'avgAcceptedDistance': 0.0,
  };

  @override
  void onInit() {
    super.onInit();
    // Listen to sort type changes and re-sort
    ever(currentSortType, (_) {
      _sortRequests();
    });
    // Listen to filter changes and re-sort
    ever(currentFilter, (_) {
      _sortRequests();
    });
    // Listen to weight changes for priority scoring
    ever(fareWeight, (_) => _sortRequests());
    ever(distanceWeight, (_) => _sortRequests());
    ever(timeWeight, (_) => _sortRequests());
  }

  @override
  void onClose() {
    // Cancel all timers
    for (var timer in _requestTimers.values) {
      timer.cancel();
    }
    _requestTimers.clear();
    super.onClose();
  }

  /// Add a new daily request to the queue
  void addDailyRequest(RideRequest request) {
    debugPrint('RequestQueue: Adding daily request ${request.rideId}');

    // Check if already exists
    if (dailyRequests.any((r) => r.rideId == request.rideId)) {
      debugPrint('RequestQueue: Request ${request.rideId} already in queue');
      return;
    }

    // Add to queue
    dailyRequests.add(request);

    // Trim if exceeds max size (remove oldest)
    if (dailyRequests.length > maxQueueSize) {
      final removed = dailyRequests.removeAt(0);
      _cancelRequestTimer(removed.rideId);
      debugPrint('RequestQueue: Removed oldest request ${removed.rideId}');
    }

    // Sort the queue
    _sortRequests();

    // Start timeout timer (auto-remove after 30 seconds)
    _startRequestTimer(request.rideId, Duration(seconds: 30));
  }

  /// Add a new rental request to the queue
  void addRentalRequest(RideRequest request) {
    debugPrint('RequestQueue: Adding rental request ${request.rideId}');

    // Check if already exists
    if (rentalRequests.any((r) => r.rideId == request.rideId)) {
      debugPrint('RequestQueue: Request ${request.rideId} already in queue');
      return;
    }

    // Add to queue
    rentalRequests.add(request);

    // Trim if exceeds max size
    if (rentalRequests.length > maxQueueSize) {
      final removed = rentalRequests.removeAt(0);
      _cancelRequestTimer(removed.rideId);
      debugPrint('RequestQueue: Removed oldest rental ${removed.rideId}');
    }

    // Sort the queue
    _sortRequests();

    // Start timeout timer
    _startRequestTimer(request.rideId, Duration(seconds: 30));
  }

  /// Remove a request by ID
  void removeRequest(String rideId) {
    debugPrint('RequestQueue: Removing request $rideId');
    dailyRequests.removeWhere((r) => r.rideId == rideId);
    rentalRequests.removeWhere((r) => r.rideId == rideId);
    _cancelRequestTimer(rideId);
  }

  /// Remove all requests
  void clearAll() {
    debugPrint('RequestQueue: Clearing all requests');
    for (var timer in _requestTimers.values) {
      timer.cancel();
    }
    _requestTimers.clear();
    dailyRequests.clear();
    rentalRequests.clear();
  }

  /// Get all requests (combined, filtered, and sorted)
  List<RideRequest> getAllRequests() {
    final combined = [...dailyRequests, ...rentalRequests];
    final filtered = _filterList(combined);
    return _sortList(filtered);
  }

  /// Get filtered daily requests only
  List<RideRequest> getFilteredDailyRequests() {
    return _filterList(dailyRequests);
  }

  /// Get filtered rental requests only
  List<RideRequest> getFilteredRentalRequests() {
    return _filterList(rentalRequests);
  }

  /// Get total count
  int get totalCount => dailyRequests.length + rentalRequests.length;

  /// Change sort type
  void changeSortType(SortType type) {
    currentSortType.value = type;
  }

  /// Change filter
  void changeFilter(FilterType filter) {
    currentFilter.value = filter;
  }

  /// Update priority weights (for custom priority scoring)
  void updatePriorityWeights({
    double? fare,
    double? distance,
    double? time,
  }) {
    if (fare != null) fareWeight.value = fare;
    if (distance != null) distanceWeight.value = distance;
    if (time != null) timeWeight.value = time;
  }

  /// Learn from accepted ride (for ML-based sorting)
  void learnFromAcceptedRide(RideRequest request) {
    // Update average accepted fare
    final currentAvg = driverPreferences['avgAcceptedFare'] as double;
    driverPreferences['avgAcceptedFare'] = (currentAvg + request.rideFare) / 2;

    // Update average accepted distance
    final currentDist = driverPreferences['avgAcceptedDistance'] as double;
    driverPreferences['avgAcceptedDistance'] =
        (currentDist + request.driverDistance) / 2;

    // Learn payment method preference
    final paymentMethod = request.paymentMethod.toLowerCase();
    if (paymentMethod.contains('cash')) {
      driverPreferences['preferredPaymentMethod'] = 'cash';
    } else if (paymentMethod.contains('digital') ||
        paymentMethod.contains('online')) {
      driverPreferences['preferredPaymentMethod'] = 'digital';
    }

    // Learn distance preference
    if (request.driverDistance < 5) {
      driverPreferences['preferredDistance'] = 'nearby';
    } else if (request.driverDistance < 15) {
      driverPreferences['preferredDistance'] = 'medium';
    } else {
      driverPreferences['preferredDistance'] = 'far';
    }

    // Learn ride type preference
    driverPreferences['preferredRideType'] =
        request.rideType == 'rental' ? 'rental' : 'daily';

    debugPrint('RequestQueue: Updated driver preferences: $driverPreferences');
  }

  /// Sort all queues based on current sort type
  void _sortRequests() {
    dailyRequests.value = _sortList(dailyRequests);
    rentalRequests.value = _sortList(rentalRequests);
  }

  /// Filter list based on current filter
  List<RideRequest> _filterList(List<RideRequest> requests) {
    switch (currentFilter.value) {
      case FilterType.all:
        return requests;

      case FilterType.cashOnly:
        return requests
            .where(
              (r) =>
                  r.paymentMethod.toLowerCase().contains('cash') &&
                  !r.paymentMethod.toLowerCase().contains('digital'),
            )
            .toList();

      case FilterType.digitalOnly:
        return requests
            .where(
              (r) =>
                  !r.paymentMethod.toLowerCase().contains('cash') ||
                  r.paymentMethod.toLowerCase().contains('digital') ||
                  r.paymentMethod.toLowerCase().contains('online'),
            )
            .toList();

      case FilterType.dailyOnly:
        return requests.where((r) => r.rideType != 'rental').toList();

      case FilterType.rentalOnly:
        return requests.where((r) => r.rideType == 'rental').toList();

      case FilterType.multiStopOnly:
        return requests.where((r) => r.stops.isNotEmpty).toList();

      case FilterType.distanceNearby:
        return requests.where((r) => r.driverDistance < 5).toList();

      case FilterType.distanceMedium:
        return requests
            .where((r) => r.driverDistance >= 5 && r.driverDistance < 15)
            .toList();

      case FilterType.distanceFar:
        return requests.where((r) => r.driverDistance >= 15).toList();
    }
  }

  /// Sort a list of requests
  List<RideRequest> _sortList(List<RideRequest> requests) {
    final sorted = List<RideRequest>.from(requests);

    switch (currentSortType.value) {
      case SortType.priceHighToLow:
        sorted.sort((a, b) => b.rideFare.compareTo(a.rideFare));
        break;

      case SortType.distanceLowToHigh:
        sorted.sort((a, b) => a.driverDistance.compareTo(b.driverDistance));
        break;

      case SortType.timeNewest:
        // Maintain order as received (newest last in queue)
        // No sorting needed as we add to end
        break;

      case SortType.priorityScore:
        // Calculate priority score for each request
        sorted.sort((a, b) {
          final scoreA = _calculatePriorityScore(a);
          final scoreB = _calculatePriorityScore(b);
          return scoreB.compareTo(scoreA); // Higher score first
        });
        break;

      case SortType.smartAI:
        // AI/ML-based sorting using driver preferences
        sorted.sort((a, b) {
          final scoreA = _calculateSmartScore(a);
          final scoreB = _calculateSmartScore(b);
          return scoreB.compareTo(scoreA);
        });
        break;
    }

    return sorted;
  }

  /// Calculate priority score based on fare, distance, and time weights
  double _calculatePriorityScore(RideRequest request) {
    // Normalize values to 0-1 range for fair comparison
    final maxFare = 1000.0; // Assumed max fare
    final maxDistance = 50.0; // Assumed max distance in km

    final normalizedFare = (request.rideFare / maxFare).clamp(0.0, 1.0);
    final normalizedDistance =
        (1 - (request.driverDistance / maxDistance)).clamp(0.0, 1.0);
    // Time weight could be based on how recently added (not implemented here)
    final normalizedTime = 1.0; // Placeholder

    final score = (normalizedFare * fareWeight.value) +
        (normalizedDistance * distanceWeight.value) +
        (normalizedTime * timeWeight.value);

    return score;
  }

  /// Calculate smart AI score based on driver preferences
  double _calculateSmartScore(RideRequest request) {
    double score = 0.0;

    // Base priority score
    score += _calculatePriorityScore(request);

    // Bonus for matching payment preference
    final preferredPayment = driverPreferences['preferredPaymentMethod'];
    if (preferredPayment == 'all') {
      score += 0.1;
    } else if (preferredPayment == 'cash' &&
        request.paymentMethod.toLowerCase().contains('cash')) {
      score += 0.3;
    } else if (preferredPayment == 'digital' &&
        !request.paymentMethod.toLowerCase().contains('cash')) {
      score += 0.3;
    }

    // Bonus for matching distance preference
    final preferredDistance = driverPreferences['preferredDistance'];
    if (preferredDistance == 'nearby' && request.driverDistance < 5) {
      score += 0.2;
    } else if (preferredDistance == 'medium' &&
        request.driverDistance >= 5 &&
        request.driverDistance < 15) {
      score += 0.2;
    } else if (preferredDistance == 'far' && request.driverDistance >= 15) {
      score += 0.2;
    }

    // Bonus for matching ride type preference
    final preferredType = driverPreferences['preferredRideType'];
    if (preferredType == 'all') {
      score += 0.1;
    } else if (preferredType == 'rental' && request.rideType == 'rental') {
      score += 0.2;
    } else if (preferredType == 'daily' && request.rideType != 'rental') {
      score += 0.2;
    }

    // Bonus for fare above average
    final avgFare = driverPreferences['avgAcceptedFare'] as double;
    if (avgFare > 0 && request.rideFare > avgFare) {
      score += 0.15;
    }

    // Bonus for multi-stop rides (usually higher fare)
    if (request.stops.isNotEmpty) {
      score += 0.1 * request.stops.length.clamp(0, 3);
    }

    return score;
  }

  /// Start a timer to auto-remove request after timeout
  void _startRequestTimer(String rideId, Duration duration) {
    _cancelRequestTimer(rideId); // Cancel existing if any

    _requestTimers[rideId] = Timer(duration, () {
      debugPrint('RequestQueue: Request $rideId timed out');
      removeRequest(rideId);
    });
  }

  /// Cancel request timer
  void _cancelRequestTimer(String rideId) {
    _requestTimers[rideId]?.cancel();
    _requestTimers.remove(rideId);
  }

  /// Get sort type display name
  String getSortTypeName(SortType type) {
    switch (type) {
      case SortType.priceHighToLow:
        return 'sortPriceHighToLow'.tr;
      case SortType.distanceLowToHigh:
        return 'sortDistanceLowToHigh'.tr;
      case SortType.timeNewest:
        return 'sortTimeNewest'.tr;
      case SortType.priorityScore:
        return 'sortPriorityScore'.tr;
      case SortType.smartAI:
        return 'sortSmartAI'.tr;
    }
  }

  /// Get filter type display name
  String getFilterTypeName(FilterType type) {
    switch (type) {
      case FilterType.all:
        return 'filterAll'.tr;
      case FilterType.cashOnly:
        return 'filterCashOnly'.tr;
      case FilterType.digitalOnly:
        return 'filterDigitalOnly'.tr;
      case FilterType.dailyOnly:
        return 'filterDailyOnly'.tr;
      case FilterType.rentalOnly:
        return 'filterRentalOnly'.tr;
      case FilterType.multiStopOnly:
        return 'filterMultiStopOnly'.tr;
      case FilterType.distanceNearby:
        return 'filterDistanceNearby'.tr;
      case FilterType.distanceMedium:
        return 'filterDistanceMedium'.tr;
      case FilterType.distanceFar:
        return 'filterDistanceFar'.tr;
    }
  }
}
