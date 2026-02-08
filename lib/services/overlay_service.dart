import 'dart:async';
import 'dart:collection';
import 'dart:developer';
import 'dart:isolate';
import 'dart:ui' as ui;
import 'dart:ui' show IsolateNameServer, Size;

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:get/get.dart';
import 'package:project_taxi_driver_app/controllers/home_page_controller.dart';

class OverlayService {
  static final OverlayService instance = OverlayService._();
  static const String actionPortName = 'overlay_action_port';

  OverlayService._() {
    _registerOverlayActionPort();

    // Keep channel listener as a fallback path.
    FlutterOverlayWindow.overlayListener.listen((data) {
      if (data is Map) {
        log("OverlayService Received Channel Data: $data");
        _handleOverlayAction(Map<String, dynamic>.from(data));
      }
    });
  }

  final Queue<Map<String, dynamic>> _rideQueue = Queue();
  ReceivePort? _overlayActionPort;
  bool _overlayVisible = false;
  bool _requestShowing = false;
  Timer? _stopServiceTimer;

  void _registerOverlayActionPort() {
    _overlayActionPort?.close();
    IsolateNameServer.removePortNameMapping(actionPortName);
    _overlayActionPort = ReceivePort();
    IsolateNameServer.registerPortWithName(
      _overlayActionPort!.sendPort,
      actionPortName,
    );

    _overlayActionPort!.listen((data) {
      if (data is Map) {
        log("OverlayService Received Port Data: $data");
        _handleOverlayAction(Map<String, dynamic>.from(data));
      }
    });
  }

  HomePageController? get _controllerOrNull {
    if (!Get.isRegistered<HomePageController>()) return null;
    return Get.find<HomePageController>();
  }

  Future<void> _handleOverlayAction(Map<String, dynamic> payload) async {
    final action = payload['action']?.toString();
    final rideId =
        payload['rideId']?.toString() ??
        _rideQueue.firstOrNull?['rideId']?.toString();

    if (action == 'OVERLAY_READY') {
      await _pushCurrentRequest();
      return;
    }

    if (action == 'OPEN_APP') {
      log("OverlayService: Opening app from overlay action");
      FlutterForegroundTask.launchApp();
      return;
    }

    final controller = _controllerOrNull;

    if (action == 'REJECT') {
      if (controller != null && rideId != null && rideId.isNotEmpty) {
        await controller.passRide(rideId);
      }
      await onRideRejected();
      return;
    }

    if (action == 'ACCEPT') {
      if (controller != null) {
        final ride = (rideId == null)
            ? controller.activeRideRequest
            : controller.activeRequests.firstWhereOrNull(
                    (r) => r.rideId == rideId,
                  ) ??
                  controller.activeRideRequest;

        if (ride != null) {
          await controller.onRideAccepted(ride);
        } else {
          log("OverlayService: Accept requested but no active ride found.");
        }
      }

      _rideQueue.clear();
      _requestShowing = false;
      await _cleanupIfIdle();
      FlutterForegroundTask.launchApp();
    }
  }

  /* ---------------- Permission ---------------- */

  Future<bool> ensurePermission() async {
    if (await FlutterOverlayWindow.isPermissionGranted()) return true;
    return await FlutterOverlayWindow.requestPermission() ?? false;
  }

  /* ---------------- Bubble ---------------- */

  Future<void> showFloatingBubble() async {
    _cancelStopService();

    if (!await ensurePermission()) return;

    await _ensureForegroundService(
      title: "Driver Online",
      text: "Waiting for rides",
    );

    // Force close to apply new drag settings
    if (await _isOverlayActive()) {
      await FlutterOverlayWindow.closeOverlay();
    }

    await FlutterOverlayWindow.showOverlay(
      height: 80,
      width: 80,
      enableDrag: true,
      alignment: OverlayAlignment.centerRight,
      flag: OverlayFlag.defaultFlag,
    );
    log("OverlayService: Bubble overlay created.");

    _overlayVisible = true;
    _requestShowing = false;
    await FlutterOverlayWindow.shareData({
      "type": "SHOW_BUBBLE",
      "overlayWidth": 80,
      "overlayHeight": 80,
    });
  }

  /* ---------------- Incoming Request ---------------- */

  Future<void> showRideRequestOverlay(Map<String, dynamic> ride) async {
    _cancelStopService();

    if (!await ensurePermission()) {
      log("OverlayService: Permission not granted. Skipping overlay.");
      return;
    }

    final sanitized = _sanitizeRideForOverlay(ride);
    final rideId = sanitized['rideId']?.toString();
    if (rideId != null &&
        _rideQueue.any((r) => r['rideId']?.toString() == rideId)) {
      log("OverlayService: Duplicate ride $rideId skipped");
      return;
    }

    log("OverlayService: onNewRide called");
    _rideQueue.add(sanitized);
    log("QUEUE SIZE: ${_rideQueue.length}");

    if (_requestShowing) return;

    await _showNextRequest();
  }

  Future<void> _showNextRequest() async {
    if (_rideQueue.isEmpty) {
      _requestShowing = false;
      if (_shouldKeepBubbleVisible()) {
        await showFloatingBubble();
      } else {
        await _cleanupIfIdle();
      }
      return;
    }

    _requestShowing = true;

    await _ensureForegroundService(
      title: "New Ride Request",
      text: "Tap to view details",
    );
    await Future.delayed(const Duration(milliseconds: 150));

    final requestSize = _requestOverlaySizeDp();

    // Force close to apply new drag settings (disable drag for request)
    if (await _isOverlayActive()) {
      await FlutterOverlayWindow.closeOverlay();
    }

    await FlutterOverlayWindow.showOverlay(
      height: requestSize.height.round(),
      width: requestSize.width.round(),
      enableDrag: false,
      alignment: OverlayAlignment.center,
      flag: OverlayFlag.defaultFlag,
    );
    log("OverlayService: Request overlay created.");
    _overlayVisible = true;
    await Future.delayed(const Duration(milliseconds: 120));

    await _pushCurrentRequest();
  }

