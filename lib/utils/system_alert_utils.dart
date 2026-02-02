import 'dart:isolate';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:system_alert_window/system_alert_window.dart';

class SystemAlertUtils {
  static const String mainAppPort = 'MainApp';

  static Future<void> requestPermissions() async {
    try {
      await SystemAlertWindow.requestPermissions(
        prefMode: SystemWindowPrefMode.OVERLAY,
      );
    } catch (e) {
      debugPrint("Error requesting permissions: $e");
    }
  }

  static Future<void> showOverlayWindow() async {
    try {
      await SystemAlertWindow.showSystemWindow(
        height: 80,
        width: 80,
        gravity: SystemWindowGravity.LEADING,

        prefMode: SystemWindowPrefMode.OVERLAY,
        layoutParamFlags: [SystemWindowFlags.FLAG_NOT_FOCUSABLE],
      );
    } catch (e) {
      debugPrint("Error showing overlay: $e");
    }
  }

  static Future<void> closeOverlayWindow() async {
    try {
      await SystemAlertWindow.closeSystemWindow(
        prefMode: SystemWindowPrefMode.OVERLAY,
      );
    } catch (e) {
      debugPrint("Error closing overlay: $e");
    }
  }

  static void registerCallBack(void Function(String) callBack) {
    final ReceivePort receivePort = ReceivePort();
    bool registered = IsolateNameServer.registerPortWithName(
      receivePort.sendPort,
      mainAppPort,
    );

    if (!registered) {
      IsolateNameServer.removePortNameMapping(mainAppPort);
      IsolateNameServer.registerPortWithName(receivePort.sendPort, mainAppPort);
    }

    receivePort.listen((message) {
      if (message is String) {
        if (message == "open_app") {
          FlutterForegroundTask.launchApp();
        }
        callBack(message);
      }
    });
  }
}
