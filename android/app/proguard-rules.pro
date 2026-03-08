# Keep flutter_overlay_window classes
-keep class flutter.overlay.window.** { *; }

# Keep foreground tasks if used simultaneously (common issue on Android 12+)
-keep class com.pravera.flutter_foreground_task.** { *; }
