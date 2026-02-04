import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:get/get.dart';
import 'package:project_taxi_driver_app/utils/app_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

class OverlayServiceEnhanced {
  static final OverlayServiceEnhanced instance = OverlayServiceEnhanced._internal();
  factory OverlayServiceEnhanced() => instance;
  OverlayServiceEnhanced._internal();

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

  /// Show multiple ride requests overlay
  Future<void> showMultipleRequestsOverlay(
    List<Map<String, dynamic>> requestsData,
    String sortType,
  ) async {
    debugPrint('OverlayService: showMultipleRequestsOverlay called with ${requestsData.length} requests');

    // Calculate dynamic dimensions
    double screenWidth = Get.width;
    double screenHeight = Get.height;

    // Safety fallback
    if (screenWidth == 0) screenWidth = 400;
    if (screenHeight == 0) screenHeight = 844;

    // Target: 90% width, taller height for multiple requests
    final targetWidth = (screenWidth * 0.9).toInt();
    final targetHeight = 600; // Taller for multiple cards

    // CHECK ACTUAL STATE
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
        overlayTitle: "Multiple Ride Requests",
        overlayContent: "You have ${requestsData.length} ride requests",
      );
      _isOverlayActive = true;
    }

    // Send data
    await sendDataToOverlay({
      'type': 'multiple_requests',
      'requests': requestsData,
      'sortType': sortType,
      'width': targetWidth,
      'height': targetHeight,
    });
  }
}
