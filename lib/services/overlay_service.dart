import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:project_taxi_driver_app/utils/app_colors.dart';
import 'package:project_taxi_driver_app/widgets/pro_library.dart';

class OverlayService extends GetxService {
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

    if (_isOverlayActive) {
      debugPrint('OverlayService: Overlay already active, skipping');
      return;
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
        height: 150,
        width: 150,
        alignment: OverlayAlignment.centerRight,
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
    if (!_isOverlayActive) return;
    await FlutterOverlayWindow.closeOverlay();
    _isOverlayActive = false;
    debugPrint('OverlayService: Overlay hidden');
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
  Get.put(OverlayController());
  runApp(const OverlayApp());
}

class OverlayController extends GetxController {
  final rideRequest = Rxn<Map<String, dynamic>>();

  @override
  void onInit() {
    super.onInit();
    // Listen for data from main app
    FlutterOverlayWindow.overlayListener.listen((data) {
      if (data['type'] == 'ride_request') {
        rideRequest.value = data['data'];
      }
    });
  }
}

class OverlayApp extends GetView<OverlayController> {
  const OverlayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      home: Material(
        color: Colors.transparent,
        child: Obx(
          () => controller.rideRequest.value != null
              ? _buildRideRequestOverlay(context)
              : _buildFloatingBubble(context),
        ),
      ),
    );
  }

  Widget _buildFloatingBubble(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        // Open main app when bubble is tapped
        await FlutterOverlayWindow.closeOverlay();
      },
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: AppColors.getAppBarGradient(context),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: const Icon(Icons.local_taxi, color: Colors.white, size: 50),
      ),
    );
  }

  Widget _buildRideRequestOverlay(BuildContext context) {
    final request = controller.rideRequest.value;
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.local_taxi,
                  color: AppColors.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'New Ride Request',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildInfoRow(
            Icons.location_on,
            'Pickup',
            request?['pickupTitle'] ?? 'Unknown',
          ),
          const SizedBox(height: 8),
          _buildInfoRow(
            Icons.flag,
            'Drop',
            request?['dropoffTitle'] ?? 'Unknown',
          ),
          const SizedBox(height: 8),
          _buildInfoRow(
            Icons.attach_money,
            'Fare',
            '₹${request?['rideFare'] ?? '0'}',
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ProButton(
                  text: 'Reject',
                  onPressed: () async {
                    // Send reject action
                    await FlutterOverlayWindow.shareData({
                      'action': 'reject',
                      'rideId': request?['rideId'],
                    });
                    controller.rideRequest.value = null;
                  },
                  backgroundColor: Colors.red,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ProButton(
                  text: 'Accept',
                  onPressed: () async {
                    // Send accept action and close overlay
                    await FlutterOverlayWindow.shareData({
                      'action': 'accept',
                      'rideId': request?['rideId'],
                    });
                    await FlutterOverlayWindow.closeOverlay();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(fontSize: 14, color: Colors.grey),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
