import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Route;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import 'package:project_taxi_driver_app/screens/earnings.dart';
import 'package:project_taxi_driver_app/screens/wallet_screen.dart';
import 'package:project_taxi_driver_app/controllers/wallet_controller.dart';
import 'package:project_taxi_driver_app/screens/goto.dart';
import 'package:project_taxi_driver_app/screens/login.dart';
import 'package:project_taxi_driver_app/screens/ride_acepted.dart';
import 'package:project_taxi_driver_app/widgets/ride_request.dart';
import 'package:project_taxi_driver_app/widgets/status_slider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:project_taxi_driver_app/screens/rental_request_screen.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:project_taxi_driver_app/services/overlay_service.dart';
import 'package:project_taxi_driver_app/services/queue_service.dart';
import 'package:project_taxi_driver_app/services/demand_service.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:project_taxi_driver_app/services/request_queue_service.dart';
import 'package:project_taxi_driver_app/services/goto_timer_service.dart';
import 'package:project_taxi_driver_app/services/overlay_service_enhanced.dart';
import 'package:project_taxi_driver_app/widgets/goto_status_banner.dart';

class HomePageController extends GetxController with WidgetsBindingObserver {
  final User user;
  final bool isActingDriver;
  final DriverStatus? initialStatus;

  HomePageController({
    required this.user,
    this.isActingDriver = false,
    this.initialStatus,
  });

  // Map Controller
  final Completer<GoogleMapController> mapController = Completer();

  // Reactive State
  final Rx<DriverStatus> driverStatus = DriverStatus.offline.obs;
  final Rxn<Map<String, dynamic>> goToDestination = Rxn<Map<String, dynamic>>();
  final RxString selectedLanguageCode = 'en'.obs;
  final RxBool isLoading = true.obs;
  final Rxn<LatLng> currentPosition = Rxn<LatLng>();
  final RxDouble sheetExtent = 0.1.obs;
  final RxSet<Polygon> polygons = <Polygon>{}.obs;

  // Ride Request State
  final Rxn<RideRequest> activeRideRequest = Rxn<RideRequest>();
  final RxBool isRideAcceptanceInProgress = false.obs;

  final RxBool hasActiveRide = false.obs;
  QuerySnapshot? lastRideRequestSnapshot;

  // Earnings State
  final RxDouble todaysEarnings = 0.0.obs;
  final RxDouble walletBalance = 0.0.obs;
  final Rxn<Ride> lastRide = Rxn<Ride>();

  // Snooze Logic / Ignored Rides
  final Map<String, DateTime> _ignoredRides = {};

  // Subscriptions and Timers
  StreamSubscription? rideRequestSubscription;
  StreamSubscription? rentalRequestSubscription;

  StreamSubscription? earningsSubscription;
  StreamSubscription?
  rentalEarningsSubscriptionLocal; // Renamed to avoid confusion with request listener
  StreamSubscription? walletSubscription;
  Timer? locationUpdateTimer;
  Timer? rideTimeoutTimer;

  // Audio
  // Static to ensure singleton control over audio across controller lifecycles
  final AudioPlayer audioPlayer = AudioPlayer();
  final FlutterTts flutterTts = FlutterTts();
  final VolumeController volumeController = VolumeController.instance;
  double? originalVolume;
  bool _isRentalRinging = false;

  // API Key
  late final String apiKey;

  // App Lifecycle
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;

  // Request Queue Service
  final RequestQueueService _queueService = RequestQueueService.instance;

  // GoTo Timer Service
  final GoToTimerService _goToTimerService = GoToTimerService.instance;

  // Translations

