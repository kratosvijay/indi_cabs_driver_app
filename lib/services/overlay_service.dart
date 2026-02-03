import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:get/get.dart';
import 'package:project_taxi_driver_app/utils/app_colors.dart'; // Ensure this import is correct based on project structure
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

class OverlayService {
  static final OverlayService instance = OverlayService._internal();
  factory OverlayService() => instance;
  OverlayService._internal();

  bool _isOverlayActive = false;
  bool get isOverlayActive => _isOverlayActive;

  /// Request overlay permission from the user
  Future<bool> requestOverlayPermission() async {
    debugPrint('OverlayService: Checking permission...');
    final bool status = await FlutterOverlayWindow.isPermissionGranted();
    debugPrint('OverlayService: Permission status: $status');
    if (!status) {
      debugPrint('OverlayService: Requesting permission...');
      final bool? result = await FlutterOverlayWindow.requestPermission();
      debugPrint('OverlayService: Permission result: $result');
      return result ?? false;
    }
    return true;
  }

  /// Show floating bubble when app is minimized
  Future<void> showFloatingBubble() async {
    debugPrint(
      'OverlayService: showFloatingBubble called, _isOverlayActive=$_isOverlayActive',
    );

    // Check actual overlay status instead of relying only on our flag
    final isActuallyActive = await FlutterOverlayWindow.isActive();
    if (isActuallyActive) {
      debugPrint('OverlayService: Overlay is actually active, skipping');
      _isOverlayActive = true;
      return;
    }

    // Reset flag if it was out of sync
    if (_isOverlayActive && !isActuallyActive) {
      debugPrint('OverlayService: Flag was out of sync, resetting');
      _isOverlayActive = false;
    }

    final hasPermission = await requestOverlayPermission();
    debugPrint('OverlayService: Has permission: $hasPermission');

    if (!hasPermission) {
      debugPrint('OverlayService: Permission denied');
      return;
    }

    try {
      debugPrint('OverlayService: Calling FlutterOverlayWindow.showOverlay...');
      await FlutterOverlayWindow.showOverlay(
        height: 200,
        width: 200,
        alignment: OverlayAlignment.centerLeft,
        positionGravity: PositionGravity.auto,
        enableDrag: true,
        flag: OverlayFlag.defaultFlag,
        overlayTitle: "Driver App",
        overlayContent: "Tap to open",
      );
      _isOverlayActive = true;
      debugPrint(
        'OverlayService: Overlay shown successfully, _isOverlayActive=$_isOverlayActive',
      );
    } catch (e) {
      debugPrint('OverlayService: Error showing overlay: $e');
      rethrow;
    }
  }

  /// Hide floating bubble
  Future<void> hideFloatingBubble() async {
    debugPrint(
      'OverlayService: hideFloatingBubble called, _isOverlayActive=$_isOverlayActive',
    );
    // Always try to close and reset flag to ensure sync
    try {
      await FlutterOverlayWindow.closeOverlay();
    } catch (e) {
      debugPrint('OverlayService: Error closing overlay: $e');
    }
    _isOverlayActive = false;
    debugPrint('OverlayService: Overlay hidden, flag reset');
  }

  /// Send data to overlay (e.g., ride request)
  Future<void> sendDataToOverlay(Map<String, dynamic> data) async {
    await FlutterOverlayWindow.shareData(data);
  }

