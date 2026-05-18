import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';

class LocationTrackingService {
  static final LocationTrackingService _instance = LocationTrackingService._internal();
  factory LocationTrackingService() => _instance;
  LocationTrackingService._internal();

  StreamSubscription<Position>? _positionSubscription;
  final _database = FirebaseDatabase.instance.ref();
  String? _currentRideId;

  void startTracking(String rideId) {
    if (_currentRideId == rideId) return;
    _currentRideId = rideId;
    
    debugPrint("LocationTrackingService: Starting tracking for ride $rideId");
    
    // Clear old subscription if exists
    _positionSubscription?.cancel();

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Send every 10 meters to avoid excessive writes
      ),
    ).listen((Position position) {
      _sendLocationToRTDB(position);
    });
  }

  void stopTracking() {
    debugPrint("LocationTrackingService: Stopping tracking for ride $_currentRideId");
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _currentRideId = null;
  }

  Future<void> _sendLocationToRTDB(Position position) async {
    if (_currentRideId == null) return;

    try {
      final pointRef = _database.child("driver_trips/$_currentRideId/points").push();
      await pointRef.set({
        "lat": position.latitude,
        "lng": position.longitude,
        "accuracy": position.accuracy,
        "speed": position.speed,
        "timestamp": DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      debugPrint("LocationTrackingService: Error sending location: $e");
    }
  }
}
