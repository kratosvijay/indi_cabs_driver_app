// ignore_for_file: unused_field

import 'package:flutter/material.dart';

class RideStatusSlider extends StatefulWidget {
  final Function() onSlideComplete;
  final String label;
  final Color color;
  final bool isEnabled;

  const RideStatusSlider({
    super.key,
    required this.onSlideComplete,
    required this.label,
    this.color = Colors.green,
    this.isEnabled = true,
  });

  @override
  State<RideStatusSlider> createState() => _RideStatusSliderState();
}

class _RideStatusSliderState extends State<RideStatusSlider> {
  double _dragValue = 0.0;
  final double _maxWidth =
      300.0; // Approximate width, will be constrained by parent

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final thumbSize = 60.0;
        final maxDrag = width - thumbSize;

        return Container(
          height: thumbSize,
          decoration: BoxDecoration(
            color: widget.color.withValues(
              alpha: 0.2,
            ), // Changed to withOpacity for compatibility
            borderRadius: BorderRadius.circular(thumbSize / 2),
          ),
          child: Stack(
            children: [
              // Label
              Center(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    color: widget.color,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ),

              // Slider Thumb
              Positioned(
                // Adjust for the extra padding (20 on each side)
                left: _dragValue - 20,
                top:
                    -20, // Center vertically relative to the 60px height container
                child: GestureDetector(
                  behavior:
                      HitTestBehavior.translucent, // Ensure touches are caught
                  onHorizontalDragStart: (_) =>
                      debugPrint("Slider: Drag Start"),
                  onHorizontalDragUpdate: (details) {
                    if (!widget.isEnabled) {
                      debugPrint("Slider: Disabled!");
                      return;
                    }
                    setState(() {
                      _dragValue += details.delta.dx;
                      _dragValue = _dragValue.clamp(0.0, maxDrag);
                    });
                    // continuous log is too noisy, maybe log every 10px?
                  },
                  onHorizontalDragEnd: (details) {
                    debugPrint("Slider: Drag End at $_dragValue / $maxDrag");
                    if (!widget.isEnabled) return;

                    // Threshold check (70%)
                    if (_dragValue >= maxDrag * 0.70) {
                      debugPrint("Slider: Threshold Met! Triggering action.");
                      setState(() {
                        _dragValue = maxDrag;
                      });
                      widget.onSlideComplete();

                      Future.delayed(const Duration(milliseconds: 500), () {
                        if (mounted) {
                          setState(() {
                            _dragValue = 0.0;
                          });
                        }
                      });
                    } else {
                      debugPrint("Slider: Threshold NOT met. Resetting.");
                      setState(() {
                        _dragValue = 0.0;
                      });
                    }
                  },
                  // Expand touch targets
                  child: Container(
                    color: Colors.transparent, // Invisible touch area
                    padding: const EdgeInsets.all(
                      20,
                    ), // 20px extra touch padding
                    child: Container(
                      width: thumbSize,
                      height: thumbSize,
                      decoration: BoxDecoration(
                        color: widget.color,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 4,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.arrow_forward_ios,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
