import 'dart:async';
import 'package:flutter/material.dart';

import 'package:project_taxi_driver_app/utils/app_colors.dart';
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

    final String vehicleClass = widget.rideRequest.vehicleClass;
    final String pickupTitle = widget.rideRequest.pickupTitle;
    final String pickupAddress = widget.rideRequest.pickupFullAddress;
    final String driverDist = widget.rideRequest.driverDistance.toStringAsFixed(
      1,
    );
    final String driverDur =
        widget.rideRequest.driverDuration?.toStringAsFixed(0) ?? "0";
    final String rideFare = widget.rideRequest.rideFare.toStringAsFixed(0);

    return PopScope(
      canPop: false,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              // Background - Dark Gradient
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black87, Colors.black],
                  ),
                ),
              ),

              // Heavy overlay pattern or image could go here if needed

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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24.0,
                          vertical: 16.0,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const SizedBox(height: 16),
                            // Title
                            Text(
                              "$vehicleClass REQUEST".toUpperCase(),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.95),
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.5,
                              ),
                            ),
                            const SizedBox(height: 32),

                            // Main Card
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.5),
                                    blurRadius: 20,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                                border: Border.all(color: Colors.white12),
                              ),
                              child: Column(
                                children: [
                                  // Package Info Box
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                      horizontal: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.08,
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: Colors.white10),
                                    ),
                                    child: Column(
                                      children: [
                                        Text(
                                          "RENTAL PACKAGE",
                                          style: TextStyle(
                                            color: Colors.white60,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: 1,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          packageDisplay,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Colors.lightBlueAccent,
                                            fontSize: 22, // Slightly larger
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 24),

                                  // Pickup Location Row
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(
                                        Icons.location_on,
                                        color: Colors.greenAccent,
                                        size: 32,
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              pickupTitle,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              pickupAddress,
                                              style: TextStyle(
                                                color: Colors.white70,
                                                fontSize: 15,
                                                height: 1.3,
                                              ),
                                              maxLines: 3,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 12),

                                            // Distance Tag
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 6,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withValues(
                                                  alpha: 0.1,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                "$driverDist km Away • ~$driverDur mins",
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 32),

                                  const Divider(
                                    height: 1,
                                    color: Colors.white10,
                                  ),
                                  const SizedBox(height: 24),

                                  // Price Section
                                  const Text(
                                    "ESTIMATED EARNINGS",
                                    style: TextStyle(
                                      color: Colors.white54,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "₹$rideFare",
                                    style: const TextStyle(
                                      fontSize: 48,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.greenAccent,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const Spacer(),

                            // Action Buttons
                            Row(
                              children: [
                                // PASS Button
                                Expanded(
                                  child: SizedBox(
                                    height: 60,
                                    child: OutlinedButton(
                                      onPressed: widget.onPass,
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.white70,
                                        side: const BorderSide(
                                          color: Colors.white24,
                                          width: 1.5,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                      ),
                                      child: const Text(
                                        "PASS",
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 1,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 20),
                                // ACCEPT Button
                                Expanded(
                                  child: SizedBox(
                                    height: 60,
                                    child: ElevatedButton(
                                      onPressed: widget.onAccept,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        foregroundColor: Colors.white,
                                        elevation: 8,
                                        shadowColor: Colors.green.withValues(
                                          alpha: 0.4,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                      ),
                                      child: const Text(
                                        "ACCEPT",
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 1,
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
      ),
    );
  }
}
