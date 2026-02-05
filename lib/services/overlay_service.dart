import 'dart:async'; // Added
import 'package:flutter/foundation.dart'; // Added
import 'dart:collection';
import 'dart:developer';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:get/get.dart';
import 'package:project_taxi_driver_app/controllers/home_page_controller.dart';

class OverlayService {
  static final OverlayService instance = OverlayService._();
  OverlayService._() {
    FlutterOverlayWindow.overlayListener.listen((data) {
      log("OverlayService Received Data: $data");
      if (data is Map) {
        final action = data['action'];
        final rideId = data['rideId'];

        if (rideId != null) {
          final controller = Get.find<HomePageController>();

          if (action == 'REJECT') {
            controller.passRide(rideId);
            onRideRejected();
          } else if (action == 'ACCEPT') {
            // We need to convert the map back to RideRequest if possible,
            // but onRideAccepted takes a RideRequest object.
            // Ideally we find the request in our activeRequests list.
            final ride = controller.activeRequests.firstWhereOrNull(
              (r) => r.rideId == rideId,
            );
            if (ride != null) {
              controller.onRideAccepted(ride);
            } else {
              // Fallback if not in list (edge case), try to reconstruct or ignore
              log("OverlayService: Accepted ride not found in activeRequests");
            }
          }
        }

        if (action == 'OPEN_APP') {
          log("OverlayService: Opening App requested");
          FlutterForegroundTask.launchApp();
        }
      }
    });
  }

  final Queue<Map<String, dynamic>> _rideQueue = Queue();
  bool _overlayVisible = false;
  bool _requestShowing = false;

  /* ---------------- Permission ---------------- */

  Future<bool> ensurePermission() async {
    if (await FlutterOverlayWindow.isPermissionGranted()) return true;
    return await FlutterOverlayWindow.requestPermission() ?? false;
  }

  /* ---------------- Bubble ---------------- */

  Future<void> showFloatingBubble() async {
    _cancelStopService(); // Cancel any pending stop

    // Check for stale state: If we think it's visible but the window is gone (user tapped it)
    if (_overlayVisible) {
      final bool isActive = await FlutterOverlayWindow.isActive();
      if (!isActive) {
        _overlayVisible = false;
      } else {
        return;
      }
    }

    if (!await ensurePermission()) return;

    // ... rest of implementation (start service, show overlay)

    // Start service only when showing overlay
    await FlutterForegroundTask.startService(
      notificationTitle: "Driver Online",
      notificationText: "Waiting for rides",
    );

    await FlutterOverlayWindow.showOverlay(
      height: 200,
      width: 200,
      enableDrag: true,
      alignment: OverlayAlignment.centerLeft,
      flag: OverlayFlag.defaultFlag,
    );

    _overlayVisible = true;
  }

  /* ---------------- Incoming Request ---------------- */

  Future<void> showRideRequestOverlay(Map<String, dynamic> ride) async {
    _cancelStopService(); // Cancel any pending stop

    // Safety: Check permission first to prevent crash
    if (!await ensurePermission()) {
      log("OverlayService: Permission not granted. Skipping overlay.");
      return;
    }

    log("OverlayService: onNewRide called");
    _rideQueue.add(ride);
    log("QUEUE SIZE: ${_rideQueue.length}");

    if (_requestShowing) return;

    await _showNextRequest();
  }

  Future<void> _showNextRequest() async {
    if (_rideQueue.isEmpty) {
      _requestShowing = false;
      await _cleanupIfIdle();
      return;
    }

    _requestShowing = true;

    // 1. ALWAYS start Foreground Service first to promote App Importance
    // This is critical for Android 14+ to allow OverlayService restart if needed.
    log(
      "OverlayService: Starting Foreground Service to promote app importance...",
    );
    await FlutterForegroundTask.startService(
      notificationTitle: "New Ride Request",
      notificationText: "Tap to view details",
    );
    // Give it time to propagate
    await Future.delayed(const Duration(milliseconds: 500));

    // 2. Manage Overlay Window
    if (_overlayVisible) {
      // If already visible (e.g. bubble), try to resize instead of close-reopen to keep service alive
      // Note: If resize not supported by plugin version, we fall back to close-open,
      // but because we promoted to FGS above, close-open SHOULD work now.
      try {
        await FlutterOverlayWindow.resizeOverlay(
          WindowSize.matchParent,
          550,
          true,
        );
      } catch (e) {
        log("Resize not supported or failed: $e");
        // CRITICAL: DO NOT close the overlay here. Closing it destroys the service,
        // and restarting it triggers the Android 14 background start restriction (crash).
        // Instead, we leave it as is (likely a Bubble) and rely on the UI to adapt (Mini Card).
        // _overlayVisible is already true, so we just proceed to shareData.
      }
    }

    if (!_overlayVisible) {
      await FlutterOverlayWindow.showOverlay(
        height: 550,
        width: WindowSize.matchParent,
        enableDrag: false,
        alignment: OverlayAlignment.center,
        flag: OverlayFlag.defaultFlag,
      );
      _overlayVisible = true;
      // Wait for isolate
      await Future.delayed(const Duration(milliseconds: 250));
    }

    // 3. Send Data
    await FlutterOverlayWindow.shareData({
      "type": "SHOW_REQUEST",
      "ride": _rideQueue.first,
    });
  }

