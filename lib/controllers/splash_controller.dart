import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:project_taxi_driver_app/controllers/auth_controller.dart';
import 'package:project_taxi_driver_app/widgets/status_slider.dart'; // For DriverStatus enum
import 'package:project_taxi_driver_app/screens/language.dart';
import 'package:project_taxi_driver_app/screens/onboarding.dart';
import 'package:project_taxi_driver_app/screens/permission_screen.dart';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class SplashController extends GetxController {
  RxString statusText = "Initializing the app...".obs;

  @override
  void onReady() {
    super.onReady();
    _init();
  }

  Future<void> _init() async {
    // 1. Basic UI Delay
    await Future.delayed(const Duration(seconds: 1));

    // CHECK FOR UPDATES BEFORE ANYTHING ELSE
    try {
      await checkForUpdates();
    } catch (e) {
      if (e.toString().contains("Update Required")) {
        return; // Stop initialization
      }
    }

    statusText.value = "Initializing the app...";

    try {
      // 2. Load Preferences FIRST
      final prefs = await SharedPreferences.getInstance();
      final bool onboardingComplete =
          prefs.getBool('onboardingComplete') ?? false;
      final bool permissionsAccepted =
          prefs.getBool('permissionsAccepted') ?? false;
      final String? selectedLanguage = prefs.getString('selectedLanguage');

      // 3. Routing Checks
      // 3. Routing Checks
      if (!permissionsAccepted) {
        Get.offAll(() => const PermissionScreen());
        return;
      } else if (!onboardingComplete) {
        Get.offAll(() => const OnboardingScreen());
        return;
      } else if (selectedLanguage == null) {
        Get.offAll(() => const LanguageSelectionScreen());
        return;
      }

      // Ensure the locale is updated immediately on startup
      Get.updateLocale(Locale(selectedLanguage));

      // 4. Initializations (Only if we are proceeding to app)
      try {
        FlutterTts flutterTts = FlutterTts();
        await flutterTts.setLanguage("en-US");
        await flutterTts.setSpeechRate(0.5);
        await flutterTts.setVolume(1.0);
      } catch (e) {
        debugPrint("Splash: Error initializing TTS: $e");
      }

      try {
        // Safe to request now as user has gone through permission screen
        // await OverlayService.instance.requestOverlayPermission();
      } catch (e) {
        debugPrint("Splash: Error initializing Overlay Service: $e");
      }

      // 5. GPS Warmup
      try {
        // Only warm up if we already have permission (which we should if permissionsAccepted is true)
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.whileInUse ||
            permission == LocationPermission.always) {
          debugPrint("Splash: Warming up GPS...");
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              timeLimit: Duration(seconds: 3),
            ),
          );
          debugPrint("Splash: GPS Warmup Complete");
        }
      } catch (e) {
        debugPrint("Splash: GPS Warmup Skipped/Failed: $e");
      }

      // 6. Check Auth & User Data
      final user = FirebaseAuth.instance.currentUser;
      DriverStatus initialStatus = DriverStatus.offline;

      if (user != null) {
        try {
          final doc = await FirebaseFirestore.instance
              .collection('drivers')
              .doc(user.uid)
              .get();

          if (doc.exists) {
            final data = doc.data();
            final isOnline = data?['isOnline'] ?? false;
            if (isOnline) {
              initialStatus = DriverStatus.online;
              debugPrint("Splash: Driver found ONLINE.");
            }
          }
        } catch (e) {
          debugPrint("Splash: Error fetching driver status: $e");
        }
      }

      // 7. Proceed to Main App
      AuthController.instance.decideRoute(initialStatus: initialStatus);
    } catch (e) {
      debugPrint("Splash: Initialization Error: $e");
      // Fallback in case of critical error reading prefs?
      Get.offAll(() => const OnboardingScreen());
    }
  }

  Future<void> checkForUpdates() async {
    try {
      statusText.value = "Checking for updates...";

      // Get current app version
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      String currentVersion = packageInfo.version;

      // Fetch latest version from Firestore
      DocumentSnapshot doc = await FirebaseFirestore.instance
          .collection('app_settings')
          .doc('driver_app')
          .get();

      if (doc.exists) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        String latestVersion = data['latest_version'] ?? currentVersion;
        String storeUrl = data['store_url'] ?? '';
        bool forceUpdate = data['force_update'] ?? false;

        debugPrint(
          "Splash: Current Version: $currentVersion, Latest: $latestVersion",
        );

        if (_isUpdateAvailable(currentVersion, latestVersion)) {
          debugPrint("Splash: Update Available!");
          if (forceUpdate) {
            _showUpdateDialog(storeUrl, true);
            // Verify this throws/stops execution flow if we want to BLOCK
            // But since we are inside _init, we should return or throw to stop further execution in _init
            throw Exception("Force Update Required");
          } else {
            // Optional update - maybe show a dialog but allow skip?
            // For now, request implies "compulsory update" if available,
            // but let's stick to the prompt: "if any update is available make sure it should be compuldary update"
            _showUpdateDialog(storeUrl, true);
            throw Exception("Update Required");
          }
        }
      }
    } catch (e) {
      if (e.toString().contains("Update Required")) {
        rethrow; // Propagate up to stop _init
      }
      debugPrint("Splash: Error checking updates: $e");
      // Continue if check fails (internet issue etc)
    }
  }

  bool _isUpdateAvailable(String current, String latest) {
    List<int> currentParts = current.split('.').map(int.parse).toList();
    List<int> latestParts = latest.split('.').map(int.parse).toList();

    for (int i = 0; i < latestParts.length; i++) {
      int cPart = (i < currentParts.length) ? currentParts[i] : 0;
      int lPart = latestParts[i];

      if (lPart > cPart) return true;
      if (lPart < cPart) return false;
    }
    return false;
  }

  void _showUpdateDialog(String url, bool isForce) {
    Get.dialog(
      PopScope(
        canPop: !isForce,
        child: AlertDialog(
          title: const Text("Update Available"),
          content: const Text(
            "A new version of the app is available. Please update to continue.",
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final Uri uri = Uri.parse(url);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                } else {
                  debugPrint("Could not launch $url");
                }
              },
              child: const Text("Update Now"),
            ),
          ],
        ),
      ),
      barrierDismissible: !isForce,
    );
  }
}
