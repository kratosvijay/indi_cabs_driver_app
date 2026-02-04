# Multiple Ride Requests Feature - Integration Guide

## Overview
This feature enables drivers to receive and manage multiple ride requests simultaneously (both daily and rental) with sorting capabilities and system overlay support.

## New Files Created

### 1. `/lib/services/request_queue_service.dart`
A service to manage multiple ride requests with sorting capabilities.

**Key Features:**
- Separate queues for daily and rental requests
- Sorting options: Price (High to Low), Distance (Low to High), Time (Newest)
- Auto-timeout for requests (30 seconds)
- Maximum queue size management (10 requests)

### 2. `/lib/widgets/multi_request_card.dart`
A widget that displays multiple requests in a swipeable card format.

**Key Features:**
- PageView for swiping between requests
- Auto-translation support for addresses
- Visual indicators for current position
- Sort menu integration
- Progress bar with auto-reject timer

### 3. `/lib/services/overlay_service_enhanced.dart`
Enhanced overlay service for displaying multiple requests over other apps.

**Key Features:**
- Support for multiple request overlays
- Sorting integration
- Dynamic sizing based on screen dimensions

## Integration Steps

### Step 1: Initialize Request Queue Service

In `lib/main.dart`, add initialization:

```dart
import 'package:project_taxi_driver_app/services/request_queue_service.dart';

void main() async {
  // ... existing initialization
  
  // Initialize Request Queue Service
  Get.put(RequestQueueService());
  
  runApp(MyApp());
}
```

### Step 2: Update Home Page Controller

In `lib/controllers/home_page_controller.dart`:

#### Import the new services:
```dart
import 'package:project_taxi_driver_app/services/request_queue_service.dart';
import 'package:project_taxi_driver_app/services/overlay_service_enhanced.dart';
```

#### Add queue service reference:
```dart
class HomePageController extends GetxController with WidgetsBindingObserver {
  // ... existing fields
  
  final RequestQueueService _queueService = RequestQueueService.instance;
  
  // ... rest of the controller
}
```

#### Modify `_processRideDocument` method:

Replace the single `activeRideRequest.value = newRequest;` with queue management:

```dart
Future<void> _processRideDocument(
  DocumentSnapshot doc,
  Map<String, dynamic> data,
) async {
  // ... existing code to create newRequest
  
  // Instead of setting activeRideRequest directly:
  // activeRideRequest.value = newRequest;
  
  // Add to queue based on ride type
  if (newRequest.rideType == 'rental') {
    _queueService.addRentalRequest(newRequest);
  } else {
    _queueService.addDailyRequest(newRequest);
  }
  
  // Trigger Overlay if Backgrounded
  if (_appLifecycleState == AppLifecycleState.paused) {
    _showMultipleRequestsOverlay();
  }
  
  // For rental requests, only navigate if it's the first rental
  if (newRequest.rideType == 'rental' && _queueService.rentalRequests.length == 1) {
    if (_isAcceptingRide) {
      debugPrint("Skipping rental screen navigation (already accepting)");
      return;
    }
    playRentalNotification();
    // Show rental request screen or handle accordingly
  } else if (newRequest.rideType != 'rental') {
    // Play sound only if not already accepting
    if (!_isAcceptingRide) {
      playRideRequestSound();
    } else {
      stopRideRequestSound();
    }
  }
  
  startRideTimeout(doc.id);
  debugPrint("Ride Request Added to Queue: ${doc.id}");
}
```

#### Add method to show multiple requests overlay:

```dart
Future<void> _showMultipleRequestsOverlay() async {
  final requests = _queueService.getAllRequests();
  if (requests.isEmpty) return;
  
  final requestsData = requests.map((r) => r.toJson()).toList();
  final sortType = _queueService.currentSortType.value.toString().split('.').last;
  
  await OverlayServiceEnhanced.instance.showMultipleRequestsOverlay(
    requestsData,
    sortType,
  );
}
```

#### Update `onRideAccepted` method:

```dart
Future<void> onRideAccepted() async {
  // Check if we have requests in queue
  final requests = _queueService.getAllRequests();
  if (requests.isEmpty) return;
  
  final request = requests.first; // Accept the first one (or current page)
  
  if (isRideAcceptanceInProgress.value) {
    debugPrint("Ride acceptance already in progress. Ignoring.");
    return;
  }
  
  // ... existing acceptance logic
  
  // Remove from queue after successful acceptance
  _queueService.removeRequest(request.rideId);
}
```

#### Update `onRideRejected` method:

```dart
Future<void> onRideRejected(String reason) async {
  debugPrint("Ride Rejected: $reason");
  
  final requests = _queueService.getAllRequests();
  if (requests.isEmpty) return;
  
  final request = requests.first; // Or the specific rejected request
  
  // Remove from queue
  _queueService.removeRequest(request.rideId);
  
  // Stop sounds
  stopRideRequestSound();
  
  // ... rest of rejection logic
}
```

### Step 3: Update Homepage Widget

In `lib/screens/homepage.dart`:

Replace the single `RideRequestCard` with `MultiRequestCard`:

