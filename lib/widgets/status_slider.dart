// ignore_for_file: unreachable_switch_default

import 'package:flutter/material.dart';
import 'package:project_taxi_driver_app/utils/app_colors.dart';

enum DriverStatus { offline, online, goTo }

class StatusSlider extends StatefulWidget {
  final Function(DriverStatus) onStatusChanged;
  final String offlineText;
  final String onlineText;
  final String goToText;
  final DriverStatus currentStatus;

  const StatusSlider({
    super.key,
    required this.onStatusChanged,
    required this.offlineText,
    required this.onlineText,
    required this.goToText,
    required this.currentStatus,
  });

  @override
  State<StatusSlider> createState() => _StatusSliderState();
}

class _StatusSliderState extends State<StatusSlider> {
  late DriverStatus _currentStatus;
  late double _sliderAlignment;

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.currentStatus;
    _sliderAlignment = _getAlignmentForStatus(_currentStatus);
  }

  @override
  void didUpdateWidget(StatusSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Always sync with the controller's status if it differs from our internal state
    if (widget.currentStatus != _currentStatus) {
      setState(() {
        _currentStatus = widget.currentStatus;
        _sliderAlignment = _getAlignmentForStatus(_currentStatus);
      });
    }
  }

  double _getAlignmentForStatus(DriverStatus status) {
    switch (status) {
      case DriverStatus.offline:
        return -1.0;
      case DriverStatus.online:
        return 0.0;
      case DriverStatus.goTo:
        return 1.0;
    }
  }

  void _updateStatus(int index) {
    if (!mounted) return;

    DriverStatus newStatus;
    if (index == 0) {
      newStatus = DriverStatus.offline;
    } else if (index == 1) {
      newStatus = DriverStatus.online;
    } else {
      newStatus = DriverStatus.goTo;
    }

    // Don't update internal state immediately - let the controller decide
    // and update via didUpdateWidget when the status actually changes
    widget.onStatusChanged(newStatus);
  }

  String _getCurrentStatusText() {
    switch (_currentStatus) {
      case DriverStatus.online:
        return widget.onlineText;
      case DriverStatus.goTo:
        return widget.goToText;
      case DriverStatus.offline:
      default:
        return widget.offlineText;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Dynamic Text Display
        Text(
          _getCurrentStatusText(),
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        // The Slider itself
        GestureDetector(
          onHorizontalDragStart: (details) {
            // Reset to current status position when drag starts
            setState(() {
              _sliderAlignment = _getAlignmentForStatus(_currentStatus);
            });
          },
          onHorizontalDragUpdate: (details) {
            setState(() {
              // The width is 150, so the draggable area is half of that.
              _sliderAlignment += details.delta.dx / (150 / 2);
              _sliderAlignment = _sliderAlignment.clamp(-1.0, 1.0);
            });
          },
          onHorizontalDragEnd: (details) {
            int targetIndex;
            DriverStatus targetStatus;

            if (_sliderAlignment < -0.5) {
              targetIndex = 0;
              targetStatus = DriverStatus.offline;
            } else if (_sliderAlignment > 0.5) {
              targetIndex = 2;
              targetStatus = DriverStatus.goTo;
            } else {
              targetIndex = 1;
              targetStatus = DriverStatus.online;
            }

            // Immediately snap to the target position visually and update internal status
            setState(() {
              _currentStatus = targetStatus;
              if (targetIndex == 0) {
                _sliderAlignment = -1.0;
              } else if (targetIndex == 1) {
                _sliderAlignment = 0.0;
              } else {
                _sliderAlignment = 1.0;
              }
            });

            // Then notify the controller (which may override our optimistic update)
            _updateStatus(targetIndex);
          },
          child: Container(
            width: 150, // Shorter by 20
            height: 35, // Made smaller
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(50),
              borderRadius: BorderRadius.circular(22.5),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // The moving circular thumb with the icon
                AnimatedAlign(
                  alignment: Alignment(_sliderAlignment, 0),
                  duration: const Duration(milliseconds: 100),
                  curve: Curves.fastOutSlowIn,
                  child: Container(
                    width: 150 / 4, // Dynamic width for each section
                    height: 45,
                    alignment: Alignment.center,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.power_settings_new,
                        color: _sliderAlignment < -0.5
                            ? Colors.grey
                            : AppColors.primary,
                        size: 28,
                      ),
                    ),
                  ),
                ),
                // Invisible tappable areas for quick selection
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(onTap: () => _updateStatus(0)),
                    ),
                    Expanded(
                      child: GestureDetector(onTap: () => _updateStatus(1)),
                    ),
                    Expanded(
                      child: GestureDetector(onTap: () => _updateStatus(2)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