  @override
  void onInit() {
    super.onInit();
    Get.lazyPut(
      () => WalletController(),
      fenix: true,
    ); // Ensure WalletController is available
    final apiKeyValue = dotenv.env['GOOGLE_MAPS_API_KEY'];
    if (apiKeyValue == null) throw Exception("API Key not found");
    apiKey = apiKeyValue;

    loadLanguage();
    goToCurrentUserLocation(shouldAnimate: false);
    WidgetsBinding.instance.addObserver(this);
    // TTS is now initialized in Splash, but we keep the instance here.
    // _initTts();

    // Set Initial Status if provided
    if (initialStatus != null) {
      debugPrint(
        "Startup: Using provided Initial Driver Status: $initialStatus",
      );
      driverStatus.value = initialStatus!;

      if (initialStatus == DriverStatus.online) {
        WakelockPlus.enable();
        // Start listeners immediately as we are already "warmed up"
        startLocationUpdates();
        listenForRideRequests();
        if (!isActingDriver) {
          listenForRentalRequests();
        }
        listenForEarnings();
      }
    }

    // Overlay Listener (permission already requested in SplashController)
    FlutterOverlayWindow.overlayListener.listen((data) {
      debugPrint("Overlay Event: $data");
      if (data is Map) {
        if (data['action'] == "accept") {
          if (activeRideRequest.value != null) {
            onRideAccepted();
          }
        } else if (data['action'] == "reject") {
          if (activeRideRequest.value != null) {
            onRideRejected("overlay_reject");
          }
        }
      }
    });

    // Listen for Polygon Updates from QueueService
    ever(QueueService().airportPolygon, (List<LatLng> points) {
      if (points.isNotEmpty) {
        polygons.assignAll({
          Polygon(
            polygonId: const PolygonId('airport_zone'),
            points: points,
            fillColor: Colors.blue.withValues(alpha: 0.15),
            strokeColor: Colors.blue,
            strokeWidth: 2,
          ),
        });
      } else {
        polygons.clear();
      }
    });

    // We don't need _syncDriverStatus anymore as Splash handles it,
    // but if you want valid data on refresh, you might keep a lighter version.
    // For now, relying on Splash->Auth->Home chain.

    // Setup GoTo expiry callback
    _goToTimerService.onGoToExpired = _onGoToExpired;

    listenForWallet();
    listenForNotifications();

    // Configure Port Listener
    // _configureIsolatePort(); // Removed Port Logic

    // Safe permission request (Moved from Splash to avoid startup ANR)
    Future.delayed(const Duration(seconds: 3), () {
      try {
        OverlayService.instance.requestOverlayPermission();
      } catch (e) {
        debugPrint("Error requesting overlay permission in Home: $e");
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    _appLifecycleState = state;
    debugPrint("App Lifecycle Changed: $state");

    if (state == AppLifecycleState.paused) {
      debugPrint("App paused. Driver Status: ${driverStatus.value}");
      if (driverStatus.value == DriverStatus.online ||
          driverStatus.value == DriverStatus.goTo) {
        // Check if we have multiple requests in queue
        if (_queueService.totalCount > 0) {
          debugPrint("Showing Overlay for Multiple Requests");
          _showMultipleRequestsOverlay();
        } else if (activeRideRequest.value != null &&
            activeRideRequest.value!.status == 'searching') {
          debugPrint("Showing Overlay for Ride Request");
          _showOverlayForRide(activeRideRequest.value!);
        } else {
          // Show status bubble if online but no active request
          debugPrint("Showing Status Bubble");
          showStatusBubble();
        }
      }
    } else if (state == AppLifecycleState.resumed) {
      debugPrint("App resumed. Checking for overlay acceptance...");

      // Check for SharedPreferences backup flag with retry
      _checkForAcceptedRideInPrefs();

      debugPrint("Closing overlay.");
      OverlayService.instance.hideFloatingBubble();
    }
  }

  void _checkForAcceptedRideInPrefs({int retries = 5}) {
    SharedPreferences.getInstance().then((prefs) async {
      await prefs
          .reload(); // CRITICAL: Force reload to see changes from Overlay isolate
      final acceptedId = prefs.getString('details_accepted_ride_id');
      if (acceptedId != null &&
          activeRideRequest.value != null &&
          activeRideRequest.value!.rideId == acceptedId) {
        debugPrint(
          "Resume: Found accepted ride ID in prefs: $acceptedId. Triggering acceptance.",
        );
        isRideAcceptanceInProgress.value =
            true; // Prevents "Processing" card flicker
        onRideAccepted();
        prefs.remove('details_accepted_ride_id'); // Clear flag
      } else {
        debugPrint(
          "Resume: No matching accepted ride found in prefs. Retries left: $retries",
        );
        if (retries > 0) {
          Future.delayed(const Duration(milliseconds: 500), () {
            _checkForAcceptedRideInPrefs(retries: retries - 1);
          });
        }
      }
    });
  }

  /// Handle GoTo expiry - switch back to online
  void _onGoToExpired() {
    debugPrint('GoTo expired, switching to online mode');

    // Clear GoTo destination
    goToDestination.value = null;

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

  Future<void> showStatusBubble() async {
    // Only show bubble when driver is online
    if (driverStatus.value != DriverStatus.online &&
        driverStatus.value != DriverStatus.goTo) {
      debugPrint("_showStatusBubble: Skipped (Driver is offline)");
      return;
    }
    debugPrint("_showStatusBubble: Showing floating bubble...");
    await OverlayService.instance.showFloatingBubble();
  }

  Future<void> _showOverlayForRide(RideRequest request) async {
    await OverlayService.instance.showRideRequestOverlay(request.toJson());
  }

  /// Show multiple requests overlay
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

  @override
  void onClose() {
    stopRideRequestSound(); // Stop TTS and Vibration too
    locationUpdateTimer?.cancel();
    rideRequestSubscription?.cancel();
    rentalRequestSubscription?.cancel();

    earningsSubscription?.cancel();
    rentalEarningsSubscriptionLocal?.cancel();
    walletSubscription?.cancel();
    notificationSubscription?.cancel();
    audioPlayer.dispose();
    WakelockPlus.disable();
    WidgetsBinding.instance.removeObserver(this);
    _stopDemandMonitoring();
    super.onClose();
  }

  Future<void> loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    selectedLanguageCode.value = prefs.getString('selectedLanguage') ?? 'en';
    Get.updateLocale(Locale(selectedLanguageCode.value));
    isLoading.value = false;
  }

  String getTranslatedString(String key) {
    return key.tr;
  }

  Future<void> handleStatusChange(DriverStatus status) async {
    debugPrint("handleStatusChange called with status: $status");

    // Off-road Check (Local Enforcement)
    if (status == DriverStatus.online) {
      // Ensure wallet data is loaded
      if (walletBalance.value <= -300) {
        Get.defaultDialog(
          title: "Account Offroaded",
          middleText:
              "Your wallet balance (-₹${walletBalance.value.abs().toStringAsFixed(2)}) exceeds the credit limit of ₹300. Please recharge to go online.",
          textConfirm: "Recharge",
          confirmTextColor: Colors.white,
          onConfirm: () {
            Get.back();
            Get.to(() => WalletScreen(user: user));
          },
          textCancel: "Cancel",
        );
        // Revert visual state if needed, or ensure ui listens to this
        // We delay slightly to let UI catch up if it was optimistic
        Future.delayed(const Duration(milliseconds: 100), () {
          driverStatus.value = DriverStatus.offline;
        });
        return;
      }
    }

    // 1. Update local state immediately for UI responsiveness
    driverStatus.value = status;

    // 2. Handle specific logic based on status
    if (status == DriverStatus.online || status == DriverStatus.goTo) {
      WakelockPlus.enable();
      // Don't await here if we want immediate UI feedback, or accept that map might move later
      // We will fire and forget log/toast if location fails, but we are "Online" now.
      goToCurrentUserLocation();

      // Start Queue Monitoring
      QueueService().onQueueEvent = (title, message, type) {
        if (Get.isSnackbarOpen) {
          Get.closeCurrentSnackbar();
        }
        Get.snackbar(
          title,
          message,
          snackPosition: SnackPosition.TOP,
          backgroundColor: type == 'warning'
              ? Colors.orange
              : type == 'error'
              ? Colors.red
              : Colors.green,
          colorText: Colors.white,
          duration: const Duration(seconds: 5),
          margin: const EdgeInsets.all(10),
        );
      };
      QueueService().startMonitoring();
      _startDemandMonitoring();
    } else {
      // Stop Queue Monitoring
      QueueService().stopMonitoring();
      _stopDemandMonitoring();
      WakelockPlus.disable();
    }

    if (status == DriverStatus.goTo) {
      debugPrint("Opening GoToScreen...");
      // Revert if GoTo Is Cancelled
      // logic handles this by checking result
      final result = await Get.to<Map<String, dynamic>>(
        () => GoToScreen(activeDestination: goToDestination.value),
      );

      if (result != null) {
        debugPrint("GoTo Result obtained: $result");
        // driverStatus.value = DriverStatus.goTo; // Already set above, but safe to keep or rely on logic
        if (result.containsKey('clear') && result['clear'] == true) {
          debugPrint("GoTo Cancelled/Cleared");
          goToDestination.value = null;
          _goToTimerService.deactivateGoTo();
          // If we cleared GoTo, do we revert to Online? Yes.
          // Firestore Update to remove GoTo
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
              await _goToTimerService.activateGoTo({
                'address': result['address'],
                'lat': (result['location'] as LatLng).latitude,
                'lng': (result['location'] as LatLng).longitude,
              });

              // Firestore Update for GoTo
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
        // User canceled - revert to online status
        driverStatus.value = DriverStatus.online;
        goToDestination.value = null;
        await FirebaseFirestore.instance
            .collection('drivers')
            .doc(user.uid)
            .set({
              'isOnline': true,
              'goToDestination': null,
            }, SetOptions(merge: true));
      }
    } else {
      // Standard Online/Offline Update
      debugPrint("Processing standard status update to: $status");
      goToDestination.value = null;

      final Map<String, dynamic> updateData = {
        'isOnline': status == DriverStatus.online,
        'goToDestination': null,
      };

      // CRITICAL FIX: Set status to 'active' when going online
      if (status == DriverStatus.online) {
        updateData['status'] = 'active';

        // SELF-CORRECTION: Fix "Car" vehicleType if possible
        try {
          final doc = await FirebaseFirestore.instance
              .collection('drivers')
              .doc(user.uid)
              .get();
          if (doc.exists) {
            final data = doc.data();
            final vType = data?['vehicleType'];
            final vClass = data?['vehicleClass'];

            if (vType == 'Car' &&
                vClass != null &&
                vClass.toString().isNotEmpty) {
              debugPrint("Auto-Correcting VehicleType from Car to $vClass");
              updateData['vehicleType'] = vClass;
            }
          }
        } catch (e) {
          debugPrint("Error auto-correcting vehicle type: $e");
        }
      }

      await FirebaseFirestore.instance
          .collection('drivers')
          .doc(user.uid)
          .set(updateData, SetOptions(merge: true));
      debugPrint("Firestore updated for status: $status");

      // DEBUG: Print current driver data to verify vehicleType
      try {
        final dDoc = await FirebaseFirestore.instance
            .collection('drivers')
            .doc(user.uid)
            .get();
        debugPrint(
          "DEBUG: Driver Data -> Type: ${dDoc.data()?['vehicleType']}, Class: ${dDoc.data()?['vehicleClass']}, Status: ${dDoc.data()?['status']}",
        );
        debugPrint(
          "DEBUG: Duty Preferences -> ${dDoc.data()?['dutyPreferences']}",
        );
      } catch (e) {
        debugPrint("DEBUG: Error fetching driver data: $e");
      }
    }

    if (driverStatus.value == DriverStatus.online ||
        driverStatus.value == DriverStatus.goTo) {
      debugPrint("Starting location updates and listening for rides");
      startLocationUpdates();
      listenForRideRequests();
      if (!isActingDriver) {
        listenForRentalRequests();
      }
    } else {
      debugPrint("Stopping location updates");
      stopLocationUpdates();
      rideRequestSubscription?.cancel();
      rentalRequestSubscription?.cancel();
    }
  }

  StreamSubscription<Position>? _positionStreamSubscription;

  void startLocationUpdates() async {
    final hasPermission = await _handleLocationPermission();
    if (!hasPermission) return;

    // Fetch immediately first
    try {
      final position = await Geolocator.getCurrentPosition();
      currentPosition.value = LatLng(position.latitude, position.longitude);
      _updateDriverLocationInFirestore(position);
    } catch (e) {
      debugPrint("Error fetching initial location: $e");
    }

    // Use Stream instead of Timer
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    _positionStreamSubscription?.cancel();
    _positionStreamSubscription =
        Geolocator.getPositionStream(
          locationSettings: locationSettings,
        ).listen((Position position) {
          currentPosition.value = LatLng(position.latitude, position.longitude);
          _updateDriverLocationInFirestore(position);
        }, onError: (e) => debugPrint("Location stream error: $e"));
  }

  Future<void> _updateDriverLocationInFirestore(Position position) async {
    await FirebaseFirestore.instance.collection('drivers').doc(user.uid).set({
      'currentLocation': GeoPoint(position.latitude, position.longitude),
    }, SetOptions(merge: true));
  }

  void stopLocationUpdates() {
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    locationUpdateTimer
        ?.cancel(); // Safety cleanup if switching from old version
  }

  Future<void> listenForRideRequests() async {
    rideRequestSubscription?.cancel();
    rideRequestSubscription?.cancel();

    final driverDoc = await FirebaseFirestore.instance
        .collection('drivers')
        .doc(user.uid)
        .get();
    if (!driverDoc.exists) return;

    // 2. Listener for Assigned Rides (Direct Assignments)
    Query query = FirebaseFirestore.instance
        .collection('ride_requests')
        .where('driverId', isEqualTo: user.uid)
        .where('status', isEqualTo: 'searching') // Only listen for searching
        .orderBy('createdAt', descending: true);

    // Filter based on driver type
    if (isActingDriver) {
      // Acting Drivers ONLY get "ActingDriver" requests
      query = query.where('vehicleType', isEqualTo: 'ActingDriver');
    } else {
      // Standard Drivers get everything EXCEPT "ActingDriver" requests
      // query = query.where('vehicleType', isNotEqualTo: 'ActingDriver');
    }

    rideRequestSubscription = query.snapshots().listen(
      (snapshot) async {
        debugPrint("Assigned Rides Snapshot: ${snapshot.docs.length} docs");

        for (var doc in snapshot.docs) {
          final data = doc.data() as Map<String, dynamic>?;

          // Client-side vehicle type check
          final vType =
              data?['vehicleType'] ?? data?['vehicleClass'] ?? 'Unknown';
          if (!isActingDriver && vType == 'ActingDriver') {
            debugPrint(
              "Ignored ActingDriver request ${doc.id} as this is a Regular Driver",
            );
            continue;
          }

          // If we already have this ride active locally, don't re-process
          if (activeRideRequest.value?.rideId == doc.id) {
            continue;
          }

          // Check if we recently rejected this ride locally to avoid loop
          if (_ignoredRides.containsKey(doc.id)) {
            final ignoredTime = _ignoredRides[doc.id]!;
            // Only ignore for 60 seconds to allow for re-dispatch or testing
            if (DateTime.now().difference(ignoredTime).inSeconds < 60) {
              continue;
            } else {
              _ignoredRides.remove(doc.id); // Expired, allow processing again
            }
          }

          debugPrint("Found new assigned ride: ${doc.id}");
          await _processRideDocument(doc, data!);
        }
      },
      onError: (e) {
        debugPrint("Error listening for rides: $e");
        if (e.toString().contains('failed-precondition')) {
          Get.snackbar(
            "Config Error",
            "Missing Database Index. Check logs for link.",
            duration: const Duration(seconds: 10),
            backgroundColor: Colors.red,
            colorText: Colors.white,
          );
        }
      },
    );
  }

  // Subscription State
  final Rxn<DateTime> subscriptionExpiry = Rxn<DateTime>();
  final RxnString subscriptionPlanName = RxnString();

  // Notification State
  final RxBool hasUnreadNotifications = false.obs;
  StreamSubscription? notificationSubscription;

  void listenForNotifications() {
    notificationSubscription?.cancel();
    notificationSubscription = FirebaseFirestore.instance
        .collection('drivers')
        .doc(user.uid)
        .collection('notifications')
        .where('isRead', isEqualTo: false)
        .limit(1)
        .snapshots()
        .listen(
          (snapshot) {
            if (snapshot.docs.isNotEmpty) {
              hasUnreadNotifications.value = true;
            } else {
              hasUnreadNotifications.value = false;
            }
          },
          onError: (e) {
            debugPrint("Error listening for unread notifications: $e");
          },
        );
  }

  bool get isPlanActive {
    if (subscriptionExpiry.value == null) return false;
    return subscriptionExpiry.value!.isAfter(DateTime.now());
  }

  void listenForWallet() {
    walletSubscription?.cancel();

    // Listen to wallet balance from subcollection
    FirebaseFirestore.instance
        .collection('drivers')
        .doc(user.uid)
        .collection('wallet')
        .doc('balance')
        .snapshots()
        .listen(
          (snapshot) {
            if (snapshot.exists) {
              walletBalance.value =
                  (snapshot.data()?['currentBalance'] as num? ?? 0.0)
                      .toDouble();
            } else {
              walletBalance.value = 0.0;
            }
          },
          onError: (e) {
            debugPrint("Error listening to wallet balance: $e");
          },
        );

    // Listen to driver document for subscription data
    walletSubscription = FirebaseFirestore.instance
        .collection('drivers')
        .doc(user.uid)
        .snapshots()
        .listen(
          (snapshot) {
            if (snapshot.exists) {
              final data = snapshot.data();

              // Subscription
              if (data?['subscriptionExpiry'] != null) {
                final ts = data!['subscriptionExpiry'] as Timestamp;
                subscriptionExpiry.value = ts.toDate();
              } else {
                subscriptionExpiry.value = null;
              }
              subscriptionPlanName.value = data?['subscriptionPlan'] as String?;
            }
          },
          onError: (e) {
            debugPrint("Error listening to driver doc: $e");
          },
        );
  }

  Future<void> listenForRentalRequests() async {
    rentalRequestSubscription?.cancel();
    rentalRequestSubscription?.cancel();

    debugPrint("Starting Rental Request Listener...");

    // Listen to 'rental_requests' where status == 'searching'
    // We can also filter by vehicleClass client-side if needed
    Query query = FirebaseFirestore.instance
        .collection('rental_requests')
        .where('status', isEqualTo: 'searching')
        .orderBy('createdAt', descending: true);

    rentalRequestSubscription = query.snapshots().listen(
      (snapshot) async {
        debugPrint(
          "Rental Requests Listener Loop: Found ${snapshot.docs.length} docs.",
        );

        if (snapshot.docs.isEmpty) {
          debugPrint(
            "Rental Request collection is empty or query matched nothing.",
          );
        }

        for (var doc in snapshot.docs) {
          final data = doc.data() as Map<String, dynamic>;
          debugPrint("Inspecting Rental Doc: ${doc.id} - Data: $data");

          if (currentPosition.value == null) {
            debugPrint("Skipping rental check (Driver Location is NULL)");
            continue;
          }

          // Geo Filter (Radius Check) - e.g. 50km
          final pickupReq = data['pickupLocation'];
          double? reqLat;
          double? reqLng;

          if (pickupReq is GeoPoint) {
            reqLat = pickupReq.latitude;
            reqLng = pickupReq.longitude;
          } else if (pickupReq is Map) {
            reqLat =
                (pickupReq['lat'] as num?)?.toDouble() ??
                (pickupReq['latitude'] as num?)?.toDouble();
            reqLng =
                (pickupReq['lng'] as num?)?.toDouble() ??
                (pickupReq['longitude'] as num?)?.toDouble();
          }

          if (reqLat != null && reqLng != null) {
            double dist =
                Geolocator.distanceBetween(
                  currentPosition.value!.latitude,
                  currentPosition.value!.longitude,
                  reqLat,
                  reqLng,
                ) /
                1000; // in km

            if (dist > 50) {
              debugPrint(
                "Rental ${doc.id} SKIPPED: Too far (${dist.toStringAsFixed(1)}km > 50km)",
              );
              continue;
            }
            debugPrint(
              "Rental ${doc.id} MATCH: Distance is ${dist.toStringAsFixed(1)}km",
            );
          } else {
            debugPrint(
              "Rental ${doc.id} WARNING: Could not parse pickupLocation: $pickupReq",
            );
          }

          // Process the Rental Request
          // We treat it just like a normal ride doc, but we ensure 'rideType' is rental in adaptation
          // Since the schema differs slightly, _processRideDocument adapts it via our updated RideRequest.fromJson

          // IMPORTANT: Check if we are already busy
          if (activeRideRequest.value != null &&
              activeRideRequest.value!.rideId != doc.id) {
            debugPrint(
              "Skipping rental (Busy with ${activeRideRequest.value!.rideId})",
            );
            continue;
          }

          await _processRideDocument(doc, data);
          // If we processed one, we break (one active request at a time)
          // Unless we want to show a list? Current UI supports single activeRideRequest.
          if (activeRideRequest.value != null) {
            break;
          }
        }
      },
      onError: (e) {
        debugPrint("Error listening for rentals: $e");
      },
    );
  }

  Future<void> _processRideDocument(
    DocumentSnapshot doc,
    Map<String, dynamic> data,
  ) async {
    debugPrint("Processing Ride Document: ${doc.id}");

    if (currentPosition.value == null) {
      debugPrint(
        "Process Ride: Warning - Current position null, but proceeding.",
      );
      // We do NOT return here anymore. We proceed so the request is shown.
    }

    // Helper to parse location data
    LatLng? parseLocation(dynamic locationData) {
      if (locationData is GeoPoint) {
        return LatLng(locationData.latitude, locationData.longitude);
      } else if (locationData is Map) {
        final lat =
            (locationData['lat'] as num?)?.toDouble() ??
            (locationData['latitude'] as num?)?.toDouble();
        final lng =
            (locationData['lng'] as num?)?.toDouble() ??
            (locationData['longitude'] as num?)?.toDouble();
        if (lat != null && lng != null) {
          return LatLng(lat, lng);
        }
      }
      return null;
    }

    final pickupLocation = parseLocation(data['pickupLocation']);
    final destinationLocation = parseLocation(data['destinationLocation']);

    if (pickupLocation == null) {
      debugPrint(
        "Error: Could not parse pickup location from ${data['pickupLocation']}",
      );
      return;
    }

    // Use pickup as fallback for destination if null (rental/package logic sometimes omits it)
    final finalDestination = destinationLocation ?? pickupLocation;

    // Calculate distances
    debugPrint("Calculating route details...");
    Map<String, dynamic>? driverRouteDetails;

    // Check if we have a valid current position before calculating driver route
    if (currentPosition.value != null) {
      driverRouteDetails = await getRouteDetails(
        currentPosition.value!,
        pickupLocation,
      );
    } else {
      debugPrint(
        "Warning: Skipping driver route calculation (Current position null)",
      );
    }

    Map<String, dynamic>? rideRouteDetails;
    // Only calculate ride route if we actually had a distinct destination provided
    if (destinationLocation != null) {
      rideRouteDetails = await getRouteDetails(
        pickupLocation,
        finalDestination,
      );
    }

    // Use defaults if route calculation fails
    // Use defaults if route calculation fails
    final driverDist = driverRouteDetails?['distance'] ?? 0.0;
    final driverDuration = driverRouteDetails?['duration'] ?? 0.0;
    final rideDist = rideRouteDetails?['distance'] ?? 0.0;

    if (driverRouteDetails == null) {
      debugPrint("Warning: Driver route details failed. Using defaults.");
    }

    debugPrint(
      "Route Details Fetched. DriverDist: $driverDist, RideDist: $rideDist",
    );

    final pickupDetails = await getParsedAddressFromLatLng(pickupLocation);
    Map<String, String> dropoffDetails = {
      'area': 'Rental',
      'fullAddress': 'Package Ride',
    };
    if (destinationLocation != null) {
      dropoffDetails = await getParsedAddressFromLatLng(finalDestination);
    }

    // Prioritize Firebase Data if available
    final String pickupFull =
        data['pickupAddress'] ?? pickupDetails['fullAddress']!;
    // Extract simple title from full address if needed, or use formatted area
    final String pickupTitle = data['pickupAddress'] != null
        ? RideRequest.extractTitle(data['pickupAddress'])
        : pickupDetails['area']!;

    final String dropoffFull =
        data['destinationAddress'] ?? dropoffDetails['fullAddress']!;
    final String dropoffTitle = data['destinationAddress'] != null
        ? RideRequest.extractTitle(data['destinationAddress'])
        : dropoffDetails['area']!;

    final newRequest = RideRequest(
      rideId: doc.id,
      userId: data['userId'],
      userName: data['userName'],
      pickupTitle: pickupTitle,
      dropoffTitle: dropoffTitle,
      pickupFullAddress: pickupFull,
      dropoffFullAddress: dropoffFull,
      driverDistance: driverDist,
      rideDistance: rideDist,
      rideFare: (data['totalFare'] ?? data['fare'] ?? 0.0).toDouble(),
      tip: data['tip']?.toDouble(),
      // FIX: Fallback to vehicleClass if vehicleType is missing or null
      vehicleType: data['vehicleType'] ?? data['vehicleClass'] ?? 'Unknown',
      pickupLocation: pickupLocation,
      dropoffLocation: finalDestination,
      rideType: data['rideType'] ?? 'daily',
      endRidePin: data['endRidePin'] ?? '',
      stops:
          (data['intermediateStops'] as List<dynamic>?)?.map((stop) {
            final loc = stop['location'];
            double lat = 0.0;
            double lng = 0.0;
            if (loc is GeoPoint) {
              lat = loc.latitude;
              lng = loc.longitude;
            } else if (loc is Map) {
              lat = (loc['latitude'] as num).toDouble();
              lng = (loc['longitude'] as num).toDouble();
            }

            return RideStop(
              title: stop['address']?.split(',')[0] ?? 'Stop',
              fullAddress: stop['address'] ?? '',
              location: LatLng(lat, lng),
            );
          }).toList() ??
          [],
      driverId: data['driverId'],
      packageName: data['packageName'],
      durationHours: data['durationHours'],
      kmLimit: data['kmLimit'],
      extraHourCharge: data['extraHourCharge'],
      extraKmCharge: data['extraKmCharge'],
      driverDuration: driverDuration,
      rideDuration: (data['estimatedDurationSeconds'] != null)
          ? (data['estimatedDurationSeconds'] as num).toDouble() / 60
          : null,
      convenienceFee: (data['convenienceFee'] ?? 0).toDouble(),
      safetyPin: data['startRidePin'] ?? data['safetyPin'] ?? '0000',
      paymentMethod: data['paymentMethod'] ?? 'Cash',
      status: data['status'] ?? 'searching',
      vehicleClass: data['vehicleClass'] ?? data['vehicleType'] ?? 'Unknown',
      paidByWallet: (data['paidByWallet'] as num?)?.toDouble() ??
          (data['walletAmountUsed'] as num?)?.toDouble(),
    );

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

    // Add to queue based on ride type
    if (newRequest.rideType == 'rental') {
      _queueService.addRentalRequest(newRequest);
    } else {
      _queueService.addDailyRequest(newRequest);
    }

    // Also set as active for backward compatibility
    activeRideRequest.value = newRequest;

    // Trigger Overlay if Backgrounded
    if (_appLifecycleState == AppLifecycleState.paused) {
      _showMultipleRequestsOverlay();
    }

    if (newRequest.rideType == 'rental') {
      // Guard: Don't show rental screen again if we're already accepting
      if (_isAcceptingRide) {
        debugPrint("Skipping rental screen navigation (already accepting)");
        return;
      }
      playRentalNotification();
      Get.to(
        () => RentalRequestScreen(
          rideRequest: newRequest,
          onAccept: onRideAccepted,
          onPass: () => onRideRejected("rental_screen_pass"),
        ),
      );
    } else {
      // Only play sound for new searching rides
      // GUARD: If we are already accepting, DO NOT play sound again
      if (activeRideRequest.value!.status == 'searching' && !_isAcceptingRide) {
        playRideRequestSound();
      } else {
        // If status changed to accepted/cancelled/etc, force stop sound!
        // This catches cases where stream updates before we manually stopped it
        stopRideRequestSound();
      }
    }

    startRideTimeout(doc.id);
    debugPrint("Ride Request Active: ${doc.id}");
  }

  // Removed Mock Rental Trigger
  // logic moved to listenForRentalRequests

  void triggerMockActingDriverRequest() {
    final mockId = "mock_acting_${DateTime.now().millisecondsSinceEpoch}";
    final pickupLocation = LatLng(12.931115, 80.217510);

    activeRideRequest.value = RideRequest(
      rideId: mockId,
      userId: "mock_user_acting",
      pickupTitle: "38, Pallikaranai, Chennai",
      dropoffTitle: "Acting Driver Request",
      pickupFullAddress: "38, Pallikaranai, Chennai",
      dropoffFullAddress: "4 Hour Package / 40 km",
      driverDistance: 1.2,
      rideDistance: 0,
      rideFare: 550.0,
      vehicleType: "ActingDriver",
      pickupLocation: pickupLocation,
      dropoffLocation: pickupLocation,
      rideType: 'rental',
      packageName: "4 Hour_Package",
      durationHours: 4,
      kmLimit: 40,
      driverId: user.uid,
      driverDuration: 8.0, // 8 mins for mock
      convenienceFee: 20.0,
      safetyPin: "9876",
      paymentMethod: "Cash",
      status: "searching",
      vehicleClass: "ActingDriver",
    );

    playRentalNotification();
    Get.to(
      () => RentalRequestScreen(
        rideRequest: activeRideRequest.value!,
        onAccept: onRideAccepted,
        onPass: () => onRideRejected("mock_acting_pass"),
      ),
    );
    startRideTimeout(mockId);
  }

  Future<Map<String, dynamic>?> getRouteDetails(
    LatLng origin,
    LatLng destination,
  ) async {
    PolylinePoints polylinePoints = PolylinePoints(apiKey: apiKey);
    final request = RoutesApiRequest(
      origin: PointLatLng(origin.latitude, origin.longitude),
      destination: PointLatLng(destination.latitude, destination.longitude),
      travelMode: TravelMode.driving,
    );

    try {
      RoutesApiResponse response = await polylinePoints
          .getRouteBetweenCoordinatesV2(request: request);
      if (response.status == 'OK' && response.routes.isNotEmpty) {
        final route = response.routes.first;

        return {
          'distance': route.distanceKm,
          'duration': route.durationMinutes!.toDouble(),
        };
      }
    } catch (e) {
      debugPrint("Error getting route details: $e");
    }
    return null;
  }

  void listenForEarnings() {
    earningsSubscription?.cancel();
    rentalEarningsSubscriptionLocal?.cancel();

    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final endOfToday = startOfToday.add(const Duration(days: 1));

    // Temporary storage for latest data from each stream
    double dailyTotal = 0;
    double rentalTotal = 0;
    Ride? latestDailyRide;
    Ride? latestRentalRide;

    // Helper to update combined state
    void updateState() {
      todaysEarnings.value = dailyTotal + rentalTotal;

      // Determine overall last ride
      if (latestDailyRide != null && latestRentalRide != null) {
        lastRide.value =
            latestDailyRide!.timestamp.isAfter(latestRentalRide!.timestamp)
            ? latestDailyRide
            : latestRentalRide;
      } else {
        lastRide.value = latestDailyRide ?? latestRentalRide;
      }
    }

    // 1. Daily Rides Stream
    earningsSubscription = FirebaseFirestore.instance
        .collection('ride_requests')
        .where('driverId', isEqualTo: user.uid)
        .where('status', isEqualTo: 'completed')
        .where('createdAt', isGreaterThanOrEqualTo: startOfToday)
        .where('createdAt', isLessThan: endOfToday)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snapshot) {
          double tempTotal = 0;
          Ride? tempLast;

          if (snapshot.docs.isNotEmpty) {
            for (var doc in snapshot.docs) {
              final data = doc.data();
              tempTotal += (data['totalFare'] as num? ?? 0.0).toDouble();
            }
            // Parse last ride
            tempLast = Ride.fromFirestore(snapshot.docs.first);
          }

          dailyTotal = tempTotal;
          latestDailyRide = tempLast;
          updateState();
        }, onError: (error) => debugPrint("Daily Earnings Error: $error"));

    // 2. Rental Rides Stream
    rentalEarningsSubscriptionLocal = FirebaseFirestore.instance
        .collection('rental_requests')
        .where('driverId', isEqualTo: user.uid)
        .where('status', isEqualTo: 'completed')
        .where('createdAt', isGreaterThanOrEqualTo: startOfToday)
        .where('createdAt', isLessThan: endOfToday)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snapshot) {
          double tempTotal = 0;
          Ride? tempLast;

          if (snapshot.docs.isNotEmpty) {
            for (var doc in snapshot.docs) {
              final data = doc.data();
              tempTotal += (data['totalFare'] as num? ?? 0.0).toDouble();
            }
            // Parse last ride using updated Ride model
            tempLast = Ride.fromFirestore(snapshot.docs.first);
          }

          rentalTotal = tempTotal;
          latestRentalRide = tempLast;
          updateState();
        }, onError: (error) => debugPrint("Rental Earnings Error: $error"));
  }

