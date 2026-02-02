import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

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
        height: 180,
        width: 180,
        alignment: OverlayAlignment.centerLeft,
        positionGravity: PositionGravity.auto,
        enableDrag: true,
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
    await sendDataToOverlay({'type': 'ride_request', 'data': rideData});
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

  @override
  void initState() {
    super.initState();
    debugPrint('_OverlayBubbleWidgetState: initState called');

    // Listen for data from main app
    FlutterOverlayWindow.overlayListener.listen((data) {
      debugPrint('_OverlayBubbleWidgetState: Received data: $data');
      if (data is Map && data['type'] == 'ride_request') {
        setState(() {
          _rideRequest = data['data'];
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    debugPrint(
      '_OverlayBubbleWidgetState: build called, _rideRequest=$_rideRequest',
    );

    return Material(
      color: Colors.transparent,
      child: _rideRequest != null
          ? _buildRideRequestOverlay()
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
          ),
        ),
      ),
    );
  }

  Widget _buildRideRequestOverlay() {
    debugPrint('_buildRideRequestOverlay: Building ride request UI');
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 15,
            spreadRadius: 3,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'New Ride Request',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text('Pickup: ${_rideRequest?['pickupTitle'] ?? 'Unknown'}'),
          Text('Drop: ${_rideRequest?['dropoffTitle'] ?? 'Unknown'}'),
          Text('Fare: ₹${_rideRequest?['rideFare'] ?? '0'}'),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () async {
                  debugPrint('_buildRideRequestOverlay: Reject pressed');
                  await FlutterOverlayWindow.shareData({
                    'action': 'reject',
                    'rideId': _rideRequest?['rideId'],
                  });
                  setState(() => _rideRequest = null);
                },
                child: const Text(
                  'Reject',
                  style: TextStyle(color: Colors.white),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                onPressed: () async {
                  debugPrint('_buildRideRequestOverlay: Accept pressed');
                  await FlutterOverlayWindow.shareData({
                    'action': 'accept',
                    'rideId': _rideRequest?['rideId'],
                  });
                  await FlutterOverlayWindow.closeOverlay();
                },
                child: const Text(
                  'Accept',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
