import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:project_taxi_driver_app/widgets/status_slider.dart'; // Contains DriverStatus enum
import 'package:project_taxi_driver_app/controllers/home_page_controller.dart';

class QueueService {
  static final QueueService _instance = QueueService._internal();

  factory QueueService() {
    return _instance;
  }

  QueueService._internal(); // No auto-fetch in constructor

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Configuration
  static const String _airportId = 'MAA'; // Unique ID for this queue
  final RxList<LatLng> airportPolygon = <LatLng>[].obs;
  bool _isLoadingBoundary = true;

  final Rxn<int> queuePosition = Rxn<int>();
  final RxString queueStatus = ''.obs; // 'queued', 'offered'
  StreamSubscription? _queueSubscription;

  StreamSubscription<Position>? _positionStream;
  bool _isInQueue = false;

  /// Starts monitoring the driver's airport status
  Future<void> startMonitoring() async {
    if (_auth.currentUser == null) return;

    debugPrint("QueueService: Monitoring started for $_airportId");

    // Fetch polygon if needed
    if (airportPolygon.isEmpty) {
      await _fetchGeofenceBoundary();
    }

    // Start Location Stream
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 50, // Check every 50 meters
    );

    _positionStream =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (Position position) {
            _checkGeofence(position);
          },
        );

    // Removed eager Geolocator.getCurrentPosition() to prevent ANR contention
    // The stream above will trigger shortly.

    // Start Queue Collection Listener
    _startQueueListener();
  }

  Future<void> _fetchGeofenceBoundary() async {
    try {
      final doc = await _firestore
          .collection('geofenced_zones')
          .doc('Chennai_Airport')
          .get();

      if (doc.exists && doc.data() != null) {
        final List<dynamic> points = doc.data()!['boundary'] ?? [];
        if (points.isNotEmpty) {
          airportPolygon.value = points.map((p) {
            final GeoPoint gp = p as GeoPoint;
            return LatLng(gp.latitude, gp.longitude);
          }).toList();
          _isLoadingBoundary = false;
          debugPrint(
            "QueueService: Loaded ${airportPolygon.length} polygon points from Firestore.",
          );
          return;
        }
      }
      _useFallbackGeofence();
    } catch (e) {
      debugPrint("QueueService: Error loading geofence: $e. Using fallback.");
      _useFallbackGeofence();
    }
  }

  void _useFallbackGeofence() {
    debugPrint(
      "QueueService: Using Hardcoded Fallback Geofence (Chennai Airport).",
    );
    airportPolygon.value = [
      const LatLng(13.007328, 80.157756),
      const LatLng(12.9963725, 80.1810161),
      const LatLng(12.9913545, 80.1810161),
      const LatLng(12.9877164, 80.167369),
      const LatLng(12.9877164, 80.167369),
      const LatLng(12.9830746, 80.1687423),
      const LatLng(12.9808791, 80.1650087),
      const LatLng(12.9785582, 80.1601807),
      const LatLng(12.9823846, 80.158507),
      const LatLng(12.9845592, 80.1552455),
      const LatLng(12.9873191, 80.1552455),
      const LatLng(13.007328, 80.157756),
    ];
    _isLoadingBoundary = false;
  }

  void _startQueueListener() {
    final user = _auth.currentUser;
    if (user == null) return;

    _queueSubscription?.cancel();
    _queueSubscription = _firestore
        .collection('airport_queues')
        .doc(_airportId)
        .collection('drivers')
        .orderBy('entryTimestamp')
        .snapshots()
        .listen(
          (snapshot) {
            if (snapshot.docs.isNotEmpty) {
              // Now we only care about OUR document to read the backend-calculated position
              bool foundMe = false;
              for (final doc in snapshot.docs) {
                if (doc.id == user.uid) {
                  final data = doc.data();
                  queuePosition.value = data['position']; // Server-calculated
                  queueStatus.value = data['status'] ?? 'queued';
                  _isInQueue = true;
                  foundMe = true;
                  break;
                }
              }

              if (!foundMe) {
                queuePosition.value = null;
                queueStatus.value = '';
                _isInQueue = false;
              }
            } else {
              queuePosition.value = null;
              queueStatus.value = '';
              _isInQueue = false;
            }
          },
          onError: (e) {
            debugPrint("Queue Listener Error: $e");
          },
        );
  }

  /// Stops monitoring
  void stopMonitoring() {
    _positionStream?.cancel();
    _queueSubscription?.cancel();
    _exitQueue("Monitoring Stopped (Offline/Logout)", showNotification: false);
    queuePosition.value = null;
    debugPrint("QueueService: Monitoring stopped");
  }

  Timer? _exitTimer;
  Timer? _heartbeatTimer;
  Function(String title, String message, String type)? onQueueEvent;

  /// Checks if the driver is within the geofence using Ray-Casting
  Future<void> _checkGeofence(Position position) async {
    if (_isLoadingBoundary || airportPolygon.isEmpty) return;

    final point = LatLng(position.latitude, position.longitude);
    final bool inside = _isPointInPolygon(point, airportPolygon);

    if (inside) {
      // 1. We are INSIDE
      if (_exitTimer != null) {
        // We were about to exit, but came back in time!
        _exitTimer?.cancel();
        _exitTimer = null;
        debugPrint("QueueService: Re-entered zone. Exit Timer cancelled.");
        onQueueEvent?.call('queueSafe'.tr, 'queueSafeMsg'.tr, 'success');
      }

      if (!_isInQueue) {
        // ENTER Queue
        await _joinQueue(position);
      }
    } else {
      // 2. We are OUTSIDE
      if (_isInQueue) {
        // Only start timer if not already running
        if (_exitTimer == null) {
          debugPrint("QueueService: Outside zone. Starting Exit Timer (2m).");
          onQueueEvent?.call(
            'warningLeftZone'.tr,
            'queueWarningMsg'.tr,
            'warning',
          );

          _exitTimer = Timer(const Duration(minutes: 2), () async {
            debugPrint("QueueService: Exit Timer expired. Exiting queue.");
            await _exitQueue("Left Geofence (>2 mins)", showNotification: true);
            _exitTimer = null;
          });
        }
      }
    }
  }

  // Ray-Casting Algorithm to check if point is inside polygon
  bool _isPointInPolygon(LatLng point, List<LatLng> polygon) {
    if (polygon.isEmpty) return false;

    bool isInside = false;
    int i, j = polygon.length - 1;

    for (i = 0; i < polygon.length; i++) {
      if (((polygon[i].latitude > point.latitude) !=
              (polygon[j].latitude > point.latitude)) &&
          (point.longitude <
              (polygon[j].longitude - polygon[i].longitude) *
                      (point.latitude - polygon[i].latitude) /
                      (polygon[j].latitude - polygon[i].latitude) +
                  polygon[i].longitude)) {
        isInside = !isInside;
      }
      j = i;
    }
    return isInside;
  }

  Future<void> _joinQueue(Position position) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      if (Get.isRegistered<HomePageController>()) {
        final homeController = Get.find<HomePageController>();
        if (homeController.driverStatus.value != DriverStatus.online) {
          debugPrint("QueueService: Driver is not purely online. Cannot join.");
          return;
        }
      }

      debugPrint("QueueService: Entering Airport Queue...");

      // Check if already exists to avoid overwriting timestamp
      final docRef = _firestore
          .collection('airport_queues')
          .doc(_airportId)
          .collection('drivers')
          .doc(user.uid);

      final doc = await docRef.get();

      if (!doc.exists) {
        await docRef.set({
          'driverId': user.uid,
          'entryTimestamp': FieldValue.serverTimestamp(),
          'lastHeartbeat': FieldValue.serverTimestamp(),
          'status': 'queued',
          'lockedForRide': false,
          'currentOfferRideId': "",
          'skipCount': 0,
          'location': GeoPoint(position.latitude, position.longitude),
        });
        _isInQueue = true;
        _startHeartbeat();
        debugPrint("QueueService: Joined Queue successfully!");
        onQueueEvent?.call('joinedQueue'.tr, 'queueJoinedMsg'.tr, 'success');

        Get.snackbar(
          'Queue Entered',
          'You have successfully joined the airport queue.',
          snackPosition: SnackPosition.TOP,
          backgroundColor: Colors.green,
          colorText: Colors.white,
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 4),
        );
      } else {
        _isInQueue = true; // Recover state
      }
    } catch (e) {
      debugPrint("QueueService Error (Join): $e");
    }
  }

  void _startHeartbeat() {
    final user = _auth.currentUser;
    if (user == null) return;

    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 60), (timer) {
      if (_isInQueue) {
        _firestore
            .collection('airport_queues')
            .doc(_airportId)
            .collection('drivers')
            .doc(user.uid)
            .update({'lastHeartbeat': FieldValue.serverTimestamp()})
            .catchError((e) => debugPrint("Heartbeat update failed: $e"));
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _exitQueue(String reason, {bool showNotification = true}) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      debugPrint("QueueService: Exiting Queue. Reason: $reason");

      await _firestore
          .collection('airport_queues')
          .doc(_airportId)
          .collection('drivers')
          .doc(user.uid)
          .delete();

      _isInQueue = false;
      _heartbeatTimer?.cancel();

      if (showNotification) {
        onQueueEvent?.call('exitedQueue'.tr, 'queueExitedMsg'.tr, 'error');

        Get.snackbar(
          'Queue Exited',
          'You have left the airport queue area.',
          snackPosition: SnackPosition.TOP,
          backgroundColor: Colors.redAccent,
          colorText: Colors.white,
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 4),
        );
      }

      debugPrint("QueueService: Exited Queue.");
    } catch (e) {
      debugPrint("QueueService Error (Exit): $e");
    }
  }
}