  Future<void> playRideRequestSound() async {
    if (isClosed || _isAcceptingRide) {
      return; // Guard against playing during acceptance
    }
    try {
      debugPrint("Attempting to play sound...");
      originalVolume = await volumeController.getVolume();
      volumeController.showSystemUI = false;
      await volumeController.setVolume(1.0);
      await audioPlayer.setReleaseMode(ReleaseMode.loop);
      await audioPlayer.play(AssetSource('sounds/ride_request_alert.mp3'));
      debugPrint("Sound playing successfully.");
      if (await Vibration.hasVibrator() == true) {
        Vibration.vibrate(pattern: [500, 1000, 500, 2000], repeat: 0);
      }
    } catch (e) {
      debugPrint("Error playing sound: $e");
    }
  }

  Future<void> playRentalNotification() async {
    _isRentalRinging = true;

    // Set volume once
    try {
      originalVolume = await volumeController.getVolume();
      volumeController.showSystemUI = false;
      await volumeController.setVolume(1.0);
    } catch (e) {
      debugPrint("Volume Error: $e");
    }

    _speakRentalLoop();
  }

  Future<void> _speakRentalLoop() async {
    await Future.delayed(const Duration(milliseconds: 500));

    while (_isRentalRinging) {
      if (isClosed) break;

      // 1. Play TTS
      try {
        try {
          await audioPlayer.stop(); // Ensure sound is stopped
        } catch (e) {
          debugPrint("Error stopping audio (TTS loop): $e");
        }

        String speechText = "Rental Request";
        if (activeRideRequest.value?.vehicleType == "ActingDriver") {
          speechText = "Acting Driver Request";
        }

        await flutterTts.speak(speechText);

        // Manual delay to ensure TTS finishes before sound starts
        // "Acting Driver Request" is slightly longer, so 2s is good safe buffer
        await Future.delayed(const Duration(seconds: 2));
      } catch (e) {
        debugPrint("TTS Error: $e");
      }

      if (!_isRentalRinging) break;

      // 2. Play Sound (One-shot)
      try {
        await flutterTts.stop(); // Ensure TTS is stopped
        await audioPlayer.setReleaseMode(ReleaseMode.release);
        await audioPlayer.play(AssetSource('sounds/ride_request_alert.mp3'));

        if (await Vibration.hasVibrator() == true) {
          Vibration.vibrate(pattern: [0, 1000], repeat: -1);
        }

        // Wait for sound duration
        await Future.delayed(const Duration(seconds: 1));
      } catch (e) {
        debugPrint("Sound Error: $e");
        await Future.delayed(const Duration(seconds: 1));
      }

      if (_isRentalRinging) {
        await Future.delayed(const Duration(seconds: 1));
      }
    }
  }

