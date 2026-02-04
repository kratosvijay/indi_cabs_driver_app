# GoTo Auto-Timeout Feature - Integration Guide

## Overview
This feature adds automatic timeout functionality to GoTo mode with destination-based request filtering. When a driver activates GoTo, they will only receive requests towards their destination for a specified duration (default: 1 hour), after which the app automatically switches back to online mode.

## New Files Created

### 1. `/lib/services/goto_timer_service.dart`
Service to manage GoTo timer, destination filtering, and auto-disable functionality.

**Key Features:**
- 1-hour default timeout with customizable duration
- Countdown timer with minute-by-minute updates
- Auto-disable when time expires
- Destination-based request filtering (within 15km or moving towards)
- Extend GoTo functionality
- Manual deactivation support

### 2. `/lib/widgets/goto_status_banner.dart`
Widget to display GoTo status with remaining time and quick actions.

**Key Features:**
- Visual banner showing destination and remaining time
- Warning when less than 10 minutes remain
- Extend GoTo button with options (30 min, 1 hour)
- Deactivate GoTo button
- Activation dialog with confirmation

## Integration Steps

### Step 1: Initialize GoTo Timer Service

In `lib/main.dart`, add initialization:

```dart
import 'package:project_taxi_driver_app/services/goto_timer_service.dart';

void main() async {
  // ... existing initialization
  
  // Initialize GoTo Timer Service
  Get.put(GoToTimerService());
  
  runApp(MyApp());
}
```

### Step 2: Update Home Page Controller

In `lib/controllers/home_page_controller.dart`:

#### Import the service:
```dart
import 'package:project_taxi_driver_app/services/goto_timer_service.dart';
import 'package:project_taxi_driver_app/widgets/goto_status_banner.dart';
```

#### Add service reference and setup callback:
```dart
class HomePageController extends GetxController with WidgetsBindingObserver {
  // ... existing fields
  
  final GoToTimerService _goToTimerService = GoToTimerService.instance;
  
  @override
  void onInit() {
    super.onInit();
    // ... existing initialization
    
    // Setup GoTo expiry callback
    _goToTimerService.onGoToExpired = _onGoToExpired;
  }
  
  // Handle GoTo expiry - switch back to online
  void _onGoToExpired() {
    debugPrint('GoTo expired, switching to online mode');
    
    // Show notification
    Get.snackbar(
      'gotoExpired'.tr,
      'gotoExpiredMessage'.tr,
      snackPosition: SnackPosition.TOP,
      backgroundColor: Colors.orange,
      colorText: Colors.white,
      duration: const Duration(seconds: 3),
      icon: const Icon(Icons.access_time, color: Colors.white),
    );
    
    // Update status to online
    handleStatusChange(DriverStatus.online);
  }
}
```

#### Modify `handleStatusChange` method to show activation dialog:

```dart
Future<void> handleStatusChange(DriverStatus status) async {
  // ... existing code
  
  if (status == DriverStatus.goTo) {
    debugPrint("Opening GoToScreen...");
    
    final result = await Get.to<Map<String, dynamic>>(
      () => GoToScreen(activeDestination: goToDestination.value),
    );
    
    if (result != null) {
      debugPrint("GoTo Result obtained: $result");
      
      if (result.containsKey('clear') && result['clear'] == true) {
        debugPrint("GoTo Cancelled/Cleared");
        goToDestination.value = null;
        _goToTimerService.deactivateGoTo();
        
        // Firestore update to remove GoTo
        await FirebaseFirestore.instance
            .collection('drivers')
            .doc(user.uid)
            .set({
              'isOnline': true,
              'goToDestination': FieldValue.delete(),
            }, SetOptions(merge: true));
      } else {
        // Show activation dialog
        showGoToActivationDialog(
          destination: result['address'],
          duration: const Duration(hours: 1),
          onConfirm: () async {
            goToDestination.value = result;
            
            // Activate GoTo timer
            await _goToTimerService.activateGoTo(result);
            
            // Firestore update for GoTo
            await FirebaseFirestore.instance
                .collection('drivers')
                .doc(user.uid)
                .set({
                  'isOnline': true,
                  'goToDestination': {
                    'address': result['address'],
                    'location': GeoPoint(
                      (result['location'] as LatLng).latitude,
                      (result['location'] as LatLng).longitude,
                    ),
                  },
                }, SetOptions(merge: true));
          },
        );
      }
    } else {
      debugPrint("GoTo cancelled, reverting to online");
      driverStatus.value = DriverStatus.online;
      await FirebaseFirestore.instance
          .collection('drivers')
          .doc(user.uid)
          .set({'isOnline': true}, SetOptions(merge: true));
    }
  }
  
  // ... rest of existing code
}
```