  /// Show ride request notification overlay
  Future<void> showRideRequestOverlay(Map<String, dynamic> rideData) async {
    debugPrint('OverlayService: showRideRequestOverlay called');

    // Calculate dynamic dimensions
    double screenWidth = Get.width;
    double screenHeight = Get.height;

    // Safety fallback
    if (screenWidth == 0) screenWidth = 400;
    if (screenHeight == 0) screenHeight = 844;

    // Target: 90% width, fixed height appropriate for card
    final targetWidth = (screenWidth * 0.9).toInt();
    final targetHeight = 550; // Enough for the content

    // CHECK ACTUAL STATE: The overlay might have closed itself (e.g. timeout)
    // without the main isolate knowing.
    bool isActive = await FlutterOverlayWindow.isActive();

    if (!isActive) {
      debugPrint('OverlayService: Overlay inactive, showing new window');
      await FlutterOverlayWindow.showOverlay(
        height: targetHeight,
        width: targetWidth,
        alignment: OverlayAlignment.center,
        positionGravity: PositionGravity.auto,
        enableDrag: true,
        flag: OverlayFlag.defaultFlag,
        overlayTitle: "New Ride Request",
        overlayContent: "You have a new ride request",
      );
      _isOverlayActive = true;
    } else {
      debugPrint(
        'OverlayService: Overlay already active, sending data to resize',
      );
      // We do NOT call resizeOverlay here anymore to avoid race conditions.
      // The OverlayBubbleWidget listener receives the data and resizes itself.
    }

    // Send data
    await sendDataToOverlay({
      'type': 'ride_request',
      'data': rideData,
      'width': targetWidth,
      'height': targetHeight,
    });
  }
}

/// Overlay entry point - this runs in a separate isolate
@pragma("vm:entry-point")
void overlayMain() {
  debugPrint('overlayMain: ENTRY POINT CALLED');
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('overlayMain: WidgetsFlutterBinding initialized');
  runApp(const OverlayBubbleApp());
  debugPrint('overlayMain: runApp called');
}

/// Simple overlay app that shows a floating bubble
class OverlayBubbleApp extends StatelessWidget {
  const OverlayBubbleApp({super.key});

  @override
  Widget build(BuildContext context) {
    debugPrint('OverlayBubbleApp: build called');
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const OverlayBubbleWidget(),
    );
  }
}

/// The actual bubble widget
class OverlayBubbleWidget extends StatefulWidget {
  const OverlayBubbleWidget({super.key});

  @override
  State<OverlayBubbleWidget> createState() => _OverlayBubbleWidgetState();
}

class _OverlayBubbleWidgetState extends State<OverlayBubbleWidget> {
  Map<String, dynamic>? _rideRequest;
  Timer? _timer;
  double _progressValue = 1.0;

  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    debugPrint('_OverlayBubbleWidgetState: initState called');