  Future<void> stopRideRequestSound() async {
    _isRentalRinging = false;
    // Do not check isClosed here, we want to stop sound regardless of controller state

    debugPrint("Stopping Audio and Vibration...");

    // 1. Stop Audio
    try {
      await audioPlayer.stop();
      await audioPlayer.setReleaseMode(
        ReleaseMode.release,
      ); // Reset release mode
    } catch (e) {
      debugPrint("Error stopping audio (stopRideRequestSound): $e");
    }

    // 2. Stop TTS
    try {
      await flutterTts.stop();
    } catch (e) {
      debugPrint("Error stopping TTS: $e");
    }

    // 3. Stop Vibration (Aggressive)
    try {
      // Just call cancel directly, don't wait for 'hasVibrator' check which can be slow or fail
      Vibration.cancel();
    } catch (e) {
      debugPrint("Error stopping vibration: $e");
    }

    // 4. Restore Volume
    try {
      volumeController.showSystemUI = false;
      if (originalVolume != null) {
        // volumeController.setVolume(originalVolume!).catchError((_) {});
      }
    } catch (e) {
      debugPrint("Error restoring volume: $e");
    }
  }

  bool _isAcceptingRide = false;

  Future<void> onRideAccepted() async {
    if (_isAcceptingRide) return;
    _isAcceptingRide = true;
    isRideAcceptanceInProgress.value = true; // Hide request card immediately
    stopRideRequestSound();
    rideTimeoutTimer?.cancel(); // CRITICAL FIX: Cancel timeout immediately

    final request = activeRideRequest.value;
    if (request == null) {
      Get.snackbar("Error", "Ride Request Expired");
      _isAcceptingRide = false;
      return;
    }

    // --- Subscription Auto-Activation Check ---
    try {
      final driverDoc = await FirebaseFirestore.instance
          .collection('drivers')
          .doc(user.uid)
          .get();
      DateTime? expiry;
      if (driverDoc.exists &&
          driverDoc.data()!.containsKey('subscriptionExpiry')) {
        final val = driverDoc.data()!['subscriptionExpiry'];
        if (val is Timestamp) expiry = val.toDate();
      }

      if (expiry == null || expiry.isBefore(DateTime.now())) {
        // Auto-buy 1 Day Plan (Free Trial)
        Get.snackbar(
          "Auto-Activation",
          "No active plan found. Activating 1 Day Free Trial.",
          duration: const Duration(seconds: 4),
        );
        await Get.find<WalletController>().activateFreeTrialPlan(
          "1 Day Auto (Trial)",
          1,
        );
        // We proceed after buying
      }
    } catch (e) {
      debugPrint("Subscription Check Error: $e");
      // Decide if we block acceptance? User requirement implies "should activate... then...".
      // We'll log error but proceed to avoid blocking work if network glitch,
      // but ideally we should ensure purchase.
    }
    // ------------------------------------------

    try {
      final rideId = request.rideId;
      final driverId = user.uid;
      final rideType = request.rideType;
      // Collection based on type
      final collectionPath = (rideType == 'rental')
          ? 'rental_requests'
          : 'ride_requests';

      debugPrint("Accepting Ride $rideId in $collectionPath");

      // 0. Fetch Driver Details First
      final driverDocSnapshot = await FirebaseFirestore.instance
          .collection('drivers')
          .doc(user.uid)
          .get();
      final dData = driverDocSnapshot.data();

      final dName = dData?['displayName'] ?? user.displayName ?? 'Driver';
      final dPhone = dData?['phoneNumber'] ?? user.phoneNumber ?? '';
      final dPhoto = dData?['photoUrl'] ?? user.photoURL ?? '';
      final dCarModel = dData?['carName'] ?? dData?['vehicleType'] ?? '';
      final dCarNumber = dData?['vehicleNumber'] ?? '';

      // 1. Transaction to claim the ride
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final rideRef = FirebaseFirestore.instance
            .collection(collectionPath)
            .doc(rideId);
        final rideDoc = await transaction.get(rideRef);

        if (!rideDoc.exists) {
          throw "Ride document does not exist";
        }

        final status = rideDoc.data()?['status'];
        if (status != 'searching') {
          throw "Ride is no longer available (Status: $status)";
        }

        transaction.update(rideRef, {
          'status': 'accepted',
          'driverId': driverId,
          'driverName': dName,
          'driverPhone': dPhone,
          'driverPhoto': dPhoto,
          'vehicleNumber': dCarNumber,
          'vehicleModel': dCarModel,
          'otp': '1234', // In real app, generate or read from doc
          'acceptedAt': FieldValue.serverTimestamp(),
        });
      });