  Future<void> _pushCurrentRequest() async {
    if (_rideQueue.isEmpty) return;
    final requestSize = _requestOverlaySizeDp();
    await _resizeOverlay(requestSize.width.round(), requestSize.height.round());
    await FlutterOverlayWindow.shareData({
      "type": "SHOW_REQUEST",
      "ride": _rideQueue.first,
      "overlayWidth": requestSize.width.round(),
      "overlayHeight": requestSize.height.round(),
    });
  }

  Future<void> sendDataToOverlay(Map<String, dynamic> data) async {
    await FlutterOverlayWindow.shareData(data);
  }

  /* ---------------- Queue Actions ---------------- */

  Future<void> hideFloatingBubble() async {
    await _cleanupIfIdle();
  }

  Future<void> popQ() async {
    if (_rideQueue.isNotEmpty) {
      _rideQueue.removeFirst();
    }
    _requestShowing = false;
    await _showNextRequest();
  }

  Future<void> removeRide(String rideId) async {
    if (_rideQueue.isEmpty) return;

    // Check if the ride to remove is currently being shown (head of queue)
    if (_rideQueue.first['rideId']?.toString() == rideId) {
      log("OverlayService: Current ride removed via app. Popping queue.");
      await popQ();
    } else {
      // Just remove from queue if it's waiting
      _rideQueue.removeWhere((r) => r['rideId']?.toString() == rideId);
      log("OverlayService: Ride $rideId removed from background queue.");
    }
  }

  Future<void> onRideRejected() async {
    await popQ();
  }

  Future<void> onRideAccepted(Map<String, dynamic> ride) async {
    _rideQueue.clear();
    _requestShowing = false;
    await _cleanupIfIdle();
    FlutterForegroundTask.launchApp();
  }

  /* ---------------- Cleanup ---------------- */

  Future<void> _cleanupIfIdle() async {
    try {
      await FlutterOverlayWindow.closeOverlay();
    } catch (_) {}

    _overlayVisible = false;
    _requestShowing = false;

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

  bool _shouldKeepBubbleVisible() {
    final controller = _controllerOrNull;
    if (controller == null) return false;
    return controller.shouldShowOverlayBubble;
  }

  Future<bool> _isOverlayActive() async {
    try {
      return await FlutterOverlayWindow.isActive();
    } catch (e) {
      debugPrint("OverlayService: isActive check failed: $e");
      return false;
    }
  }

  Future<void> _ensureForegroundService({
    required String title,
    required String text,
  }) async {
    try {
      await FlutterForegroundTask.startService(
        notificationTitle: title,
        notificationText: text,
      );
    } catch (e) {
      debugPrint("OverlayService: Foreground service start skipped: $e");
    }
  }

  Future<void> _resizeOverlay(int width, int height) async {
    try {
      await FlutterOverlayWindow.resizeOverlay(width, height, false);
    } catch (_) {}
  }

  Size _screenSizeDp() {
    final view = ui.PlatformDispatcher.instance.views.first;
    final dpr = view.devicePixelRatio;
    return Size(view.physicalSize.width / dpr, view.physicalSize.height / dpr);
  }

  Size _requestOverlaySizeDp() {
    final screen = _screenSizeDp();
    final width = (screen.width - 16).clamp(280.0, 420.0).toDouble();
    final height = (screen.height * 0.62).clamp(320.0, 540.0).toDouble();
    return Size(width, height);
  }

  Map<String, dynamic> _sanitizeRideForOverlay(Map<String, dynamic> ride) {
    final stops = ride['stops'] ?? ride['intermediateStops'];
    final safeStops = <Map<String, dynamic>>[];
    if (stops is List) {
      for (final s in stops) {
        if (s is Map) {
          safeStops.add({
            'address': s['address']?.toString() ?? '',
            'status': s['status']?.toString() ?? 'pending',
          });
        } else if (s is String) {
          safeStops.add({'address': s, 'status': 'pending'});
        }
      }
    }

    num? numVal(dynamic v) =>
        v is num ? v : (v is String ? num.tryParse(v) : null);
    String strVal(dynamic v, [String fallback = '']) =>
        v == null ? fallback : v.toString();

    return {
      'rideId': strVal(ride['rideId']),
      'rideType': strVal(ride['rideType'], 'daily'),
      'vehicleClass': strVal(ride['vehicleClass']),
      'paymentMethod': strVal(ride['paymentMethod'], 'Cash'),
      'paidByWallet': numVal(ride['paidByWallet']) ?? 0,
      'driverDistance': numVal(ride['driverDistance']) ?? 0,
      'driverDuration': numVal(ride['driverDuration']),
      'rideDistance': numVal(ride['rideDistance']) ?? 0,
      'rideDuration': numVal(ride['rideDuration']),
      'pickupTitle': strVal(ride['pickupTitle']),
      'pickupFullAddress': strVal(ride['pickupFullAddress']),
      'dropoffTitle': strVal(ride['dropoffTitle']),
      'dropoffFullAddress': strVal(ride['dropoffFullAddress']),
      'rideFare': numVal(ride['rideFare']) ?? 0,
      'tip': numVal(ride['tip']),
      'stops': safeStops,
    };
  }
}
