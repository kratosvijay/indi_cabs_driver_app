import 'dart:ui'; // For PlatformDispatcher
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sms_autofill/sms_autofill.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:io';
import 'package:flutter_displaymode/flutter_displaymode.dart';

import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:project_taxi_driver_app/controllers/auth_controller.dart';
import 'package:project_taxi_driver_app/screens/splash_screen.dart';
import 'package:upgrader/upgrader.dart';

// import 'package:flutter_refresh_rate_control/flutter_refresh_rate_control.dart';
import 'package:project_taxi_driver_app/utils/app_colors.dart';
import 'package:project_taxi_driver_app/utils/app_translations.dart';

import 'package:project_taxi_driver_app/services/overlay_main.dart' show OverlayApp;

// Overlay entry point for flutter_overlay_window.
// MUST be in main.dart and annotated with @pragma("vm:entry-point") for Release builds.
@pragma("vm:entry-point")
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  runApp(const OverlayApp());
}

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
    providerAndroid: kDebugMode ? AndroidDebugProvider() : AndroidPlayIntegrityProvider(),
    providerApple: kDebugMode ? AppleDebugProvider() : AppleAppAttestProvider(),
  );

  if (kDebugMode) {
    debugPrint("--------------------------------------------------");
    debugPrint("FIREBASE APP CHECK DEBUG MODE ACTIVE");
    debugPrint("Please ensure your Debug Token is added to Firebase Console");
    debugPrint("--------------------------------------------------");
  }

  // Set high refresh rate
  try {
    if (Platform.isAndroid) {
      await FlutterDisplayMode.setHighRefreshRate();
    }
  } catch (e) {
    debugPrint("Error setting high refresh rate: $e");
  }

  // Enable edge-to-edge support (Handles Android 15/Play Console warning)
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarContrastEnforced: false,
    ),
  );

  // Initialize AuthController globally
  Get.put(AuthController());

  // Print App Signature for SMS Autofill
  SmsAutoFill().getAppSignature.then((signature) {
    debugPrint("--------------------------------------------------");
    debugPrint("DRIVER APP SIGNATURE HASH: $signature");
    debugPrint("--------------------------------------------------");
  });

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    // Overlay permission is requested in SplashController after permission check
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

      home: UpgradeAlert(child: const SplashScreen()),
    );
  }
}