```dart
import 'package:project_taxi_driver_app/widgets/multi_request_card.dart';
import 'package:project_taxi_driver_app/services/request_queue_service.dart';

// ... in build method, replace the RideRequestCard Obx widget:

// Multi-Request Card
Obx(() {
  final queueService = RequestQueueService.instance;
  if ((queueService.dailyRequests.isNotEmpty || 
       queueService.rentalRequests.isNotEmpty) &&
      !controller.isRideAcceptanceInProgress.value) {
    return MultiRequestCard(
      onAccept: (request) {
        // Set as active request and accept
        controller.activeRideRequest.value = request;
        controller.onRideAccepted();
      },
      onReject: (request) {
        RequestQueueService.instance.removeRequest(request.rideId);
        controller.stopRideRequestSound();
      },
    );
  }
  return const SizedBox.shrink();
}),
```

### Step 4: Update Overlay Entry Point

In `lib/services/overlay_service.dart`, update the overlay listener to handle multiple requests:

```dart
// In _OverlayBubbleWidgetState's initState, update the listener:

_subscription = FlutterOverlayWindow.overlayListener.listen((data) async {
  debugPrint('_OverlayBubbleWidgetState: Received data: $data');
  if (!mounted) return;
  
  if (data is Map) {
    if (data['type'] == 'multiple_requests') {
      final width = (data['width'] as num?)?.toInt() ?? 500;
      final height = (data['height'] as num?)?.toInt() ?? 600;
      
      try {
        await FlutterOverlayWindow.resizeOverlay(width, height, true);
      } catch (e) {
        debugPrint("Error resizing overlay: $e");
      }
      
      if (mounted) {
        setState(() {
          _multipleRequests = List<Map<String, dynamic>>.from(data['requests'] ?? []);
          _sortType = data['sortType'] ?? 'timeNewest';
          _currentPage = 0;
          _startTimer();
        });
      }
    }
    // ... existing single request handling
  }
});
```

Add new state variables to `_OverlayBubbleWidgetState`:

```dart
class _OverlayBubbleWidgetState extends State<OverlayBubbleWidget> {
  Map<String, dynamic>? _rideRequest;
  List<Map<String, dynamic>>? _multipleRequests;
  String _sortType = 'timeNewest';
  int _currentPage = 0;
  
  Timer? _timer;
  double _progressValue = 1.0;
  
  StreamSubscription? _subscription;
  final PageController _pageController = PageController();
  
  // ... rest of the class
}
```

## Testing Checklist

- [ ] Multiple daily requests display correctly in swipeable card
- [ ] Multiple rental requests display separately
- [ ] Sorting by price works (high to low)
- [ ] Sorting by distance works (low to high)
- [ ] Sorting by time works (newest first)
- [ ] Overlay displays when app is backgrounded
- [ ] Overlay supports swiping between multiple requests
- [ ] Accept button works from in-app card
- [ ] Accept button works from overlay
- [ ] Reject/Pass button removes request from queue
- [ ] Auto-timeout removes requests after 30 seconds
- [ ] Queue doesn't exceed 10 requests
- [ ] Translations work for different languages
- [ ] Progress bar shows correctly
- [ ] Sound plays only once for multiple requests
- [ ] Rental requests open rental screen appropriately

## Configuration Options

### Adjust Queue Size
In `request_queue_service.dart`:
```dart
final int maxQueueSize = 10; // Change this value
```

### Adjust Timeout Duration
In `request_queue_service.dart`:
```dart
_startRequestTimer(request.rideId, Duration(seconds: 30)); // Change duration
```

### Adjust Card Timer
In `multi_request_card.dart`:
```dart
_progressValue -= 0.01; // Adjust for different timeout (currently 5 seconds)
```

## Troubleshooting

### Requests Not Showing
- Check that `RequestQueueService` is initialized in `main.dart`
- Verify `_processRideDocument` is calling `_queueService.addDailyRequest()` or `addRentalRequest()`
- Check console logs for "RequestQueue: Adding..." messages

### Sorting Not Working
- Verify sort type is being saved: `_queueService.changeSortType(type)`
- Check that requests have valid `rideFare` and `driverDistance` values

### Overlay Not Appearing
- Ensure overlay permissions are granted
- Check `_appLifecycleState == AppLifecycleState.paused`
- Verify `OverlayServiceEnhanced.instance.showMultipleRequestsOverlay()` is called

### Multiple Sounds Playing
- Ensure `_isAcceptingRide` flag is checked before playing sounds
- Call `stopRideRequestSound()` when accepting or rejecting

## Future Enhancements

1. **Priority Queue**: Assign priority based on fare, distance, or driver ratings
2. **Filter Options**: Filter by payment method, ride type, or distance range
3. **Smart Sorting**: ML-based sorting based on driver preferences
4. **Request Preview**: Show thumbnail map preview for each request
5. **Batch Accept**: Allow accepting multiple compatible requests
6. **Custom Timeout**: Let drivers set their own timeout preferences
7. **Analytics**: Track which sorting method leads to most acceptances

## API Changes Summary

### New Services
- `RequestQueueService`: Manages request queue
- `OverlayServiceEnhanced`: Enhanced overlay with multiple request support

### New Widgets
- `MultiRequestCard`: Displays multiple requests with sorting

### Modified Files
- `app_translations.dart`: Added sorting translation keys
- `home_page_controller.dart`: Integrated queue service (requires manual integration)
- `homepage.dart`: Uses new multi-request card (requires manual integration)
- `overlay_service.dart`: Supports multiple requests in overlay (requires manual updates)

## Breaking Changes
None - This feature is additive and maintains backward compatibility with existing single-request flow.

## Version Compatibility
- Flutter SDK: >=3.0.0
- Dart SDK: >=3.0.0
- Dependencies: Uses existing project dependencies

## Support
For issues or questions, refer to the project's main documentation or contact the development team.
