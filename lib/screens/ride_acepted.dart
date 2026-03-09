// ignore_for_file: unused_field

import 'dart:async';
import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:project_taxi_driver_app/screens/homepage.dart';
import 'package:project_taxi_driver_app/widgets/ride_request.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:project_taxi_driver_app/widgets/ride_status_slider.dart';

import 'package:project_taxi_driver_app/screens/chat_screen.dart';
import 'package:project_taxi_driver_app/screens/navigation_screen.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart'
    as nav;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:project_taxi_driver_app/screens/ride_start_otp_screen.dart';

class RideAcceptedScreen extends StatefulWidget {
  final RideRequest rideRequest;

  const RideAcceptedScreen({super.key, required this.rideRequest});

  @override
  State<RideAcceptedScreen> createState() => _RideAcceptedScreenState();
}

class _RideAcceptedScreenState extends State<RideAcceptedScreen> {
  String get collectionPath => widget.rideRequest.rideType == 'rental'
      ? 'rental_requests'
      : 'ride_requests';

  final Completer<GoogleMapController> _controller = Completer();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Ride State
  String _rideStatus = 'accepted'; // accepted, arrived, started, completed
  bool _isLoading = false;
  String _otp = ''; // Will be loaded from Firestore

  String _customerName = 'Customer';
  String _customerPhone = '';

  // Timer & Billing
  Timer? _timer;
  int _elapsedSeconds = 0;
  double _waitingCharge = 0.0;

  // Chat Notifications
  int _unreadMessages = 0;
  StreamSubscription<QuerySnapshot>? _messagesSubscription;
  String? _lastMessageId;

  // Location & Map
  LatLng? _driverLocation;
  LatLng? _pickupLocation;
  LatLng? _dropLocation;
  LatLng? _userLocation; // User's live location
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  StreamSubscription<Position>? _positionStream;
  final List<LatLng> _polylineCoordinates = [];
  late PolylinePoints polylinePoints;
  BitmapDescriptor? _humanMarkerIcon;

  // Translations
  String _selectedLanguageCode = 'en';
  String? _translatedPickupTitle;
  String? _translatedPickupAddress;
  String? _translatedDropoffTitle;
  String? _translatedDropoffAddress;
  final bool _isTranslatingAddresses = true;

  // Wakelock Timer
  Timer? _wakelockTimer;

  // TTS
  final FlutterTts flutterTts = FlutterTts();

  @override
  void initState() {
    super.initState();
    _loadLanguage();
    if (widget.rideRequest.userName != null &&
        widget.rideRequest.userName!.isNotEmpty) {
      _customerName = widget.rideRequest.userName!;
    }
    _enableWakelock(); // Keep screen on
    _loadMarkerIcons();
    _initializeRide();
    _fetchCustomerDetails();
    _listenToMessages();
  }

  Future<void> _loadMarkerIcons() async {
    try {
      final icon = await _createMarkerImageFromIcon(Icons.person, Colors.blue);
      setState(() {
        _humanMarkerIcon = icon;
        // Refresh markers if user location already exists
        if (_userLocation != null) {
          _updateMarkers();
        }
      });
    } catch (e) {
      debugPrint("Error loading marker icon: $e");
    }
  }

  Future<BitmapDescriptor> _createMarkerImageFromIcon(
    IconData icon,
    Color color,
  ) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    final Paint paint = Paint()..color = color;
    const double size = 50.0; // Icon size

    // Draw Circle Background
    canvas.drawCircle(const Offset(size / 2, size / 2), size / 2, paint);

