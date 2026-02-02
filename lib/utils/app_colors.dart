import 'package:flutter/material.dart';

class AppColors {
  // Light Theme Colors
  static final lightStart = Colors.blue.shade400;
  static final lightEnd = Colors.indigo.shade400;

  // Dark Theme Colors
  static final darkStart = Colors.blueGrey.shade900;
  static final darkEnd = Colors.black87;

  // Primary Color Alias
  static final primary = lightEnd;

  // Helper to get the Gradient based on current context
  static LinearGradient getAppBarGradient(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    return LinearGradient(
      colors: dark ? [darkStart, darkEnd] : [lightStart, lightEnd],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }
}
