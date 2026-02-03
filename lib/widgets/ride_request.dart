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
  final double? actualDistance;
  final double? actualDuration;

  final double waitingCharge;
  final double? paidByWallet; // Amount paid by wallet in a split payment

  final String? userName;

  RideRequest({
    required this.rideId,
    required this.userId,
    this.userName,
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
    this.actualDistance,
    this.actualDuration,
    this.waitingCharge = 0.0,
    this.paidByWallet,
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
    double? actualDistance,
    double? actualDuration,
    double? waitingCharge,
    double? paidByWallet,
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
      actualDistance: actualDistance ?? this.actualDistance,
      actualDuration: actualDuration ?? this.actualDuration,
      waitingCharge: waitingCharge ?? this.waitingCharge,
      paidByWallet: paidByWallet ?? this.paidByWallet,
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
      'actualDistance': actualDistance,
      'actualDuration': actualDuration,
      'waitingCharge': waitingCharge,
      'paidByWallet': paidByWallet,
    };
  }

  factory RideRequest.fromJson(Map<String, dynamic> json) {
    // Parse stops - check both 'stops' (Firestore) and 'intermediateStops' (legacy)
    var rawStops = json['stops'] ?? json['intermediateStops'];
    List<RideStop> parsedStops = [];
    if (rawStops != null && rawStops is List) {
      parsedStops = rawStops.map((s) {
        // Handle both direct lat/lng and nested location object
        double lat = 0.0;
        double lng = 0.0;

        if (s['location'] != null) {
          // Nested location object (legacy format)
          final loc = s['location'];
          lat = (loc['latitude'] as num?)?.toDouble() ?? 0.0;
          lng = (loc['longitude'] as num?)?.toDouble() ?? 0.0;
        } else {
          // Direct latitude/longitude fields (Firestore format)
          lat = (s['latitude'] as num?)?.toDouble() ?? 0.0;
          lng = (s['longitude'] as num?)?.toDouble() ?? 0.0;
        }

        return RideStop(
          title: s['address']?.split(',')[0] ?? 'Stop',
          fullAddress: s['address'] ?? '',
          location: LatLng(lat, lng),
          status: s['status'] ?? 'pending',
        );
      }).toList();
    }

    return RideRequest(
      rideId: json['rideId'] ?? '',
      userId: json['userId'] ?? '',
      userName: json['userName'] ?? '',
      pickupTitle:
          json['pickupTitle'] ??
          extractTitle(
            json['pickupAddress'] ?? json['pickupFullAddress'] ?? '',
          ),
      dropoffTitle:
          json['dropoffTitle'] ??
          extractTitle(
            json['destinationAddress'] ??
                json['dropoffAddress'] ??
                json['dropoffFullAddress'] ??
                '',
          ),
      pickupFullAddress:
          json['pickupFullAddress'] ?? json['pickupAddress'] ?? '',
      dropoffFullAddress:
          json['dropoffFullAddress'] ?? json['destinationAddress'] ?? '',
      driverDistance: (json['driverDistance'] as num? ?? 0).toDouble(),
      rideDistance: (json['rideDistance'] as num? ?? 0).toDouble(),
      rideFare: (json['totalFare'] ?? json['fare'] ?? json['rideFare'] ?? 0)
          .toDouble(),
      tip: (json['tip'] as num?)?.toDouble(),
      vehicleType: json['vehicleType'] ?? 'Car',
      pickupLocation: LatLng(
        (json['pickupLocation'] is Map)
            ? (json['pickupLocation']['lat'] as num? ?? 0).toDouble()
            : (json['pickupLocation'] as GeoPoint).latitude,
        (json['pickupLocation'] is Map)
            ? (json['pickupLocation']['lng'] as num? ?? 0).toDouble()
            : (json['pickupLocation'] as GeoPoint).longitude,
      ),
      dropoffLocation:
          ((json['destinationLocation'] ?? json['dropoffLocation']) != null)
          ? LatLng(
              ((json['destinationLocation'] ?? json['dropoffLocation']) is Map)
                  ? ((json['destinationLocation'] ??
                                    json['dropoffLocation'])['lat']
                                as num? ??
                            (json['destinationLocation'] ??
                                    json['dropoffLocation'])['latitude']
                                as num? ??
                            0)
                        .toDouble()
                  : ((json['destinationLocation'] ?? json['dropoffLocation'])
                            as GeoPoint)
                        .latitude,
              ((json['destinationLocation'] ?? json['dropoffLocation']) is Map)
                  ? ((json['destinationLocation'] ??
                                    json['dropoffLocation'])['lng']
                                as num? ??
                            (json['destinationLocation'] ??
                                    json['dropoffLocation'])['longitude']
                                as num? ??
                            0)
                        .toDouble()
                  : ((json['destinationLocation'] ?? json['dropoffLocation'])
                            as GeoPoint)
                        .longitude,
            )
          : LatLng(
              (json['pickupLocation'] is Map)
                  ? (json['pickupLocation']['lat'] as num? ?? 0).toDouble()
                  : (json['pickupLocation'] as GeoPoint).latitude,
              (json['pickupLocation'] is Map)
                  ? (json['pickupLocation']['lng'] as num? ?? 0).toDouble()
                  : (json['pickupLocation'] as GeoPoint).longitude,
            ),
      rideType: json['rideType'] ?? 'daily',
      stops: parsedStops,
      driverId: json['driverId'] ?? '',
      packageName: json['packageName'],
      durationHours: json['durationHours'],
      kmLimit: json['kmLimit'],
      extraHourCharge: json['extraHourCharge'],
      extraKmCharge: json['extraKmCharge'],
      driverDuration: (json['driverDuration'] as num?)?.toDouble(),
      rideDuration: (json['rideDuration'] as num?)?.toDouble(),
      convenienceFee: (json['convenienceFee'] as num?)?.toDouble() ?? 0.0,
      safetyPin: json['startRidePin'] ?? json['safetyPin'] ?? '',

      paymentMethod: json['paymentMethod'] ?? 'Cash',
      status: json['status'] ?? 'searching',
      vehicleClass: json['vehicleClass'] ?? 'Unknown',
      endRidePin: json['endRidePin'] ?? '',
      startedAt: (json['startedAt'] != null)
          ? (json['startedAt'] as Timestamp).toDate()
          : null,
      actualDistance: (json['actualDistance'] as num?)?.toDouble(),
      actualDuration: (json['actualDuration'] as num?)?.toDouble(),
      waitingCharge: (json['waitingCharge'] as num?)?.toDouble() ?? 0.0,
      paidByWallet:
          (json['paidByWallet'] as num?)?.toDouble() ??
          (json['walletAmountUsed'] as num?)?.toDouble(),
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

    // Strategy: Find "Chennai" (City) and take the part before it.
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

    // Fallback: Skip first part if it's digits or Plus Code
    String candidate = filteredParts[0].trim();
    final startsWithDigit = RegExp(r'^\d').hasMatch(candidate);

    if ((startsWithDigit || isPlusCode(candidate)) &&
        filteredParts.length > 1) {
      return filteredParts[1].trim();
    }

    // Fallback for Airport case: if first part contains 'Airport', try second part
    if (candidate.contains('Airport') && filteredParts.length > 1) {
      return filteredParts[1].trim();
    }

    return candidate;
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
      LocationService().getLocalizedAddress(
        widget.rideRequest.pickupLocation,
        langCode,
      ),
      LocationService().getLocalizedAddress(
        widget.rideRequest.dropoffLocation,
        langCode,
      ),
    ]);

    if (mounted) {
      setState(() {
        if (results[0] != null) {
          _translatedPickupAddress = results[0];
          _translatedPickupTitle = RideRequest.extractTitle(results[0]!);
        }
        if (results[1] != null) {
          _translatedDropoffAddress = results[1];
          _translatedDropoffTitle = RideRequest.extractTitle(results[1]!);
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
    _timer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _progressValue -= 0.01; // 1.0 / (5000ms / 50ms) -> 5 seconds duration
      });
      if (_progressValue <= 0) {
        // Round Robin Mode: Reject to pass to next driver
        timer.cancel(); // Stop timer
        widget.onReject();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Fix for "incorrect configuration id" crash on Android 14+ when resuming from background.
    // We create a FRESH MediaQueryData from the view to bypass stale inherited widgets.
    // We also forcefully reset the textScaler to 1.0 to avoid any invalid system configuration IDs.
    final mediaQueryData = MediaQueryData.fromView(
      View.of(context),
    ).copyWith(textScaler: const TextScaler.linear(1.0));

    return MediaQuery(
      data: mediaQueryData,
      child: Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        child: GestureDetector(
          onTap: widget.onAccept,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              boxShadow: [
                BoxShadow(
                  blurRadius: 15,
                  color: Colors.black.withValues(alpha: 0.3),
                ),
              ],
            ),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- Payment Method Header ---
                      Center(
                        child: Text(
                          widget.rideRequest.rideType == 'daily'
                              ? _getPaymentHeaderText()
                              : "${widget.rideRequest.vehicleClass} ${'rideHeader'.tr}",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _isTranslating
                          ? _buildShimmerRow()
                          : _buildDetailRow(
                              Icons.location_on,
                              _translatedPickupTitle ??
                                  widget.rideRequest.pickupTitle,
                              _translatedPickupAddress ??
                                  widget.rideRequest.pickupFullAddress,
                              "${widget.rideRequest.driverDistance.toStringAsFixed(1)} ${'kmAway'.tr}${(widget.rideRequest.driverDuration != null) ? " (~${widget.rideRequest.driverDuration!.toStringAsFixed(0)} ${'mins'.tr})" : ""}",
                            ),
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: 8.0,
                          horizontal: 12.0,
                        ),
                        child: Icon(
                          Icons.more_vert,
                          color: Colors.white54,
                          size: 20,
                        ),
                      ),
                      _isTranslating
                          ? _buildShimmerRow()
                          : _buildDetailRow(
                              Icons.flag,
                              _translatedDropoffTitle ??
                                  widget.rideRequest.dropoffTitle,
                              _translatedDropoffAddress ??
                                  widget.rideRequest.dropoffFullAddress,
                              "${widget.rideRequest.rideDistance.toStringAsFixed(1)} ${'kmRide'.tr}${(widget.rideRequest.rideDuration != null) ? " (~${widget.rideRequest.rideDuration!.toStringAsFixed(0)} ${'mins'.tr})" : ""}",
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
                      const Divider(height: 32, color: Colors.white54),
                      Center(
                        child: Column(
                          children: [
                            Text(
                              "₹${widget.rideRequest.rideFare.toStringAsFixed(2)}",
                              style: const TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            if (widget.rideRequest.tip != null &&
                                widget.rideRequest.tip! > 0) ...[
                              const SizedBox(height: 4),
                              Text(
                                "+ ₹${widget.rideRequest.tip!.toStringAsFixed(0)} Tip Included",
                                style: const TextStyle(
                                  color: Colors.greenAccent,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: widget.onReject,
                  ),
                ),
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
                      backgroundColor: Colors.blue.shade300,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Colors.white,
                      ),
                      minHeight: 6,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(
    IconData icon,
    String title,
    String fullAddress,
    String distanceInfo,
  ) {
    return Row(
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
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                fullAddress,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 14,
                ),
                maxLines: 4,
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