#### Filter requests based on GoTo destination in `_processRideDocument`:

```dart
Future<void> _processRideDocument(
  DocumentSnapshot doc,
  Map<String, dynamic> data,
) async {
  // ... existing code to parse locations and create newRequest
  
  // Filter by GoTo destination if active
  if (_goToTimerService.isGoToActive.value) {
    final isTowardsDestination = _goToTimerService.isRequestTowardsDestination(
      pickupLocation,
      finalDestination,
    );
    
    if (!isTowardsDestination) {
      debugPrint(
        'Skipping request ${doc.id}: Not towards GoTo destination',
      );
      return; // Skip this request
    }
    
    debugPrint('Request ${doc.id} is towards GoTo destination');
  }
  
  // ... rest of processing code
}
```

### Step 3: Update Homepage Widget

In `lib/screens/homepage.dart`:

#### Import the widget:
```dart
import 'package:project_taxi_driver_app/widgets/goto_status_banner.dart';
import 'package:project_taxi_driver_app/services/goto_timer_service.dart';
```

#### Add GoTo status banner to the Stack:

```dart
body: Stack(
  children: [
    // ... existing map and content
    
    // GoTo Status Banner (below queue banner, above ride request cards)
    Positioned(
      top: 160, // Adjust based on your layout
      left: 0,
      right: 0,
      child: GoToStatusBanner(
        onExtend: () {
          // Optional: Refresh or update something
        },
        onDeactivate: () {
          // Switch back to online mode
          controller.handleStatusChange(DriverStatus.online);
        },
      ),
    ),
    
    // ... ride request cards
  ],
),
```

### Step 4: Update GoTo Screen

In `lib/screens/goto.dart`, show the activation dialog when selecting a destination:

```dart
import 'package:project_taxi_driver_app/widgets/goto_status_banner.dart';

// In _saveAndSelectLocation method:
Future<void> _saveAndSelectLocation(Map<String, dynamic> placeData) async {
  final destinationToSave = {
    'address': placeData['address'],
    'lat': (placeData['location'] as LatLng).latitude,
    'lng': (placeData['location'] as LatLng).longitude,
  };
  await _saveRecentDestinations(destinationToSave);
  
  if (mounted) {
    // Return the destination - activation dialog will be shown in controller
    Get.back(result: placeData);
  }
}
```

## Features Explained

### 1. Automatic Timeout (1 Hour Default)
When GoTo is activated, a timer starts for 1 hour. After this time:
- GoTo automatically deactivates
- Driver status switches to online mode
- Notification is shown to the driver
- All ride requests become visible again

### 2. Destination-Based Filtering
Requests are filtered based on two criteria:
- **Within 15km**: Dropoff location is within 15km of GoTo destination
- **Moving Towards**: Ride is moving towards the destination (even if not reaching it exactly)

This ensures drivers get relevant requests that help them reach their destination.

### 3. Visual Status Banner
The banner shows:
- GoTo destination address
- Remaining time (updates every minute)
- Warning when less than 10 minutes remain (orange color)
- Quick extend and deactivate buttons

### 4. Extend Functionality
Drivers can extend GoTo time:
- **30 minutes**: Quick extension
- **1 hour**: Full hour extension
- Multiple extensions allowed
- Timer resets with new end time

### 5. Manual Deactivation
Drivers can manually deactivate GoTo:
- Confirmation dialog prevents accidental deactivation
- Immediately switches back to online mode
- Clears GoTo destination from Firestore

## Configuration Options

### Adjust Default Duration
In `goto_timer_service.dart`:
```dart
final Duration goToDuration = const Duration(hours: 1); // Change this
```

