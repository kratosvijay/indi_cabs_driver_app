import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:project_taxi_driver_app/screens/earnings.dart';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:project_taxi_driver_app/utils/app_colors.dart';
import 'package:flutter/services.dart';

class RideDetailsScreen extends StatefulWidget {
  final Ride ride;
  const RideDetailsScreen({super.key, required this.ride});

  @override
  State<RideDetailsScreen> createState() => _RideDetailsScreenState();
}

class _RideDetailsScreenState extends State<RideDetailsScreen> {
  final Set<Polyline> _polylines = {};
  final Set<Marker> _markers = {};
  late GoogleMapController _mapController;

  String? _pickupAddress;
  String? _dropoffAddress;
  bool _isLoadingAddress = false;

  @override
  void initState() {
    super.initState();
    _pickupAddress = widget.ride.pickupAddress;
    _dropoffAddress = widget.ride.dropoffAddress;
    _resolveAddresses(); // Attempt to fetch better addresses if needed
    _setupMap();
  }

  Future<void> _resolveAddresses() async {
    setState(() => _isLoadingAddress = true);

    // Check if we need to resolve pickup
    if (_shouldResolve(_pickupAddress)) {
      if (!_isZeroCoordinates(widget.ride.pickupLocation)) {
        final addr = await _getAddressFromLatLng(widget.ride.pickupLocation);
        if (addr != null && mounted) {
          setState(() => _pickupAddress = addr);
        }
      }
    }

    // Check if we need to resolve dropoff
    if (_shouldResolve(_dropoffAddress)) {
      if (!_isZeroCoordinates(widget.ride.dropoffLocation)) {
        final addr = await _getAddressFromLatLng(widget.ride.dropoffLocation);
        if (addr != null && mounted) {
          setState(() => _dropoffAddress = addr);
        }
      }
    }

    if (mounted) setState(() => _isLoadingAddress = false);
  }

  bool _shouldResolve(String? address) {
    if (address == null) return true;
    final lower = address.toLowerCase();
    // Check for coordinates pattern (numbers, comma, numbers)
    final isCoordinates =
        RegExp(r'^-?\d+\.\d+,\s*-?\d+\.\d+$').hasMatch(address) ||
        RegExp(r'^Lat:').hasMatch(address);

    return lower.contains('loading') ||
        lower.contains('unknown') ||
        lower.contains('getting') || // Added 'getting' check
        address.isEmpty ||
        isCoordinates;
  }

  bool _isZeroCoordinates(LatLng loc) {
    return loc.latitude.abs() < 0.0001 && loc.longitude.abs() < 0.0001;
  }

  Future<String?> _getAddressFromLatLng(LatLng position) async {
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

  void _setupMap() {
    if (!_isZeroCoordinates(widget.ride.pickupLocation)) {
      _markers.add(
        Marker(
          markerId: const MarkerId('pickup'),
          position: widget.ride.pickupLocation,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          infoWindow: const InfoWindow(title: "Pickup"),
        ),
      );
    }

    // Add Intermediate Stops
    for (int i = 0; i < widget.ride.stops.length; i++) {
      final stop = widget.ride.stops[i];
      if (!_isZeroCoordinates(stop.location)) {
        _markers.add(
          Marker(
            markerId: MarkerId('stop_$i'),
            position: stop.location,
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueOrange,
            ),
            infoWindow: InfoWindow(title: "Stop ${i + 1}", snippet: stop.title),
          ),
        );
      }
    }

    if (!_isZeroCoordinates(widget.ride.dropoffLocation)) {
      _markers.add(
        Marker(
          markerId: const MarkerId('dropoff'),
          position: widget.ride.dropoffLocation,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: "Drop-off"),
        ),
      );
    }

    // Build Polyline Points
    final List<LatLng> polylinePoints = [];
    if (!_isZeroCoordinates(widget.ride.pickupLocation)) {
      polylinePoints.add(widget.ride.pickupLocation);
    }
    for (var stop in widget.ride.stops) {
      if (!_isZeroCoordinates(stop.location)) {
        polylinePoints.add(stop.location);
      }
    }
    if (!_isZeroCoordinates(widget.ride.dropoffLocation)) {
      polylinePoints.add(widget.ride.dropoffLocation);
    }

