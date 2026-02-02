import 'dart:ui'; // For PlatformDispatcher
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:project_taxi_driver_app/controllers/auth_controller.dart';
import 'package:project_taxi_driver_app/screens/splash_screen.dart';

import 'package:flutter_refresh_rate_control/flutter_refresh_rate_control.dart';
import 'package:project_taxi_driver_app/utils/app_colors.dart';
import 'package:project_taxi_driver_app/utils/app_translations.dart';
import 'package:project_taxi_driver_app/services/overlay_service.dart';

// Re-export the overlay entry point for flutter_overlay_window
// This MUST be in main.dart for the plugin to find it
export 'package:project_taxi_driver_app/services/overlay_service.dart'
    show overlayMain;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: "dotenv.env");
  await Firebase.initializeApp();

  // Pass all uncaught "fatal" errors from the framework to Crashlytics
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

  // Pass all uncaught asynchronous errors that aren't handled by the Flutter framework to Crashlytics
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  await FirebaseAppCheck.instance.activate(
    providerAndroid: AndroidDebugProvider(),
    providerApple: AppleDebugProvider(),
  );

  // Set high refresh rate
  try {
    await FlutterRefreshRateControl().requestHighRefreshRate();
  } catch (e) {
    debugPrint("Error setting high refresh rate: $e");
  }

  // Initialize AuthController globally
  Get.put(AuthController());

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Request permissions and register app-side listener
    Future.delayed(Duration.zero, () async {
      OverlayService.instance.requestOverlayPermission();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Auto-hide overlay when app is resumed
      OverlayService.instance.hideFloatingBubble();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Indi Cabs Partner',
      debugShowCheckedModeBanner: false,
      translations: AppTranslations(),
      locale: Get.deviceLocale,
      fallbackLocale: const Locale('en', 'US'),

      // **1. Light Theme Configuration**
      theme: ThemeData(
        brightness: Brightness.light,
        useMaterial3: true,
        textTheme: GoogleFonts.notoSansTextTheme(ThemeData.light().textTheme),
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.lightEnd,
          brightness: Brightness.light,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.lightEnd, // Solid fallback
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),

      // **2. Dark Theme Configuration**
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        textTheme: GoogleFonts.notoSansTextTheme(ThemeData.dark().textTheme),
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.darkStart,
          brightness: Brightness.dark,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.darkEnd, // Solid fallback
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        scaffoldBackgroundColor: const Color(0xFF121212),
      ),

      // Automatically switch based on phone settings
      themeMode: ThemeMode.system,

      home: const SplashScreen(),
    );
  }
}
