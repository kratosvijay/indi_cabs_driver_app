import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:project_taxi_driver_app/utils/app_colors.dart';
import 'package:project_taxi_driver_app/services/location_service.dart';
import 'package:get/get.dart';

class RideStop {
  final String title;
  final String fullAddress;
  final LatLng location;
  String status; // 'pending' or 'completed'

  RideStop({
    required this.title,
    required this.fullAddress,
    required this.location,
    this.status = 'pending',
  });

  bool get isPending => status == 'pending';
  bool get isCompleted => status == 'completed';
}

class RideRequest {
  final String rideId;
  final String userId;
  final String pickupTitle;
  final String dropoffTitle;
  final String pickupFullAddress;
  final String dropoffFullAddress;
  final double driverDistance; // in km
  final double rideDistance; // in km
  final double rideFare;
  final double? tip;
  final String vehicleType;
  final LatLng pickupLocation;
  final LatLng dropoffLocation;
  final String rideType; // 'daily' or 'multistop'
  final List<RideStop> stops;

  final String? driverId;
  final String? packageName;
  final int? durationHours;
  final int? kmLimit;
  final int? extraHourCharge;
  final int? extraKmCharge;
  final double? driverDuration; // in minutes
  final double? rideDuration; // in minutes

  final double convenienceFee;
  final String safetyPin;
  final String paymentMethod;
  final String status;
  final String vehicleClass;
  final String endRidePin;
  final DateTime? startedAt;
  final DateTime? createdAt; // Added for distributed timer logic
  final double? actualDistance;
  final double? accumulatedDistanceMeters;
  final double? actualDuration;

  final double waitingCharge;
  final double? paidByWallet; // Amount paid by wallet in a split payment
  final double? tollPrice; // Added toll price
  final double? surgeMultiplier; // **NEW** Added surge multiplier

  final String? userName;
  final String? pickupPlaceName; // **NEW**
  final String? dropoffPlaceName; // **NEW**

  RideRequest({
    required this.rideId,
    required this.userId,
    this.surgeMultiplier, // **NEW**
    this.userName,
    this.pickupPlaceName, // **NEW**
    this.dropoffPlaceName, // **NEW**
    required this.pickupTitle,
    required this.dropoffTitle,
    required this.pickupFullAddress,
    required this.dropoffFullAddress,
    required this.driverDistance,
    required this.rideDistance,
    required this.rideFare,
    this.tip,
    required this.vehicleType,
    required this.pickupLocation,
    required this.dropoffLocation,
    this.rideType = 'daily',
    this.stops = const [],
    this.driverId,
    this.packageName,
    this.durationHours,
    this.kmLimit,
    this.extraHourCharge,
    this.extraKmCharge,
    this.driverDuration,
    this.rideDuration,
    this.convenienceFee = 0.0,
    required this.safetyPin,
    required this.paymentMethod,
    required this.status,
    required this.vehicleClass,
    this.endRidePin = '',
    this.startedAt,
    this.createdAt,
    this.actualDistance,
    this.accumulatedDistanceMeters,
    this.actualDuration,
    this.waitingCharge = 0.0,
    this.paidByWallet,
    this.tollPrice,
  });

