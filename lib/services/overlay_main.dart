import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show IsolateNameServer;
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
  static const String _actionPortName = 'overlay_action_port';
  OverlayMode _mode = OverlayMode.bubble;
  Map<String, dynamic>? _ride;
  Timer? _timer;
  double _progress = 1.0;
  bool _actionInFlight = false;

  @override
  void initState() {
    super.initState();

    FlutterOverlayWindow.overlayListener.listen((data) {
      if (data is! Map) return;
      final type = data["type"]?.toString();

      if (type == "SHOW_REQUEST") {
        final int? widthHint = (data["overlayWidth"] is num)
            ? (data["overlayWidth"] as num).toInt()
            : null;
        final int? heightHint = (data["overlayHeight"] is num)
            ? (data["overlayHeight"] as num).toInt()
            : null;

        setState(() {
          _ride = Map<String, dynamic>.from(data["ride"] as Map? ?? const {});
          _mode = OverlayMode.request;
        });
        _startTimer();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _resizeForRequest(widthHint: widthHint, heightHint: heightHint);
        });
        return;
      }

      if (type == "SHOW_BUBBLE") {
        _timer?.cancel();
        _progress = 1.0;
        setState(() {
          _ride = null;
          _mode = OverlayMode.bubble;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _resizeForBubble();
        });
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sendActionToMain({"action": "OVERLAY_READY"});
    });
  }

  Future<void> _sendActionToMain(Map<String, dynamic> payload) async {
    try {
      final sendPort = IsolateNameServer.lookupPortByName(_actionPortName);
      if (sendPort != null) {
        sendPort.send(payload);
        return;
      }
    } catch (e) {
      debugPrint("Overlay action port send failed: $e");
    }

    // Fallback path for builds where IsolateNameServer bridge is unavailable.
    try {
      await FlutterOverlayWindow.shareData(payload);
    } catch (e) {
      debugPrint("Overlay fallback shareData failed: $e");
    }
  }

  Future<void> _resizeForRequest({int? widthHint, int? heightHint}) async {
    if (!mounted) return;

    final mediaSize = MediaQuery.of(context).size;
    final int targetWidth =
        widthHint ?? (mediaSize.width - 24).clamp(280.0, 420.0).round();
    final int targetHeight =
        heightHint ?? (mediaSize.height * 0.62).clamp(320.0, 540.0).round();

    try {
      await FlutterOverlayWindow.resizeOverlay(
        targetWidth,
        targetHeight,
        false,
      );
    } catch (e) {
      debugPrint("Resize overlay failed in overlay isolate: $e");
    }
  }

  Future<void> _resizeForBubble() async {
    try {
      await FlutterOverlayWindow.resizeOverlay(88, 88, false);
    } catch (e) {
      debugPrint("Resize bubble failed in overlay isolate: $e");
    }
  }

  /* ---------------- Timer ---------------- */

  void _startTimer() {
    _timer?.cancel();
    _progress = 1;

    const totalSeconds = 5;
    const tickMs = 100;
    const decrement = tickMs / (totalSeconds * 1000);
    _timer = Timer.periodic(const Duration(milliseconds: tickMs), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _progress = (_progress - decrement).clamp(0.0, 1.0));
      if (_progress <= 0) _reject();
    });
  }

  /* ---------------- Actions ---------------- */

  Future<void> _reject() async {
    if (_actionInFlight) return;
    _actionInFlight = true;
    _timer?.cancel();

    try {
      await _sendActionToMain({"action": "REJECT", "rideId": _ride?['rideId']});
      if (mounted) {
        setState(() {
          _ride = null;
          _mode = OverlayMode.bubble;
        });
      }
      await _resizeForBubble();
    } catch (e) {
      debugPrint("Overlay reject flow failed: $e");
    } finally {
      _actionInFlight = false;
    }
  }

  Future<void> _accept() async {
    if (_actionInFlight) return;
    _actionInFlight = true;
    _timer?.cancel();

    try {
      await _sendActionToMain({
        "action": "ACCEPT",
        "ride": _ride,
        "rideId": _ride?['rideId'],
        "rideType": _ride?['rideType'],
      });

      FlutterForegroundTask.launchApp();
    } catch (e) {
      debugPrint("Overlay accept flow failed: $e");
    } finally {
      _actionInFlight = false;
    }
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
        await _sendActionToMain({"action": "OPEN_APP"});
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
    if (MediaQuery.of(context).size.height < 400 ||
        MediaQuery.of(context).size.width < 280) {
      return _miniCard();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxCardHeight = math.max(260.0, constraints.maxHeight - 24);
        return Align(
          alignment: Alignment.topCenter,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 28, 12, 8),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: math.min(560, constraints.maxWidth),
                  maxHeight: maxCardHeight,
                ),
                child: SingleChildScrollView(child: _card()),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _miniCard() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isTiny =
            constraints.maxHeight < 140 || constraints.maxWidth < 140;
        final actionWidth = constraints.maxWidth.isFinite
            ? (constraints.maxWidth - 16).clamp(150.0, 260.0).toDouble()
            : 240.0;
        final content = Column(
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
              width: actionWidth,
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      onPressed: _reject,
                      child: const Text("Pass"),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      onPressed: _accept,
                      child: const Text("Accept"),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: actionWidth,
              child: TextButton(
                onPressed: () {
                  _sendActionToMain({"action": "OPEN_APP"});
                },
                child: const Text(
                  "Open App",
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ),
          ],
        );

        return Container(
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(16),
          ),
          width: double.infinity,
          height: double.infinity,
          padding: const EdgeInsets.all(12),
          child: Center(
            child: isTiny
                ? FittedBox(fit: BoxFit.scaleDown, child: content)
                : SingleChildScrollView(child: content),
          ),
        );
      },
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