      // 2. Set Driver Status to Busy/Offline locally & server (Server triggered by Cloud Function usually)
      driverStatus.value = DriverStatus.goTo;
      // Note: Cloud Function 'manageDriverStatus' will likely update driver doc to 'on_trip'

      Get.offAll(() => RideAcceptedScreen(rideRequest: request));
    } catch (e) {
      Get.snackbar("Error", "Could not accept ride: $e");
      debugPrint("Accept Error: $e");
      _isAcceptingRide = false;
      isRideAcceptanceInProgress.value = false; // Re-show card on error
    }
  }

  Future<void> onRideRejected(String reason) async {
    stopRideRequestSound();
    if (activeRideRequest.value == null) return;

    final rideId = activeRideRequest.value!.rideId;
    final driverId = user.uid;
    _ignoredRides[rideId] =
        DateTime.now(); // Ignore this ride ID locally from now on
    final rideType = activeRideRequest.value!.rideType;
    final collectionPath = (rideType == 'rental')
        ? 'rental_requests'
        : 'ride_requests';

    debugPrint("Rejecting Ride $rideId (Reason: $reason) in $collectionPath");

    // Clear local state immediately to hide UI
    activeRideRequest.value = null;

    // CRITICAL FIX: Close overlay if it's open (especially for background timeout/rejection)
    OverlayService.instance.hideFloatingBubble();

    Get.back(); // Close Request Card/Screen if open

    try {
      // Add driver to 'rejectedBy' array in Firestore
      // Server Function will see this change and assign to next driver
      await FirebaseFirestore.instance
          .collection(collectionPath)
          .doc(rideId)
          .update({
            'rejectedBy': FieldValue.arrayUnion([driverId]),
          });
    } catch (e) {
      debugPrint("Error rejecting ride: $e");
    }
  }

  void startRideTimeout(String rideId) {
    rideTimeoutTimer?.cancel();

    final isRental = activeRideRequest.value?.rideType == 'rental';
    // Rental requests: 10 seconds (match RentalRequestScreen timer)
    // Regular rides: 5 seconds (quick round robin)
    final timeoutDuration = isRental ? 10 : 5;

    debugPrint("Starting Ride Timeout for $rideId: $timeoutDuration seconds");

    rideTimeoutTimer = Timer(Duration(seconds: timeoutDuration), () async {
      // Only clear if still pointing to the same ride
      if (activeRideRequest.value != null &&
          activeRideRequest.value!.rideId == rideId) {
        stopRideRequestSound();

        if (isRental) {
          Get.back(); // Close Rental Screen
        }

        debugPrint('Triggering local timeout for ride $rideId');

        // REJECT on timeout to pass to next driver (Round Robin)
        onRideRejected("timeout_local");

        debugPrint("Local timeout triggered. Rejection sent to server.");
      } else {
        debugPrint(
          "Ride Timeout callback ignored: Active(${activeRideRequest.value?.rideId}) != Target($rideId)",
        );
      }
    });
  }

  Future<bool> _handleLocationPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      Get.snackbar(
        'Location Services Disabled',
        'Please enable location services to use the app.',
      );
      return false;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        Get.snackbar('Permission Denied', 'Location permissions are denied.');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      Get.snackbar(
        'Permission Denied',
        'Location permissions are permanently denied, we cannot request permissions.',
      );
      return false;
    }

    return true;
  }

  Future<void> goToCurrentUserLocation({bool shouldAnimate = true}) async {
    debugPrint("goToCurrentUserLocation: Start");
    final hasPermission = await _handleLocationPermission();
    debugPrint(
      "goToCurrentUserLocation: Permission check result: $hasPermission",
    );
    if (!hasPermission) return;

    try {
      debugPrint("goToCurrentUserLocation: Fetching position...");
      Position? position;

      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        ).timeout(const Duration(seconds: 10));
      } catch (e) {
        debugPrint(
          "goToCurrentUserLocation: High accuracy timed out/failed ($e). Checking last known...",
        );
      }

      // If high accuracy failed, try last known position
      if (position == null) {
        position = await Geolocator.getLastKnownPosition();
        if (position != null) {
          debugPrint("goToCurrentUserLocation: Using Last Known Position.");
        }
      }

      // If still null, try low accuracy with a timeout
      if (position == null) {
        debugPrint(
          "goToCurrentUserLocation: Last known invalid. Trying low accuracy...",
        );
        try {
          position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.low,
            ),
          ).timeout(const Duration(seconds: 5));
        } catch (e) {
          debugPrint("goToCurrentUserLocation: Low accuracy also failed: $e");
        }
      }

      if (position != null) {
        debugPrint(
          "goToCurrentUserLocation: Position fetched: ${position.latitude}, ${position.longitude}",
        );
        currentPosition.value = LatLng(position.latitude, position.longitude);

        if (mapController.isCompleted) {
          debugPrint(
            "goToCurrentUserLocation: MapController is completed. Updating camera.",
          );
          final controller = await mapController.future;
          if (shouldAnimate) {
            await controller.animateCamera(
              CameraUpdate.newCameraPosition(
                CameraPosition(target: currentPosition.value!, zoom: 14.5),
              ),
            );
          } else {
            await controller.moveCamera(
              CameraUpdate.newCameraPosition(
                CameraPosition(target: currentPosition.value!, zoom: 14.5),
              ),
            );
          }
        } else {
          debugPrint("goToCurrentUserLocation: MapController NOT completed.");
        }
      } else {
        debugPrint(
          "goToCurrentUserLocation: Unable to determine location after all attempts.",
        );
        Get.snackbar(
          "Location Error",
          "Unable to detect your location. Please ensure GPS is active.",
        );
      }
    } catch (e) {
      debugPrint("Error getting current location: $e");
    }
    debugPrint("goToCurrentUserLocation: End");
  }

  Future<Map<String, String>> getParsedAddressFromLatLng(
    LatLng position,
  ) async {
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/geocode/json?latlng=${position.latitude},${position.longitude}&key=$apiKey',
    );
    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final parsed = json.decode(response.body);
        if (parsed['status'] == 'OK' && parsed['results'].isNotEmpty) {
          final result = parsed['results'][0];
          final components = result['address_components'];

          String area = "";
          for (var component in components) {
            final types = component['types'] as List;
            if (types.contains('sublocality') ||
                types.contains('locality') ||
                types.contains('sublocality_level_1')) {
              area = component['long_name'];
              break;
            }
          }

          return {
            'area': area.isNotEmpty ? area : result['formatted_address'],
            'fullAddress': result['formatted_address'],
          };
        }
      }
    } catch (e) {
      debugPrint("Error detecting address: $e");
    }
    return {'area': 'Unknown', 'fullAddress': 'Unknown'};
  }

  Future<void> logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    Get.offAll(() => const LoginScreen());
  }

  // --- Demand Zones (Heatmap) Logic ---
  final RxSet<Circle> demandCircles = <Circle>{}.obs;
  final DemandService _demandService = DemandService();
  StreamSubscription? _demandSubscription;

  void _startDemandMonitoring() {
    _stopDemandMonitoring(); // ensure previous sub is cancelled
    debugPrint("Starting Demand Monitoring...");
    _demandSubscription = _demandService.getDemandZones().listen(
      (zones) {
        debugPrint("Demand Zones Update: ${zones.length} zones found");
        final circles = <Circle>{};
        for (var zone in zones) {
          Color circleColor;
          // Use standard red/yellow/green logic
          if (zone.count >= 5) {
            circleColor = Colors.red.withValues(alpha: 0.4); // High Demand
          } else if (zone.count >= 3) {
            circleColor = Colors.orange.withValues(alpha: 0.4); // Medium Demand
          } else {
            circleColor = Colors.yellow.withValues(alpha: 0.4); // Low Demand
          }

          circles.add(
            Circle(
              circleId: CircleId(zone.geohash),
              center: zone.center,
              radius: 600, // ~600m radius to cover the block visibly
              fillColor: circleColor,
              strokeWidth: 0,
              zIndex: 1, // Below markers
            ),
          );
        }
        demandCircles.assignAll(circles);
      },
      onError: (e) {
        debugPrint("Error fetching demand zones: $e");
      },
    );
  }

  void _stopDemandMonitoring() {
    _demandSubscription?.cancel();
    _demandSubscription = null;
    demandCircles.clear();
  }
}