    if (polylinePoints.length > 1) {
      _polylines.add(
        Polyline(
          polylineId: const PolylineId('ride_route'),
          points: polylinePoints,
          color: AppColors.primary,
          width: 5,
          geodesic: true,
        ),
      );
    }
  }

  void _fitBounds() {
    if (_markers.isEmpty) return;

    try {
      final pickup = widget.ride.pickupLocation;
      final dropoff = widget.ride.dropoffLocation;

      double minLat = pickup.latitude;
      double maxLat = pickup.latitude;
      double minLng = pickup.longitude;
      double maxLng = pickup.longitude;

      // Include dropoff
      if (dropoff.latitude < minLat) minLat = dropoff.latitude;
      if (dropoff.latitude > maxLat) maxLat = dropoff.latitude;
      if (dropoff.longitude < minLng) minLng = dropoff.longitude;
      if (dropoff.longitude > maxLng) maxLng = dropoff.longitude;

      // Include all stops
      for (var stop in widget.ride.stops) {
        if (stop.location.latitude < minLat) minLat = stop.location.latitude;
        if (stop.location.latitude > maxLat) maxLat = stop.location.latitude;
        if (stop.location.longitude < minLng) minLng = stop.location.longitude;
        if (stop.location.longitude > maxLng) maxLng = stop.location.longitude;
      }

      final bounds = LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      );

      _mapController.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
    } catch (e) {
      debugPrint("Error fitting bounds: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    // Pro Design Theme Colors
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF5F7FA);
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF2D3436);
    final subTextColor = isDark ? Colors.white60 : const Color(0xFF636E72);

    return Scaffold(
      backgroundColor: bgColor,
      body: CustomScrollView(
        slivers: [
          // 1. Pro Header with Map Background
          SliverAppBar(
            expandedHeight: 300.0,
            floating: false,
            pinned: true,
            backgroundColor: isDark ? Colors.black : AppColors.primary,
            elevation: 0,
            leading: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_back, color: Colors.white),
              ),
              onPressed: () => Get.back(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: widget.ride.pickupLocation,
                      zoom: 12,
                    ),
                    mapType: MapType.normal,
                    markers: _markers,
                    polylines: _polylines,
                    onMapCreated: (controller) {
                      _mapController = controller;
                      // small delay to let map layout before fitting bounds
                      Future.delayed(
                        const Duration(milliseconds: 600),
                        () => _fitBounds(),
                      );
                    },
                    zoomControlsEnabled: false,
                    mapToolbarEnabled: false,
                    myLocationButtonEnabled: false,
                  ),
                  // Gradient Overlay for readability at top
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 100,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.7),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Bottom curve decoration
                  Positioned(
                    bottom: -1,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 30,
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(30),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 2. Content Body
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status & Date Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: widget.ride.status == RideStatus.completed
                              ? Colors.green.withValues(alpha: 0.15)
                              : Colors.red.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: widget.ride.status == RideStatus.completed
                                ? Colors.green.withValues(alpha: 0.5)
                                : Colors.red.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              widget.ride.status == RideStatus.completed
                                  ? Icons.check_circle
                                  : Icons.cancel,
                              size: 16,
                              color: widget.ride.status == RideStatus.completed
                                  ? Colors.green
                                  : Colors.red,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              widget.ride.status.name.toUpperCase(),
                              style: TextStyle(
                                color:
                                    widget.ride.status == RideStatus.completed
                                    ? Colors.green
                                    : Colors.red,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        DateFormat(
                          'MMM d, yyyy • h:mm a',
                        ).format(widget.ride.timestamp),
                        style: TextStyle(
                          color: subTextColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Ride ID with Copy Button
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: widget.ride.id));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Ride ID copied to clipboard'),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: textColor.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "Ride ID: ${widget.ride.id}",
                            style: TextStyle(
                              color: subTextColor,
                              fontFamily: 'RobotoMono', // Monospace for ID
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.copy, size: 14, color: subTextColor),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Route Timeline Card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: isDark ? 0.3 : 0.05,
                          ),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        _buildTimelineRow(
                          context,
                          title: widget.ride.pickupPlaceName ?? "Pickup",
                          address: _pickupAddress ?? widget.ride.pickupAddress,
                          location: widget.ride.pickupLocation,
                          icon: Icons.my_location,
                          iconColor: Colors.green,
                          isFirst: true,
                          isLast: false,
                        ),
                        // Intermediate Stops
                        ...widget.ride.stops.asMap().entries.map((entry) {
                          final index = entry.key;
                          final stop = entry.value;
                          return _buildTimelineRow(
                            context,
                            title: "Stop ${index + 1}",
                            address: stop.fullAddress.isNotEmpty
                                ? stop.fullAddress
                                : stop.title,
                            location: stop.location,
                            icon: Icons.stop_circle_outlined,
                            iconColor: Colors.orange,
                            isFirst: false,
                            isLast: false,
                          );
                        }),
                        _buildTimelineRow(
                          context,
                          title: widget.ride.dropoffPlaceName ?? "Drop-off",
                          address:
                              _dropoffAddress ?? widget.ride.dropoffAddress,
                          location: widget.ride.dropoffLocation,
                          icon: Icons.location_on,
                          iconColor: Colors.red,
                          isFirst: false,
                          isLast: true,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Stats Overview (Earnings, Distance, Time)
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final width =
                          (constraints.maxWidth - 32) / 3; // 3 items with gaps
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildStatCard(
                            context,
                            "Earnings",
                            "₹${widget.ride.earnings.toStringAsFixed(0)}",
                            Icons.currency_rupee,
                            Colors.green,
                            width,
                            cardColor,
                          ),
                          _buildStatCard(
                            context,
                            "Distance",
                            "${widget.ride.distance.toStringAsFixed(1)} km",
                            Icons.directions_car_filled,
                            Colors.blue,
                            width,
                            cardColor,
                          ),
                          _buildStatCard(
                            context,
                            "Time",
                            widget.ride.time,
                            Icons.access_time_filled,
                            Colors.orange,
                            width,
                            cardColor,
                          ),
                        ],
                      );
                    },
                  ),

                  // Rental Details Section (if applicable)
                  if (widget.ride.rideType == 'rental' &&
                      widget.ride.packageName != null) ...[
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: isDark ? 0.3 : 0.05,
                            ),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Rental Details - ${widget.ride.packageName}",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                          const Divider(height: 24),
                          _buildRentalRow(
                            "Base Package Fare",
                            "Included in Fare",
                            textColor,
                            subTextColor,
                          ),
                          if ((widget.ride.extraTimeCost ?? 0) > 0)
                            _buildRentalRow(
                              "Extra Time Charges",
                              "₹${widget.ride.extraTimeCost!.toStringAsFixed(2)}",
                              textColor,
                              subTextColor,
                            ),
                          if ((widget.ride.extraDistanceCost ?? 0) > 0)
                            _buildRentalRow(
                              "Extra Km Charges",
                              "₹${widget.ride.extraDistanceCost!.toStringAsFixed(2)}",
                              textColor,
                              subTextColor,
                            ),
                          if ((widget.ride.tollPrice ?? 0) > 0) ...[
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.directions, color: Colors.orange, size: 18),
                                    const SizedBox(width: 8),
                                    Text(
                                      "Toll Charges",
                                      style: TextStyle(
                                        color: subTextColor,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  "₹${widget.ride.tollPrice!.toStringAsFixed(2)}",
                                  style: const TextStyle(
                                    color: Colors.orange,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          ],

                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "Total Earnings",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                ),
                              ),
                              Text(
                                "₹${widget.ride.earnings.toStringAsFixed(2)}",
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineRow(
    BuildContext context, {
    required String title,
    required String address,
    required LatLng location,
    required IconData icon,
    required Color iconColor,
    required bool isFirst,
    required bool isLast,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline Line & Icon
          Column(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          iconColor.withValues(alpha: 0.5),
                          Colors.grey.withValues(alpha: 0.2),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),
          // Text Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4), // Align with icon
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white54
                        : Colors.grey[500],
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                // Address logic
                Text(
                  _formatAddress(address, location),
                  style: TextStyle(
                    fontSize: 15,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : const Color(0xFF2D3436),
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                ),
                if (!isLast) const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatAddress(String address, LatLng loc) {
    if (_shouldResolve(address)) {
      if (_isLoadingAddress) return "Resolving location...";

      if (_isZeroCoordinates(loc)) {
        return "Location details not available";
      }

      // Fallback if still unknown
      return "${loc.latitude.toStringAsFixed(4)}, ${loc.longitude.toStringAsFixed(4)}";
    }
    return address;
  }

  Widget _buildStatCard(
    BuildContext context,
    String title,
    String value,
    IconData icon,
    Color color,
    double width,
    Color bgColor,
  ) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: color.withValues(alpha: 0.1), width: 1),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : const Color(0xFF2D3436),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white54
                  : Colors.grey[500],
              letterSpacing: 0.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildRentalRow(
    String label,
    String value,
    Color textColor,
    Color subTextColor,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: subTextColor, fontSize: 14)),
          Text(
            value,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
