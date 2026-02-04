import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:project_taxi_driver_app/widgets/ride_request.dart';

enum SortType {
  priceHighToLow,
  distanceLowToHigh,
  timeNewest,
}

class RequestQueueService extends GetxService {
  static RequestQueueService get instance => Get.find<RequestQueueService>();

  // Separate queues for daily and rental requests
  final RxList<RideRequest> dailyRequests = <RideRequest>[].obs;
  final RxList<RideRequest> rentalRequests = <RideRequest>[].obs;

  // Current sorting preference
  final Rx<SortType> currentSortType = SortType.timeNewest.obs;

  // Maximum number of requests to keep in queue
  final int maxQueueSize = 10;

  // Request timeout tracking
  final Map<String, Timer> _requestTimers = {};

  @override
  void onInit() {
    super.onInit();
    // Listen to sort type changes and re-sort
    ever(currentSortType, (_) {
      _sortRequests();
    });
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

  /// Get all requests (combined and sorted)
  List<RideRequest> getAllRequests() {
    final combined = [...dailyRequests, ...rentalRequests];
    return _sortList(combined);
  }

  /// Get total count
  int get totalCount => dailyRequests.length + rentalRequests.length;

  /// Change sort type
  void changeSortType(SortType type) {
    currentSortType.value = type;
  }

  /// Sort all queues based on current sort type
  void _sortRequests() {
    dailyRequests.value = _sortList(dailyRequests);
    rentalRequests.value = _sortList(rentalRequests);
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
    }

    return sorted;
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
    }
  }
}
