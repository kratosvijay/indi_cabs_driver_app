// ignore_for_file: unused_field

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as maps;
import 'package:project_taxi_driver_app/widgets/ride_request.dart';
import 'package:project_taxi_driver_app/widgets/ride_status_slider.dart';
import 'package:project_taxi_driver_app/screens/ride_payment.dart';
import 'package:project_taxi_driver_app/services/pricing_service.dart';
import 'package:project_taxi_driver_app/screens/navigation_screen.dart'; // Import NavigationScreen
import 'package:project_taxi_driver_app/screens/ride_end_otp_screen.dart';
import 'package:project_taxi_driver_app/services/ride_queue_service.dart';

import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart'
    as nav; // Keep for data types if needed, or remove if unused in this file.
import 'package:flutter_polyline_points/flutter_polyline_points.dart';

class RideStartedScreen extends StatefulWidget {
  final RideRequest rideRequest;

  const RideStartedScreen({super.key, required this.rideRequest});

  @override
  State<RideStartedScreen> createState() => _RideStartedScreenState();
}

class _RideStartedScreenState extends State<RideStartedScreen> {
  String get collectionPath => widget.rideRequest.rideType == 'rental'
      ? 'rental_requests'
      : 'ride_requests';

  final Completer<maps.GoogleMapController> _controller = Completer();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Use standard Maps LatLng here for the overview map
  maps.LatLng? _driverLocation;
  maps.LatLng? _dropLocation;
  final Set<maps.Marker> _markers = {};
  final Set<maps.Polyline> _polylines = {};

  StreamSubscription<Position>? _positionStream;
  StreamSubscription<DocumentSnapshot>? _rideSubscription;

  RideRequest? _dynamicRideRequest;
  RideRequest get _rideRequest => _dynamicRideRequest ?? widget.rideRequest;

  String _customerName = 'Customer';
  String _customerPhone = '';
  int _currentStopIndex = 0;
  bool _isLoading = false;
  Timer? _wakelockTimer;

  // Multi-stop Waiting State
  bool _isWaiting = false;
  bool _isFirstListen = true;
  Timer? _waitTimer;
  int _waitTimeRemaining = 180; // 3 minutes in seconds
  int _paidWaitSeconds = 0;

  String _fetchedAddress = ''; // Store locally fetched address
  Timer? _syncTimer;
  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    _initDistanceTracking();
    debugPrint(
      "RideStarted Init - Name: ${widget.rideRequest.userName}, Type: ${widget.rideRequest.rideType}, Stops: ${widget.rideRequest.stops.length}",
    );
    if (widget.rideRequest.userName != null &&
        widget.rideRequest.userName!.isNotEmpty) {
      _customerName = widget.rideRequest.userName!;
    }
    _enableWakelock();

    final rideDrop = _rideRequest.dropoffLocation;
    _dropLocation = maps.LatLng(rideDrop.latitude, rideDrop.longitude);

    _fetchCustomerDetails();
    _startLocationUpdates();
    _listenToRideUpdates();
    _getInitialRoute();

