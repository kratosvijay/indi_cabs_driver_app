import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:project_taxi_driver_app/services/location_tracking_service.dart';
import 'package:project_taxi_driver_app/services/waiting_timer_service.dart';
import 'package:flutter/foundation.dart';

enum TripState {
  accepted,
  arrived,
  started,
  paused,
  resumed,
  completed,
  cancelled
}

class TripController extends GetxController {
  final String rideId;
  final String rideType;
  
  var currentState = TripState.accepted.obs;
  var accumulatedDistance = 0.0.obs;
  var currentFare = 0.0.obs;
  var waitingMinutes = 0.obs;
  
  final _firestore = FirebaseFirestore.instance;
  final _functions = FirebaseFunctions.instanceFor(region: 'asia-south1');
  
  TripController({required this.rideId, required this.rideType});

  @override
  void onInit() {
    super.onInit();
    _listenToRideUpdates();
    WaitingTimerService().waitingSecondsStream.listen((seconds) {
      waitingMinutes.value = (seconds / 60).ceil();
      // Sync to Firestore every 30 seconds or so to keep backend fare accurate
      if (seconds % 30 == 0) {
        _syncWaitingMinutes();
      }
    });
  }

  Future<void> _syncWaitingMinutes() async {
    String collection = rideType == 'rental' ? 'rental_requests' : 'ride_requests';
    await _firestore.collection(collection).doc(rideId).update({
      'waitingMinutes': waitingMinutes.value,
    });
  }

  void startWaiting() => WaitingTimerService().startWaiting();
  void stopWaiting() {
    WaitingTimerService().stopWaiting();
    _syncWaitingMinutes(); // Final sync when stopping
  }

  void _listenToRideUpdates() {
    String collection = rideType == 'rental' ? 'rental_requests' : 'ride_requests';
    _firestore.collection(collection).doc(rideId).snapshots().listen((snapshot) {
      if (snapshot.exists) {
        final data = snapshot.data()!;
        accumulatedDistance.value = (data['actualDistance'] ?? 0.0).toDouble();
        currentFare.value = (data['totalFare'] ?? data['rideFare'] ?? 0.0).toDouble();
        
        // Update state if changed by backend or other device
        final status = data['status'] as String?;
        if (status != null) {
          _updateStateFromStatus(status);
        }
      }
    });
  }

  void _updateStateFromStatus(String status) {
    switch (status) {
      case 'accepted': currentState.value = TripState.accepted; break;
      case 'arrived': currentState.value = TripState.arrived; break;
      case 'started': currentState.value = TripState.started; break;
      case 'paused': currentState.value = TripState.paused; break;
      case 'resumed': currentState.value = TripState.resumed; break;
      case 'completed': currentState.value = TripState.completed; break;
      case 'cancelled': currentState.value = TripState.cancelled; break;
    }
  }

  Future<void> updateStatus(TripState newState) async {
    String statusStr = newState.toString().split('.').last;
    String collection = rideType == 'rental' ? 'rental_requests' : 'ride_requests';
    
    try {
      await _firestore.collection(collection).doc(rideId).update({
        'status': statusStr,
        if (newState == TripState.started) 'startedAt': FieldValue.serverTimestamp(),
      });
      currentState.value = newState;
      
      if (newState == TripState.started || newState == TripState.resumed) {
        LocationTrackingService().startTracking(rideId);
      } else if (newState == TripState.paused || newState == TripState.completed || newState == TripState.cancelled) {
        LocationTrackingService().stopTracking();
        WaitingTimerService().stopWaiting();
      }
    } catch (e) {
      debugPrint("TripController: Error updating status: $e");
    }
  }

  Future<Map<String, dynamic>> calculateFinalFare() async {
    try {
      final result = await _functions.httpsCallable('calculateDynamicPricing').call({
        'rideId': rideId,
        'rideType': rideType,
        'waitingMinutes': WaitingTimerService().currentWaitingMinutes,
      });
      
      if (result.data['success'] == true) {
        currentFare.value = (result.data['finalFare'] as num).toDouble();
        return Map<String, dynamic>.from(result.data);
      }
    } catch (e) {
      debugPrint("TripController: Error calculating fare: $e");
    }
    return {};
  }
}
