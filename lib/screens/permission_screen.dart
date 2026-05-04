import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:project_taxi_driver_app/screens/onboarding.dart'; // Added OnboardingScreen import
import 'package:project_taxi_driver_app/utils/app_colors.dart';
import 'package:project_taxi_driver_app/widgets/pro_library.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_overlay_window/flutter_overlay_window.dart';

class PermissionScreen extends StatefulWidget {
  const PermissionScreen({super.key});

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen>
    with WidgetsBindingObserver {
  bool _isLoading = false;
  bool _locationGranted = false;
  bool _notificationGranted = false;
  bool _overlayGranted = false;
  bool _batteryGranted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check permissions when user returns from settings
    if (state == AppLifecycleState.resumed) {
      _checkStatus();
    }
  }

  Future<void> _checkStatus() async {
    // Check initial status
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse) {
      setState(() => _locationGranted = true);
    }

    // Notification permission check is trickier on Android < 13 without request,
    // but we can assume false or just let the button handle it.

    // Check Overlay Permission
    bool overlayStatus = await FlutterOverlayWindow.isPermissionGranted();
    if (overlayStatus) {
      setState(() => _overlayGranted = true);
    }

    // Check Battery Optimization
    bool isIgnoringBattery =
        await Permission.ignoreBatteryOptimizations.isGranted;
    if (isIgnoringBattery) {
      setState(() => _batteryGranted = true);
    }
  }

  Future<void> _requestLocation() async {
    if (_locationGranted) return;

    // Show prominent disclosure before requesting permission
    final bool? accepted = await _showLocationDisclosure();
    if (accepted != true) return;

    try {
      LocationPermission permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse) {
        if (mounted) setState(() => _locationGranted = true);
      } else if (permission == LocationPermission.deniedForever) {
        await Geolocator.openAppSettings();
      }
    } catch (e) {
      debugPrint('Error requesting location permission: $e');
    }
  }

  Future<bool?> _showLocationDisclosure() async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        final bool isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: isDark ? const Color(0xFF2C2C2C) : Colors.white,
          title: Row(
            children: [
              Icon(Icons.location_on, color: AppColors.primary),
              const SizedBox(width: 10),
              const Text("Location Usage"),
            ],
          ),
          content: const Text(
            "Indicabs Partner collects location data to enable nearby ride matching and trip tracking features even when the app is closed or not in use.\n\n"
            "This data is also used for calculating trip distances and ensuring driver/passenger safety.",
            style: TextStyle(fontSize: 15, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                "Deny",
                style: TextStyle(
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text("Accept"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _requestNotification() async {
    if (_notificationGranted) return;

    try {
      NotificationSettings settings = await FirebaseMessaging.instance
          .requestPermission(
            alert: true,
            announcement: false,
            badge: true,
            carPlay: false,
            criticalAlert: false,
            provisional: false,
            sound: true,
          );

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        if (mounted) setState(() => _notificationGranted = true);
      }
    } catch (e) {
      debugPrint('Error requesting notification permission: $e');
    }
  }

  Future<void> _requestOverlay() async {
    if (_overlayGranted) {
      debugPrint('Overlay: Already granted, skipping');
      return;
    }

    debugPrint('Overlay: Requesting permission...');
    try {
      // Don't await - requestPermission opens settings and never returns properly
      // The lifecycle observer (didChangeAppLifecycleState) will re-check status
      FlutterOverlayWindow.requestPermission();

      // Wait a brief moment then re-check (user may have already granted)
      await Future.delayed(const Duration(milliseconds: 500));
      bool overlayStatus = await FlutterOverlayWindow.isPermissionGranted();
      debugPrint('Overlay: Quick check status: $overlayStatus');
      if (overlayStatus && mounted) {
        setState(() => _overlayGranted = true);
      }
    } catch (e) {
      debugPrint('Error requesting overlay permission: $e');
    }
    debugPrint('Overlay: Request complete, _overlayGranted=$_overlayGranted');
  }

  Future<void> _requestBattery() async {
    if (_batteryGranted) return;

    try {
      PermissionStatus status = await Permission.ignoreBatteryOptimizations
          .request();
      if (status.isGranted) {
        if (mounted) setState(() => _batteryGranted = true);
      } else if (status.isPermanentlyDenied) {
        openAppSettings();
      } else {
        debugPrint('Battery optimization denied');
        Get.snackbar(
          'Optimization Required',
          'Please disable battery optimization to ensure consistent GPS tracking.',
          backgroundColor: Colors.orange,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    } catch (e) {
      debugPrint('Error requesting battery permission: $e');
      Get.snackbar(
        'Error',
        'Could not open battery settings: $e',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  Future<void> _requestAllPermissions() async {
    debugPrint('RequestAll: Starting...');
    setState(() => _isLoading = true);

    try {
      debugPrint('RequestAll: Location granted=$_locationGranted');
      if (!_locationGranted) await _requestLocation();

      debugPrint('RequestAll: Notification granted=$_notificationGranted');
      if (!_notificationGranted) await _requestNotification();

      debugPrint('RequestAll: Overlay granted=$_overlayGranted');
      if (!_overlayGranted) await _requestOverlay();

      debugPrint('RequestAll: Battery granted=$_batteryGranted');
      if (!_batteryGranted) await _requestBattery();

      debugPrint('RequestAll: All requests done. Location=$_locationGranted');
      if (_locationGranted) {
        debugPrint('RequestAll: Completing permissions...');
        await _completePermissions();
      } else {
        debugPrint('RequestAll: Location not granted, showing error');
        if (mounted) {
          Get.snackbar(
            'Permission Required',
            'Location permission is required to receive rides.',
            backgroundColor: Colors.red,
            colorText: Colors.white,
          );
        }
      }
    } catch (e) {
      debugPrint('RequestAll: Error occurred: $e');
    } finally {
      debugPrint('RequestAll: Finally block, setting loading=false');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _completePermissions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('permissionsAccepted', true);

    if (mounted) {
      Get.off(() => const OnboardingScreen());
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
      appBar: ProAppBar(
        automaticallyImplyLeading: false,
        titleText: "Permissions",
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              Text(
                "Enable Access",
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                "Tap on each item to grant permission.",
                style: TextStyle(
                  fontSize: 16,
                  color: isDark ? Colors.white60 : Colors.black54,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 40),

              _buildPermissionTile(
                icon: Icons.location_on,
                title: "Location Services",
                description:
                    "Required for ride matching and tracking, even when the app is closed or not in use.",
                isGranted: _locationGranted,
                onTap: _requestLocation,
              ),

              const SizedBox(height: 20),

              _buildPermissionTile(
                icon: Icons.notifications_active,
                title: "Notifications",
                description: "Get instant alerts for new ride requests.",
                isGranted: _notificationGranted,
                onTap: _requestNotification,
              ),

              const SizedBox(height: 20),

              _buildPermissionTile(
                icon: Icons.layers,
                title: "Display Over Apps",
                description:
                    "Required to show ride requests while using other apps.",
                isGranted: _overlayGranted,
                onTap: _requestOverlay,
              ),

              const SizedBox(height: 20),

              _buildPermissionTile(
                icon: Icons.battery_charging_full,
                title: "Battery Optimization",
                description:
                    "Disable optimization to keep GPS tracking and notifications active in background.",
                isGranted: _batteryGranted,
                onTap: _requestBattery,
              ),

              const Spacer(),

              ProButton(
                text: "Allow & Continue",
                isLoading: _isLoading,
                onPressed: _requestAllPermissions,
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionTile({
    required IconData icon,
    required String title,
    required String description,
    required bool isGranted,
    required VoidCallback onTap,
  }) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isGranted ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2C2C2C) : Colors.grey[100],
            borderRadius: BorderRadius.circular(16),
            border: isGranted
                ? Border.all(color: Colors.green.withValues(alpha: 0.5))
                : Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isGranted
                      ? Colors.green.withValues(alpha: 0.1)
                      : AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isGranted ? Icons.check : icon,
                  color: isGranted ? Colors.green : AppColors.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              if (isGranted)
                const Padding(
                  padding: EdgeInsets.only(left: 8.0),
                  child: Icon(
                    Icons.check_circle,
                    color: Colors.green,
                    size: 20,
                  ),
                )
              else
                Icon(
                  Icons.chevron_right,
                  color: isDark ? Colors.white54 : Colors.grey,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
