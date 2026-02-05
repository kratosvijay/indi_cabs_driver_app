import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:project_taxi_driver_app/utils/app_colors.dart';

@pragma("vm:entry-point")
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OverlayApp());
}

/* ---------------- APP ---------------- */

class OverlayApp extends StatelessWidget {
  const OverlayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: OverlayRoot(),
    );
  }
}

/* ---------------- STATE ---------------- */

enum OverlayMode { bubble, request }

class OverlayRoot extends StatefulWidget {
  const OverlayRoot({super.key});

  @override
  State<OverlayRoot> createState() => _OverlayRootState();
}

class _OverlayRootState extends State<OverlayRoot> {
  OverlayMode _mode = OverlayMode.bubble;
  Map<String, dynamic>? _ride;
  Timer? _timer;
  double _progress = 1.0;

  @override
  void initState() {
    super.initState();

    FlutterOverlayWindow.overlayListener.listen((data) {
      if (data is Map && data["type"] == "SHOW_REQUEST") {
        setState(() {
          _ride = data["ride"];
          _mode = OverlayMode.request;
        });
        _startTimer();
      }
    });
  }

  /* ---------------- Timer ---------------- */

  void _startTimer() {
    _timer?.cancel();
    _progress = 1;

    // 5 seconds timer: 50ms interval * 100 ticks = 5000ms
    _timer = Timer.periodic(const Duration(milliseconds: 50), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _progress -= 0.01);
      if (_progress <= 0) _reject();
    });
  }

  /* ---------------- Actions ---------------- */

  Future<void> _reject() async {
    _timer?.cancel();

    // Send Rejection Signal
    await FlutterOverlayWindow.shareData({
      "action": "REJECT",
      "rideId": _ride?['rideId'],
    });

    // Close overlay (which will trigger cleanup in service)
    await FlutterOverlayWindow.closeOverlay();

    if (mounted) {
      setState(() {
        _ride = null;
        _mode = OverlayMode.bubble;
      });
    }
  }

  Future<void> _accept() async {
    _timer?.cancel();

    await FlutterOverlayWindow.shareData({
      "action": "ACCEPT",
      "ride": _ride,
      "rideId": _ride?['rideId'],
      "rideType": _ride?['rideType'],
    });

    // Launch App explicitly
    FlutterForegroundTask.launchApp();
    await FlutterOverlayWindow.closeOverlay();
  }

  /* ---------------- UI ---------------- */

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: _mode == OverlayMode.request ? _fullScreenCard() : _bubble(),
    );
  }

  Widget _bubble() {
    return GestureDetector(
      onTap: () async {
        // Bring app to foreground
        FlutterForegroundTask.launchApp();
        await FlutterOverlayWindow.closeOverlay();
      },
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: ClipOval(
          child: Image.asset(
            'assets/logos/app_logo.png',
            width: 80,
            height: 80,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                color: Colors.amber,
                child: const Icon(Icons.local_taxi, size: 40),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _fullScreenCard() {
    // If resize failed, the window might be small (e.g., 200). Show a mini card in that case.
    if (MediaQuery.of(context).size.height < 400) {
      return _miniCard();
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _card(), // Rich card
      ),
    );
  }

  Widget _miniCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(16),
      ),
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            "New Ride Request!",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "₹${_ride?['rideFare'] ?? '0'}",
            style: const TextStyle(
              color: Colors.greenAccent,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
              ),
              onPressed: () {
                // Request main app to open
                FlutterOverlayWindow.shareData({"action": "OPEN_APP"});
              },
              child: const Text("Open App"),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card() {
    final ride = _ride;
    if (ride == null) return const SizedBox();

    // Determine Header text
    String headerText = "New Ride Request";
    final isRental = ride['rideType'] == 'rental';
    final vehicleClass = ride['vehicleClass'] ?? 'Unknown';

    // Logic matching RideRequestCard _getPaymentHeaderText
    final paymentMethod = ride['paymentMethod'] ?? 'Cash';
    final walletUsed = (ride['paidByWallet'] as num?)?.toDouble() ?? 0.0;

    if (isRental) {
      headerText = "$vehicleClass Rental";
    } else {
      // "Cash Payment", "Cash + Wallet", "Digital Payment" logic
      if (walletUsed > 0 || paymentMethod == 'Cash + Wallet') {
        headerText = "Cash + Wallet";
      } else if (paymentMethod.toLowerCase().contains('cash')) {
        headerText = "Cash Payment";
      } else {
        headerText = "Digital Payment";
      }
    }

    final stops = ride['stops'] as List?;
    final hasStops = stops != null && stops.isNotEmpty;

    // Distances
    final driverDist =
        (ride['driverDistance'] as num?)?.toDouble().toStringAsFixed(1) ??
        "0.0";
    final driverDur = (ride['driverDuration'] as num?)?.toDouble().toInt();
    final rideDist =
        (ride['rideDistance'] as num?)?.toDouble().toStringAsFixed(1) ?? "0.0";
    final rideDur = (ride['rideDuration'] as num?)?.toDouble().toInt();

    final pickupTitle = ride['pickupTitle'] ?? 'Pickup';
    final pickupAddress = ride['pickupFullAddress'] ?? '';
    final dropoffTitle = ride['dropoffTitle'] ?? 'Dropoff';
    final dropoffAddress = ride['dropoffFullAddress'] ?? '';

    return Container(
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
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. Header
                Center(
                  child: Text(
                    headerText,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // 2. Pickup
                _buildDetailRow(
                  Icons.location_on,
                  pickupTitle,
                  pickupAddress,
                  isRental
                      ? "Rental"
                      : "$driverDist km Away${driverDur != null ? " (~$driverDur mins)" : ""}",
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                  child: Icon(Icons.more_vert, color: Colors.white54, size: 16),
                ),

                // 3. Dropoff
                _buildDetailRow(
                  Icons.flag,
                  dropoffTitle,
                  dropoffAddress,
                  isRental
                      ? ""
                      : "$rideDist km Ride${rideDur != null ? " (~$rideDur mins)" : ""}",
                ),

                // 4. Stops (if any)
                if (hasStops) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
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
                            "${stops.length} Stops Added",
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
                            "+ ₹${stops.length * 30}",
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
                ],

                const SizedBox(height: 20),

                // 5. Price & Actions
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Price
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "₹${ride['rideFare'] ?? '0'}",
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        if (ride['tip'] != null && (ride['tip'] as num) > 0)
                          Text(
                            "+ ₹${ride['tip']} Tip",
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ),

                    // Actions
                    Row(
                      children: [
                        // Pass (Styled like TextButton in card)
                        TextButton(
                          onPressed: _reject,
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
                        // Accept
                        ElevatedButton.icon(
                          onPressed: _accept,
                          icon: const Icon(Icons.check_circle, size: 18),
                          label: const Text("Accept"),
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
              ],
            ),
          ),

          // Timer Progress Bar
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
              child: LinearProgressIndicator(
                value: _progress,
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
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              if (distanceInfo.isNotEmpty)
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
}
