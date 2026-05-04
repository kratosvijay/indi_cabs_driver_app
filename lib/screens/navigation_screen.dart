import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:get/get.dart';

class NavigationScreen extends StatefulWidget {
  final LatLng destination;
  final String destinationTitle;

  const NavigationScreen({
    super.key,
    required this.destination,
    required this.destinationTitle,
  });

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  bool _navigationSessionInitialized = false;
  bool _isMuted = false;

  @override
  void initState() {
    super.initState();
    // Force status bar and navigation bar to be visible
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    _loadSettings();
    _initNavigation();
    WakelockPlus.enable();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _isMuted = prefs.getBool('nav_is_muted') ?? false;
      });
    }
  }

  Future<void> _applyAudioSettings() async {
    try {
      await GoogleMapsNavigator.setAudioGuidance(
        NavigationAudioGuidanceSettings(
          guidanceType: _isMuted
              ? NavigationAudioGuidanceType.silent
              : NavigationAudioGuidanceType.alertsAndGuidance,
        ),
      );
    } catch (e) {
      debugPrint('Error applying audio settings: $e');
    }
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _cleanupNavigationSession();
    super.dispose();
  }

  bool _isCleaningUp = false;

  Future<void> _cleanupNavigationSession() async {
    if (_isCleaningUp) return;
    _isCleaningUp = true;

    // Safety: If not initialized, try cleanup anyway just in case native side is stuck?
    // But mostly rely on initialized flag.
    if (!_navigationSessionInitialized) {
      _isCleaningUp = false;
      return;
    }

    try {
      debugPrint("Stopping guidance...");
      await GoogleMapsNavigator.stopGuidance().timeout(
        const Duration(seconds: 1),
        onTimeout: () => debugPrint("timeout stopping guidance"),
      );
      debugPrint("Cleaning up navigator...");
      await GoogleMapsNavigator.cleanup().timeout(
        const Duration(seconds: 2),
        onTimeout: () => debugPrint("timeout cleaning up"),
      );
      _navigationSessionInitialized = false;
    } catch (e) {
      debugPrint('Error cleaning up navigation: $e');
    } finally {
      _isCleaningUp = false;
    }
  }

  Future<void> _initNavigation({bool retry = true}) async {
    if (!mounted) return;

    // Avoid re-entry?
    // Ideally we should wait if cleanup is happening?
    // But for now, let's just proceed carefully.

    try {
      // 0. Proactive Cleanup
      try {
        await GoogleMapsNavigator.cleanup();
      } catch (_) {}

      if (!mounted) return;

      // 1. Check Terms
      bool termsAccepted = false;
      try {
        termsAccepted = await GoogleMapsNavigator.areTermsAccepted();
      } catch (e) {
        debugPrint("Error checking terms: $e");
      }

      if (!termsAccepted) {
        if (mounted) {
          try {
            termsAccepted =
                await GoogleMapsNavigator.showTermsAndConditionsDialog(
                  'Navigation Terms',
                  'Indi Cabs',
                );
          } catch (e) {
            debugPrint("Error showing TOS dialog: $e");
            throw Exception("Could not verify Terms of Service: $e");
          }
        }
        if (!termsAccepted) {
          throw Exception("Terms rejected by user");
        }
      }

      if (!mounted) return;

      // 2. Initialize
      debugPrint("Initializing Navigation Session...");
      await GoogleMapsNavigator.initializeNavigationSession().timeout(
        const Duration(seconds: 15),
      );

      if (mounted) {
        setState(() {
          _navigationSessionInitialized = true;
        });
      }
    } catch (e) {
      debugPrint('Error initializing navigation session (Retry: $retry): $e');
      if (retry && mounted) {
        // Attempt cleanup and retry once
        try {
          // Don't call full _cleanupNavigationSession as it checks _navigationSessionInitialized
          await GoogleMapsNavigator.cleanup();
        } catch (cleanupError) {
          debugPrint('Cleanup failed during retry: $cleanupError');
        }

        await Future.delayed(const Duration(seconds: 1)); // Small delay
        if (mounted) {
          await _initNavigation(retry: false);
        }
      } else {
        if (mounted) {
          setState(() {
            _navigationSessionInitialized = false;
          });
          Get.snackbar(
            'Navigation Error',
            'Navigation Init Failed: $e',
            snackPosition: SnackPosition.TOP,
            backgroundColor: Colors.red,
            colorText: Colors.white,
            duration: const Duration(seconds: 5),
            mainButton: TextButton(
              onPressed: () {
                Get.back();
                _initNavigation(retry: true);
              },
              child: const Text('Retry', style: TextStyle(color: Colors.white)),
            ),
          );
        }
      }
    }
  }

  void _onViewCreated(GoogleNavigationViewController controller) {
    // Reinforce status bar visibility
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );

    // Explicitly enable UI elements
    controller.setNavigationUIEnabled(true);
    controller.setMyLocationEnabled(true);

    _startGuidance();
  }

  Future<void> _startGuidance() async {
    final dest = NavigationWaypoint.withLatLngTarget(
      title: widget.destinationTitle,
      target: widget.destination,
    );

    final displayOptions = NavigationDisplayOptions(
      showDestinationMarkers: true,
      showTrafficLights: true,
      showStopSigns: true,
    );

    final routingOptions = RoutingOptions(
      routingStrategy: NavigationRoutingStrategy.defaultBest,
      alternateRoutesStrategy: NavigationAlternateRoutesStrategy.none,
    );

    try {
      try {
        await GoogleMapsNavigator.setDestinations(
          Destinations(
            waypoints: [dest],
            displayOptions: displayOptions,
            routingOptions: routingOptions,
          ),
        );
      } catch (e) {
        debugPrint('Nav_Error: setDestinations failed: $e');
        if (mounted) {
          Get.snackbar(
            "Route Error",
            "Failed to calculate route: $e",
            backgroundColor: Colors.red,
            colorText: Colors.white,
            duration: const Duration(seconds: 5),
          );
        }
      }

      try {
        await GoogleMapsNavigator.startGuidance();
      } catch (e) {
        debugPrint('Nav_Error: startGuidance failed: $e');
      }

      // Apply persisted audio settings immediately after starting guidance
      await _applyAudioSettings();
    } catch (e) {
      debugPrint('Nav_Error: Error starting guidance flow: $e');
    }
  }

  Future<void> _toggleMute() async {
    final newState = !_isMuted;
    setState(() => _isMuted = newState);

    // Save to prefs
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('nav_is_muted', newState);

    try {
      await GoogleMapsNavigator.setAudioGuidance(
        NavigationAudioGuidanceSettings(
          guidanceType: newState
              ? NavigationAudioGuidanceType.silent
              : NavigationAudioGuidanceType.alertsAndGuidance,
        ),
      );
    } catch (e) {
      debugPrint('Error setting audio guidance: $e');
      // Revert state if failed (and not persisted?)
      // Ideally we shouldn't revert UI if API fails but verify.
      // For now keep simple
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        toolbarHeight: 0,
        elevation: 0,
        backgroundColor: Colors.transparent,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light, // White icons for dark map
          statusBarBrightness: Brightness.dark,
        ),
      ),
      body: Stack(
        children: [
          // Map stays full screen
          if (_navigationSessionInitialized)
            GoogleMapsNavigationView(
              onViewCreated: _onViewCreated,
              initialNavigationUIEnabledPreference:
                  NavigationUIEnabledPreference.automatic,
              initialPadding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 10,
              ),
            )
          else
            const Center(child: CircularProgressIndicator()),

          // UI Overlays
          // Voice Control Button - Positioned to align with compass vertically
          Positioned(
            top: 200,
            right: 12,
            child: SafeArea(
              child: FloatingActionButton(
                heroTag: 'nav_mute_btn',
                mini: true,
                backgroundColor: Colors.white.withValues(alpha: 0.9),
                foregroundColor: Colors.black,
                onPressed: _toggleMute,
                child: Icon(_isMuted ? Icons.volume_off : Icons.volume_up),
              ),
            ),
          ),

          // Close button
          Positioned(
            bottom: 10,
            right: 20,
            child: SafeArea(
              child: Material(
                color: Colors.red[700]?.withValues(alpha: 0.9),
                elevation: 6,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => Get.back(),
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Icon(Icons.close, color: Colors.white, size: 28),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
