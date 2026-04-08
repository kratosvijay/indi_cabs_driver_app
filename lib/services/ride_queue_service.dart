import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as maps;

/// Service for managing ride queues - back-to-back ride functionality
class RideQueueService {
  static final RideQueueService _instance = RideQueueService._internal();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  factory RideQueueService() {
    return _instance;
  }

  RideQueueService._internal();

  /// Calculate ETA (in seconds) from current location to destination
  /// Returns null if calculation fails
  Future<int?> calculateETAToDestination(
    maps.LatLng currentLocation,
    maps.LatLng destination,
  ) async {
    try {
      // Calculate straight-line distance
      final distanceInMeters = Geolocator.distanceBetween(
        currentLocation.latitude,
        currentLocation.longitude,
        destination.latitude,
        destination.longitude,
      );

      // Assume average speed of 40 km/h in urban areas (adjust as needed)
      // distanceInMeters / (40 km/h in m/s) = distanceInMeters / 11.11
      const double averageSpeedMs = 11.11; // 40 km/h converted to m/s
      final int etaSeconds = (distanceInMeters / averageSpeedMs).toInt();

      debugPrint(
        "[RideQueueService] ETA Calculation: ${distanceInMeters}m @ ${averageSpeedMs}m/s = ${etaSeconds}s",
      );

      return etaSeconds;
    } catch (e) {
      debugPrint("[RideQueueService] Error calculating ETA: $e");
      return null;
    }
  }

  /// Check if driver is approaching destination (within 3 minutes)
  Future<bool> isApproachingDestination(
    maps.LatLng currentLocation,
    maps.LatLng destination,
  ) async {
    final eta = await calculateETAToDestination(currentLocation, destination);
    return eta != null && eta <= 180; // 180 seconds = 3 minutes
  }

  /// Create a new ride queue for driver
  Future<void> createQueue({
    required String driverId,
    required String currentRideId,
    required DateTime estimatedDropTime,
  }) async {
    try {
      await _firestore
          .collection('driver_ride_queue')
          .doc(driverId)
          .set({
        'driverId': driverId,
        'currentRideId': currentRideId,
        'queuedRideIds': [],
        'estimatedDropTime': Timestamp.fromDate(estimatedDropTime),
        'position': 0,
        'createdAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
      });

      debugPrint("[RideQueueService] Queue created for driver: $driverId");
    } catch (e) {
      debugPrint("[RideQueueService] Error creating queue: $e");
    }
  }

  /// Add ride to driver's queue
  Future<bool> addToQueue({
    required String driverId,
    required String rideId,
  }) async {
    try {
      await _firestore
          .collection('driver_ride_queue')
          .doc(driverId)
          .update({
        'queuedRideIds': FieldValue.arrayUnion([rideId]),
        'updatedAt': Timestamp.now(),
      });

      // Also update the ride to mark it as queued
      await _firestore.collection('ride_requests').doc(rideId).update({
        'isQueuedRide': true,
        'queuePosition': FieldValue.increment(1),
        'acceptedAt': Timestamp.now(),
      });

      debugPrint("[RideQueueService] Added $rideId to queue for $driverId");
      return true;
    } catch (e) {
      debugPrint("[RideQueueService] Error adding to queue: $e");
      return false;
    }
  }

  /// Remove ride from queue
  Future<bool> removeFromQueue({
    required String driverId,
    required String rideId,
  }) async {
    try {
      await _firestore
          .collection('driver_ride_queue')
          .doc(driverId)
          .update({
        'queuedRideIds': FieldValue.arrayRemove([rideId]),
        'updatedAt': Timestamp.now(),
      });

      debugPrint("[RideQueueService] Removed $rideId from queue for $driverId");
      return true;
    } catch (e) {
      debugPrint("[RideQueueService] Error removing from queue: $e");
      return false;
    }
  }

  /// Get current queue for driver
  Future<Map<String, dynamic>?> getQueue(String driverId) async {
    try {
      final doc = await _firestore
          .collection('driver_ride_queue')
          .doc(driverId)
          .get();

      if (doc.exists) {
        return doc.data();
      }
      return null;
    } catch (e) {
      debugPrint("[RideQueueService] Error getting queue: $e");
      return null;
    }
  }

  /// Pop (get and remove) next ride from queue
  Future<String?> popNextRide(String driverId) async {
    try {
      final queue = await getQueue(driverId);
      if (queue == null || (queue['queuedRideIds'] as List).isEmpty) {
        return null;
      }

      final nextRideId = (queue['queuedRideIds'] as List).first as String;

      // Remove from queue
      await removeFromQueue(driverId: driverId, rideId: nextRideId);

      // Update as current ride
      await _firestore
          .collection('driver_ride_queue')
          .doc(driverId)
          .update({
        'currentRideId': nextRideId,
        'position': 0,
        'updatedAt': Timestamp.now(),
      });

      debugPrint(
        "[RideQueueService] Popped next ride: $nextRideId for driver: $driverId",
      );
      return nextRideId;
    } catch (e) {
      debugPrint("[RideQueueService] Error popping next ride: $e");
      return null;
    }
  }

  /// Clear all queued rides for driver (when going offline)
  Future<void> clearQueue(String driverId) async {
    try {
      await _firestore.collection('driver_ride_queue').doc(driverId).delete();
      debugPrint("[RideQueueService] Queue cleared for driver: $driverId");
    } catch (e) {
      debugPrint("[RideQueueService] Error clearing queue: $e");
    }
  }

  /// Update estimated drop time
  Future<void> updateEstimatedDropTime({
    required String driverId,
    required DateTime newEstimatedTime,
  }) async {
    try {
      await _firestore
          .collection('driver_ride_queue')
          .doc(driverId)
          .update({
        'estimatedDropTime': Timestamp.fromDate(newEstimatedTime),
        'updatedAt': Timestamp.now(),
      });

      debugPrint("[RideQueueService] Updated drop time for $driverId");
    } catch (e) {
      debugPrint("[RideQueueService] Error updating drop time: $e");
    }
  }

  /// Listen to queue changes in real-time
  Stream<Map<String, dynamic>?> listenToQueue(String driverId) {
    return _firestore
        .collection('driver_ride_queue')
        .doc(driverId)
        .snapshots()
        .map((snapshot) {
      if (snapshot.exists) {
        return snapshot.data();
      }
      return null;
    }).handleError((e) {
      debugPrint("[RideQueueService] Queue listener error: $e");
      return null;
    });
  }

  /// Check if driver has queued rides
  Future<bool> hasQueuedRides(String driverId) async {
    try {
      final queue = await getQueue(driverId);
      return queue != null && (queue['queuedRideIds'] as List).isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Get count of queued rides
  Future<int> getQueuedRideCount(String driverId) async {
    try {
      final queue = await getQueue(driverId);
      return queue != null ? (queue['queuedRideIds'] as List).length : 0;
    } catch (e) {
      return 0;
    }
  }
}
