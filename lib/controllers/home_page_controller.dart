import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart' hide Query;
import 'package:flutter/material.dart' hide Route;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:project_taxi_driver_app/services/id_service.dart';
import 'package:project_taxi_driver_app/services/ride_queue_service.dart';

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
import 'package:project_taxi_driver_app/utils/app_colors.dart';
import 'package:flutter_tts/flutter_tts.dart';

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
  final RxString driverId = ''.obs;
  final Rxn<LatLng> currentPosition = Rxn<LatLng>();
  final RxDouble sheetExtent = 0.1.obs;
  final RxSet<Polygon> polygons = <Polygon>{}.obs;

  // Driver Profile State
  final RxString driverVehicleClass = ''.obs;
  final RxString driverVehicleType = ''.obs;
  final RxString driverName = ''.obs;
  final RxString driverRole = ''.obs;

  // Ride Request State
  // CHANGED: List of requests instead of single request
  final RxList<RideRequest> activeRequests = <RideRequest>[].obs;
  final RxString currentSortOption = 'Smart'.obs; // Default sort
  final RxBool isRideAcceptanceInProgress = false.obs;


  // Helper for backward compatibility or easy access to "top" request
  RideRequest? get activeRideRequest =>
      activeRequests.isNotEmpty ? activeRequests.first : null;

  final RxBool hasActiveRide = false.obs;
  QuerySnapshot? lastRideRequestSnapshot;

  // Earnings State
  final RxDouble todaysEarnings = 0.0.obs;
  final RxDouble walletBalance = 0.0.obs;
  final Rxn<Ride> lastRide = Rxn<Ride>();

  // Snooze Logic / Ignored Rides
  final Map<String, DateTime> _ignoredRides = {};
  final Set<String> _processingRideIds = <String>{};
  final Set<String> _recentlyClearedRideIds = <String>{}; // Fixed: One-last-time bug
  SharedPreferences? _prefs;
  final RxSet<String> _ignoredPersistentRides = <String>{}.obs;

  // Subscriptions and Timers
  StreamSubscription? rideRequestSubscription;
  StreamSubscription? rentalRequestSubscription;

  StreamSubscription? earningsSubscription;
  StreamSubscription?
  rentalEarningsSubscriptionLocal; // Renamed to avoid confusion with request listener
  StreamSubscription? walletSubscription;
  StreamSubscription? overlaySubscription; // Added this line
  Timer? locationUpdateTimer;
  final Map<String, Timer> rideTimers = {};
  final Map<String, StreamSubscription> _activeRideSubscriptions =
      {}; // Track individual ride listeners

  // Audio
  // Static to ensure singleton control over audio across controller lifecycles
  final AudioPlayer audioPlayer = AudioPlayer();
  final FlutterTts flutterTts = FlutterTts();
  final VolumeController volumeController = VolumeController.instance;
  double? originalVolume;
  bool _isRentalRinging = false;
  bool _isStoppingRideSound = false;

  // API Key
  late final String apiKey;

  // App Lifecycle
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;
  DateTime? _lastBubbleShowTime;

  //  Timer? locationUpdateTimer;
  Timer? _revaluationTimer; // Added for re-checking ignored rides
  QuerySnapshot? _lastSnapshot; // Cache for re-evaluation
  String? _driverDocId;
  DateTime? _lastOverlayActionTime; // Time of last major overlay action (accept/reject)
  bool _locationUpdatesRunning = false; // Flag to prevent duplicate location updates

  // NEW: Back-to-back rides queue management
  final RideQueueService _rideQueueService = RideQueueService();
  Timer? _etaCheckTimer;

  Future<void> _loadDocId() async {
    _driverDocId = await IdService.getDriverDocId(user.uid);
    debugPrint("HomePageController: Final driverDocId: $_driverDocId");
  }

  @override
  void onInit() {
    super.onInit();
    Get.lazyPut(
      () => WalletController(),
      fenix: true,
    ); // Ensure WalletController is available
    
    // Diagnostic Check: Verify real Firestore data
    _runDiagnostics();

    WidgetsBinding.instance.addObserver(this);
    ever(driverStatus, (status) => handleStatusChange(status));
    _loadDocId().then((_) {
      listenForWallet();
      listenForNotifications();
      _fetchTollZones(); // Pre-fetch toll zones for dynamic pricing
      if ((driverStatus.value == DriverStatus.online ||
              driverStatus.value == DriverStatus.goTo) &&
          _appLifecycleState != AppLifecycleState.resumed) {
        showStatusBubble();
      }
    });

    // Request initial position immediately
    goToCurrentUserLocation();
    
    final apiKeyValue = dotenv.env['GOOGLE_MAPS_API_KEY'];
    if (apiKeyValue == null) {
      debugPrint("ERROR: GOOGLE_MAPS_API_KEY not found in .env file");
      isLoading.value = false;
      return;
    }
    apiKey = apiKeyValue;

    loadLanguage();
    _loadAndInitialize();

    // Safe API Key Initialization
    try {
      // Check API Key
    } catch (e) {
      // ignore
    }

    // Configure Audio Context for Background Playback
    _configureAudioSession();

    // Safe permission request
    Future.delayed(const Duration(seconds: 3), () {
      try {
        OverlayService.instance.ensurePermission();
      } catch (e) {
        debugPrint("Error requesting overlay permission in Home: $e");
      }
    });
  }

  Future<void> _runDiagnostics() async {
    try {
      debugPrint("Starting Diagnostics...");
      final callable = FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('debugDriver');
      final result = await callable.call();
      debugPrint("DIAGNOSTICS - Driver Doc ID: ${result.data['docId']}");
      debugPrint("DIAGNOSTICS - Exists: ${result.data['exists']}");
      debugPrint("DIAGNOSTICS - Raw Data: ${result.data['data']}");
    } catch (e) {
      debugPrint("DIAGNOSTICS FAILED: $e");
    }
  }

  String get currentUserId => user.uid; // Added for easy access

  Future<void> _loadAndInitialize() async {
    await _loadDocId();
    
    // Fetch initial driver profile for matching logic
    try {
      final doc = await FirebaseFirestore.instance
          .collection('drivers')
          .doc(_driverDocId ?? user.uid)
          .get();
      if (doc.exists) {
        final data = doc.data();
        driverVehicleClass.value = data?['vehicleClass'] ?? '';
        driverVehicleType.value = data?['vehicleType'] ?? '';
        driverName.value = data?['displayName'] ?? data?['name'] ?? '';
        driverRole.value = data?['role'] ?? '';
        debugPrint("HomePageController: Profile loaded. Class: ${driverVehicleClass.value}, Role: ${driverRole.value}");
      }
    } catch (e) {
      debugPrint("HomePageController: Error loading driver profile: $e");
    }

    _init(); // Existing map init
    
    // Pre-load SharedPreferences
    _prefs = await SharedPreferences.getInstance();
    final ignoredList = _prefs?.getStringList('ignored_rides') ?? [];
    _ignoredPersistentRides.assignAll(ignoredList);
    debugPrint("HomePageController: Pre-loaded ${_ignoredPersistentRides.length} ignored rides.");

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

    listenForWallet();
    listenForNotifications();

    // Set Initial Status if provided
    if (initialStatus != null) {
      debugPrint(
        "Startup: Using provided Initial Driver Status: $initialStatus",
      );
      driverStatus.value = initialStatus!;

      if (initialStatus == DriverStatus.online ||
          initialStatus == DriverStatus.goTo) {
        WakelockPlus.enable();
        // Start listeners immediately as we are already "warmed up"
        startLocationUpdates();
        listenForRideRequests();
        if (!isActingDriver) {
          listenForRentalRequests();
        }
        listenForEarnings();

        // Start back-to-back rides ETA monitoring
        _startETAMonitoring();

        // Start Queue Monitoring on startup if already online
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
      }
    }
  }

  Future<void> _init() async {
    try {
      await goToCurrentUserLocation(shouldAnimate: false);
    } catch (e) {
      debugPrint("Initialization Error: $e");
    } finally {
      isLoading.value = false;
    }
  }


  Map<String, dynamic> _buildOverlayPayload(RideRequest request) {
    return {
      'rideId': request.rideId,
      'rideType': request.rideType,
      'vehicleClass': request.vehicleClass,
      'paymentMethod': request.paymentMethod,
      'paidByWallet': request.paidByWallet ?? 0,
      'driverDistance': request.driverDistance,
      'driverDuration': request.driverDuration,
      'rideDistance': request.rideDistance,
      'rideDuration': request.rideDuration,
      'pickupTitle': request.pickupTitle,
      'pickupFullAddress': request.pickupFullAddress,
      'dropoffTitle': request.dropoffTitle,
      'dropoffFullAddress': request.dropoffFullAddress,
      'rideFare': request.rideFare,
      'tip': request.tip,
      'createdAt': request.createdAt?.millisecondsSinceEpoch,
      'durationHours': request.durationHours, // Added for Rental
      'kmLimit': request.kmLimit, // Added for Rental
      'packageName': request.packageName, // Added for Rental
      'stops': request.stops
          .map((s) => {'address': s.fullAddress, 'status': s.status})
          .toList(),
      'tollPrice': request.tollPrice,
    };
  }

  Future<void> _showOverlayForRide(RideRequest request) async {
    await OverlayService.instance.showRideRequestOverlay(
      _buildOverlayPayload(request),
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
    overlaySubscription?.cancel(); // Cancel overlay subscription
    audioPlayer.dispose();
    WakelockPlus.disable();
    WidgetsBinding.instance.removeObserver(this);
    _stopDemandMonitoring();
    // Cancel all active ride subscriptions
    for (var sub in _activeRideSubscriptions.values) {
      sub.cancel();
    }
    _activeRideSubscriptions.clear();
    super.onClose();
  }

  Future<void> loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    selectedLanguageCode.value = prefs.getString('selectedLanguage') ?? 'en';
    Get.updateLocale(Locale(selectedLanguageCode.value));
  }
  // ------------------------------------------------------------------
  // Helper Methods
  // ------------------------------------------------------------------

  String getTranslatedString(String key) {
    return key.tr;
  }

  // ------------------------------------------------------------------
  // Multi-Ride Support Methods
  // ------------------------------------------------------------------

  // ------------------------------------------------------------------
  // Individual Ride Status Listener
  // ------------------------------------------------------------------

  void _listenToRideStatus(String rideId, String rideType) {
    if (_activeRideSubscriptions.containsKey(rideId)) return;

    final collection = (rideType == 'rental')
        ? 'rental_requests'
        : 'ride_requests';
    debugPrint("Starting status listener for $rideId in $collection");

    _activeRideSubscriptions[rideId] = FirebaseFirestore.instance
        .collection(collection)
        .doc(rideId)
        .snapshots()
        .listen(
          (snapshot) {
            if (!snapshot.exists) {
              // Doc deleted? Treat as cancelled or just remove
              debugPrint("Ride $rideId document deleted. Cleaning up.");
              if (Get.isSnackbarOpen) Get.closeCurrentSnackbar();
              Get.snackbar(
                "Ride Cancelled",
                "User cancelled the ride",
                backgroundColor: Colors.orange,
                colorText: Colors.white,
                duration: const Duration(seconds: 4),
                snackPosition: SnackPosition.TOP,
              );
              _clearLocalRide(rideId);
              return;
            }

            final data = snapshot.data();
            final status = data?['status'];
            debugPrint("Ride $rideId status update: $status");

            // Ignore updates if we are in the middle of accepting THIS ride
            // Only skip if WE are currently in the acceptance flow
            // Check driverUid (auth UID) — driverId is the professional ID
            if (status == 'accepted' &&
                (data?['driverUid'] == user.uid || data?['driverId'] == user.uid) &&
                _isAcceptingRide) {
              return;
            }

            if (status != 'searching') {
              debugPrint(
                "Ride $rideId is no longer searching (Status: $status). Removing.",
              );

              // Specific Messages
              if (status == 'cancelled' || status == 'canceled') {
                if (Get.isSnackbarOpen) Get.closeCurrentSnackbar();
                Get.snackbar(
                  "Ride Cancelled",
                  "User cancelled the ride",
                  backgroundColor: Colors.orange,
                  colorText: Colors.white,
                  duration: const Duration(seconds: 4),
                  snackPosition: SnackPosition.TOP,
                );
              } else if (status == 'accepted') {
                // Accepted by someone else (checked above that it's not us)
                if (Get.isSnackbarOpen) Get.closeCurrentSnackbar();
                Get.snackbar(
                  "Ride Missed",
                  "Accepted by another driver",
                  backgroundColor: Colors.redAccent,
                  colorText: Colors.white,
                  duration: const Duration(seconds: 4),
                );
              }

              _clearLocalRide(rideId);
            }
          },
          onError: (e) {
            debugPrint("Error listening to ride $rideId status: $e");
          },
        );
  }

  void _clearLocalRide(String rideId) {
    debugPrint("Clearing local ride: $rideId");
    
    // 0. Trigger Overlay Lockdown
    _lastOverlayActionTime = DateTime.now();

    // Add to temporary blacklist to prevent "one last time" reappear bug
    _recentlyClearedRideIds.add(rideId);
    Future.delayed(const Duration(seconds: 10), () {
      _recentlyClearedRideIds.remove(rideId);
      debugPrint("Removed $rideId from recently cleared blacklist");
    });

    // 1. Cancel Subscription
    _activeRideSubscriptions[rideId]?.cancel();
    _activeRideSubscriptions.remove(rideId);

    // 2. Local Cleanup
    _ignoredRides[rideId] = DateTime.now();

    // Remove from overlay queue immediately
    OverlayService.instance.removeRide(rideId);

    // Remove from active list
    activeRequests.removeWhere((r) => r.rideId == rideId);

    // Cancel specific timer
    rideTimers[rideId]?.cancel();
    rideTimers.remove(rideId);

    // Update UI
    activeRequests.refresh();
    update();

    // Check if we need to close Rental Screen
    // logic: if top active request matches rideId (before removal) - effectively handled by removeWhere
    // But if we are ON the screen, we might need to pop.
    // However, startRideTimeout handles the pop for rental if it expires.
    // Here we should probably check if we are on the rental screen for THIS ride.
    // A simple way is to check if activeRequests is empty or if the top one changed.

    // If we were showing a rental screen for this ride, we should probably close it.
    // But safely. For now, rely on strict "activeRequests" binding in UI or `Obx`.
    // Actually, `RentalRequestScreen` might effectively be checking `activeRideRequest`.
    // If `activeRideRequest` becomes null, we might want to pop.
    if (Get.currentRoute == '/RentalRequestScreen') {
      // We can't easily check args here without Get.arguments.
      // Safe bet: just close it if no active rental request remains.
      if (activeRequests.isEmpty || activeRequests.first.rideType != 'rental') {
        Get.back(); // close rental screen
      }
    }

    // Stop sound if no requests left
    if (activeRequests.isEmpty) {
      stopRideRequestSound();
      hasActiveRide.value = false;

      if (driverStatus.value == DriverStatus.online &&
          _appLifecycleState != AppLifecycleState.resumed) {
        showStatusBubble();
      } else {
        OverlayService.instance.hideFloatingBubble();
      }
    } else {
      // If there are more requests, ensure sorting is applied
      _applySort();
      // Update overlay with next ride if backgrounded
      if (activeRequests.isNotEmpty &&
          _appLifecycleState != AppLifecycleState.resumed) {
        _showOverlayForRide(activeRequests.first);
      }
    }
  }

  Future<void> passRide(String rideId) async {
    if (_isAcceptingRide) return; // Don't pass if we are accepting

    debugPrint("Passing ride: $rideId");

    final ride = activeRequests.firstWhereOrNull((r) => r.rideId == rideId);
    if (ride == null) {
      // Already removed?
      _clearLocalRide(rideId);
      return;
    }

    final isRental = ride.rideType == 'rental';
    final collection = isRental ? 'rental_requests' : 'ride_requests';

    // 1. Local Cleanup
    _clearLocalRide(rideId);

    // 2. Server Side Update
    try {
      await FirebaseFirestore.instance
          .collection(collection)
          .doc(rideId)
          .update({
            'driverId': '', // Unassign me
            'rejectedBy': FieldValue.arrayUnion([user.uid]),
          });
      debugPrint("Server rejection successful for $rideId");
    } catch (e) {
      debugPrint("Error rejecting ride on server: $e");
    }
  }

  void sortRequests(String criteria) {
    currentSortOption.value = criteria;
    _applySort();
  }

  void _applySort() {
    if (activeRequests.isEmpty) return;

    switch (currentSortOption.value) {
      case 'Price':
        activeRequests.sort(
          (a, b) => b.rideFare.compareTo(a.rideFare),
        ); // High to Low
        break;
      case 'Distance':
        // sort by pickup distance (closest first)
        activeRequests.sort(
          (a, b) => a.driverDistance.compareTo(b.driverDistance),
        );
        break;
      case 'Time':
        // sort by created time (newest first) or pickup time?
        // Assuming newest first for responsiveness, or oldest first to avoid starvation?
        // Let's go with Distance as default "Time" proxy usually implies "how long to get there".
        // Actually, let's use driverDuration if available.
        activeRequests.sort(
          (a, b) => (a.driverDuration ?? 0).compareTo(b.driverDuration ?? 0),
        );
        break;
      case 'Smart':
      default:
        // Smart: High Price/Km ratio AND Close Pickup
        // Score = Fare / (TotalDistance + PickupDistance)
        // Or just Fare / Distance - penalty for pickup time.
        // Simple heuristic: Fare / (RideDist + DriverDist/2)
        activeRequests.sort((a, b) {
          double scoreA = _calculateSmartScore(a);
          double scoreB = _calculateSmartScore(b);
          return scoreB.compareTo(scoreA); // High score first
        });
        break;
    }
    activeRequests.refresh(); // Update UI
  }

  double _calculateSmartScore(RideRequest r) {
    double totalDist = r.rideDistance + (r.driverDistance);
    if (totalDist == 0) return 0;
    return r.rideFare / totalDist;
  }

  Future<void> handleStatusChange(DriverStatus status) async {
    debugPrint("handleStatusChange called with status: $status");

    // Persist status locally for faster restoration on next app start
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('lastDriverStatus', status.name);
      debugPrint("Status persisted locally: ${status.name}");
    } catch (e) {
      debugPrint("Error persisting status: $e");
    }

    // Blocked and Off-road Checks
    if (status == DriverStatus.online) {
      // 1. Blocked Status Check
      try {
        final doc = await FirebaseFirestore.instance
            .collection('drivers')
            .doc(_driverDocId ?? user.uid)
            .get();
        if (doc.exists) {
          final data = doc.data();
          final isBlocked = data?['isBlocked'] ?? false;
          if (isBlocked) {
            Get.defaultDialog(
              title: "Account Blocked",
              middleText:
                  "Your account has been blocked. Please contact customer care for more info.",
              textConfirm: "OK",
              confirmTextColor: Colors.white,
              buttonColor: AppColors.primary,
              onConfirm: () {
                Get.back();
              },
            );
            
            // Revert visual state
            Future.delayed(const Duration(milliseconds: 100), () {
              driverStatus.value = DriverStatus.offline;
            });
            return;
          }
        }
      } catch (e) {
        debugPrint("Error checking blocked status: $e");
      }

      // 2. Off-road Check (Local Enforcement)
      final prefs = await SharedPreferences.getInstance();
      bool isOffroaded = prefs.getBool('isWalletOffroaded') ?? false;

      // Ensure wallet data is loaded
      if (walletBalance.value <= -300) {
        isOffroaded = true;
        await prefs.setBool('isWalletOffroaded', true);
      } else if (walletBalance.value >= -100) {
        isOffroaded = false;
        await prefs.setBool('isWalletOffroaded', false);
      }

      if (isOffroaded) {
        Get.defaultDialog(
          title: "Account Offroaded",
          middleText:
              "Vehicle offroaded. Please recharge your wallet to at least ₹-100 to go online. Current balance: ₹${walletBalance.value.toStringAsFixed(2)}",
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
      OverlayService.instance.startDriverForeground();
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

      // Re-sync polygon from existing data since ever() only fires on changes
      final existingPolygon = QueueService().airportPolygon;
      if (existingPolygon.isNotEmpty && polygons.isEmpty) {
        polygons.assignAll({
          Polygon(
            polygonId: const PolygonId('airport_zone'),
            points: existingPolygon.toList(),
            fillColor: Colors.blue.withValues(alpha: 0.15),
            strokeColor: Colors.blue,
            strokeWidth: 2,
          ),
        });
      }
    } else {
      // Stop Queue Monitoring
      QueueService().stopMonitoring();
      _stopDemandMonitoring();
      WakelockPlus.disable();
      OverlayService.instance.stopDriverForeground();
    }

    if (status == DriverStatus.goTo && activeRequests.isEmpty && !_isAcceptingRide) {
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
          // If we cleared GoTo, do we revert to Online? Yes.
          // Firestore Update to remove GoTo
          await FirebaseFirestore.instance
              .collection('drivers')
              .doc(_driverDocId ?? user.uid)
              .set({
                'isOnline': true,
                'goToDestination': FieldValue.delete(),
              }, SetOptions(merge: true));
        } else {
          goToDestination.value = result;

          // Firestore Update for GoTo
          await FirebaseFirestore.instance
              .collection('drivers')
              .doc(_driverDocId ?? user.uid)
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
        }
      } else {
        debugPrint("GoTo cancelled, reverting to online");
        // User canceled - revert to online status
        driverStatus.value = DriverStatus.online;
        goToDestination.value = null;
        try {
          await FirebaseFirestore.instance
              .collection('drivers')
              .doc(_driverDocId ?? user.uid)
              .set({
                'isOnline': true,
                'goToDestination': null,
              }, SetOptions(merge: true));
          debugPrint("Firestore updated for GoTo cancellation");
        } catch (e) {
          debugPrint("Error updating Firestore for GoTo cancellation: $e");
          // Continue anyway, we already set the local status
        }
      }
    } else {
      // Standard Online/Offline Update
      debugPrint("Processing standard status update to: $status");
      goToDestination.value = null;

      // Use Cloud Function to update status (bypasses Firestore security rules)
      // This fixes PERMISSION_DENIED for professional ID docs (indi-drv-X)
      String? correctedVehicleType;
      if (status == DriverStatus.online) {
        // Check if vehicleType needs correction
        try {
          final doc = await FirebaseFirestore.instance
              .collection('drivers')
              .doc(_driverDocId ?? user.uid)
              .get();
          if (doc.exists) {
            final data = doc.data();
            final vType = data?['vehicleType'];
            final vClass = data?['vehicleClass'];
            if (vType == 'Car' && vClass != null && vClass.toString().isNotEmpty) {
              debugPrint("Auto-Correcting VehicleType from Car to $vClass");
              correctedVehicleType = vClass.toString();
            }
          }
        } catch (e) {
          debugPrint("Error reading vehicle type: $e");
        }
      }

      try {
        final callable = FirebaseFunctions.instanceFor(region: 'asia-south1')
            .httpsCallable('setDriverStatus');
        final result = await callable.call({
          'isOnline': status == DriverStatus.online || status == DriverStatus.goTo,
          if (correctedVehicleType != null) 'vehicleType': correctedVehicleType,
        });
        debugPrint("Cloud Function setDriverStatus success: ${result.data}");
      } catch (e) {
        debugPrint("Warning: Cloud Function setDriverStatus failed: $e. Trying direct write...");
        // Fallback to direct Firestore write
        try {
          final Map<String, dynamic> updateData = {
            'isOnline': status == DriverStatus.online || status == DriverStatus.goTo,
            'goToDestination': null,
          };
          if (status == DriverStatus.online) {
            updateData['status'] = 'active';
            if (correctedVehicleType != null) {
              updateData['vehicleType'] = correctedVehicleType;
            }
          }
          await FirebaseFirestore.instance
              .collection('drivers')
              .doc(_driverDocId ?? user.uid)
              .set(updateData, SetOptions(merge: true));
          debugPrint("Firestore direct write succeeded as fallback.");
        } catch (e2) {
          debugPrint("WARNING: Both Cloud Function AND direct Firestore write FAILED: $e2");
          debugPrint("Driver may not appear online to the dispatch system!");
        }
      }
    }

    if (driverStatus.value == DriverStatus.online ||
        driverStatus.value == DriverStatus.goTo) {
      debugPrint("Starting location updates (Status: ${driverStatus.value})");
      startLocationUpdates();

      if (driverStatus.value == DriverStatus.online) {
        debugPrint("Starting ride listeners (Status: Online)");
        listenForRideRequests();
        if (!isActingDriver) {
          listenForRentalRequests();
        }
      } else {
        // Driver is 'goTo' (Heading to Pickup) - stop looking for new 'searching' rides
        debugPrint("Stopping ride listeners (Status: Busy/GoTo)");
        rideRequestSubscription?.cancel();
        rentalRequestSubscription?.cancel();
        // Nuclear Cleanup of overlay data
        activeRequests.clear();
        OverlayService.instance.clearRideQueue();
      }
    } else {
      debugPrint("Stopping location updates and listeners (Status: Offline)");
      stopLocationUpdates();
      rideRequestSubscription?.cancel();
      rentalRequestSubscription?.cancel();
      activeRequests.clear();
    }
  }

  StreamSubscription<Position>? _positionStreamSubscription;
  Position? _lastSentPosition;

  void startLocationUpdates() async {
    // Prevent duplicate location updates if already running
    if (_locationUpdatesRunning) {
      debugPrint("Location updates already running, skipping duplicate start");
      return;
    }

    final hasPermission = await _handleLocationPermission();
    if (!hasPermission) return;

    _locationUpdatesRunning = true;
    final driverIdForRTDB = _driverDocId ?? user.uid;
    debugPrint("QueueService: Starting Location Updates for RTDB with ID: $driverIdForRTDB");
    final locRef = FirebaseDatabase.instance.ref('driver_locations/$driverIdForRTDB');

    // Auto-set offline if connection drops
    locRef.onDisconnect().remove();

    // Fetch immediately first
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      currentPosition.value = LatLng(position.latitude, position.longitude);
      _updateDriverLocationInRTDB(position, locRef);
      // Fallback for profile data if needed in Firestore
      _updateDriverLocationInFirestore(position);
    } catch (e) {
      debugPrint("Error fetching initial location: $e");
    }

    // Use Stream with Distance Filter
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 15,
    );

    _positionStreamSubscription?.cancel();
    _positionStreamSubscription =
        Geolocator.getPositionStream(
          locationSettings: locationSettings,
        ).listen((Position position) {
          currentPosition.value = LatLng(position.latitude, position.longitude);
          _lastSentPosition = position;
        }, onError: (e) => debugPrint("Location stream error: $e"));

    // Throttle RTDB Sync to Every 1 Second to maintain fresh heartbeat for dispatch
    locationUpdateTimer?.cancel();
    locationUpdateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_lastSentPosition != null) {
        _updateDriverLocationInRTDB(_lastSentPosition!, locRef);
        // Also update Firestore roughly mostly for backwards compatibility Profile views
        _updateDriverLocationInFirestore(_lastSentPosition!);
        _lastSentPosition = null;
      } else if (currentPosition.value != null) {
        // Driver is stationary, but we MUST update RTDB to keep `updatedAt` fresh
        // otherwise the backend will skip dispatching rides to them
        locRef
            .set({
              'lat': currentPosition.value!.latitude,
              'lng': currentPosition.value!.longitude,
              'heading': 0.0,
              'updatedAt': ServerValue.timestamp,
            })
            .catchError((e) => debugPrint("RTDB Sync Error (Stationary): $e"));
      }
    });
  }

  void _updateDriverLocationInRTDB(Position position, DatabaseReference ref) {
    ref
        .set({
          'lat': position.latitude,
          'lng': position.longitude,
          'heading': position.heading,
          'updatedAt': ServerValue.timestamp,
        })
        .catchError((e) => debugPrint("RTDB Sync Error: $e"));
  }

  Future<void> _updateDriverLocationInFirestore(Position position) async {
    try {
      await FirebaseFirestore.instance
          .collection('drivers')
          .doc(_driverDocId ?? user.uid)
          .set({
            'currentLocation': GeoPoint(position.latitude, position.longitude),
          }, SetOptions(merge: true));
    } catch (e) {
      // Non-critical: RTDB is the primary location source for dispatch.
      // This is only for backwards-compatible profile views.
      debugPrint("Firestore location update failed (non-critical): $e");
    }
  }

  // NEW: ETA Monitoring for back-to-back rides
  void _startETAMonitoring() {
    _etaCheckTimer?.cancel();
    _etaCheckTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _checkAndShowNextRides();
    });
    debugPrint("[BackToBack] ETA monitoring started");
  }

  Future<void> _checkAndShowNextRides() async {
    try {
      // Skip if driver is offline or not on a ride
      if (driverStatus.value != DriverStatus.online ||
          activeRideRequest == null ||
          currentPosition.value == null) {
        return;
      }

      // Check if driver already has queued rides
      final hasQueued =
          await _rideQueueService.hasQueuedRides(user.uid);
      if (hasQueued) {
        debugPrint("[BackToBack] Already has queued rides, skipping");
        return;
      }

      // Calculate ETA to destination
      final isApproaching =
          await _rideQueueService.isApproachingDestination(
        currentPosition.value!,
        activeRideRequest!.dropoffLocation,
      );

      if (isApproaching) {
        debugPrint(
          "[BackToBack] ETA < 3 mins - Show next rides overlay",
        );
        _showNextRidesOverlay();
      }
    } catch (e) {
      debugPrint("[BackToBack] Error checking ETA: $e");
    }
  }

  void _showNextRidesOverlay() {
    // This will be integrated with your existing overlay system
    debugPrint("[BackToBack] Next rides overlay should be shown here");
  }

  void stopLocationUpdates() {
    _locationUpdatesRunning = false;
    _etaCheckTimer?.cancel();
    _etaCheckTimer = null;
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    locationUpdateTimer?.cancel();
    locationUpdateTimer = null;

    // Remove from RTDB immediately on stop
    try {
      final rtdbId = _driverDocId ?? user.uid;
      if (rtdbId.isNotEmpty) {
        FirebaseDatabase.instance.ref('driver_locations/$rtdbId').remove();
      }
    } catch (e) {
      debugPrint("Error removing driver location from RTDB: $e");
    }

    // NEW: Clear ride queue when going offline
    _rideQueueService.clearQueue(user.uid);
  }

  Future<void> listenForRideRequests() async {
    rideRequestSubscription?.cancel();
    rideRequestSubscription?.cancel();
    _revaluationTimer?.cancel();

    // Start periodic re-evaluation for ignored rides (cleanup only, not real-time)
    // The Firestore snapshots() listener handles real-time updates.
    // This timer only re-checks for rides whose ignore cooldown has expired.
    _revaluationTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_lastSnapshot != null) {
        _processSnapshot(_lastSnapshot!);
      }
    });

    debugPrint("DEBUG: listenForRideRequests called. Checking driver doc...");
    final driverDoc = await FirebaseFirestore.instance
        .collection('drivers')
        .doc(_driverDocId ?? user.uid)
        .get();
    if (!driverDoc.exists) {
      debugPrint(
        "DEBUG: Driver doc DOES NOT EXIST. Aborting listenForRideRequests.",
      );
      return;
    }
    debugPrint("DEBUG: Driver doc exists. Setting up query...");
    debugPrint("DEBUG: Querying ride_requests WHERE driverUid == '${user.uid}' AND status == 'searching'");

    // 2. Listener for All Searching Rides (Unassigned Area Broadcast)
    // Since automated assignment logic was removed from the backend, drivers must 
    // listen to all locally searching rides and filter by distance.
    Query query = FirebaseFirestore.instance
        .collection('ride_requests')
        .where('status', isEqualTo: 'searching')
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
        debugPrint("DEBUG: Received ride_requests snapshot with ${snapshot.docs.length} docs");
        _lastSnapshot = snapshot; // Cache it
        _processSnapshot(snapshot);
      },
      onError: (e) {
        debugPrint("CRITICAL: Error listening for rides: $e");
        if (e.toString().contains('failed-precondition') || e.toString().contains('index')) {
          Get.snackbar(
            "Database Index Missing",
            "Broadcasting query requires a new index. Please deploy firestore.indexes.json via Firebase CLI or check logs for the auto-generation link.",
            duration: const Duration(seconds: 15),
            backgroundColor: Colors.red,
            colorText: Colors.white,
            snackPosition: SnackPosition.TOP,
          );
          debugPrint("INDEX ERROR: To fix this, open the following link OR run 'firebase deploy --only firestore:indexes':");
          debugPrint(e.toString());
        }
      },
    );
  }

  int _getVehicleClassRank(String? className) {
    if (className == null) return 0;
    switch (className.toLowerCase()) {
      case 'suv':
        return 3;
      case 'sedan':
        return 2;
      case 'hatchback':
      case 'mini':
        return 1;
      default:
        return 0;
    }
  }

  bool _isCar(String? className) {
    if (className == null) return false;
    final normalized = className.toLowerCase();
    return normalized == 'suv' || normalized == 'sedan' || normalized == 'hatchback' || normalized == 'mini';
  }

  Future<void> _processSnapshot(QuerySnapshot snapshot) async {
    debugPrint("----------------------------------------------------------------");
    debugPrint("PROD [${DateTime.now().toIso8601String()}]: Processing Ride Snapshot - ${snapshot.docs.length} total ride(s)");

    for (var doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>?;

      // 1. Instant check against recently cleared rides
      if (_recentlyClearedRideIds.contains(doc.id)) {
        debugPrint("Ride ${doc.id} SKIPPED: Recently cleared");
        continue;
      }

      // 2. Instant check against persisted ignored rides (survives Get.offAll)
      if (_ignoredPersistentRides.contains(doc.id)) {
        debugPrint("Ride ${doc.id} SKIPPED: Persisted in ignored list");
        continue;
      }

      if (currentPosition.value == null) {
        debugPrint("Skipping ride check (Driver Location is NULL)");
        continue;
      }

      // Geo Filter (Radius Check) - e.g. 50km
      final pickupReq = data?['pickupLocation'];
      double? reqLat;
      double? reqLng;

      if (pickupReq is GeoPoint) {
        reqLat = pickupReq.latitude;
        reqLng = pickupReq.longitude;
      } else if (pickupReq is Map) {
        reqLat = (pickupReq['lat'] as num?)?.toDouble() ??
            (pickupReq['latitude'] as num?)?.toDouble();
        reqLng = (pickupReq['lng'] as num?)?.toDouble() ??
            (pickupReq['longitude'] as num?)?.toDouble();
      }

      if (reqLat != null && reqLng != null) {
        double dist = Geolocator.distanceBetween(
              currentPosition.value!.latitude,
              currentPosition.value!.longitude,
              reqLat,
              reqLng,
            ) /
            1000; // in km

        if (dist > 50) {
          debugPrint("Ride ${doc.id} SKIPPED: Too far (${dist.toStringAsFixed(1)}km > 50km)");
          continue;
        }
      }

      // Client-side matching logic
      final rideVehicleClass = data?['vehicleClass'];
      final rideVehicleType = data?['vehicleType'];

      if (!isActingDriver) {
        // Regular drivers shouldn't see Acting Driver rides
        if (rideVehicleType == 'ActingDriver' || rideVehicleClass == 'ActingDriver') {
          debugPrint("Ride ${doc.id} SKIPPED: ActingDriver filter");
          continue;
        }

        // Tier-based matching logic for Cars:
        // A driver can see any ride of their class OR any LOWER class (e.g. Sedan sees Hatchback).
        if (driverVehicleClass.isNotEmpty && rideVehicleClass != null) {
          final int driverRank = _getVehicleClassRank(driverVehicleClass.value);
          final int rideRank = _getVehicleClassRank(rideVehicleClass);

          // Only apply rank-based matching if both are Cars
          if (_isCar(driverVehicleClass.value) && _isCar(rideVehicleClass)) {
            if (driverRank < rideRank) {
              debugPrint("Ride ${doc.id} SKIPPED: Insufficient Vehicle Rank (Driver: ${driverVehicleClass.value}[$driverRank], Ride: $rideVehicleClass[$rideRank])");
              continue;
            }
          } else {
            // Non-car categories (Auto, Bike, etc.) still require exact match to prevent incorrect cross-category matching
            if (rideVehicleClass != driverVehicleClass.value) {
              debugPrint("Ride ${doc.id} SKIPPED: Category Mismatch (Driver: ${driverVehicleClass.value}, Ride: $rideVehicleClass)");
              continue;
            }
          }
        }
      }

      debugPrint("Ride ${doc.id} MATCH: Processing for local acceptance...");

      // If we already have this ride active locally, don't re-process
      if (activeRequests.any((r) => r.rideId == doc.id)) {
        continue;
      }

      // If this ride is already being processed asynchronously, skip duplicate work.
      if (_processingRideIds.contains(doc.id)) {
        continue;
      }

      // 2. In-memory temporary ignore cooldown
      if (_ignoredRides.containsKey(doc.id)) {
        final ignoredTime = _ignoredRides[doc.id]!;
        // Keep a local cooldown to prevent immediate bounce-back of the same request.
        if (DateTime.now().difference(ignoredTime).inSeconds < 6) {
          continue;
        } else {
          _ignoredRides.remove(doc.id); // Expired, allow processing again
        }
      }

      // Safety check: Don't process rides that are no longer searching
      final status = data?['status'];
      if (status != 'searching') {
        continue;
      }

      debugPrint("Found new assigned ride: ${doc.id}");
      // Manage activeRequests list
      _processingRideIds.add(doc.id);
      try {
        await _processRideDocument(doc, data!);
      } finally {
        _processingRideIds.remove(doc.id);
      }
    }
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
        .doc(_driverDocId ?? user.uid)
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
        .doc(_driverDocId ?? user.uid)
        .collection('wallet')
        .doc('balance')
        .snapshots()
        .listen(
          (snapshot) async {
            if (snapshot.exists) {
              walletBalance.value =
                  (snapshot.data()?['currentBalance'] as num? ?? 0.0)
                      .toDouble();
            } else {
              walletBalance.value = 0.0;
            }

            // Real-time offroading check
            if (walletBalance.value <= -300) {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('isWalletOffroaded', true);

              if (driverStatus.value == DriverStatus.online ||
                  driverStatus.value == DriverStatus.goTo) {
                // Kick offline
                handleStatusChange(DriverStatus.offline);
                Get.snackbar(
                  "Account Offroaded",
                  "Vehicle offroaded. Please recharge your wallet to go online.",
                  backgroundColor: Colors.red,
                  colorText: Colors.white,
                  duration: const Duration(seconds: 5),
                );
              }
            } else if (walletBalance.value >= -100) {
              // Clear the offroaded flag when they've recharged enough
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('isWalletOffroaded', false);
            }
          },
          onError: (e) {
            debugPrint("Error listening to wallet balance: $e");
          },
        );

    // Listen to driver document for subscription data
    walletSubscription = FirebaseFirestore.instance
        .collection('drivers')
        .doc(_driverDocId ?? user.uid)
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
        debugPrint("----------------------------------------------------------------");
        debugPrint(
          "PROD [${DateTime.now().toIso8601String()}]: Processing Rental Snapshot - ${snapshot.docs.length} total rental(s)",
        );

        if (snapshot.docs.isEmpty) {
          debugPrint("Rental Requests: No active rentals found.");
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
          }
          // Client-side matching logic
          final rideVehicleClass = data['vehicleClass'];
          final rideVehicleType = data['vehicleType'];

          if (!isActingDriver) {
            // Regular drivers shouldn't see Acting Driver rentals
            if (rideVehicleType == 'ActingDriver' || rideVehicleClass == 'ActingDriver') {
              continue;
            }

            // Broad matching: If driver has a class, only show rides for that class OR rides with no specified class
            if (driverVehicleClass.isNotEmpty && rideVehicleClass != null) {
              if (rideVehicleClass != driverVehicleClass.value) {
                debugPrint("Rental ${doc.id} SKIPPED: Vehicle Class Mismatch (Driver: ${driverVehicleClass.value}, Ride: $rideVehicleClass)");
                continue;
              }
            }
          }

          // Process the Rental Request
          // We treat it just like a normal ride doc, but we ensure 'rideType' is rental in adaptation
          // Since the schema differs slightly, _processRideDocument adapts it via our updated RideRequest.fromJson

          // IMPORTANT: Check if we are already busy
          if (activeRideRequest != null &&
              activeRideRequest!.rideId != doc.id) {
            debugPrint(
              "Skipping rental (Busy with ${activeRideRequest!.rideId})",
            );
            continue;
          }

          if (_processingRideIds.contains(doc.id)) {
            continue;
          }
          _processingRideIds.add(doc.id);
          try {
            await _processRideDocument(doc, data);
          } finally {
            _processingRideIds.remove(doc.id);
          }
          // If we processed one, we break (one active request at a time)
          // Unless we want to show a list? Current UI supports single activeRideRequest.
          if (activeRideRequest != null) {
            break;
          }
        }
      },
      onError: (e) {
        debugPrint("CRITICAL: Error listening for rentals: $e");
        if (e.toString().contains('failed-precondition') || e.toString().contains('index')) {
          Get.snackbar(
            "Rental Index Missing",
            "Broadcast rental query requires a new index in indicabs-prod. Please deploy firestore.indexes.json.",
            duration: const Duration(seconds: 15),
            backgroundColor: Colors.red,
            colorText: Colors.white,
            snackPosition: SnackPosition.TOP,
          );
          debugPrint("INDEX ERROR (RENTAL): To fix this, open the following link OR run 'firebase deploy --only firestore:indexes -P prod':");
          debugPrint(e.toString());
        }
      },
    );
  }

  Future<void> _processRideDocument(
    DocumentSnapshot doc,
    Map<String, dynamic> data,
  ) async {
    debugPrint("Processing Ride Document: ${doc.id}");

    if (activeRequests.any((r) => r.rideId == doc.id)) {
      debugPrint("Process Ride: ${doc.id} already active. Skipping.");
      return;
    }

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
    double driverDist = 0.0;
    double rideDist = (data['rideDistance'] ?? data['totalDistance'] ?? data['distance'] ?? 0.0).toDouble();

    // 1. Optimized Driver-to-Pickup Distance
    // We use straight-line distance initially to prevent UI delay, or await if data is missing
    if (currentPosition.value != null) {
      if (data.containsKey('driverDistance') && data['driverDistance'] != null) {
        driverDist = (data['driverDistance'] as num).toDouble();
      } else {
        // Use fast Haversine distance for instant response
        driverDist = Geolocator.distanceBetween(
          currentPosition.value!.latitude,
          currentPosition.value!.longitude,
          pickupLocation.latitude,
          pickupLocation.longitude,
        ) / 1000;
        
        // Optionally update with road distance asynchronously (not blocking)
        getRouteDetails(currentPosition.value!, pickupLocation).then((details) {
          if (details != null && details['distance'] != null) {
            final double roadDist = (details['distance'] as num).toDouble();
            final existing = activeRequests.firstWhereOrNull((r) => r.rideId == doc.id);
            if (existing != null) {
              final idx = activeRequests.indexOf(existing);
              activeRequests[idx] = existing.copyWith(driverDistance: roadDist);
              activeRequests.refresh();
            }
          }
        });
      }
    }

    // 2. Optimized Ride Distance (Pickup to Dropoff)
    // Only calculate if not provided by User app
    if (rideDist == 0 && destinationLocation != null) {
      final rideRouteDetails = await getRouteDetails(
        pickupLocation,
        finalDestination,
      );
      rideDist = (rideRouteDetails?['distance'] ?? 0.0).toDouble();
    }

    debugPrint(
      "Route Details Prepared. DriverDist: $driverDist, RideDist: $rideDist",
    );

    final String? dataPickup = data['pickupAddress'];
    final String? dataDropoff = data['destinationAddress'] ?? data['dropoffAddress'];

    String pickupFull = dataPickup ?? 'Unknown Location';
    String pickupTitle = data['pickupPlaceName'] ?? 
                        data['pickupTitle'] ?? 
                        (dataPickup != null ? RideRequest.extractTitle(dataPickup) : 'Unknown Area');

    String dropoffFull = dataDropoff ?? (destinationLocation != null ? 'Dropoff Location' : 'Package Ride');
    String dropoffTitle = data['destinationPlaceName'] ?? 
                         data['dropoffPlaceName'] ?? 
                         data['dropoffTitle'] ??
                         (dataDropoff != null ? RideRequest.extractTitle(dataDropoff) : (destinationLocation != null ? 'Dropoff' : 'Rental'));

    // Only geocode IF addresses are missing from Firestore
    if (dataPickup == null) {
      final pickupDetails = await getParsedAddressFromLatLng(pickupLocation);
      pickupFull = pickupDetails['fullAddress'] ?? pickupFull;
      pickupTitle = pickupDetails['area'] ?? pickupTitle;
    }

    if (dataDropoff == null && destinationLocation != null) {
      final dropoffDetails = await getParsedAddressFromLatLng(finalDestination);
      dropoffFull = dropoffDetails['fullAddress'] ?? dropoffFull;
      dropoffTitle = dropoffDetails['area'] ?? dropoffTitle;
    }

    // Extract common fields
    final rideId = doc.id;
    final userId = data['userId'];
    final userName = data['userName'];
    final rideType = data['rideType'] ?? 'ride'; // Default to 'ride'
    final driverDistance = driverDist;
    final rideDistance = rideDist;

    try {
      final paymentMethod = data['paymentMethod'] ?? 'Cash';
      final status = data['status'] ?? 'searching';
      final vehicleClass = data['vehicleClass'] ?? 'Unknown';
      var stops = data['stops'] ?? data['intermediateStops'];

      // Parse Toll Price
      double? tollPrice;
      if (data.containsKey('tollPrice')) {
        tollPrice = (data['tollPrice'] as num?)?.toDouble();
      }

      // If no toll from server, calculate using geofenced zones
      if (tollPrice == null || tollPrice == 0.0) {
        tollPrice = calculateToll(pickupLocation);
      }

      final double? surge = (data['surgeMultiplier'] as num?)?.toDouble();

      // Create RideRequest object
      RideRequest newRequest = RideRequest(
        rideId: rideId,
        userId: userId,
        userName: userName,
        surgeMultiplier: surge,
        pickupTitle: pickupTitle,
        dropoffTitle: dropoffTitle,
        pickupFullAddress: pickupFull,
        dropoffFullAddress: dropoffFull,
        driverDistance: driverDistance,
        rideDistance: rideDistance,
        rideFare: (data['totalFare'] ?? data['fare'] ?? data['rideFare'] ?? 0)
            .toDouble(),
        tip: (data['tip'] as num?)?.toDouble(),
        vehicleType: data['vehicleType'] ?? data['vehicleClass'] ?? 'Unknown',
        pickupLocation: pickupLocation,
        dropoffLocation: finalDestination,
        rideType: rideType,
        stops: (stops != null && stops is List)
            ? stops.map<RideStop>((s) {
                return RideStop(
                  title: s['address']?.split(',')[0] ?? 'Stop',
                  fullAddress: s['address'] ?? '',
                  location: LatLng(
                    (s['latitude'] as num?)?.toDouble() ?? 0.0,
                    (s['longitude'] as num?)?.toDouble() ?? 0.0,
                  ),
                  status: s['status'] ?? 'pending',
                );
              }).toList()
            : [],
        driverId: data['driverId'],
        packageName: data['packageName'],
        durationHours: data['durationHours'],
        kmLimit: data['kmLimit'],
        extraHourCharge: data['extraHourCharge'],
        extraKmCharge: data['extraKmCharge'],
        driverDuration: (data['driverDuration'] as num?)?.toDouble(),
        rideDuration: (data['estimatedDurationSeconds'] != null && data['estimatedDurationSeconds'] is num)
            ? ((data['estimatedDurationSeconds'] as num).toDouble() / 60)
            : null,
        convenienceFee: (data['convenienceFee'] as num?)?.toDouble() ?? 0.0,
        safetyPin: data['startRidePin'] ?? data['safetyPin'] ?? '',
        paymentMethod: paymentMethod,
        status: status,
        vehicleClass: vehicleClass,
        endRidePin: data['endRidePin'] ?? '',
        startedAt: (data['startedAt'] != null)
            ? (data['startedAt'] as Timestamp).toDate()
            : null,
        createdAt: (data['createdAt'] != null)
            ? (data['createdAt'] is Timestamp
                  ? (data['createdAt'] as Timestamp).toDate()
                  : null)
            : null,
        actualDistance: (data['actualDistance'] as num?)?.toDouble(),
        actualDuration: (data['actualDuration'] as num?)?.toDouble(),
        waitingCharge: (data['waitingCharge'] as num?)?.toDouble() ?? 0.0,
        paidByWallet:
            (data['paidByWallet'] as num?)?.toDouble() ??
            (data['walletAmountUsed'] as num?)?.toDouble(),
        tollPrice: tollPrice,
      );


      if (activeRequests.any((r) => r.rideId == newRequest.rideId)) {
        debugPrint("Process Ride: ${newRequest.rideId} duplicate add skipped.");
        return;
      }

      activeRequests.add(newRequest);
      _listenToRideStatus(
        newRequest.rideId,
        newRequest.rideType,
      ); // Start monitoring
      _applySort();
      hasActiveRide.value = true;

      // Trigger Overlay if Backgrounded
      if (_appLifecycleState == AppLifecycleState.paused) {
        _showOverlayForRide(newRequest);
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
            onAccept: () => onRideAccepted(newRequest),
            onPass: () => onRideRejected("rental_screen_pass"),
          ),
          routeName: '/RentalRequestScreen',
        );
      } else {
        // Play sound for new ride requests
        // GUARD: If we are already accepting, DO NOT play sound again
        if (!_isAcceptingRide) {
          playRideRequestSound();
        }
      }
      startRideTimeout(newRequest.rideId);
    } catch (e) {
      debugPrint("Error processing ride document $rideId: $e");
    }
  }

  // Removed Mock Rental Trigger
  // logic moved to listenForRentalRequests

  void triggerMockActingDriverRequest() {
    final mockId = "mock_acting_${DateTime.now().millisecondsSinceEpoch}";
    final pickupLocation = LatLng(12.931115, 80.217510);

    activeRequests.add(
      RideRequest(
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
      ),
    );

    _applySort();

    playRentalNotification();
    Get.to(
      () => RentalRequestScreen(
        rideRequest: activeRideRequest!,
        onAccept: () => onRideAccepted(activeRideRequest!),
        onPass: () => onRideRejected("mock_acting_pass"),
      ),
      routeName: '/RentalRequestScreen',
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
          'duration': (route.durationMinutes as num?)?.toDouble() ?? 0.0,
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

    // 1. Daily Rides Stream — use driverUid (auth UID), not driverId (professional ID)
    earningsSubscription = FirebaseFirestore.instance
        .collection('ride_requests')
        .where('driverUid', isEqualTo: user.uid)
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

    // 2. Rental Rides Stream — use driverUid (auth UID), not driverId (professional ID)
    rentalEarningsSubscriptionLocal = FirebaseFirestore.instance
        .collection('rental_requests')
        .where('driverUid', isEqualTo: user.uid)
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

  Future<void> _configureAudioSession() async {
    try {
      await audioPlayer.setAudioContext(
        AudioContext(
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playAndRecord,
            options: {
              AVAudioSessionOptions.defaultToSpeaker,
              AVAudioSessionOptions.mixWithOthers,
            },
          ),
          android: AudioContextAndroid(
            isSpeakerphoneOn: true,
            stayAwake: true,
            usageType: AndroidUsageType.alarm,
            contentType: AndroidContentType.music,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          ),
        ),
      );
      debugPrint("Audio Session Configured for Background Playback");
    } catch (e) {
      debugPrint("Error configuring audio session: $e");
    }
  }

  Future<void> playRideRequestSound() async {
    if (isClosed || _isAcceptingRide) {
      return; // Guard against playing during acceptance
    }
    try {
      debugPrint("Attempting to play sound...");

      // Ensure Audio Context is active
      await _configureAudioSession();

      try {
        originalVolume = await volumeController.getVolume();
        volumeController.showSystemUI = false;
        await volumeController.setVolume(1.0);
      } catch (e) {
        debugPrint("Error setting volume: $e");
      }

      // Reset player if needed
      await audioPlayer.stop(); // Safe to call even if stopped

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
    await Future.delayed(const Duration(milliseconds: 100));

    while (_isRentalRinging) {
      if (isClosed) break;

      // 1. Play TTS
      try {
        try {
          if (audioPlayer.state == PlayerState.playing) {
            await audioPlayer.stop(); // Ensure sound is stopped
          }
        } catch (e) {
          debugPrint("Error stopping audio (TTS loop): $e");
        }

        String speechText = "Rental Request";
        if (activeRideRequest?.vehicleType == "ActingDriver") {
          speechText = "Acting Driver Request";
        }

        await flutterTts.speak(speechText);

        // Manual delay to ensure TTS finishes before sound starts
        // "Acting Driver Request" is slightly longer, so 2s is good safe buffer
        await Future.delayed(const Duration(milliseconds: 500));
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
    if (_isStoppingRideSound) return;
    _isStoppingRideSound = true;
    _isRentalRinging = false;
    // Do not check isClosed here, we want to stop sound regardless of controller state

    debugPrint("Stopping Audio and Vibration...");

    try {
      // 1. Stop Audio
      try {
        await audioPlayer
            .stop(); // Just call stop, it handles state internally or throws specific errors we can catch
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
    } finally {
      _isStoppingRideSound = false;
    }
  }

  bool _isAcceptingRide = false;

  Future<void> onRideAccepted(RideRequest request) async {
    debugPrint("onRideAccepted: Closing Overlay immediately");
    FlutterOverlayWindow.closeOverlay();
    
    _lastOverlayActionTime = DateTime.now();
    _isAcceptingRide = true;
    isRideAcceptanceInProgress.value = true;
    stopRideRequestSound();

    // Dismiss all pending overlays immediately
    OverlayService.instance.clearRideQueue();
    OverlayService.instance.hideFloatingBubble();
    activeRequests.clear();

    // Persist this ride ID to ignored_rides so it doesn't ghost-appear
    // after Get.offAll recreates the controller
    _persistIgnoredRide(request.rideId);
    _ignoredRides[request.rideId] = DateTime.now();

    for (var timer in rideTimers.values) {
      timer.cancel();
    }
    rideTimers.clear();

    // Cancel all active ride subscriptions
    for (var sub in _activeRideSubscriptions.values) {
      sub.cancel();
    }
    _activeRideSubscriptions.clear();

    // --- Subscription Auto-Activation Check ---
    // Activates a free 1-day trial only when driver accepts a ride with no active plan.
    // Uses _driverDocId (professional ID) so drivers with indi-drv-X docs are read correctly.
    try {
      final docId = _driverDocId ?? user.uid;
      final driverDoc = await FirebaseFirestore.instance
          .collection('drivers')
          .doc(docId)
          .get();
      DateTime? expiry;
      String? queuedPlan;
      if (driverDoc.exists) {
        final data = driverDoc.data()!;
        if (data.containsKey('subscriptionExpiry')) {
          final val = data['subscriptionExpiry'];
          if (val is Timestamp) expiry = val.toDate();
        }
        queuedPlan = data['queuedPlanName'] as String?;
      }

      final bool hasActivePlan = expiry != null && expiry.isAfter(DateTime.now());
      final bool hasQueuedPlan = queuedPlan != null && queuedPlan.isNotEmpty;

      // Only auto-activate if no active plan AND no plan already queued.
      // This prevents the free trial from being stacked on top of paid queued plans.
      if (!hasActivePlan && !hasQueuedPlan) {
        debugPrint("[Sub] No active plan and no queued plan. Auto-activating free trial on ride acceptance.");
        if (Get.isRegistered<WalletController>()) {
          await Get.find<WalletController>().activateFreeTrialPlan(
            "1 Day Auto (Trial)",
            1,
          );
        }
      } else {
        debugPrint("[Sub] Skipping auto-activation. hasActivePlan=$hasActivePlan, hasQueuedPlan=$hasQueuedPlan");
      }
    } catch (e) {
      debugPrint("[Sub] Subscription Check Error: $e");
    }

    try {
      final rideId = request.rideId;
      final driverId = _driverDocId ?? user.uid; // Professional ID
      final driverUid = user.uid; // Auth UID
      final rideType = request.rideType;

      final collectionPath = (rideType == 'rental')
          ? 'rental_requests'
          : 'ride_requests';

      debugPrint("Accepting Ride $rideId in $collectionPath");

      // 0. Fetch Driver Details First
      final driverDocSnapshot = await FirebaseFirestore.instance
          .collection('drivers')
          .doc(driverId) // Correct Professional ID
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
          throw Exception("Ride document does not exist");
        }

        final status = rideDoc.data()?['status'];
        if (status != 'searching') {
          throw Exception("Ride is no longer available (Status: $status)");
        }

        transaction.update(rideRef, {
          'status': 'accepted',
          'driverId': driverId,
          'driverUid': driverUid, // For security rules and future status updates
          'driverName': dName,
          'driverPhone': dPhone,
          'driverPhoto': dPhoto,
          'vehicleNumber': dCarNumber,
          'vehicleModel': dCarModel,
          'otp': '1234',
          'acceptedAt': FieldValue.serverTimestamp(),
        });
      });

      // 2. Set Driver Status to Online locally (so they return to duty after ride)
      driverStatus.value = DriverStatus.online;
      handleStatusChange(DriverStatus.online);

      // Preserve ONLY the accepted ride so we don't re-process it
      activeRequests.removeWhere((r) => r.rideId != rideId);
      if (!activeRequests.any((r) => r.rideId == rideId)) {
        activeRequests.add(request);
      }

      _isAcceptingRide = false;
      isRideAcceptanceInProgress.value = false;

      Get.offAll(() => RideAcceptedScreen(rideRequest: request));
    } catch (e) {
      if (e.toString().contains("Ride is no longer available")) {
        // Check if THIS driver actually accepted it (double-tap / race condition)
        try {
          final rideDoc = await FirebaseFirestore.instance
              .collection(request.rideType == 'rental' ? 'rental_requests' : 'ride_requests')
              .doc(request.rideId)
              .get();
          final rideData = rideDoc.data();
          final acceptedDriverUid = rideData?['driverUid'];
          final acceptedStatus = rideData?['status'];

          if (acceptedStatus == 'accepted' && acceptedDriverUid == user.uid) {
            // This driver already accepted it — navigate to ride screen
            debugPrint("Accept: Ride already accepted by this driver. Navigating...");
            OverlayService.instance.clearRideQueue();
            handleStatusChange(DriverStatus.online);
            _isAcceptingRide = false;
            isRideAcceptanceInProgress.value = false;
            Get.offAll(() => RideAcceptedScreen(rideRequest: request));
            return;
          }
        } catch (_) {}

        Get.snackbar(
          "Ride Missed",
          "Ride accepted by another driver",
          backgroundColor: Colors.redAccent,
          colorText: Colors.white,
          duration: const Duration(seconds: 4),
        );
      } else {
        Get.snackbar("Error", "Could not accept ride: $e");
      }
      debugPrint("Accept Error: $e");
      _isAcceptingRide = false;
      isRideAcceptanceInProgress.value = false;
    }
  }

  void ignoreRide(String rideId) {
    _ignoredRides[rideId] = DateTime.now();
    activeRequests.removeWhere((r) => r.rideId == rideId);
    _persistIgnoredRide(rideId);
  }

  Future<void> _persistIgnoredRide(String rideId) async {
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      _prefs ??= prefs;

      List<String> ignoredList = prefs.getStringList('ignored_rides') ?? [];
      if (!ignoredList.contains(rideId)) {
        ignoredList.add(rideId);
        // Keep list size manageable
        if (ignoredList.length > 50) {
          ignoredList = ignoredList.sublist(ignoredList.length - 50);
        }
        await prefs.setStringList('ignored_rides', ignoredList);
        _ignoredPersistentRides.assignAll(ignoredList);
        debugPrint("HomePageController: Persisted ignored ride $rideId. Total: ${ignoredList.length}");
      }
    } catch (e) {
      debugPrint("Error persisting ignored ride: $e");
    }
  }

  void removeIgnoredRide(String rideId) {
    _ignoredRides.remove(rideId);
    _removePersistedIgnoredRide(rideId);
  }

  Future<void> _removePersistedIgnoredRide(String rideId) async {
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      _prefs ??= prefs;

      List<String> ignoredList = prefs.getStringList('ignored_rides') ?? [];
      if (ignoredList.contains(rideId)) {
        ignoredList.remove(rideId);
        await prefs.setStringList('ignored_rides', ignoredList);
        _ignoredPersistentRides.assignAll(ignoredList);
        debugPrint("HomePageController: Removed $rideId from persisted ignored list.");
      }
    } catch (e) {
      debugPrint("Error removing persisted ignored ride: $e");
    }
  }

  Future<void> onRideRejected(String reason) async {
    // Determine which ride to reject. Default to top active.
    // If specific ID is needed, use passRide(id) instead.
    // This method handles the logic of "User clicked Reject on current/top card" or overlay.

    stopRideRequestSound();
    if (activeRideRequest == null) return;

    final rideId = activeRideRequest!.rideId;

    // Use passRide logic but also send server rejection?
    // Actually, passRide is just local skip. "Reject" usually means "I don't want this specific ride ever".
    // Server rejection: add to 'rejectedBy'.

    debugPrint("Rejecting Ride $rideId (Reason: $reason)");
    passRide(rideId);

    // Also update server to avoid getting it again
    try {
      final rideType = activeRideRequest?.rideType ?? 'daily';
      final collectionPath = (rideType == 'rental')
          ? 'rental_requests'
          : 'ride_requests';
      await FirebaseFirestore.instance
          .collection(collectionPath)
          .doc(rideId)
          .update({
            'rejectedBy': FieldValue.arrayUnion([user.uid]),
          });
    } catch (e) {
      debugPrint("Error sending rejection to server: $e");
    }
  }

  void startRideTimeout(String rideId) {
    rideTimers[rideId]?.cancel();

    final isRental = activeRideRequest?.rideType == 'rental';

    int timeoutDuration = 20; // Default max duration

    debugPrint("Starting Ride Timeout for $rideId: $timeoutDuration seconds");

    rideTimers[rideId] = Timer(Duration(seconds: timeoutDuration), () async {
      // Only clear if still pointing to the same ride or in list
      if (activeRequests.any((r) => r.rideId == rideId)) {
        stopRideRequestSound();

        if (isRental) {
          Get.back(); // Close Rental Screen
        }

        debugPrint('Triggering local timeout for ride $rideId');

        // REJECT on timeout to pass to next driver (Round Robin)
        // For list view, we just pass this specific ride
        passRide(rideId);

        debugPrint("Local timeout triggered. Rejection sent.");
      }
    });
  }

  // -------------------------
  // Overlay Helper
  // -------------------------

  // NOTE: Overlay methods moved below to avoid duplicates.

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

  void showStatusBubble() {
    final now = DateTime.now();
    _lastBubbleShowTime = now;

    // GUARD: Never show anything while mid-acceptance flow.
    if (_isAcceptingRide) {
      debugPrint("showStatusBubble: Skip (isAcceptingRide=true)");
      return;
    }

    // LOCKDOWN GUARD: After accept/reject/clear, show bubble only (never the
    // ride card) to prevent ghost card overlays during app transitions.
    if (_lastOverlayActionTime != null &&
        now.difference(_lastOverlayActionTime!).inMilliseconds < 3000) {
      debugPrint("showStatusBubble: Lockdown active - bubble only");
      if (driverStatus.value == DriverStatus.online ||
          driverStatus.value == DriverStatus.goTo) {
        OverlayService.instance.showFloatingBubble();
      }
      return;
    }

    // Show ride-request card when online with pending requests; otherwise just
    // show the small bubble so the driver can tap back into the app.
    if (activeRequests.isNotEmpty && driverStatus.value == DriverStatus.online) {
      _showOverlayForRide(activeRequests.first);
    } else if (driverStatus.value == DriverStatus.online ||
        driverStatus.value == DriverStatus.goTo) {
      OverlayService.instance.showFloatingBubble();
    }
    // offline: show nothing
  }

  void hideFloatingBubble() {
    OverlayService.instance.hideFloatingBubble();
  }

  final RxList<Map<String, dynamic>> _tollZones = <Map<String, dynamic>>[].obs;

  Future<void> _fetchTollZones() async {
    try {
      final snapshot =
          await FirebaseFirestore.instance.collection('geofenced_zones').get();
      _tollZones.assignAll(
        snapshot.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList(),
      );
      debugPrint("Fetched ${_tollZones.length} toll zones.");
    } catch (e) {
      debugPrint("Error fetching toll zones: $e");
    }
  }

  double calculateToll(LatLng point) {
    for (var zone in _tollZones) {
      final boundary = zone['boundary'] as List<dynamic>?;
      final surcharge = (zone['surcharge_amount'] as num?)?.toDouble() ?? 0.0;

      if (boundary != null && boundary.isNotEmpty && surcharge > 0) {
        final List<LatLng> polygon = boundary.map((p) {
          if (p is GeoPoint) return LatLng(p.latitude, p.longitude);
          if (p is Map) {
            final lat = (p['latitude'] as num?)?.toDouble() ??
                (p['lat'] as num?)?.toDouble();
            final lng = (p['longitude'] as num?)?.toDouble() ??
                (p['lng'] as num?)?.toDouble();
            if (lat != null && lng != null) {
              return LatLng(lat, lng);
            }
          }
          return const LatLng(0, 0);
        }).toList();

        if (_isPointInPolygon(point, polygon)) {
          debugPrint("Point in toll zone: ${zone['id']} (+₹$surcharge)");
          return surcharge;
        }
      }
    }
    return 0.0;
  }

  bool _isPointInPolygon(LatLng point, List<LatLng> polygon) {
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;
    debugPrint("App Lifecycle Changed: $state");

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.inactive) {
      // GUARD: Avoid triggering overlay if we are in the middle of accepting a ride
      if (_isAcceptingRide) {
        debugPrint("didChangeAppLifecycleState: Skip bubble (isAcceptingRide=true)");
        return;
      }

      if (driverStatus.value == DriverStatus.online ||
          driverStatus.value == DriverStatus.goTo) {
        showStatusBubble();
      }
    } else if (state == AppLifecycleState.resumed) {
      final now = DateTime.now();
      final diff = _lastBubbleShowTime == null
          ? 1001
          : now.difference(_lastBubbleShowTime!).inMilliseconds;

      if (activeRequests.isEmpty) {
        if (diff > 1000) {
          OverlayService.instance.hideFloatingBubble();
        } else {
          // Schedule a delayed hide to catch the end of the transition guard
          Future.delayed(Duration(milliseconds: 1050 - diff), () {
            if (_appLifecycleState == AppLifecycleState.resumed &&
                activeRequests.isEmpty) {
              OverlayService.instance.hideFloatingBubble();
            }
          });
        }
      }
    }
  }

  bool get shouldShowOverlayBubble {
    return (driverStatus.value == DriverStatus.online ||
            driverStatus.value == DriverStatus.goTo) &&
        _appLifecycleState != AppLifecycleState.resumed;
  }

  // ------------------------------------------------------------------
}
