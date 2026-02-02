import 'dart:async';
import 'package:flutter/material.dart';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:project_taxi_driver_app/widgets/ride_request.dart';

class RentalRequestScreen extends StatefulWidget {
  final RideRequest rideRequest;
  final VoidCallback onAccept;
  final VoidCallback onPass;

  const RentalRequestScreen({
    super.key,
    required this.rideRequest,
    required this.onAccept,
    required this.onPass,
  });

  @override
  State<RentalRequestScreen> createState() => _RentalRequestScreenState();
}

class _RentalRequestScreenState extends State<RentalRequestScreen> {
  late Timer _timer;
  double _progressValue = 1.0;
  final int _totalDurationSeconds = 10;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void _startTimer() {
    const updateInterval = Duration(milliseconds: 100);
    // Total steps = 10s * 1000ms / 100ms = 100 steps
    final totalSteps =
        (_totalDurationSeconds * 1000) / updateInterval.inMilliseconds;
    final decrement = 1.0 / totalSteps;

    _timer = Timer.periodic(updateInterval, (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _progressValue -= decrement;
      });

      if (_progressValue <= 0) {
        timer.cancel();
        widget.onPass();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Construct package display string
    String packageDisplay = widget.rideRequest.packageName ?? "Rental Package";
    if (widget.rideRequest.durationHours != null &&
        widget.rideRequest.kmLimit != null) {
      packageDisplay =
          "${widget.rideRequest.durationHours} Hours / ${widget.rideRequest.kmLimit} km";
    }

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black, // Fallback background
        body: Stack(
          children: [
            // Background (Could be map or dark gradient)
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black87, Colors.black],
                ),
              ),
            ),

            // Main Content
            SafeArea(
              child: Column(
                children: [
                  // Progress Indicator
                  LinearProgressIndicator(
                    value: _progressValue,
                    backgroundColor: Colors.white12,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Colors.greenAccent,
                    ),
                    minHeight: 4,
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title
                          Center(
                            child: Text(
                              widget.rideRequest.vehicleType == "ActingDriver"
                                  ? "ACTING DRIVER REQUEST"
                                  : "RENTAL REQUEST",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Content Card
                          Expanded(
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // Map Preview
                                  Container(
                                    height: 140, // Reduced height to fit
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: Colors.white54),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Colors.black26,
                                          blurRadius: 8,
                                          offset: Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: GoogleMap(
                                        initialCameraPosition: CameraPosition(
                                          target:
                                              widget.rideRequest.pickupLocation,
                                          zoom: 15.0,
                                        ),
                                        mapType: MapType.normal,
                                        markers: {
                                          Marker(
                                            markerId: const MarkerId('pickup'),
                                            position: widget
                                                .rideRequest
                                                .pickupLocation,
                                            icon:
                                                BitmapDescriptor.defaultMarkerWithHue(
                                                  BitmapDescriptor.hueRed,
                                                ),
                                          ),
                                        },
                                        zoomControlsEnabled: false,
                                        scrollGesturesEnabled: false,
                                        zoomGesturesEnabled: false,
                                        myLocationButtonEnabled: false,
                                        rotateGesturesEnabled: false,
                                        tiltGesturesEnabled: false,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),

                                  // Driver Approach Info (Distance & Time)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white24,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.directions_car,
                                          color: Colors.white70,
                                          size: 16,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          "${widget.rideRequest.driverDistance.toStringAsFixed(1)} Km • ${widget.rideRequest.driverDuration?.toStringAsFixed(0) ?? '0'} mins away",
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),

                                  // Pickup Address
                                  Text(
                                    widget.rideRequest.pickupTitle,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.rideRequest.pickupFullAddress,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 14,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),

                                  const Divider(
                                    height: 32,
                                    color: Colors.white24,
                                  ),

                                  // Package Details
                                  const Text(
                                    "PACKAGE",
                                    style: TextStyle(
                                      color: Colors.white54,
                                      fontSize: 12,
                                      letterSpacing: 2,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    packageDisplay,
                                    style: const TextStyle(
                                      color: Colors.lightBlueAccent,
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),

                                  const SizedBox(height: 16),

                                  // Price
                                  const Text(
                                    "Minimum Fare",
                                    style: TextStyle(
                                      color: Colors.white54,
                                      fontSize: 12,
                                      letterSpacing: 2,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "₹${widget.rideRequest.rideFare.toStringAsFixed(0)}",
                                    style: const TextStyle(
                                      color: Colors.greenAccent,
                                      fontSize: 40,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Buttons
                          Row(
                            children: [
                              // PASS Button
                              Expanded(
                                child: SizedBox(
                                  height: 56,
                                  child: ElevatedButton(
                                    onPressed: widget.onPass,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red.withValues(
                                        alpha: 0.2,
                                      ),
                                      foregroundColor: Colors.redAccent,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        side: const BorderSide(
                                          color: Colors.redAccent,
                                        ),
                                      ),
                                      elevation: 0,
                                    ),
                                    child: const Text(
                                      "PASS",
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 24),
                              // ACCEPT Button
                              Expanded(
                                child: SizedBox(
                                  height: 56,
                                  child: ElevatedButton(
                                    onPressed: widget.onAccept,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      elevation: 4,
                                    ),
                                    child: const Text(
                                      "ACCEPT",
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