  RideRequest copyWith({
    String? rideId,
    String? userId,
    String? userName,
    String? pickupTitle,
    String? dropoffTitle,
    String? pickupFullAddress,
    String? dropoffFullAddress,
    double? driverDistance,
    double? rideDistance,
    double? rideFare,
    double? tip,
    String? vehicleType,
    LatLng? pickupLocation,
    LatLng? dropoffLocation,
    String? rideType,
    List<RideStop>? stops,
    String? driverId,
    String? packageName,
    int? durationHours,
    int? kmLimit,
    int? extraHourCharge,
    int? extraKmCharge,
    double? driverDuration,
    double? rideDuration,
    double? convenienceFee,
    String? safetyPin,
    String? paymentMethod,
    String? status,
    String? vehicleClass,
    String? endRidePin,
    DateTime? startedAt,
    DateTime? createdAt,
    double? actualDistance,
    double? accumulatedDistanceMeters,
    double? actualDuration,
    double? waitingCharge,
    double? paidByWallet,
    double? tollPrice,
  }) {
    return RideRequest(
      rideId: rideId ?? this.rideId,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      pickupTitle: pickupTitle ?? this.pickupTitle,
      dropoffTitle: dropoffTitle ?? this.dropoffTitle,
      pickupFullAddress: pickupFullAddress ?? this.pickupFullAddress,
      dropoffFullAddress: dropoffFullAddress ?? this.dropoffFullAddress,
      driverDistance: driverDistance ?? this.driverDistance,
      rideDistance: rideDistance ?? this.rideDistance,
      rideFare: rideFare ?? this.rideFare,
      tip: tip ?? this.tip,
      vehicleType: vehicleType ?? this.vehicleType,
      pickupLocation: pickupLocation ?? this.pickupLocation,
      dropoffLocation: dropoffLocation ?? this.dropoffLocation,
      rideType: rideType ?? this.rideType,
      stops: stops ?? this.stops,
      driverId: driverId ?? this.driverId,
      packageName: packageName ?? this.packageName,
      durationHours: durationHours ?? this.durationHours,
      kmLimit: kmLimit ?? this.kmLimit,
      extraHourCharge: extraHourCharge ?? this.extraHourCharge,
      extraKmCharge: extraKmCharge ?? this.extraKmCharge,
      driverDuration: driverDuration ?? this.driverDuration,
      rideDuration: rideDuration ?? this.rideDuration,
      convenienceFee: convenienceFee ?? this.convenienceFee,
      safetyPin: safetyPin ?? this.safetyPin,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      status: status ?? this.status,
      vehicleClass: vehicleClass ?? this.vehicleClass,
      endRidePin: endRidePin ?? this.endRidePin,
      startedAt: startedAt ?? this.startedAt,
      createdAt: createdAt ?? this.createdAt,
      actualDistance: actualDistance ?? this.actualDistance,
      accumulatedDistanceMeters:
          accumulatedDistanceMeters ?? this.accumulatedDistanceMeters,
      actualDuration: actualDuration ?? this.actualDuration,
      waitingCharge: waitingCharge ?? this.waitingCharge,
      paidByWallet: paidByWallet ?? this.paidByWallet,
      tollPrice: tollPrice ?? this.tollPrice,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'rideId': rideId,
      'userId': userId,
      'userName': userName,
      'pickupTitle': pickupTitle,
      'dropoffTitle': dropoffTitle,
      'pickupFullAddress': pickupFullAddress,
      'dropoffFullAddress': dropoffFullAddress,
      'driverDistance': driverDistance,
      'rideDistance': rideDistance,
      'rideFare': rideFare,
      'tip': tip,
      'vehicleType': vehicleType,
      'pickupLocation': {
        'lat': pickupLocation.latitude,
        'lng': pickupLocation.longitude,
      },
      'dropoffLocation': {
        'lat': dropoffLocation.latitude,
        'lng': dropoffLocation.longitude,
      },
      'rideType': rideType,
      'driverId': driverId,
      'packageName': packageName,
      'durationHours': durationHours,
      'kmLimit': kmLimit,
      'extraHourCharge': extraHourCharge,
      'extraKmCharge': extraKmCharge,
      'driverDuration': driverDuration,
      'rideDuration': rideDuration,
      'convenienceFee': convenienceFee,
      'safetyPin': safetyPin,
      'paymentMethod': paymentMethod,
      'status': status,
      'vehicleClass': vehicleClass,
      'endRidePin': endRidePin,
      'startedAt': startedAt != null ? Timestamp.fromDate(startedAt!) : null,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : null,
      'actualDistance': actualDistance,
      'accumulatedDistanceMeters': accumulatedDistanceMeters,
      'actualDuration': actualDuration,
      'waitingCharge': waitingCharge,
      'paidByWallet': paidByWallet,
      'tollPrice': tollPrice,
    };
  }