    // Check if we need to resolve address
    _checkAndResolveAddress();
  }

  Future<void> _initDistanceTracking() async {
    _prefs = await SharedPreferences.getInstance();
    final localDistance =
        _prefs?.getDouble('distance_tracking_${widget.rideRequest.rideId}') ??
        0.0;
    final firestoreDistance =
        widget.rideRequest.accumulatedDistanceMeters ?? 0.0;

    // Use the maximum to ensure we don't lose data
    _accumulatedDistance = (localDistance > firestoreDistance)
        ? localDistance
        : firestoreDistance;

    // Start 5 min sync timer
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      if (!mounted) return;
      _firestore
          .collection(collectionPath)
          .doc(widget.rideRequest.rideId)
          .update({'accumulatedDistanceMeters': _accumulatedDistance})
          .catchError(
            (e) => debugPrint("Error syncing distance to Firestore: $e"),
          );
    });
  }

  Future<void> _checkAndResolveAddress() async {
    String addressToCheck = "";
    maps.LatLng locationToResolve;

    if (_rideRequest.stops.isNotEmpty &&
        _currentStopIndex < _rideRequest.stops.length) {
      addressToCheck = _rideRequest.stops[_currentStopIndex].fullAddress;
      locationToResolve = _rideRequest.stops[_currentStopIndex].location;
    } else {
      addressToCheck = _rideRequest.dropoffFullAddress;
      locationToResolve = _rideRequest.dropoffLocation;
    }

    if (addressToCheck.isEmpty ||
        addressToCheck.toLowerCase().contains("getting address")) {
      // Safeguard: Check if locationToResolve is suspiciously close to pickup (implies fallback)
      bool isFallback = false;
      try {
        final dist = Geolocator.distanceBetween(
          locationToResolve.latitude,
          locationToResolve.longitude,
          _rideRequest.pickupLocation.latitude,
          _rideRequest.pickupLocation.longitude,
        );
        if (dist < 50 && _rideRequest.rideType != 'rental') {
          isFallback = true;
        }
      } catch (e) {
        // ignore
      }

      if (isFallback) {
        if (mounted) {
          setState(() {
            _fetchedAddress = "Drop-off Location";
          });
        }
      } else {
        final addr = await _getAddressFromLatLng(locationToResolve);
        if (addr != null && mounted) {
          setState(() {
            _fetchedAddress = addr;
          });
        }
      }
    }

    // --- PATCH REMOVED: It was incorrectly resetting destination to pickup if dropoff was 0,0 ---
    // The _repairDropoffLocation() method handles this safely via geocoding later in the lifecycle.

  }

  void _listenToRideUpdates() {
    _rideSubscription = _firestore
        .collection(collectionPath)
        .doc(widget.rideRequest.rideId) // rideId is unexpected to change
        .snapshots()
        .listen((snapshot) {
          if (snapshot.exists && snapshot.data() != null) {
            try {
              final data = snapshot.data() as Map<String, dynamic>;
              // Ensure rideId (which is the doc ID) is passed if missing in data
              data['rideId'] ??= snapshot.id;

              final updatedRide = RideRequest.fromJson(data);
              // Detect if destination changed
              final newDrop = maps.LatLng(
                updatedRide.dropoffLocation.latitude,
                updatedRide.dropoffLocation.longitude,
              );

              bool destChanged = false;
              if (_dropLocation != null) {
                final dist = Geolocator.distanceBetween(
                  _dropLocation!.latitude,
                  _dropLocation!.longitude,
                  newDrop.latitude,
                  newDrop.longitude,
                );
                if (dist > 50) {
                  // Threshold: 50 meters
                  destChanged = true;
                }
              } else {
                destChanged = true;
              }

              setState(() {
                // Detect if stops changed (new stops added or status changed)
                final oldPendingCount = _rideRequest.stops
                    .where((s) => s.isPending)
                    .length;
                final newPendingCount = updatedRide.stops
                    .where((s) => s.isPending)
                    .length;
                final stopsChanged =
                    oldPendingCount != newPendingCount ||
                    _rideRequest.stops.length != updatedRide.stops.length;

                // Preserve locally-resolved or critical fields if server update is missing them
                _dynamicRideRequest = updatedRide.copyWith(
                  rideDistance: (updatedRide.rideDistance == 0 && _rideRequest.rideDistance > 0)
                      ? _rideRequest.rideDistance
                      : updatedRide.rideDistance,
                  createdAt: updatedRide.createdAt ?? _rideRequest.createdAt,
                  startedAt: updatedRide.startedAt ?? _rideRequest.startedAt,
                  surgeMultiplier: updatedRide.surgeMultiplier ?? _rideRequest.surgeMultiplier,
                );

                if (destChanged) {
                  debugPrint("Destination changed! Updating route.");
                  _dropLocation = newDrop;
                  _routeFetched = false; // Force re-fetch
                  _polylines.clear();

                  // Update the local address display to the new one
                  if (updatedRide.dropoffFullAddress.isNotEmpty) {
                    _fetchedAddress = updatedRide.dropoffFullAddress;
                  } else {
                    _fetchedAddress =
                        ''; // Reset to force re-fetch or use fallback
                    _checkAndResolveAddress();
                  }

                  if (_driverLocation != null) {
                    _getRoute(_driverLocation!, _dropLocation!);
                  }

                  // Notify Driver (Only if not the first load)
                  if (!_isFirstListen) {
                    Get.snackbar(
                      'tripUpdated'.tr,
                      updatedRide.dropoffTitle,
                      backgroundColor: Colors.blueAccent,
                      colorText: Colors.white,
                      snackPosition: SnackPosition.TOP,
                      duration: const Duration(seconds: 5),
                      icon: const Icon(
                        Icons.edit_location_alt,
                        color: Colors.white,
                      ),
                    );
                  }
                }

                // Handle stops changes - clear fetched address to show pending stop address
                if (stopsChanged && !_isFirstListen) {
                  debugPrint(
                    "Stops changed! Old pending: $oldPendingCount, New pending: $newPendingCount",
                  );
                  _fetchedAddress = ''; // Clear to show stop address from list

                  // Notify about new stop if added
                  if (newPendingCount > oldPendingCount) {
                    try {
                      final pendingStops = updatedRide.stops
                          .where((s) => s.isPending)
                          .toList();
                      if (pendingStops.isNotEmpty) {
                        final newStop = pendingStops.last;
                        Get.snackbar(
                          'stopAdded'.tr,
                          newStop.title,
                          backgroundColor: Colors.orange,
                          colorText: Colors.white,
                          snackPosition: SnackPosition.TOP,
                          duration: const Duration(seconds: 4),
                          icon: const Icon(
                            Icons.add_location,
                            color: Colors.white,
                          ),
                        );
                      }
                    } catch (e) {
                      debugPrint("Error notifying about new stop: $e");
                    }
                  }

                  _isFirstListen = false;

                  // Always update markers (for stops or single dest)
                  _updateMarkers();
                }
              });
            } catch (e) {
              debugPrint("Error parsing dynamic ride update: $e");
            }
          }
        });
  }

  bool _routeFetched = false;

  Future<void> _getInitialRoute() async {
    // Wait for driver location to be available
    int retries = 0;
    while (_driverLocation == null && retries < 10) { // Increased retries slightly
      await Future.delayed(const Duration(milliseconds: 500));
      retries++;
    }

    // Attempt to repair drop location if it looks suspicious (equals pickup)
    // Doing this AFTER waiting for driver location ensures we have location bias for geocoding
    await _repairDropoffLocation();

    if (_driverLocation != null &&
        _driverLocation!.latitude != 0 &&
        _dropLocation != null &&
        _dropLocation!.latitude != 0) {
      await _getRoute(_driverLocation!, _dropLocation!);
    } else {
      // Fallback: If driver location is not valid yet, just center on dropoff.
      // Do NOT route from pickup, as that is confusing for a Started ride.
      if (_dropLocation != null && _dropLocation!.latitude != 0) {
        final controller = await _controller.future;
        controller.animateCamera(
          maps.CameraUpdate.newLatLngZoom(_dropLocation!, 16),
        );
      }
    }
  }

  Future<void> _repairDropoffLocation() async {
    if (_dropLocation == null) return;

    final pickup = _rideRequest.pickupLocation;
    final dist = Geolocator.distanceBetween(
      _dropLocation!.latitude,
      _dropLocation!.longitude,
      pickup.latitude,
      pickup.longitude,
    );

    // If dropoff is basically pickup, and it's not a rental...
    if (dist < 50 && _rideRequest.rideType != 'rental') {
      debugPrint(
        "Dropoff Location is suspicious (close to pickup). Attempting repair...",
      );

      String addressToGeocode = "";
      if (_rideRequest.dropoffFullAddress.isNotEmpty &&
          _rideRequest.dropoffFullAddress != "Unknown" &&
          !_rideRequest.dropoffFullAddress.contains("getting address")) {
        addressToGeocode = _rideRequest.dropoffFullAddress;
      } else if (_fetchedAddress.isNotEmpty &&
          _fetchedAddress != "Drop-off Location" &&
          !_fetchedAddress.contains("getting address")) {
        addressToGeocode = _fetchedAddress;
      } else if (_rideRequest.dropoffTitle.isNotEmpty &&
          _rideRequest.dropoffTitle != "Unknown") {
        // Fallback to title if address is completely missing
        addressToGeocode = _rideRequest.dropoffTitle;
      }

      if (addressToGeocode.isNotEmpty) {
        debugPrint("Repairing Dropoff: Geocoding $addressToGeocode");
        final resolvedLoc = await _getLatLngFromAddress(addressToGeocode);
        if (resolvedLoc != null) {
          setState(() {
            _dropLocation = resolvedLoc;
            _updateMarkers(); // Refresh markers with new location

            // Force re-fetch route
            _routeFetched = false;
            _polylines.clear();
          });

          if (_driverLocation != null) {
            await _getRoute(_driverLocation!, _dropLocation!);
          }

          debugPrint("Dropoff Location Repaired to: $_dropLocation");
        }
      }
    }
  }

  Future<void> _getRoute(maps.LatLng origin, maps.LatLng destination) async {
    if (_routeFetched) return; // Only fetch once

    try {
      final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';
      debugPrint("Fetching Route with API Key length: ${apiKey.length}");
      if (apiKey.isEmpty) {
        debugPrint("API Key is empty! Cannot fetch route.");
        return;
      }

      PolylinePoints polylinePoints = PolylinePoints(apiKey: apiKey);
      final originLoc = origin.latitude != 0 ? origin : maps.LatLng(
        _rideRequest.pickupLocation.latitude,
        _rideRequest.pickupLocation.longitude,
      );

      final request = RoutesApiRequest(
        origin: PointLatLng(originLoc.latitude, originLoc.longitude),
        destination: PointLatLng(destination.latitude, destination.longitude),
        travelMode: TravelMode.driving,
      );

      debugPrint(
        "Requesting route from ${originLoc.latitude},${originLoc.longitude} to ${destination.latitude},${destination.longitude}",
      );

      RoutesApiResponse result = await polylinePoints
          .getRouteBetweenCoordinatesV2(request: request);

      debugPrint("Route Params: ${result.routes.length} routes found.");

      if (result.routes.isNotEmpty && mounted) {
        final route = result.routes.first;
        if (route.polylinePoints != null) {
          debugPrint(
            "Route found with points: ${route.polylinePoints!.length}",
          );
          List<maps.LatLng> polylineCoordinates = route.polylinePoints!
              .map((point) => maps.LatLng(point.latitude, point.longitude))
              .toList();

          setState(() {
            // Update Distance if missing from server
            if (_rideRequest.rideDistance == 0 && (route.distanceKm ?? 0) > 0) {
              _dynamicRideRequest = _rideRequest.copyWith(rideDistance: route.distanceKm);
              debugPrint("Auto-resolved missing rideDistance: ${route.distanceKm} km");
            }

            _polylines.add(
              maps.Polyline(
                polylineId: const maps.PolylineId('route'),
                points: polylineCoordinates,
                color: Colors.blue,
                width: 5,
              ),
            );
            _routeFetched = true;
          });
          debugPrint("Polyline added to map.");

          // Fit camera to show entire route
          _fitCameraToRoute(origin, destination);
        } else {
          debugPrint("Route found but no polyline points!");
        }
      } else {
        debugPrint("No routes found in result.");
        if (result.errorMessage != null) {
          debugPrint("Route Error Message: ${result.errorMessage}");
        }
      }
    } catch (e) {
      debugPrint("Error fetching route detailed: $e");
    }
  }

  Future<void> _fitCameraToRoute(
    maps.LatLng origin,
    maps.LatLng destination,
  ) async {
    final controller = await _controller.future;

    // Add safety check for (0,0) coordinates
    if (origin.latitude == 0 ||
        origin.longitude == 0 ||
        destination.latitude == 0 ||
        destination.longitude == 0) {
      debugPrint("SKIPPING fitCameraToRoute: Invalid coordinates detected.");
      // Just center on destination if possible
      if (destination.latitude != 0) {
        controller.animateCamera(maps.CameraUpdate.newLatLngZoom(destination, 15));
      }
      return;
    }

    // Calculate LatLngBounds to fit both points
    final southwestLat = origin.latitude < destination.latitude ? origin.latitude : destination.latitude;
    final southwestLng = origin.longitude < destination.longitude ? origin.longitude : destination.longitude;
    final northeastLat = origin.latitude > destination.latitude ? origin.latitude : destination.latitude;
    final northeastLng = origin.longitude > destination.longitude ? origin.longitude : destination.longitude;

    final bounds = maps.LatLngBounds(
      southwest: maps.LatLng(southwestLat, southwestLng),
      northeast: maps.LatLng(northeastLat, northeastLng),
    );

    controller.animateCamera(maps.CameraUpdate.newLatLngBounds(bounds, 100)); // Increased padding to 100
  }

  void _enableWakelock() {
    WakelockPlus.enable();
    _wakelockTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      WakelockPlus.enable();
    });
  }

  double _accumulatedDistance = 0.0; // In meters
  maps.LatLng? _lastRecordedLocation;

  void _startLocationUpdates() {
    _positionStream =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5, // Receive updates every 5 meters
          ),
        ).listen((Position position) {
          if (!mounted) return;

          final newLoc = maps.LatLng(position.latitude, position.longitude);

          if (_lastRecordedLocation != null) {
            final dist = Geolocator.distanceBetween(
              _lastRecordedLocation!.latitude,
              _lastRecordedLocation!.longitude,
              newLoc.latitude,
              newLoc.longitude,
            );
            // Sanity check: verify reasonable speed to avoid massive jumps?
            // For now, trust Geolocator with high accuracy.
            _accumulatedDistance += dist;
            _prefs?.setDouble(
              'distance_tracking_${widget.rideRequest.rideId}',
              _accumulatedDistance,
            );
          }

          _lastRecordedLocation = newLoc;

          setState(() {
            _driverLocation = newLoc;
            _updateMarkers();
            _moveCamera();

            // Retry route fetch if not yet fetched and drop location exists
            if (!_routeFetched && _dropLocation != null) {
              _getRoute(_driverLocation!, _dropLocation!);
            }
          });
        });
  }

  // Track previous status to avoid redundant writes
  final String _lastSetStatus = '';

  void _updateMarkers() {
    _markers.clear();
    if (_driverLocation != null) {
      _markers.add(
        maps.Marker(
          markerId: const maps.MarkerId('driver'),
          position: _driverLocation!,
          icon: maps.BitmapDescriptor.defaultMarkerWithHue(
            maps.BitmapDescriptor.hueBlue,
          ),
          rotation: 0, // Could add bearing if available
        ),
      );
    }

    // Add destinations
    if (_rideRequest.stops.isNotEmpty) {
      for (int i = 0; i < _rideRequest.stops.length; i++) {
        final stop = _rideRequest.stops[i];
        _markers.add(
          maps.Marker(
            markerId: maps.MarkerId('stop_$i'),
            position: maps.LatLng(
              stop.location.latitude,
              stop.location.longitude,
            ),
            infoWindow: maps.InfoWindow(title: 'Stop ${i + 1}: ${stop.title}'),
            icon: maps.BitmapDescriptor.defaultMarkerWithHue(
              maps.BitmapDescriptor.hueOrange,
            ),
          ),
        );
      }
    }
    
    // Always add final destination Marker if available
    if (_dropLocation != null && _dropLocation!.latitude != 0) {
      _markers.add(
        maps.Marker(
          markerId: const maps.MarkerId('destination'),
          position: _dropLocation!,
          infoWindow: maps.InfoWindow(title: _rideRequest.dropoffTitle),
        ),
      );
    }

    // Explicitly add Pickup Marker as requested
    _markers.add(
      maps.Marker(
        markerId: const maps.MarkerId('pickup'),
        position: maps.LatLng(
          _rideRequest.pickupLocation.latitude,
          _rideRequest.pickupLocation.longitude,
        ),
        infoWindow: maps.InfoWindow(title: _rideRequest.pickupTitle),
        icon: maps.BitmapDescriptor.defaultMarkerWithHue(
          maps.BitmapDescriptor.hueGreen,
        ),
      ),
    );
  }

  Future<void> _moveCamera() async {
    final maps.GoogleMapController controller = await _controller.future;
    if (_driverLocation != null) {
      controller.animateCamera(maps.CameraUpdate.newLatLng(_driverLocation!));
    }
  }

  Future<void> _fetchCustomerDetails() async {
    try {
      DocumentSnapshot userDoc = await _firestore
          .collection('users')
          .doc(_rideRequest.userId)
          .get();

      if (userDoc.exists) {
        final data = userDoc.data() as Map<String, dynamic>;

        debugPrint("Customer Data: $data");

        if (mounted) {
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
            debugPrint("Final Customer Name: $_customerName");
          });
        }
      } else {
        debugPrint(
          "User document ${_rideRequest.userId} not found, using default 'Customer'",
        );
      }
    } catch (e) {
      debugPrint("Error fetching customer details: $e");
    }
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _rideSubscription?.cancel();
    _wakelockTimer?.cancel();
    _waitTimer?.cancel();
    _syncTimer?.cancel();
    // WakelockPlus.disable(); // Handled globally/by home
    super.dispose();
  }

  bool _isNavigating = false;

  void _onNavigatePressed() async {
    if (_isNavigating) return;
    setState(() => _isNavigating = true);

    try {
      // Navigate to NavigationScreen
      // Logic: Pass current target.
      // Use maps.LatLng for local logic, convert to nav.LatLng for NavigationScreen.

      // 1. Identify Target: First pending stop, or final destination
      maps.LatLng target;
      String title;
      final pendingStopIndex = _rideRequest.stops.indexWhere((s) => s.isPending);
      
      if (pendingStopIndex != -1) {
        final stop = _rideRequest.stops[pendingStopIndex];
        target = maps.LatLng(stop.location.latitude, stop.location.longitude);
        title = stop.title;
        debugPrint("Navigating to Stop ${pendingStopIndex + 1}: $title");
      } else {
        target = _dropLocation ??
            maps.LatLng(
              _rideRequest.dropoffLocation.latitude,
              _rideRequest.dropoffLocation.longitude,
            );
        title = _rideRequest.dropoffTitle;
        debugPrint("Navigating to Final Destination: $title");
      }

      // --- NAV SAFETY CHECK ---
      // If target is 0,0 or suspiciously close to pickup (implies invalid data),
      // try one last time to resolve from address before opening navigation.
      final distToPickup = Geolocator.distanceBetween(
        target.latitude,
        target.longitude,
        _rideRequest.pickupLocation.latitude,
        _rideRequest.pickupLocation.longitude,
      );

      if ((target.latitude == 0 && target.longitude == 0) ||
          (distToPickup < 100 && _rideRequest.rideType != 'rental')) {
        debugPrint(
          "Nav_Safety: Target is invalid or at pickup. Geocoding address...",
        );
        String address = (pendingStopIndex != -1)
            ? _rideRequest.stops[pendingStopIndex].fullAddress
            : (_rideRequest.dropoffFullAddress.isNotEmpty &&
                    _rideRequest.dropoffFullAddress != "Unknown" &&
                    !_rideRequest.dropoffFullAddress.contains("getting address")
                ? _rideRequest.dropoffFullAddress
                : _rideRequest.dropoffTitle);

        if (address.isNotEmpty && address != "Unknown") {
          final resolved = await _getLatLngFromAddress(address);
          if (resolved != null) {
            target = resolved;
            debugPrint("Nav_Safety: Resolved target to $target");
          }
        }
      }

      // Final Validity Check
      if (target.latitude == 0 && target.longitude == 0) {
        Get.snackbar(
          "Error",
          "Invalid dropoff location (0,0). Cannot start navigation.",
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
        setState(() => _isNavigating = false);
        return;
      }

      final navTarget = nav.LatLng(
        latitude: target.latitude,
        longitude: target.longitude,
      );

      // NavigationScreen uses nav.LatLng because it imports google_navigation_flutter
      await Get.to(
        () => NavigationScreen(destination: navTarget, destinationTitle: title),
      );
    } catch (e) {
      debugPrint("Navigation Error: $e");
    } finally {
      if (mounted) {
        setState(() => _isNavigating = false);
      }
    }
  }

  Future<maps.LatLng?> _getLatLngFromAddress(String address) async {
    try {
      final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'];
      if (apiKey == null) return null;

      // Add location bias if driver location is available to prevent results from 500km away
      String biasParam = "";
      if (_driverLocation != null) {
        biasParam = "&locationbias=circle:50000@${_driverLocation!.latitude},${_driverLocation!.longitude}";
      }

      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json?address=${Uri.encodeComponent(address)}$biasParam&key=$apiKey',
      );
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final parsed = json.decode(response.body);
        if (parsed['status'] == 'OK' && parsed['results'].isNotEmpty) {
          final loc = parsed['results'][0]['geometry']['location'];
          return maps.LatLng(
            (loc['lat'] as num).toDouble(),
            (loc['lng'] as num).toDouble(),
          );
        }
      }
    } catch (e) {
      debugPrint("Error resolving coordinates from address: $e");
    }
    return null;
  }

  Future<void> _makePhoneCall() async {
    final Uri launchUri = Uri(scheme: 'tel', path: '04446972845');
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    } else {
      if (mounted) {
        Get.snackbar(
          'Error',
          'Could not launch phone dialer',
          snackPosition: SnackPosition.TOP,
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    }
  }

  Future<String?> _getAddressFromLatLng(maps.LatLng position) async {
    try {
      final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'];
      if (apiKey == null) return null;

      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json?latlng=${position.latitude},${position.longitude}&key=$apiKey',
      );
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final parsed = json.decode(response.body);
        if (parsed['status'] == 'OK' && parsed['results'].isNotEmpty) {
          return parsed['results'][0]['formatted_address'];
        }
      }
    } catch (e) {
      debugPrint("Error resolving address: $e");
    }
    return null;
  }

  void _handleSlideComplete() {
    if (_isWaiting) {
      _resumeRide();
    } else {
      // Find first pending stop index dynamically
      final pendingStopIndex = _rideRequest.stops.indexWhere(
        (s) => s.isPending,
      );
      if (pendingStopIndex != -1) {
        _currentStopIndex = pendingStopIndex;
        _startStopWait();
      } else {
        _showEndRideConfirmation();
      }
    }
  }

  void _startStopWait() async {
    // Update stop status in Firestore first
    try {
      final stopsData = _rideRequest.stops.asMap().entries.map((entry) {
        final stop = entry.value;
        final isCurrentStop = entry.key == _currentStopIndex;
        return {
          'address': stop.fullAddress,
          'latitude': stop.location.latitude,
          'longitude': stop.location.longitude,
          'status': isCurrentStop ? 'completed' : stop.status,
        };
      }).toList();

      await _firestore
          .collection(collectionPath)
          .doc(widget.rideRequest.rideId)
          .update({'stops': stopsData});
      debugPrint(
        "Updated stop $_currentStopIndex status to completed in Firestore",
      );
    } catch (e) {
      debugPrint("Error updating stop status: $e");
    }

    // Update local state to mark stop as completed
    if (_currentStopIndex < _rideRequest.stops.length) {
      _rideRequest.stops[_currentStopIndex].status = 'completed';
    }

    // For RENTAL rides - no waiting timer, just mark complete and move on
    if (_rideRequest.rideType == 'rental') {
      setState(() {
        _currentStopIndex++;
        _fetchedAddress = '';
      });
      _checkAndResolveAddress();

      Get.snackbar(
        'stopCompleted'.tr,
        'proceedingToNext'.tr,
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );

      // Update route to next destination
      if (_driverLocation != null) {
        final pendingStopIndex = _rideRequest.stops.indexWhere(
          (s) => s.isPending,
        );
        maps.LatLng target;
        if (pendingStopIndex != -1) {
          target = _rideRequest.stops[pendingStopIndex].location;
        } else {
          target = maps.LatLng(
            _rideRequest.dropoffLocation.latitude,
            _rideRequest.dropoffLocation.longitude,
          );
        }
        _routeFetched = false;
        _polylines.clear();
        _getRoute(_driverLocation!, target);
      }
      return;
    }

    // For NON-RENTAL rides - start waiting timer
    setState(() {
      _isWaiting = true;
      _waitTimeRemaining = 180;
    });

    Get.snackbar(
      'stopReached'.tr,
      'waitingTimerStarted'.tr,
      snackPosition: SnackPosition.TOP,
      backgroundColor: Colors.orange,
      colorText: Colors.white,
    );

    _waitTimer?.cancel();
    _waitTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_waitTimeRemaining > 0) {
          _waitTimeRemaining--;
        } else {
          // Free wait over, start paid wait
          _paidWaitSeconds++;
        }
      });
    });
  }

  void _resumeRide() {
    _waitTimer?.cancel();
    setState(() {
      _isWaiting = false;
      _currentStopIndex++;
      _fetchedAddress = ''; // Reset fetched address for next leg
    });
    _checkAndResolveAddress(); // Check next leg address

    Get.snackbar(
      'resuming'.tr,
      'resumingRide'.tr,
      snackPosition: SnackPosition.TOP,
      backgroundColor: Colors.green,
      colorText: Colors.white,
    );

    // Auto-update map to next leg?
    if (_driverLocation != null) {
      // Logic to re-route could go here if needed,
      // but _getInitialRoute usually only runs once.
      // You might want to clear _routeFetched and call _getRoute again for the next leg.
      // For now, simpler implementation.

      maps.LatLng target;
      if (_currentStopIndex < _rideRequest.stops.length) {
        final nextStop = _rideRequest.stops[_currentStopIndex];
        target = nextStop.location;
      } else {
        target = maps.LatLng(
          _rideRequest.dropoffLocation.latitude,
          _rideRequest.dropoffLocation.longitude,
        );
      }
      _getRoute(
        _driverLocation!,
        target,
      ); // This will only work if we reset flags or change logic,
      // but current _getRoute has `if (_routeFetched) return;`.
      // Let's reset the flag to allow re-routing.
      _routeFetched = false;
      _polylines.clear(); // Clear old route
      _getRoute(_driverLocation!, target);
    }
  }

  void _showEndRideConfirmation() {
    if (widget.rideRequest.rideType == 'rental') {
      _showRentalEndOtpDialog();
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('endRideConfirm'.tr),
        content: Text('endRideConfirmMsg'.tr),
        actions: [
          TextButton(onPressed: () => Get.back(), child: Text('no'.tr)),
          ElevatedButton(
            onPressed: () {
              Get.back();
              _endRide();
            },
            child: Text('yes'.tr),
          ),
        ],
      ),
    );
  }

  void _showRentalEndOtpDialog() {
    Get.to(
      () => RideEndOtpScreen(
        rideRequest: _rideRequest,
        driverLocation: _driverLocation,
        accumulatedDistance: _accumulatedDistance,
      ),
    );
  }

  Future<void> _endRide() async {
    setState(() => _isLoading = true);
    try {
      double actualDistance = 0.0;

      // Use accumulated distance if available and non-zero
      if (_accumulatedDistance > 0) {
        actualDistance = _accumulatedDistance / 1000.0; // Convert to km
      } else if (_driverLocation != null) {
        // Fallback to straight line if accumulation failed (e.g. app restarted)
        actualDistance =
            Geolocator.distanceBetween(
              _rideRequest.pickupLocation.latitude,
              _rideRequest.pickupLocation.longitude,
              _driverLocation!.latitude,
              _driverLocation!.longitude,
            ) /
            1000;
      } else {
        actualDistance = 0.0;
      }
      debugPrint(
        "Ending Ride. Accumulated Distance: ${_accumulatedDistance}m. Final used km: $actualDistance",
      );

      // Cleanup local SharedPreferences backup
      _prefs?.remove('distance_tracking_${widget.rideRequest.rideId}');
      _syncTimer?.cancel();

      // Calculate Paid Waiting Charge
      // pickupWait comes from the pickup phase (passed via RideRequest)
      double pickupWait = _rideRequest.waitingCharge;

      // stopWait is total seconds beyond the free 3 mins per stop during the trip
      int totalStopWaitMinutes = (_paidWaitSeconds / 60).ceil();
      double stopWait = totalStopWaitMinutes * 3.0; // ₹3 per min

      double totalWaitCharge = pickupWait + stopWait;

      // ---------------------------------------------------------
      // OPTIMIZED BILLING LOGIC
      // ---------------------------------------------------------
      // Calculate Duration for pricing
      final double durationMins = _rideRequest.startedAt != null
          ? DateTime.now().difference(_rideRequest.startedAt!).inMinutes.toDouble()
          : 0.0;

      // Local Recalculation
      final localResult = PricingService.calculateFareLocally(
        rideRequest: _rideRequest,
        actualDistanceKm: actualDistance,
        actualDurationMins: durationMins,
        waitingCharge: 0.0, // We add waitingCharge manually later
      );

      double finalFare = (localResult['finalFare'] as num).toDouble();
      bool priceUpdated = localResult['priceUpdated'] as bool;
      String pricingReason = localResult['reason'] as String;

      debugPrint("BILLING_DEBUG: Local Result - Fare: $finalFare, Updated: $priceUpdated, Reason: $pricingReason");

      // Optional: If we still want to fetch toll information from Cloud, 
      // we could call it in the background or only if needed.
      // For now, we trust the local calculation for the base fare.
      bool tollCrossed = false;
      List<dynamic> tollZones = [];
      double tollCharge = 0.0;

      // If price was updated (distance changed), we might want to verify tolls via Cloud
      // but the user wants to avoid the "always calling" delay.
      // So we use the estimated toll from the original request as a baseline if distance matches.
      // Always include tolls if they were part of the initial request
      tollCharge = _rideRequest.tollPrice ?? 0.0;
      tollCrossed = tollCharge > 0;
      // ---------------------------------------------------------

      // Start Address Fetch in Parallel if location known
      Future<String?>? addressFuture;
      if (_driverLocation != null) {
        addressFuture = _getAddressFromLatLng(_driverLocation!);
      }

      debugPrint(
        "PRICING_DEBUG: totalWaitCharge=$totalWaitCharge, tollCharge=$tollCharge, baseDynamicFare (finalFare)=$finalFare",
      );
      final double totalAmountForUser = finalFare + totalWaitCharge + tollCharge;

      final Map<String, dynamic> updateData = {
        'status': 'completed',
        'rideFare': finalFare,
        'baseFare': finalFare,
        'totalFare': totalAmountForUser, // NEW: Added for dashboard earnings sync
        'waitingCharge': totalWaitCharge,
        'pickupWaitingCharge': pickupWait,
        'stopWaitingCharge': stopWait,
        'priceUpdated': priceUpdated,
        'tollCrossed': tollCrossed,
        'tollZonesCrossed': tollZones,
        'tollCharge': tollCharge,
        'completedAt': FieldValue.serverTimestamp(),
      };

      // Use the duration calculated earlier for pricing
      updateData['actualDuration'] = durationMins;
      updateData['actualDistance'] =
          actualDistance; // Also save distance explicitly

      RideRequest updatedRequest = _rideRequest;

      if (_driverLocation != null) {
        updateData['destinationLocation'] = GeoPoint(
          _driverLocation!.latitude,
          _driverLocation!.longitude,
        );

        updatedRequest = updatedRequest.copyWith(
          dropoffLocation: maps.LatLng(
            _driverLocation!.latitude,
            _driverLocation!.longitude,
          ),
        );

        // Wait for Address
        final address = (addressFuture != null) ? await addressFuture : null;

        if (address != null) {
          updateData['dropoffAddress'] = address;
          updateData['dropoffFullAddress'] = address;
          updatedRequest = updatedRequest.copyWith(dropoffFullAddress: address);
        }
      }

      updatedRequest = updatedRequest.copyWith(
        actualDuration: durationMins,
        actualDistance: actualDistance,
        waitingCharge: totalWaitCharge,
        tollPrice: tollCharge,
        rideFare: finalFare, // Store dynamic base portion
      );

      await _firestore
          .collection(collectionPath)
          .doc(_rideRequest.rideId)
          .update(updateData);

      // NEW: Check for back-to-back ride queuing
      final rideQueueService = RideQueueService();
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId != null) {
        final hasNextRide = await rideQueueService.hasQueuedRides(
          currentUserId,
        );

        if (hasNextRide) {
          debugPrint("[BackToBack] Next ride queued, auto-transitioning...");
          final nextRideId = await rideQueueService.popNextRide(currentUserId);
          if (nextRideId != null) {
            try {
              final nextRideDoc = await _firestore
                  .collection('ride_requests')
                  .doc(nextRideId)
                  .get();

              if (nextRideDoc.exists) {
                final nextRide = RideRequest.fromJson(nextRideDoc.data()!);

                if (mounted) {
                  debugPrint(
                    "[BackToBack] Auto-transitioning to next ride: $nextRideId",
                  );
                  Get.off(() => RideStartedScreen(rideRequest: nextRide));
                }
                return; // Don't show payment screen
              }
            } catch (e) {
              debugPrint("[BackToBack] Error fetching next ride: $e");
            }
          }
        }
      }

      // Regular payment screen flow (if no queued ride)
      if (mounted) {
        Get.off(
          () => RidePaymentScreen(
            rideRequest: updatedRequest,
            totalAmount: finalFare + totalWaitCharge + tollCharge,
            priceUpdated: priceUpdated,
            tollCrossed: tollCrossed,
            tollCharge: tollCharge,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        Get.snackbar(
          'Error',
          "Error ending ride: $e",
          snackPosition: SnackPosition.TOP,
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
            title: Text('rideStartedTitle'.tr),
            automaticallyImplyLeading: false,
            actions: [
              // Info Button logic
              PopupMenuButton(
                icon: const Icon(Icons.info_outline),
                itemBuilder: (context) {
                  // Calculate Duration - Handled by LiveRideTimer now

                  // Calculate Distance
                  String distanceString = "0.0 km";
                  if (_accumulatedDistance > 0) {
                    distanceString =
                        "${(_accumulatedDistance / 1000).toStringAsFixed(2)} km";
                  }

                  return <PopupMenuEntry<dynamic>>[
                    PopupMenuItem(
                      enabled: false,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${'timeElapsed'.tr}: ',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(
                                context,
                              ).textTheme.bodyLarge?.color,
                            ),
                          ),
                          LiveRideTimer(startedAt: _rideRequest.startedAt),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      enabled: false,
                      child: Text(
                        '${'distance'.tr}: $distanceString',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).textTheme.bodyLarge?.color,
                        ),
                      ),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      enabled: false,
                      child: Text(
                        '${'vehicle'.tr}: ${_rideRequest.vehicleClass}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).textTheme.bodyLarge?.color,
                        ),
                      ),
                    ),
                  ];
                },
              ),
            ],
          ),
          body: Stack(
            children: [
              maps.GoogleMap(
                initialCameraPosition: maps.CameraPosition(
                  target: _driverLocation ??
                      maps.LatLng(
                        _rideRequest.pickupLocation.latitude,
                        _rideRequest.pickupLocation.longitude,
                      ),
                  zoom: 14, // Slightly wider initial zoom
                ),
                mapType: maps.MapType.normal,
                onMapCreated: (maps.GoogleMapController controller) {
                  _controller.complete(controller);
                  _updateMarkers(); // Ensure markers are drawn immediately
                  // Immediately try to fit bounds if we have locations
                  if (_driverLocation != null && _dropLocation != null) {
                    _fitCameraToRoute(_driverLocation!, _dropLocation!);
                  } else {
                    // Fallback to ride request locations if driver loc not yet ready
                    final pickup = maps.LatLng(
                      widget.rideRequest.pickupLocation.latitude,
                      widget.rideRequest.pickupLocation.longitude,
                    );
                    final dropoff = maps.LatLng(
                      widget.rideRequest.dropoffLocation.latitude,
                      widget.rideRequest.dropoffLocation.longitude,
                    );
                    _fitCameraToRoute(pickup, dropoff);
                    // Also trigger route fetch if we are using fallback locations!
                    _getRoute(pickup, dropoff);
                  }
                },
                markers: _markers,
                polylines: _polylines,
                myLocationEnabled: true,
                myLocationButtonEnabled: true,
              ),

              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Navigate Button
                    FloatingActionButton.extended(
                      heroTag: 'ride_started_navigate_btn',
                      onPressed: _onNavigatePressed,
                      icon: const Icon(Icons.navigation),
                      label: Text('navigateBtn'.tr),
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    const SizedBox(height: 8),

                    // Bottom Sheet
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(20),
                        ),
                        boxShadow: const [
                          BoxShadow(color: Colors.black12, blurRadius: 10),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Customer Info
                          Row(
                            children: [
                              const CircleAvatar(child: Icon(Icons.person)),
                              const SizedBox(width: 10),
                              Text(
                                _customerName,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                onPressed: _makePhoneCall,
                                icon: const Icon(
                                  Icons.phone,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                          const Divider(),
                          // Destination Info
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Theme.of(context).dividerColor,
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.flag, color: Colors.red),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Builder(
                                    builder: (context) {
                                      final pendingStop =
                                          _rideRequest.stops
                                              .where((s) => s.isPending)
                                              .isNotEmpty
                                          ? _rideRequest.stops.firstWhere(
                                              (s) => s.isPending,
                                            )
                                          : null;

                                      String title = "";
                                      String address = "";

                                      if (pendingStop != null) {
                                        title = pendingStop.title;
                                        address = pendingStop.fullAddress;
                                      } else {
                                        title =
                                            _rideRequest.dropoffPlaceName ??
                                            _rideRequest.dropoffTitle;
                                        address =
                                            _rideRequest.dropoffFullAddress;
                                      }

                                      // Fallback if address is empty but we have fetched one
                                      if (address.isEmpty &&
                                          _fetchedAddress.isNotEmpty) {
                                        address = _fetchedAddress;
                                      }

                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if (title.isNotEmpty)
                                            Text(
                                              title,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                                color: Theme.of(
                                                  context,
                                                ).textTheme.bodyLarge?.color,
                                              ),
                                            ),
                                          Text(
                                            address,
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Theme.of(
                                                context,
                                              ).textTheme.bodySmall?.color,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Fare display
                          Row(
                            children: [
                              const Icon(
                                Icons.currency_rupee,
                                color: Colors.green,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                _rideRequest.rideType == 'rental'
                                    ? "${'packageRate'.tr}: ₹${_rideRequest.rideFare}"
                                    : "${'rideFare'.tr}: ₹${_rideRequest.rideFare}",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(
                                    context,
                                  ).textTheme.bodyLarge?.color,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // Distance display (Countdown / Remaining)
                          Row(
                            children: [
                              const Icon(
                                Icons.straighten,
                                color: Colors.blue,
                              ),
                              const SizedBox(width: 10),
                              Builder(
                                builder: (context) {
                                  double totalKm = _rideRequest.rideDistance;
                                  if (_rideRequest.rideType == 'rental' &&
                                      (_rideRequest.kmLimit ?? 0) > 0) {
                                    totalKm = _rideRequest.kmLimit!.toDouble();
                                  }

                                  double drivenKm = _accumulatedDistance / 1000.0;
                                  double remainingKm = totalKm - drivenKm;
                                  if (remainingKm < 0) remainingKm = 0;

                                  return Row(
                                    crossAxisAlignment: CrossAxisAlignment.baseline,
                                    textBaseline: TextBaseline.alphabetic,
                                    children: [
                                      Text(
                                        "${'remaining'.tr}: ${remainingKm.toStringAsFixed(1)} km",
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Theme.of(context).textTheme.bodyLarge?.color,
                                        ),
                                      ),
                                      if (totalKm > 0)
                                        Text(
                                          " / ${totalKm.toStringAsFixed(1)} km total",
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Theme.of(context).textTheme.bodySmall?.color,
                                          ),
                                        ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // Toll Display if applicable
                          if ((_rideRequest.tollPrice ?? 0) > 0)
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.orange.withAlpha(20),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.orange.withAlpha(100),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.directions, color: Colors.orange),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Toll Charges',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Theme.of(
                                              context,
                                            ).textTheme.bodySmall?.color,
                                          ),
                                        ),
                                        Text(
                                          '₹${_rideRequest.tollPrice!.toStringAsFixed(0)}',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.orange,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 10),
                          if (_isWaiting) ...[
                            Text(
                              (_waitTimeRemaining > 0)
                                  ? "${'freeWait'.tr}: ${_formatTime(_waitTimeRemaining)}"
                                  : "${'paidWait'.tr}: ${_formatTime(_paidWaitSeconds)}",
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: (_waitTimeRemaining > 0)
                                    ? Colors.orange
                                    : Colors.red,
                              ),
                            ),
                            if (_paidWaitSeconds > 0)
                              Text(
                                "+ ₹${((_paidWaitSeconds / 60).ceil() * 3)}",
                                style: const TextStyle(
                                  fontSize: 18,
                                  color: Colors.redAccent,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            const SizedBox(height: 10),
                          ] else if (_rideRequest.rideType == 'rental') ...[
                            // Metrics Row - Only show for rentals
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16.0),
                              child: Row(
                                children: [
                                  // Duration Box
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).cardColor,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Theme.of(context).dividerColor,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'duration'.tr,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Theme.of(
                                                context,
                                              ).textTheme.bodySmall?.color,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          _DurationDisplay(
                                            startedAt: _rideRequest.startedAt,
                                            limitHours:
                                                _rideRequest.durationHours,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  // Distance Box
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).cardColor,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Theme.of(context).dividerColor,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'distance'.tr,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Theme.of(
                                                context,
                                              ).textTheme.bodySmall?.color,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _buildDistanceString(),
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                              color: Theme.of(
                                                context,
                                              ).textTheme.bodyLarge?.color,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: RideStatusSlider(
                              key: ValueKey(
                                'slider_${_currentStopIndex}_$_isWaiting',
                              ),
                              label: _getSliderLabel(),
                              color: _isWaiting
                                  ? Colors.green
                                  : (_getSliderLabel() == 'End Ride'
                                        ? Colors.red
                                        : Colors.orange),
                              onSlideComplete: _handleSlideComplete,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (_isLoading)
                Container(
                  color: Colors.black54,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Colors.white),
                        SizedBox(height: 16),
                        Text(
                          'endingRide'.tr,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _getSliderLabel() {
    if (_isWaiting) {
      return 'continueRide'.tr;
    }
    // Check for any pending stop dynamically
    final pendingStopIndex = _rideRequest.stops.indexWhere((s) => s.isPending);
    if (pendingStopIndex != -1) {
      final stopNumber = pendingStopIndex + 1;
      return '${'arrivedAtStop'.tr} $stopNumber';
    }
    return 'endRide'.tr;
  }

  String _buildDistanceString() {
    final distKm = _accumulatedDistance / 1000.0;
    String text = "${distKm.toStringAsFixed(1)} km";
    if (_rideRequest.kmLimit != null && _rideRequest.kmLimit! > 0) {
      text += " / ${_rideRequest.kmLimit} km";
    }
    return text;
  }
}

class LiveRideTimer extends StatefulWidget {
  final DateTime? startedAt;

  const LiveRideTimer({super.key, required this.startedAt});

  @override
  State<LiveRideTimer> createState() => _LiveRideTimerState();
}

class _LiveRideTimerState extends State<LiveRideTimer> {
  late Timer _timer;
  String _durationString = "00:00:00";

  @override
  void initState() {
    super.initState();
    debugPrint("LiveRideTimer: initState, startedAt=${widget.startedAt}");
    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        _updateTime();
      }
    });
  }

  void _updateTime() {
    if (widget.startedAt != null) {
      final duration = DateTime.now().difference(widget.startedAt!);
      final hours = duration.inHours.toString().padLeft(2, '0');
      final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
      final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
      setState(() {
        _durationString = "$hours:$minutes:$seconds";
      });
    } else {
      setState(() {
        _durationString = "Not started";
      });
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _durationString,
      style: TextStyle(
        fontWeight: FontWeight.bold,
        color: Theme.of(context).textTheme.bodyLarge?.color,
      ),
    );
  }
}

class _DurationDisplay extends StatefulWidget {
  final DateTime? startedAt;
  final int? limitHours;

  const _DurationDisplay({required this.startedAt, this.limitHours});

  @override
  State<_DurationDisplay> createState() => _DurationDisplayState();
}

class _DurationDisplayState extends State<_DurationDisplay> {
  late Timer _timer;
  String _durationText = "--:--";

  @override
  void initState() {
    super.initState();
    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) _updateTime();
    });
  }

  void _updateTime() {
    if (widget.startedAt == null) return;
    final duration = DateTime.now().difference(widget.startedAt!);
    final h = duration.inHours;
    final m = (duration.inMinutes % 60).toString().padLeft(2, '0');
    // For space, maybe just H:MM or HH:MM
    // If > 0 hours, show 1:20 hr.

    // User requested format: "1:20 hr"
    String elapsed = "";
    if (h > 0) {
      elapsed = "$h:$m hr";
    } else {
      // If < 1 hour, maybe just mins? or 0:45 hr?
      // Let's stick to user example 1:20 hr
      elapsed = "0:$m hr";
    }

    if (widget.limitHours != null && widget.limitHours! > 0) {
      elapsed += " / ${widget.limitHours} hr";
    }

    setState(() {
      _durationText = elapsed;
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _durationText,
      style: TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 16,
        color: Theme.of(context).textTheme.bodyLarge?.color,
      ),
    );
  }
}