### Adjust Destination Distance Threshold
In `goto_timer_service.dart`:
```dart
final double maxDestinationDistance = 15.0; // Change this (in km)
```

### Adjust Warning Threshold
In `goto_status_banner.dart`:
```dart
final isExpiringSoon = goToService.remainingMinutes.value <= 10; // Change this
```

## Testing Checklist

- [ ] GoTo activation shows confirmation dialog
- [ ] Dialog displays destination and duration correctly
- [ ] Status banner appears after activation
- [ ] Remaining time updates every minute
- [ ] Only requests towards destination are shown
- [ ] Requests outside 15km range are filtered
- [ ] Warning appears when less than 10 minutes remain
- [ ] Extend 30 min option works
- [ ] Extend 1 hour option works
- [ ] Manual deactivation shows confirmation
- [ ] Manual deactivation switches to online mode
- [ ] Auto-timeout triggers after 1 hour
- [ ] Expiry notification is shown
- [ ] Auto-timeout switches to online mode
- [ ] GoTo state persists across app restarts (if desired)
- [ ] Firestore GoTo destination is updated correctly
- [ ] Firestore GoTo destination is cleared on deactivation

## Firestore Integration

The GoTo destination is stored in Firestore under the driver document:

```json
{
  "driverId": "...",
  "isOnline": true,
  "goToDestination": {
    "address": "123 Main St, City",
    "location": {
      "_latitude": 13.0827,
      "_longitude": 80.2707
    }
  }
}
```

This allows:
- Backend services to route appropriate requests
- State persistence across app sessions
- Analytics on GoTo usage patterns

## Algorithm Details

### Destination Filtering Logic

```dart
isValid = (distanceToDestination <= 15km) OR 
          (movingTowardsDestination AND distanceToDestination <= 30km)
```

Where:
- `distanceToDestination` = Distance from dropoff to GoTo destination
- `movingTowardsDestination` = Dropoff is closer to destination than pickup

This ensures:
- Rides ending near the destination are always shown
- Rides moving towards but not reaching the destination are also shown
- Rides going away from the destination are filtered out

## UI/UX Considerations

### Color Coding
- **Blue**: Normal GoTo mode (plenty of time)
- **Orange**: Warning mode (< 10 minutes remaining)
- **Icons**: Navigation icon for active, warning icon for expiring

### User Flow
1. Driver opens GoTo screen
2. Driver selects destination
3. Confirmation dialog appears with:
   - Destination address
   - Duration (1 hour)
   - Warning about filtered requests
4. Driver confirms activation
5. Success notification appears
6. Status banner shows at top of screen
7. Only relevant requests appear
8. Driver can extend or deactivate at any time
9. After 1 hour, automatic expiry notification
10. Switch back to online mode

## Performance Considerations

- Timer updates every 1 minute (not every second) to save battery
- Distance calculations only performed for incoming requests
- No polling - uses reactive state management
- Banner only renders when GoTo is active

## Future Enhancements

1. **Multiple Duration Options**: Let driver choose 30min, 1hr, 2hr, etc.
2. **Smart Extensions**: Auto-suggest extension when close to destination
3. **Route Optimization**: Show estimated time to reach destination
4. **History**: Track GoTo usage patterns
5. **Analytics**: Dashboard showing GoTo effectiveness
6. **Pause/Resume**: Temporarily pause GoTo without deactivating
7. **Custom Radius**: Let driver set destination radius preference
8. **Multi-Destination**: Support waypoints on the way to destination

## Troubleshooting

### GoTo Not Filtering Requests
- Check `maxDestinationDistance` value
- Verify destination coordinates are correct
- Ensure `isRequestTowardsDestination` is called in `_processRideDocument`
- Check console logs for distance calculations

### Timer Not Auto-Disabling
- Verify `onGoToExpired` callback is set
- Check if timer is being canceled prematurely
- Ensure app lifecycle doesn't interfere with timer

### Banner Not Showing
- Check if `GoToStatusBanner` is in the widget tree
- Verify `GoToTimerService` is initialized
- Use `Obx` wrapper if needed for reactivity

### Extend Not Working
- Check if new end time is being calculated correctly
- Verify timers are being restarted
- Check console logs for extend operations

## Support

For issues or questions, refer to the project's main documentation or contact the development team.