  factory RideRequest.fromJson(Map<String, dynamic> json) {
    // Parse stops - check both 'stops' (intermediateStops) and 'intermediateStops' (legacy)
    var rawStops = json['stops'] ?? json['intermediateStops'];
    List<RideStop> parsedStops = [];
    if (rawStops != null && rawStops is List) {
      parsedStops = rawStops.map((s) {
        // Stop might be a raw GeoPoint or a Map containing a GeoPoint/lat-lng
        double lat = 0.0;
        double lng = 0.0;
        String title = 'Stop';
        String fullAddress = '';
        String status = 'pending';

        if (s is GeoPoint) {
          lat = s.latitude;
          lng = s.longitude;
        } else if (s is Map) {
          if (s['location'] != null) {
            final loc = s['location'];
            if (loc is GeoPoint) {
              lat = loc.latitude;
              lng = loc.longitude;
            } else {
              // Nested location object (legacy format)
              lat =
                  (loc['latitude'] as num?)?.toDouble() ??
                  (loc['lat'] as num?)?.toDouble() ??
                  0.0;
              lng =
                  (loc['longitude'] as num?)?.toDouble() ??
                  (loc['lng'] as num?)?.toDouble() ??
                  0.0;
            }
          } else {
            // Direct latitude/longitude fields (Firestore format)
            lat = (s['latitude'] as num?)?.toDouble() ?? 0.0;
            lng = (s['longitude'] as num?)?.toDouble() ?? 0.0;
          }

          title = s['address']?.split(',')[0] ?? 'Stop';
          fullAddress = s['address'] ?? '';
          status = s['status'] ?? 'pending';
        }

        return RideStop(
          title: title,
          fullAddress: fullAddress,
          location: LatLng(lat, lng),
          status: status,
        );
      }).toList();
    }

    return RideRequest(
      rideId: json['rideId'] ?? '',
      userId: json['userId'] ?? '',
      userName: json['userName'],
      pickupTitle: json['pickupTitle'] ?? '',
      dropoffTitle: json['dropoffTitle'] ?? '',
      pickupFullAddress:
          json['pickupFullAddress'] ?? json['pickupAddress'] ?? '',
      dropoffFullAddress:
          json['dropoffFullAddress'] ??
          json['destinationAddress'] ??
          json['dropoffAddress'] ??
          '',
      pickupPlaceName: json['pickupPlaceName'], // **NEW**
      dropoffPlaceName:
          json['destinationPlaceName'] ?? json['dropoffPlaceName'], // **NEW**
      driverDistance: (json['driverDistance'] as num?)?.toDouble() ?? 0.0,
      rideDistance: (json['rideDistance'] as num?)?.toDouble() ?? 0.0,
      rideFare:
          (json['rideFare'] as num?)?.toDouble() ??
          (json['fare'] as num?)?.toDouble() ??
          0.0,
      tip: (json['tip'] as num?)?.toDouble(),
      vehicleType: json['vehicleType'] ?? '',
      pickupLocation: () {
        final loc = json['pickupLocation'];
        if (loc is GeoPoint) {
          return LatLng(loc.latitude, loc.longitude);
        } else if (loc is Map) {
          return LatLng(
            (loc['lat'] as num?)?.toDouble() ?? 0.0,
            (loc['lng'] as num?)?.toDouble() ?? 0.0,
          );
        }
        return const LatLng(0.0, 0.0);
      }(),
      dropoffLocation: () {
        final loc = json['dropoffLocation'];
        if (loc is GeoPoint) {
          return LatLng(loc.latitude, loc.longitude);
        } else if (loc is Map) {
          return LatLng(
            (loc['lat'] as num?)?.toDouble() ?? 0.0,
            (loc['lng'] as num?)?.toDouble() ?? 0.0,
          );
        }
        return const LatLng(0.0, 0.0);
      }(),
      rideType: json['rideType'] ?? 'daily',
      stops: parsedStops,
      driverId: json['driverId'],
      packageName: json['packageName'],
      durationHours: json['durationHours'],
      kmLimit: json['kmLimit'],
      extraHourCharge: json['extraHourCharge'],
      extraKmCharge: json['extraKmCharge'],
      driverDuration: (json['driverDuration'] as num?)?.toDouble(),
      rideDuration: (json['rideDuration'] as num?)?.toDouble(),
      convenienceFee: (json['convenienceFee'] as num?)?.toDouble() ?? 0.0,
      safetyPin: json['safetyPin'] ?? '',
      paymentMethod: json['paymentMethod'] ?? '',
      status: json['status'] ?? '',
      vehicleClass: json['vehicleClass'] ?? '',
      endRidePin: json['endRidePin'] ?? '',
      startedAt: (json['startedAt'] != null)
          ? (json['startedAt'] is Timestamp
                ? (json['startedAt'] as Timestamp).toDate()
                : null)
          : null,
      createdAt: (json['createdAt'] != null)
          ? (json['createdAt'] is Timestamp
                ? (json['createdAt'] as Timestamp).toDate()
                : null)
          : null,
      actualDistance: (json['actualDistance'] as num?)?.toDouble(),
      accumulatedDistanceMeters: (json['accumulatedDistanceMeters'] as num?)
          ?.toDouble(),
      actualDuration: (json['actualDuration'] as num?)?.toDouble(),
      waitingCharge: (json['waitingCharge'] as num?)?.toDouble() ?? 0.0,
      paidByWallet: (json['paidByWallet'] as num?)?.toDouble(),
      tollPrice: (json['tollPrice'] as num?)?.toDouble(),
    );
  }