    // Draw Icon
    final TextPainter textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );
    textPainter.text = TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: size * 0.7,
        fontFamily: icon.fontFamily,
        color: Colors.white,
      ),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset((size - textPainter.width) / 2, (size - textPainter.height) / 2),
    );

    final ui.Image image = await pictureRecorder.endRecording().toImage(
      size.toInt(),
      size.toInt(),
    );
    final ByteData? data = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    return BitmapDescriptor.bytes(data!.buffer.asUint8List());
  }

  void _enableWakelock() {
    WakelockPlus.enable();
    // Re-enable periodically to handle race conditions
    _wakelockTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      WakelockPlus.enable();
    });
  }

  void _listenToMessages() {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    _messagesSubscription = _firestore
        .collection(collectionPath)
        .doc(widget.rideRequest.rideId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .listen((snapshot) {
          if (snapshot.docs.isNotEmpty) {
            final doc = snapshot.docs.first;
            final data = doc.data();
            final senderId = data['senderId'];
            final messageId = doc.id;

            if (senderId != currentUserId && messageId != _lastMessageId) {
              // New message from user
              if (_lastMessageId != null) {
                // Only notify if this is not the initial load
                if (mounted) {
                  setState(() {
                    _unreadMessages++;
                  });
                  Get.snackbar(
                    'New Message',
                    data['text'] ?? 'You have a new message',
                    backgroundColor: Colors.black87,
                    colorText: Colors.white,
                    snackPosition: SnackPosition.TOP,
                    duration: const Duration(seconds: 3),
                    onTap: (_) {
                      _openChat();
                    },
                  );
                }
              }
              _lastMessageId = messageId;
            } else {
              _lastMessageId ??= messageId;
            }
          }
        });
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _elapsedSeconds++;
          if (_elapsedSeconds > 180) {
            // Charge ₹5 for every minute (or part of it) after 3 mins
            int extraMinutes = ((_elapsedSeconds - 180) / 60).ceil();
            _waitingCharge = extraMinutes * 5.0;
          }
        });
      }
    });
  }

  void _openChat() {
    setState(() {
      _unreadMessages = 0;
    });
    Get.to(
      () => ChatScreen(
        rideId: widget.rideRequest.rideId,
        currentUserId: FirebaseAuth.instance.currentUser!.uid,
        otherUserName: _customerName,
      ),
    );
  }

  Future<void> _fetchCustomerDetails() async {
    try {
      DocumentSnapshot userDoc = await _firestore
          .collection('users')
          .doc(widget.rideRequest.userId)
          .get();

      if (userDoc.exists) {
        final data = userDoc.data() as Map<String, dynamic>;
        debugPrint("Accepted Screen Customer Data: $data");
        setState(() {
          final fName = data['firstName'] as String? ?? '';
          final lName = data['lastName'] as String? ?? '';
          String fullName = '$fName $lName'.trim();

          if (fullName.isEmpty) {
            // Only fallback if we don't have a name yet
            if (_customerName == 'Customer') {
              fullName =
                  widget.rideRequest.userName ??
                  data['userName'] ??
                  data['name'] ??
                  'Customer';
            } else {
              fullName = _customerName;
            }
          }
          _customerName = fullName;
          _customerPhone = data['phoneNumber'] ?? '';
          debugPrint("Final Accepted Customer Name: $_customerName");
        });
      } else {
        debugPrint("User doc ${widget.rideRequest.userId} not found.");
      }
    } catch (e) {
      debugPrint("Error fetching customer details: $e");
    }
  }

  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _selectedLanguageCode = prefs.getString('selectedLanguage') ?? 'en';
      });
      Get.updateLocale(Locale(_selectedLanguageCode));
      _playAcceptedTts();
    }
  }

  Future<void> _playAcceptedTts() async {
    try {
      String speechLanguage = _selectedLanguageCode == 'en'
          ? 'en-IN'
          : '$_selectedLanguageCode-IN';
      await flutterTts.setLanguage(speechLanguage);
      await flutterTts.speak(_getTranslatedString('rideAcceptedTts'));
    } catch (e) {
      debugPrint("Error playing TTS: $e");
    }
  }

  String _getTranslatedString(String key) {
    return key.tr;
  }

  void _initializeRide() {
    _rideStatus = 'accepted';

    _pickupLocation = widget.rideRequest.pickupLocation;
    _dropLocation = widget.rideRequest.dropoffLocation;

    // Initialize PolylinePoints with API Key
    polylinePoints = PolylinePoints(apiKey: dotenv.env['GOOGLE_MAPS_API_KEY']!);

    _getCurrentLocation();
    _startLocationUpdates();

    // Initial route to pickup
    _getCurrentLocation().then((_) {
      if (_driverLocation != null) {
        _getPolyline(_driverLocation!, _pickupLocation!);
      }
    });

    // Listen to safetyPin (OTP) and User Live Location from Firestore
    _firestore
        .collection(collectionPath)
        .doc(widget.rideRequest.rideId)
        .snapshots()
        .listen((snapshot) {
          if (snapshot.exists && mounted) {
            final data = snapshot.data();
            if (data != null) {
              // 1. Check for Safety Pin
              if (data.containsKey('safetyPin')) {
                setState(() {
                  _otp = data['safetyPin'].toString();
                });
              }

              // 2. Check for User Live Location
              if (data.containsKey('userLocation')) {
                debugPrint(
                  "RideAccepted: User Location Data: ${data['userLocation']}",
                );
                try {
                  final userLoc = data['userLocation'];
                  double? lat;
                  double? lng;

                  if (userLoc is Map) {
                    lat = (userLoc['latitude'] as num?)?.toDouble();
                    lng = (userLoc['longitude'] as num?)?.toDouble();
                  } else if (userLoc is GeoPoint) {
                    // Fallback just in case
                    lat = userLoc.latitude;
                    lng = userLoc.longitude;
                  }

                  if (lat != null && lng != null) {
                    setState(() {
                      _userLocation = LatLng(lat!, lng!);
                      _updateMarkers();
                    });
                  }
                } catch (e) {
                  debugPrint("Error parsing userLocation: $e");
                }
              }
            }
          }
        });
  }

  @override
  void dispose() {
    flutterTts.stop();
    _positionStream?.cancel();
    _timer?.cancel();
    _messagesSubscription?.cancel();
    _wakelockTimer?.cancel();
    // WakelockPlus.disable(); // Handled globally/by home
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (mounted) {
        setState(() {
          _driverLocation = LatLng(position.latitude, position.longitude);
          _updateMarkers();
        });
        _moveCamera(_driverLocation!);
      }
    } catch (e) {
      debugPrint("Error getting location: $e");
    }
  }

  void _startLocationUpdates() {
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );
    _positionStream =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (Position position) {
            if (mounted) {
              setState(() {
                _driverLocation = LatLng(position.latitude, position.longitude);
                _updateMarkers();
              });
            }
          },
        );
  }

  void _updateMarkers() {
    _markers.clear();

    if (_rideStatus == 'accepted' || _rideStatus == 'arrived') {
      if (_pickupLocation != null) {
        _markers.add(
          Marker(
            markerId: const MarkerId('pickup'),
            position: _pickupLocation!,
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueGreen,
            ),
            infoWindow: const InfoWindow(title: "Pickup Location"),
          ),
        );
      }

      // Add User Live Location Marker
      if (_userLocation != null) {
        _markers.add(
          Marker(
            markerId: const MarkerId('user_live'),
            position: _userLocation!,
            icon:
                _humanMarkerIcon ?? // Use custom icon if available
                BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueAzure,
                ),
            infoWindow: const InfoWindow(title: "User Location"),
          ),
        );
      }
    } else if (_rideStatus == 'started') {
      if (_dropLocation != null) {
        _markers.add(
          Marker(
            markerId: const MarkerId('drop'),
            position: _dropLocation!,
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueRed,
            ),
            infoWindow: const InfoWindow(title: "Drop Location"),
          ),
        );
      }
    }
  }

  Future<void> _getPolyline(LatLng start, LatLng end) async {
    try {
      final request = RoutesApiRequest(
        origin: PointLatLng(start.latitude, start.longitude),
        destination: PointLatLng(end.latitude, end.longitude),
        travelMode: TravelMode.driving,
      );

      RoutesApiResponse result = await polylinePoints
          .getRouteBetweenCoordinatesV2(request: request);

      if (result.routes.isNotEmpty) {
        _polylineCoordinates.clear();
        final route = result.routes.first;
        if (route.polylinePoints != null) {
          for (var point in route.polylinePoints!) {
            _polylineCoordinates.add(LatLng(point.latitude, point.longitude));
          }
        }

        if (mounted) {
          setState(() {
            _polylines.clear();
            _polylines.add(
              Polyline(
                polylineId: const PolylineId('route'),
                points: _polylineCoordinates,
                color: Colors.blue,
                width: 5,
              ),
            );
          });
        }
      }
    } catch (e) {
      debugPrint("Error getting polyline: $e");
    }
  }

  Future<void> _moveCamera(LatLng target) async {
    final GoogleMapController controller = await _controller.future;
    controller.animateCamera(CameraUpdate.newLatLngZoom(target, 16));
  }

  Future<void> _makePhoneCall() async {
    setState(() => _isLoading = true);
    try {
      final result = await FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('initiateCall')
          .call({'rideId': widget.rideRequest.rideId});

      if (mounted) {
        setState(() => _isLoading = false);
        if (result.data['success'] == true) {
          Get.snackbar(
            'Call',
            'Connecting call...',
            snackPosition: SnackPosition.TOP,
            backgroundColor: Colors.green,
            colorText: Colors.white,
          );
        } else {
          throw Exception("Call initiation failed");
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        Get.snackbar(
          'Error',
          'Call failed: $e',
          snackPosition: SnackPosition.TOP,
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    }
  }

  // --- Ride Actions ---

  Future<void> _onArrived() async {
    setState(() => _isLoading = true);
    try {
      await _firestore
          .collection(collectionPath)
          .doc(widget.rideRequest.rideId)
          .update({
            'status': 'arrived',
            'arrivedAt': FieldValue.serverTimestamp(),
          });
      setState(() {
        _rideStatus = 'arrived';
        _isLoading = false;
      });
      _startTimer(); // Start waiting timer
      if (mounted) {
        Get.snackbar(
          'Arrived',
          _getTranslatedString('arrivedMsg'),
          snackPosition: SnackPosition.TOP,
          backgroundColor: Colors.green,
          colorText: Colors.white,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        Get.snackbar(
          'Error',
          'Error updating status: $e',
          snackPosition: SnackPosition.TOP,
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    }
  }

  void _showCancelRideDialog() {
    String cancellationReason = 'Other';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(_getTranslatedString('cancelRide')),
            content: RadioGroup<String>(
              groupValue: cancellationReason,
              onChanged: (val) =>
                  setDialogState(() => cancellationReason = val!),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<String>(
                    title: Text(_getTranslatedString('other')),
                    value: 'Other',
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Get.back(),
                child: Text(_getTranslatedString('cancel')),
              ),
              ElevatedButton(
                onPressed: () {
                  Get.back();
                  _cancelRide(cancellationReason);
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: Text(
                  _getTranslatedString('cancelRide'),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _cancelRide(String reason) async {
    setState(() => _isLoading = true);
    try {
      await _firestore
          .collection(collectionPath)
          .doc(widget.rideRequest.rideId)
          .update({
            'status': 'cancelled',
            'cancelledBy': 'driver',
            'cancellationReason': reason,
            'cancelledAt': FieldValue.serverTimestamp(),
          });

      if (mounted) {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          Get.offAll(() => DriverHomePage(user: user));
        }
        Get.snackbar(
          'Cancelled',
          "Ride cancelled.",
          backgroundColor: Colors.orange,
          colorText: Colors.white,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        Get.snackbar(
          'Error',
          "Error cancelling ride: $e",
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // FIX: Force fresh MediaQueryData to avoid "incorrect configuration id" crash on Android 14+
    final mediaQueryData = MediaQueryData.fromView(
      View.of(context),
    ).copyWith(textScaler: const TextScaler.linear(1.0));

    return MediaQuery(
      data: mediaQueryData,
      child: PopScope(
        canPop: false,
        child: Scaffold(
          appBar: AppBar(
            title: Text(_getTranslatedString('title')),
            actions: [
              // Vehicle Info Button
              Theme(
                data: Theme.of(context).copyWith(
                  dividerColor: Colors.transparent,
                  cardColor: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey[900]
                      : Colors.white,
                ),
                child: PopupMenuButton(
                  icon: const Icon(Icons.info_outline),
                  itemBuilder: (context) {
                    final isDark =
                        Theme.of(context).brightness == Brightness.dark;
                    final textColor = isDark ? Colors.white : Colors.black;
                    return [
                      PopupMenuItem(
                        enabled: false,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Vehicle: ${widget.rideRequest.vehicleType}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.rideRequest.rideType == 'rental'
                                  ? 'Package: ${widget.rideRequest.packageName} (${(widget.rideRequest.rideDuration ?? 0) / 3600} Hr)'
                                  : 'Est. Fare: ₹${widget.rideRequest.rideFare}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                            const Divider(),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () {
                                  Get.back();
                                  _showCancelRideDialog();
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                ),
                                child: Text(_getTranslatedString('cancelRide')),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ];
                  },
                ),
              ),
            ],
          ),
          body: Stack(
            children: [
              GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: _driverLocation ?? const LatLng(0, 0),
                  zoom: 16,
                ),
                mapType: MapType.normal,
                onMapCreated: (GoogleMapController controller) {
                  _controller.complete(controller);
                },
                markers: _markers,
                polylines: _polylines,
                myLocationEnabled: true,
                myLocationButtonEnabled: false,
              ),
              // Bottom Action Sheet with Navigate Button
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Navigate Button (Dynamic Position)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FloatingActionButton.extended(
                          heroTag: 'ride_accepted_navigate_btn',
                          onPressed: () {
                            final lat =
                                widget.rideRequest.pickupLocation.latitude;
                            final lng =
                                widget.rideRequest.pickupLocation.longitude;
                            Get.to(
                              () => NavigationScreen(
                                destination: nav.LatLng(
                                  latitude: lat,
                                  longitude: lng,
                                ),
                                destinationTitle:
                                    widget.rideRequest.pickupTitle,
                              ),
                            );
                          },
                          icon: const Icon(Icons.navigation),
                          label: Text('navigateBtn'.tr),
                          backgroundColor: Colors.blue,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Bottom Sheet
                    Container(
                      padding: const EdgeInsets.all(16.0),
                      decoration: BoxDecoration(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(20),
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 10,
                            offset: Offset(0, -5),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // --- Payment Method Header ---
                          Center(
                            child: Text(
                              widget.rideRequest.rideType == 'daily'
                                  ? _getPaymentHeaderText()
                                  : "${widget.rideRequest.vehicleType} Ride",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(
                                  context,
                                ).textTheme.bodyLarge?.color,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Timer Display (Only show if arrived)
                          if (_rideStatus == 'arrived')
                            Container(
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: _elapsedSeconds > 180
                                    ? Colors.red.withAlpha(30)
                                    : Colors.green.withAlpha(30),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _elapsedSeconds > 180
                                      ? Colors.red
                                      : Colors.green,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _elapsedSeconds > 180
                                        ? '${'waitingTime'.tr}: ${_formatDuration(_elapsedSeconds - 180)}'
                                        : '${'freeWaitTime'.tr}: ${_formatDuration(180 - _elapsedSeconds)}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: _elapsedSeconds > 180
                                          ? Colors.red
                                          : Colors.green,
                                      fontSize: 16,
                                    ),
                                  ),
                                  if (_waitingCharge > 0)
                                    Text(
                                      '+ ₹${_waitingCharge.toStringAsFixed(0)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.red,
                                        fontSize: 16,
                                      ),
                                    ),
                                ],
                              ),
                            ),

                          // Customer Info
                          Row(
                            children: [
                              const CircleAvatar(
                                backgroundColor: Colors.grey,
                                child: Icon(Icons.person, color: Colors.white),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _customerName,
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color:
                                            Theme.of(context).brightness ==
                                                Brightness.dark
                                            ? Colors.white
                                            : Colors.black,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Chat Button
                              Stack(
                                children: [
                                  IconButton(
                                    onPressed: _openChat,
                                    icon: const Icon(
                                      Icons.chat,
                                      color: Colors.blue,
                                      size: 32,
                                    ),
                                  ),
                                  if (_unreadMessages > 0)
                                    Positioned(
                                      right: 8,
                                      top: 8,
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: const BoxDecoration(
                                          color: Colors.red,
                                          shape: BoxShape.circle,
                                        ),
                                        constraints: const BoxConstraints(
                                          minWidth: 12,
                                          minHeight: 12,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              // Call Button
                              IconButton(
                                onPressed: _makePhoneCall,
                                icon: const Icon(
                                  Icons.phone,
                                  color: Colors.green,
                                  size: 32,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 24),

                          // Address Titles
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.location_on,
                                color: Colors.green,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget
                                          .rideRequest
                                          .pickupTitle, // Area Name
                                      style: const TextStyle(
                                        color: Colors.grey,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      widget.rideRequest.pickupFullAddress,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color:
                                            Theme.of(context).brightness ==
                                                Brightness.dark
                                            ? Colors.white
                                            : Colors.black,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 24),

                          // Rental Details Section
                          if (widget.rideRequest.rideType == 'rental') ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.blue.withAlpha(20),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.blue),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "${'rentalPackage'.tr}: ${widget.rideRequest.packageName}",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "${'duration'.tr}: ${(widget.rideRequest.rideDuration ?? 0) / 3600} ${'hours'.tr} | ${'distance'.tr}: ${widget.rideRequest.kmLimit ?? 0} km",
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 24),
                          ],

                          // Multi-stop Details
                          if (widget.rideRequest.rideType == 'multistop' &&
                              widget.rideRequest.stops.isNotEmpty) ...[
                            Text(
                              '${'stops'.tr}:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ...widget.rideRequest.stops.asMap().entries.map((
                              entry,
                            ) {
                              int idx = entry.key;
                              // Assuming RideStop is a defined class/type
                              // If not, you might need to adjust this type or use dynamic
                              dynamic stop = entry.value;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8.0),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    CircleAvatar(
                                      radius: 10,
                                      backgroundColor: Colors.orange,
                                      child: Text(
                                        '${idx + 1}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            stop.title,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                          Text(
                                            stop.fullAddress,
                                            style: const TextStyle(
                                              color: Colors.grey,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                            const Divider(height: 24),
                          ],

                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.flag, color: Colors.red),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.rideRequest.dropoffTitle,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color:
                                            Theme.of(context).brightness ==
                                                Brightness.dark
                                            ? Colors.white
                                            : Colors.black,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      widget.rideRequest.dropoffFullAddress,
                                      style: const TextStyle(
                                        color: Colors.grey,
                                        fontSize: 12,
                                        fontWeight: FontWeight.normal,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // Slider
                          Padding(
                            padding: const EdgeInsets.only(bottom: 30),
                            child: RideStatusSlider(
                              key: ValueKey(_rideStatus),
                              label: _rideStatus == 'accepted'
                                  ? 'iHaveArrived'.tr
                                  : 'startRideBtn'.tr,
                              color: _rideStatus == 'accepted'
                                  ? Colors.orange
                                  : Colors.green,
                              onSlideComplete: () {
                                debugPrint(
                                  "Slider Action Triggered. Status: $_rideStatus",
                                );
                                if (_rideStatus == 'accepted') {
                                  _onArrived();
                                } else {
                                  // Navigate to new OTP Screen
                                  debugPrint(
                                    "Navigating to RideStartOtpScreen",
                                  );
                                  Get.to(
                                    () => RideStartOtpScreen(
                                      rideRequest: widget.rideRequest,
                                    ),
                                  );
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getPaymentHeaderText() {
    final method = widget.rideRequest.paymentMethod; // e.g. "Cash"
    final walletUsed = widget.rideRequest.paidByWallet ?? 0.0;
    debugPrint("PaymentHeader: method=$method, walletUsed=$walletUsed");

    if (walletUsed > 0 || method == 'Cash + Wallet') {
      return "cashPlusWallet".tr;
    }
    if (method.toLowerCase() == 'cash') {
      return "cashPayment".tr;
    }
    return "digitalPayment".tr;
  }

  String _formatDuration(int seconds) {
    final minutes = (seconds / 60).floor();
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }
}
