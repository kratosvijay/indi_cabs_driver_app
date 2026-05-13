import 'dart:async';
import 'dart:ui';
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
    final totalSteps = (_totalDurationSeconds * 1000) / updateInterval.inMilliseconds;
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppColors.darkStart : Colors.white;
    final primaryTextColor = isDark ? Colors.white : Colors.black87;
    final secondaryTextColor = isDark ? Colors.white70 : Colors.black54;

    String packageDisplay = widget.rideRequest.packageName ?? "Rental Package";
    if (widget.rideRequest.durationHours != null && widget.rideRequest.kmLimit != null) {
      packageDisplay = "${widget.rideRequest.durationHours} Hours / ${widget.rideRequest.kmLimit} km Package";
    }

    return PopScope(
      canPop: false,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              // 1. Blurred Background
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.6),
                  ),
                ),
              ),

              // 2. Main Content
              SafeArea(
                child: Column(
                  children: [
                    // Top Progress Bar
                    LinearProgressIndicator(
                      value: _progressValue,
                      backgroundColor: Colors.white10,
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
                      minHeight: 6,
                    ),

                    Expanded(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24.0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: cardColor,
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.4),
                                  blurRadius: 30,
                                  offset: const Offset(0, 15),
                                ),
                              ],
                              border: isDark ? Border.all(color: Colors.white10) : null,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Header
                                  Center(
                                    child: Text(
                                      "${widget.rideRequest.vehicleClass} RENTAL".toUpperCase(),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? Colors.white.withValues(alpha: 0.9) : AppColors.primary,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 24),

                                  // Pickup
                                  _buildInfoRow(
                                    Icons.location_on,
                                    widget.rideRequest.pickupTitle,
                                    widget.rideRequest.pickupFullAddress,
                                    "${widget.rideRequest.driverDistance.toStringAsFixed(1)} km Away",
                                    primaryTextColor,
                                    secondaryTextColor,
                                    isDark,
                                    isPickup: true,
                                  ),

                                  const Padding(
                                    padding: EdgeInsets.only(left: 14, top: 4, bottom: 4),
                                    child: Icon(Icons.more_vert, color: Colors.grey, size: 20),
                                  ),

                                  // Package
                                  _buildInfoRow(
                                    Icons.work_history,
                                    widget.rideRequest.packageName ?? "Rental Package",
                                    packageDisplay,
                                    "Package Details",
                                    primaryTextColor,
                                    secondaryTextColor,
                                    isDark,
                                  ),

                                  const SizedBox(height: 32),
                                  const Divider(),
                                  const SizedBox(height: 24),

                                  // Price & Actions
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            "ESTIMATED FARE",
                                            style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold),
                                          ),
                                          Text(
                                            "₹${widget.rideRequest.rideFare.toStringAsFixed(0)}",
                                            style: TextStyle(
                                              fontSize: 36,
                                              fontWeight: FontWeight.bold,
                                              color: isDark ? Colors.greenAccent : AppColors.primary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 32),

                                  // Actions
                                  Row(
                                    children: [
                                      Expanded(
                                        child: SizedBox(
                                          height: 56,
                                          child: OutlinedButton(
                                            onPressed: widget.onPass,
                                            style: OutlinedButton.styleFrom(
                                              side: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                            ),
                                            child: Text("PASS", style: TextStyle(color: isDark ? Colors.white70 : Colors.grey.shade700, fontWeight: FontWeight.bold, fontSize: 16)),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: SizedBox(
                                          height: 56,
                                          child: ElevatedButton(
                                            onPressed: widget.onAccept,
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.green,
                                              foregroundColor: Colors.white,
                                              elevation: 0,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                            ),
                                            child: const Text("ACCEPT", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (widget.rideRequest.tip != null && widget.rideRequest.tip! > 0)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 24),
                                      child: Center(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                          decoration: BoxDecoration(
                                            color: Colors.green,
                                            borderRadius: BorderRadius.circular(12),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.green.withValues(alpha: 0.3),
                                                blurRadius: 10,
                                                offset: const Offset(0, 4),
                                              ),
                                            ],
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.card_giftcard, color: Colors.white, size: 20),
                                              const SizedBox(width: 10),
                                              Text(
                                                "Customer Added TIP: ₹${widget.rideRequest.tip!.toStringAsFixed(0)}",
                                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
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

  Widget _buildInfoRow(
    IconData icon,
    String title,
    String subtitle,
    String meta,
    Color primaryTextColor,
    Color secondaryTextColor,
    bool isDark, {
    bool isPickup = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark 
                ? (isPickup ? Colors.green.withValues(alpha: 0.15) : Colors.blue.withValues(alpha: 0.15))
                : (isPickup ? Colors.green.shade50 : Colors.blue.shade50),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: isPickup ? Colors.green : Colors.blue, size: 24),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(color: primaryTextColor, fontSize: 18, fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(color: secondaryTextColor, fontSize: 14, height: 1.4),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                meta,
                style: TextStyle(
                  color: isPickup ? (isDark ? Colors.greenAccent : Colors.green) : (isDark ? Colors.lightBlueAccent : Colors.blue),
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