  static String extractTitle(String address) {
    if (address.isEmpty) return '';
    final parts = address.split(',');
    if (parts.isEmpty) return address;

    // Helper to detect Google Plus Codes (format: XXXX+XXX or contains + with alphanumeric)
    bool isPlusCode(String s) {
      final trimmed = s.trim();
      // Plus codes are typically 4-8 chars, a +, then 2-4 chars
      // Examples: "9W4G+PV", "VXJV+8X2", "234R+R4 Chennai"
      final plusCodePattern = RegExp(
        r'^[A-Z0-9]{2,8}\+[A-Z0-9]{2,4}(\s|$)',
        caseSensitive: false,
      );
      return plusCodePattern.hasMatch(trimmed);
    }

    // Filter out Plus Code parts first
    final filteredParts = parts.where((p) => !isPlusCode(p.trim())).toList();
    if (filteredParts.isEmpty) {
      // If all parts are Plus Codes, try to use the full address minus the plus code
      return parts.length > 1 ? parts[1].trim() : address;
    }

    // Fallback strategy: Handle addresses starting with house numbers (e.g. "636, Balaji Dental...")
    String p1 = filteredParts[0].trim();
    final startsWithDigit = RegExp(r'^\d').hasMatch(p1);

    if (startsWithDigit && filteredParts.length > 1) {
      String p2 = filteredParts[1].trim();
      // If the second part contains alphabetic characters, it's likely the landmark/building name
      if (RegExp(r'[a-zA-Z]').hasMatch(p2)) {
        return p2;
      }
    }

    // Secondary Strategy: Find "Chennai" (City) and take the part before it.
    // SEARCH BACKWARDS to find the true City component (e.g. "Chennai", "Chennai - 600...")
    int cityIndex = -1;
    for (int i = filteredParts.length - 1; i >= 0; i--) {
      final p = filteredParts[i].trim().toLowerCase();
      if (p == 'chennai' ||
          p.startsWith('chennai ') ||
          p.startsWith('chennai-')) {
        cityIndex = i;
        break;
      }
    }

    if (cityIndex > 0) {
      final area = filteredParts[cityIndex - 1].trim();
      // Only use it if it's not a house number (digits) and not a Plus Code
      if (!RegExp(r'^\d').hasMatch(area) && !isPlusCode(area)) {
        return area;
      }
    }

    return p1;
  }
}

class RideRequestCard extends StatefulWidget {
  final RideRequest rideRequest;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const RideRequestCard({
    super.key,
    required this.rideRequest,
    required this.onAccept,
    required this.onReject,
  });

  @override
  State<RideRequestCard> createState() => _RideRequestCardState();
}

