import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show IsolateNameServer;
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:project_taxi_driver_app/utils/app_colors.dart';
import 'package:project_taxi_driver_app/widgets/rental_overlay_card.dart';

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
      await FlutterOverlayWindow.resizeOverlay(80, 80, true);
    } catch (e) {
      debugPrint("Resize bubble failed in overlay isolate: $e");
    }
  }

  /* ---------------- Timer ---------------- */

  void _startTimer() {
    _timer?.cancel();

    int totalSeconds = _ride?['rideType'] == 'rental' ? 10 : 5;
    int remainingMs = totalSeconds * 1000;

    final createdAtMs = _ride?['createdAt'] as int?;
    if (createdAtMs != null) {
      final createdAt = DateTime.fromMillisecondsSinceEpoch(createdAtMs);
      final elapsed = DateTime.now().difference(createdAt);
      remainingMs = (totalSeconds * 1000) - elapsed.inMilliseconds;
    }

    if (remainingMs <= 0) {
      _progress = 0;
      _reject();
      return;
    }

    _progress = remainingMs / (totalSeconds * 1000);

    const tickMs = 100;
    final decrement = tickMs / (totalSeconds * 1000); // Decrement per tick

    _timer = Timer.periodic(const Duration(milliseconds: tickMs), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _progress = (_progress - decrement).clamp(0.0, 1.0);
      });
      if (_progress <= 0) {
        t.cancel();
        _reject();
      }
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
              // blurRadius: 1,
              // spreadRadius: 0,
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
        final isDark = MediaQuery.of(context).platformBrightness == Brightness.dark;
        final maxCardHeight = math.max(260.0, constraints.maxHeight - 24);
        return Align(
          alignment: Alignment.topCenter,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: math.min(560, constraints.maxWidth),
                  maxHeight: maxCardHeight,
                ),
                child: Stack(
                  children: [
                    _ride?['rideType'] == 'rental'
                        ? RentalOverlayCard(
                            ride: _ride!,
                            onAccept: _accept,
                            onReject: _reject,
                          )
                        : SingleChildScrollView(child: _card()),
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
                          backgroundColor: isDark 
                              ? Colors.white.withValues(alpha: 0.1)
                              : Colors.grey.shade100,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isDark ? Colors.white : AppColors.primary,
                          ),
                          minHeight: 4,
                        ),
                      ),
                    ),
                  ],
                ),
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
        final isDark = MediaQuery.of(context).platformBrightness == Brightness.dark;
        final cardColor = isDark ? AppColors.darkStart : Colors.white;
        final primaryTextColor = isDark ? Colors.white : Colors.black87;

        final isTiny =
            constraints.maxHeight < 140 || constraints.maxWidth < 140;
        final actionWidth = constraints.maxWidth.isFinite
            ? (constraints.maxWidth - 16).clamp(150.0, 260.0).toDouble()
            : 240.0;
        final content = Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "New Ride Request!",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: primaryTextColor,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "₹${_ride?['rideFare'] ?? '0'}",
              style: TextStyle(
                color: isDark ? Colors.greenAccent : Colors.green.shade700,
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
                        foregroundColor: primaryTextColor,
                        side: BorderSide(
                          color: isDark ? Colors.white54 : Colors.grey.shade400,
                        ),
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
                child: Text(
                  "Open App",
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.blue.shade700,
                  ),
                ),
              ),
            ),
          ],
        );

        return Container(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(16),
            border: isDark ? null : Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 10,
              ),
            ],
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
    final tollPrice = (ride['tollPrice'] as num?)?.toDouble() ?? 0.0;

    if (isRental) {
      headerText = "$vehicleClass REQUEST";
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
    final pickupArea = ride['pickupArea'] as String?; // **NEW**
    final pickupAddress = ride['pickupFullAddress'] ?? '';
    final dropoffTitle = ride['dropoffTitle'] ?? 'Dropoff';
    final dropoffArea = ride['dropoffArea'] as String?; // **NEW**
    final dropoffAddress = ride['dropoffFullAddress'] ?? '';

    final isDark = MediaQuery.of(context).platformBrightness == Brightness.dark;
    final cardColor = isDark ? AppColors.darkStart : Colors.white;
    final primaryTextColor = isDark ? Colors.white : Colors.black87;
    final secondaryTextColor = isDark ? Colors.white70 : Colors.black54;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            blurRadius: 15,
            color: Colors.black.withValues(alpha: 0.15),
            offset: const Offset(0, 4),
          ),
        ],
        border: isDark ? null : Border.all(color: Colors.grey.shade200, width: 1),
      ),
      child: Padding(
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
                  color: isDark ? Colors.white.withValues(alpha: 0.9) : AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 2. Pickup
            _buildDetailRow(
              Icons.location_on,
              pickupTitle,
              pickupAddress,
              pickupArea, // **NEW**
              isRental
                  ? "Rental"
                  : "$driverDist km Away${driverDur != null ? " (~$driverDur mins)" : ""}",
              primaryTextColor,
              secondaryTextColor,
              isDark,
            ),

            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
              child: Icon(Icons.more_vert, color: secondaryTextColor.withValues(alpha: 0.5), size: 16),
            ),

            // 3. Dropoff
            _buildDetailRow(
              Icons.flag,
              dropoffTitle,
              dropoffAddress,
              dropoffArea, // **NEW**
              isRental
                  ? ""
                  : "$rideDist km Ride${rideDur != null ? " (~$rideDur mins)" : ""}",
              primaryTextColor,
              secondaryTextColor,
              isDark,
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
                  color: isDark ? Colors.white.withValues(alpha: 0.15) : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark ? Colors.white.withValues(alpha: 0.3) : Colors.orange.shade200,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.add_location_alt_outlined,
                      color: isDark ? Colors.yellowAccent : Colors.orange.shade700,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "${stops.length} Stops Added",
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
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
                        color: isDark ? Colors.yellowAccent : Colors.orange.shade700,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        "+ ₹${stops.length * 30}",
                        style: TextStyle(
                          color: isDark ? Colors.black87 : Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            Divider(height: 24, color: isDark ? Colors.white24 : Colors.grey.shade200),

            // 5. Price & Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Price & Badges
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                    Text(
                      "₹${ride['rideFare'] ?? '0'}",
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : AppColors.primary,
                      ),
                    ),
                    if (tollPrice > 0)
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
                              const Icon(
                                Icons.directions,
                                color: Colors.orange,
                                size: 14,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                "Toll: ₹${tollPrice.toStringAsFixed(0)}",
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
                    if (ride['surgeMultiplier'] != null &&
                        (ride['surgeMultiplier'] as num) > 1.0)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          "Surge Active: ${(ride['surgeMultiplier'] as num).toStringAsFixed(1)}x",
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Actions
                Row(
                  children: [
                    // Pass (Styled like TextButton in card)
                    TextButton(
                      onPressed: _reject,
                      style: TextButton.styleFrom(
                        backgroundColor: isDark 
                            ? Colors.white.withValues(alpha: 0.1)
                            : Colors.grey.shade100,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                      child: Text(
                        "Pass",
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.grey.shade600,
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
            if (ride['tip'] != null && (ride['tip'] as num) > 0)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.green.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.card_giftcard,
                          color: Colors.white,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "Customer Added TIP: ₹${(ride['tip'] as num).toStringAsFixed(0)}",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(
    IconData icon,
    String title,
    String fullAddress,
    String? area,
    String distanceInfo,
    Color primaryColor,
    Color secondaryColor,
    bool isDark,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: isDark ? Colors.white : AppColors.primary, size: 28),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: primaryColor,
                  fontSize: 18,
                ),
              ),
              if (area != null && area.isNotEmpty && area != title) ...[
                const SizedBox(height: 2),
                Text(
                  area,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: primaryColor.withValues(alpha: 0.8),
                    fontSize: 15,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 2),
              Text(
                fullAddress,
                style: TextStyle(
                  color: secondaryColor,
                  fontSize: 14,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              if (distanceInfo.isNotEmpty)
                Text(
                  distanceInfo,
                  style: TextStyle(
                    color: primaryColor,
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
