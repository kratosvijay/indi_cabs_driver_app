import 'dart:isolate';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:project_taxi_driver_app/utils/system_alert_utils.dart';
import 'package:system_alert_window/system_alert_window.dart';

class CustomOverlay extends StatefulWidget {
  const CustomOverlay({super.key});

  @override
  State<CustomOverlay> createState() => _CustomOverlayState();
}

class _CustomOverlayState extends State<CustomOverlay> {
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          final SendPort? mainAppPort = IsolateNameServer.lookupPortByName(
            SystemAlertUtils.mainAppPort,
          );
          if (mainAppPort != null) {
            mainAppPort.send("open_app");
          } else {
            SystemAlertWindow.sendMessageToOverlay("open_app");
          }
        },
        borderRadius: BorderRadius.circular(50),
        child: Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.all(8),
          child: Image.asset('assets/logos/app_logo.png', fit: BoxFit.contain),
        ),
      ),
    );
  }
}