    // Listen for data from main app
    _subscription = FlutterOverlayWindow.overlayListener.listen((data) async {
      debugPrint('_OverlayBubbleWidgetState: Received data: $data');
      if (!mounted) return;
      if (data is Map && data['type'] == 'ride_request') {
        final width = (data['width'] as num?)?.toInt() ?? 500;
        final height = (data['height'] as num?)?.toInt() ?? 600;

        // Expand window for card - use passed dimensions
        try {
          await FlutterOverlayWindow.resizeOverlay(width, height, true);
        } catch (e) {
          debugPrint("Error resizing overlay: $e");
        }

        if (mounted) {
          setState(() {
            _rideRequest = data['data'];
            _startTimer(); // Start timer when request arrives
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _progressValue = 1.0;
    _timer?.cancel();
    // 5 seconds timer: 50ms interval * 100 ticks = 5000ms
    _timer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _progressValue -= 0.01;
      });
      if (_progressValue <= 0) {
        timer.cancel();
        if (mounted) {
          _rejectRide(); // Auto reject
        }
      }
    });
  }

  Future<void> _rejectRide() async {
    debugPrint('_rejectRide: Auto-rejecting or user rejected');
    _timer?.cancel();

    // Send rejection data
    await FlutterOverlayWindow.shareData({
      'action': 'reject',
      'rideId': _rideRequest?['rideId'],
    });

    // Close immediately - DO NOT resize to bubble
    await FlutterOverlayWindow.closeOverlay();

    // We don't nullify _rideRequest here because the window is closing anyway,
    // and we want to avoid a frame where it turns into a bubble or empty state.
  }

  Future<void> _acceptRide() async {
    debugPrint('_acceptRide: Accepted');
    _timer?.cancel();

    // 1. Launch App IMMEDIATELY
    FlutterForegroundTask.launchApp();

    // 2. Backup: Save to SharedPreferences (Fire and Forget)
    SharedPreferences.getInstance()
        .then((prefs) {
          if (_rideRequest != null && _rideRequest!['rideId'] != null) {
            prefs.setString(
              'details_accepted_ride_id',
              _rideRequest!['rideId'],
            );
            debugPrint(
              "Overlay: Saved accepted ride ID to prefs: ${_rideRequest!['rideId']}",
            );
          }
        })
        .catchError((e) {
          debugPrint("Overlay: Error saving prefs: $e");
        });

    // 3. Fallback: Send Standard Stream Data
    await FlutterOverlayWindow.shareData({
      'action': 'accept',
      'rideId': _rideRequest?['rideId'],
    });

    // 4. DO NOT close overlay here.
    // The main app will close it when it resumes.
    // The main app will close it when it resumes and processes the acceptance.
    // The main app's lifecycle listener (didChangeAppLifecycleState) in HomePageController
    // or main.dart will detect 'resumed' and close the overlay.
    // Closing it here causes a race condition and potential ANR/Crash.
  }

  @override
  Widget build(BuildContext context) {
    debugPrint(
      '_OverlayBubbleWidgetState: build called, _rideRequest=$_rideRequest',
    );

    return Material(
      color: Colors.transparent,
      child: _rideRequest != null
          ? _buildRequestCard()
          : _buildFloatingBubble(),
    );
  }

  Widget _buildFloatingBubble() {
    debugPrint('_buildFloatingBubble: Building bubble UI');
    return GestureDetector(
      onTap: () async {
        debugPrint('_buildFloatingBubble: Bubble tapped!');
        // Bring the main app to foreground, then close overlay
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

  Widget _buildRequestCard() {
    // Determine Header Text similar to app
    String headerText = "New Ride Request";
    if (_rideRequest != null) {
      final method = _rideRequest!['paymentMethod'] ?? 'Cash';
      final walletUsed =
          (_rideRequest!['paidByWallet'] as num?)?.toDouble() ?? 0.0;

      if (widgetIsRental) {
        headerText = "${_rideRequest!['vehicleClass'] ?? 'Car'} Rental";
      } else if (walletUsed > 0 || method == 'Cash + Wallet') {
        headerText = "Cash + Wallet"; // Simplified translation
      } else if (method.toLowerCase().contains('cash')) {
        headerText = "Cash Payment";
      } else {
        headerText = "Digital Payment";
      }
    }

    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(blurRadius: 15, color: Colors.black.withValues(alpha: 0.3)),
        ],
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
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
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 2. Pickup Location
                _buildDetailRow(
                  Icons.location_on,
                  _rideRequest?['pickupTitle'] ?? 'Pickup',
                  _rideRequest?['pickupFullAddress'] ?? '',
                  widgetIsRental
                      ? "Rental"
                      : "${(_rideRequest?['driverDistance']?.toStringAsFixed(1)) ?? '0.0'} km Away",
                ),

                // Connector Dots (Visual only, inside column for simplicity or absolute)
                const Padding(
                  padding: EdgeInsets.only(left: 11.0, top: 4, bottom: 4),
                  child: Icon(Icons.more_vert, color: Colors.white54, size: 20),
                ),

                // 3. Dropoff Location
                _buildDetailRow(
                  Icons.flag,
                  _rideRequest?['dropoffTitle'] ?? 'Dropoff',
                  _rideRequest?['dropoffFullAddress'] ?? '',
                  widgetIsRental
                      ? ""
                      : "${(_rideRequest?['rideDistance']?.toStringAsFixed(1)) ?? '0.0'} km Ride",
                ),

                const Divider(height: 32, color: Colors.white54),

                // 4. Fare
                Center(
                  child: Column(
                    children: [
                      Text(
                        "₹${_rideRequest?['rideFare'] ?? '0'}",
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        "Includes Tip", // Assuming tip logic is handled in fare or simplified for overlay
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 5. Buttons
                _buildActionButtons(),
              ],
            ),
          ),

          // Close Button (Top Right)
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: _rejectRide, // Treat close as reject/dismiss
            ),
          ),

          // Progress Bar (Bottom)
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
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                minHeight: 6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool get widgetIsRental => _rideRequest?['rideType'] == 'rental';

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

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey.shade800,
              foregroundColor: Colors.white, // Text color
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: _rejectRide,
            child: const Text(
              'Pass',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green, // Accept color
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: _acceptRide,
            child: const Text(
              'Accept',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }
}