class _RideRequestCardState extends State<RideRequestCard> {
  late Timer _timer;
  double _progressValue = 1.0;
  String? _translatedPickupAddress;
  String? _translatedDropoffAddress;
  String? _translatedPickupTitle;
  String? _translatedDropoffTitle;
  bool _isTranslating = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
    final langCode = Get.locale?.languageCode ?? 'en';
    if (langCode != 'en') {
      _isTranslating = true;
    }
    _translateAddresses();
  }

  Future<void> _translateAddresses() async {
    final langCode = Get.locale?.languageCode ?? 'en';
    if (langCode == 'en') {
      return; // No need to translate if English (assuming default is English)
    }

    // Parallel fetch
    final results = await Future.wait([
      LocationService().getLocalizedLocationData(
        widget.rideRequest.pickupLocation,
        langCode,
      ),
      LocationService().getLocalizedLocationData(
        widget.rideRequest.dropoffLocation,
        langCode,
      ),
    ]);

    if (mounted) {
      setState(() {
        final pickupRes = results[0];
        final dropoffRes = results[1];

        if (pickupRes != null) {
          _translatedPickupAddress = pickupRes['address'];
          _translatedPickupTitle = pickupRes['name'];
        }
        if (dropoffRes != null) {
          _translatedDropoffAddress = dropoffRes['address'];
          _translatedDropoffTitle = dropoffRes['name'];
        }
        _isTranslating = false;
      });
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void _startTimer() {
    int totalSeconds = widget.rideRequest.rideType == 'rental'
        ? 10
        : 5; // aligned with backend
    int remainingMs = totalSeconds * 1000;

    if (remainingMs <= 0) {
      // Already expired
      remainingMs = 0;
      _progressValue = 0.0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onReject();
      });
      return;
    }

    // Set initial progress
    _progressValue = remainingMs / (totalSeconds * 1000);

    // Timer tick calculation
    const tickMs = 100;
    final decrement = tickMs / (totalSeconds * 1000);

    _timer = Timer.periodic(const Duration(milliseconds: tickMs), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        _progressValue -= decrement;
      });

      if (_progressValue <= 0) {
        timer.cancel();
        widget.onReject();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Fix for "incorrect configuration id" crash on Android 14+ when resuming from background.
    // We create a FRESH MediaQueryData from the view to bypass stale inherited widgets.
    // We also forcefully reset the textScaler to 1.0 to avoid any invalid system configuration IDs.

    // We will handle MediaQuery in the parent or assume context is fine.
    // For list usage, we don't want Positioned.

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            blurRadius: 15,
            color: Colors.black.withValues(alpha: 0.3),
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min, // Important for list items
              children: [
                // --- Payment Method Header ---
                Center(
                  child: Text(
                    widget.rideRequest.rideType == 'daily'
                        ? _getPaymentHeaderText()
                        : "${widget.rideRequest.vehicleClass} ${'rideHeader'.tr}",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _isTranslating
                    ? _buildShimmerRow()
                    : _buildDetailRow(
                        Icons.location_on,
                        _translatedPickupTitle ??
                            widget.rideRequest.pickupPlaceName ?? // **NEW**
                            widget.rideRequest.pickupTitle,
                        _translatedPickupAddress ??
                            widget.rideRequest.pickupFullAddress,
                        "${widget.rideRequest.driverDistance.toStringAsFixed(1)} ${'kmAway'.tr}${(widget.rideRequest.driverDuration != null) ? " (~${widget.rideRequest.driverDuration!.toStringAsFixed(0)} ${'mins'.tr})" : ""}",
                      ),
                const Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: 4.0,
                    horizontal: 12.0,
                  ),
                  child: Icon(Icons.more_vert, color: Colors.white54, size: 16),
                ),
                _isTranslating
                    ? _buildShimmerRow()
                    : Builder(
                        builder: (context) {
                          final pendingStop =
                              widget.rideRequest.stops
                                  .where((s) => s.isPending)
                                  .isNotEmpty
                              ? widget.rideRequest.stops.firstWhere(
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
                                _translatedDropoffTitle ??
                                widget.rideRequest.dropoffPlaceName ??
                                widget.rideRequest.dropoffTitle;
                            address =
                                _translatedDropoffAddress ??
                                widget.rideRequest.dropoffFullAddress;
                          }

                          return _buildDestinationRow(
                            Icons.flag,
                            title,
                            address,
                            "${widget.rideRequest.rideDistance.toStringAsFixed(1)} ${'kmRide'.tr}${(widget.rideRequest.rideDuration != null) ? " (~${widget.rideRequest.rideDuration!.toStringAsFixed(0)} ${'mins'.tr})" : ""}",
                          );
                        },
                      ),
                if (widget.rideRequest.stops.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.add_location_alt_outlined,
                          color: Colors.yellowAccent,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "${widget.rideRequest.stops.length} ${'stopsAdded'.tr}",
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.yellowAccent,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            "₹${widget.rideRequest.stops.length * 30} added",
                            style: const TextStyle(
                              color: Colors.black87,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                const Divider(height: 24, color: Colors.white24),

                // --- Footer: Price and Actions ---
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Price
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "₹${widget.rideRequest.rideFare.toStringAsFixed(0)}",
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        if (widget.rideRequest.tollPrice != null &&
                            widget.rideRequest.tollPrice! > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: Colors.orange.withValues(alpha: 0.5),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.directions,
                                    color: Colors.orange,
                                    size: 14,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    "Toll: ₹${widget.rideRequest.tollPrice!.toStringAsFixed(0)}",
                                    style: const TextStyle(
                                      color: Colors.orange,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (widget.rideRequest.surgeMultiplier != null &&
                            widget.rideRequest.surgeMultiplier! > 1.0)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              "Surge Active: ${widget.rideRequest.surgeMultiplier!.toStringAsFixed(1)}x",
                              style: const TextStyle(
                                color: Colors.yellowAccent,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        if (widget.rideRequest.tip != null &&
                            widget.rideRequest.tip! > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              "+ ₹${widget.rideRequest.tip!.toStringAsFixed(0)} Tip",
                              style: const TextStyle(
                                color: Colors.greenAccent,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),

                    // Buttons: Pass / Accept
                    Row(
                      children: [
                        // Pass Button
                        TextButton(
                          onPressed: widget.onReject,
                          style: TextButton.styleFrom(
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.1,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                          ),
                          child: const Text(
                            "Pass",
                            style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Accept Button (Tap the card triggers it, but explicit button is nice too)
                        ElevatedButton.icon(
                          onPressed: widget.onAccept,
                          icon: const Icon(Icons.check_circle, size: 18),
                          label: Text("Accept".tr),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 8),
              ],
            ),
          ),

          // Progress Bar (Timer)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(20),
              ),
              child: LinearProgressIndicator(
                value: _progressValue,
                backgroundColor: Colors.white.withValues(alpha: 0.1),
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                minHeight: 4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(
    IconData icon,
    String title,
    String fullAddress,
    String distanceInfo,
  ) {
    // If title and address are identical, don't show the redundant title
    final bool isTitleRedundant = title.trim() == fullAddress.trim();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.white, size: 28),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isTitleRedundant) ...[
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  fullAddress,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 14,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ] else
                Text(
                  fullAddress,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 16,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: 8),
              Text(
                distanceInfo,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDestinationRow(
    IconData icon,
    String title,
    String fullAddress,
    String distanceInfo,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 22,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  fullAddress,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 14,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Text(
                  distanceInfo,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmerRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 18,
                width: 120,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                height: 14,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 4),
              Container(
                height: 14,
                width: 180,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                height: 14,
                width: 100,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _getPaymentHeaderText() {
    final method = widget.rideRequest.paymentMethod; // e.g. "Cash"
    final walletUsed = widget.rideRequest.paidByWallet ?? 0.0;
    debugPrint("RideRequestCard: method=$method, walletUsed=$walletUsed");

    if (walletUsed > 0 || method == 'Cash + Wallet') {
      return "cashPlusWallet".tr;
    }
    if (method.toLowerCase() == 'cash') {
      return "cashPayment".tr;
    }
    return "digitalPayment".tr;
  }
}