  // Legacy method support if any code calls it
  Future<void> sendDataToOverlay(Map<String, dynamic> data) async {
    await FlutterOverlayWindow.shareData(data);
  }

  /* ---------------- Overlay Callbacks ---------------- */

  /* ---------------- Overlay Callbacks ---------------- */
  // These should be called when we detect a signal from the overlay,
  // OR when we want to manipulate the queue from the main app.

  // Note: The UI isolate handles its own rejection via closeOverlay logic usually,
  // but if we need to sync state, we listen to messages.
  // Ideally, the main app (OverlayService) listens to the Overlay stream?
  // flutter_overlay_window doesn't support bi-directional streams easily back to *this* class instance
  // unless we use a port or check `FlutterOverlayWindow.overlayListener` (but that's for the overlay side usually).
  // Actually, standard usage is: Logic -> Overlay. Overlay -> Logic is via MethodChannels or ports?
  // The plugin has `FlutterOverlayWindow.overlayListener` which is `receivePort`.
  // Wait, `FlutterOverlayWindow.overlayListener` is used *inside* the overlay to receive data.
  // To send data back, the overlay uses `FlutterOverlayWindow.shareData`.
  // Does `FlutterOverlayWindow` exposed to the main isolate have a listener for data coming *from* overlay?
  // Checking docs/source... usually `FlutterOverlayWindow.onData`?
  // No, the plugin relies on `shareData` broadcasting to *currently active* listeners.
  // If `OverlayService` is in the main isolate, can it listen?
  // The plugin's stream is often broadcast. Let's assume we can't easily get data back without a port.
  // BUT the user's design shows `onRideRejected` etc.
  // Code should just manage the queue.
  // If the overlay closes itself (user tapped reject), the main app needs to know to show the next one.

  // CRITICAL: We need to know when the overlay closes or rejects.
  // `flutter_overlay_window` exposes `FlutterOverlayWindow.overlayListener` but that's for receiving IN the overlay.
  // To receive IN MAIN APP, we usually need a `ReceivePort` passed to the isolate, or rely on `isActive` polling?
  // Or maybe `FlutterForegroundTask` can help?
  // Actually, standard pattern is:
  // Overlay calls `closeOverlay`.
  // Main app might likely assume if `_rideQueue` still has items, it should show next?
  // But how does Main app know the previous one finished?

  // Workaround: We will assume the overlay UI handles the "Reject" action by closing itself.
  // But we need to pop the queue.
  // We can expose `popTop()` method and call it when we *know* it's done (e.g. from Home Controller listening to backend changes?)
  // OR, we can try to listen to the *same* `shareData` if it broadcasts to all?
  // (Usually only works one way or strictly to Isolate).

  // Let's implement queue management methods that the *Controller* calls.
  // The Home Page Controller is the one that gets the 'rejected' status modification from backend or timeout.

  Future<void> hideFloatingBubble() async {
    await _cleanupIfIdle();
  }

  Future<void> popQ() async {
    if (_rideQueue.isNotEmpty) {
      _rideQueue.removeFirst();
    }
    _requestShowing = false;
    await _showNextRequest(); // Auto show next
  }

  Future<void> onRideRejected() async {
    await popQ();
  }

  Future<void> onRideAccepted(Map<String, dynamic> ride) async {
    _rideQueue.clear();
    _requestShowing = false;

    // Stop service and close overlay
    await _cleanupIfIdle();

    // Launch app
    FlutterForegroundTask.launchApp();
  }

  Timer? _stopServiceTimer;

  /* ---------------- Cleanup ---------------- */

  Future<void> _cleanupIfIdle() async {
    try {
      await FlutterOverlayWindow.closeOverlay();
    } catch (e) {
      /* ignore */
    }

    _overlayVisible = false;
    _requestShowing = false;

    // Debounce stop service to prevent race condition if app is minimized immediately
    _stopServiceTimer?.cancel();
    _stopServiceTimer = Timer(const Duration(seconds: 2), () async {
      if (!_overlayVisible) {
        debugPrint("Stopping Foreground Service (Debounced)...");
        await FlutterForegroundTask.stopService();
      }
    });
  }

  void _cancelStopService() {
    if (_stopServiceTimer != null && _stopServiceTimer!.isActive) {
      _stopServiceTimer!.cancel();
      debugPrint("Cancelled Service Stop");
    }
  }
}
