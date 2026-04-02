# Flutter Engine and standard plugins
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**

# GeneratedPluginRegistrant (important for background isolates)
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }

# flutter_overlay_window
-keep class flutter.overlay.window.** { *; }
-keep interface flutter.overlay.window.** { *; }
-dontwarn flutter.overlay.window.**

# flutter_foreground_task
-keep class com.pravera.flutter_foreground_task.** { *; }
-keep interface com.pravera.flutter_foreground_task.** { *; }
-dontwarn com.pravera.flutter_foreground_task.**

# Common AndroidX Lifecycle (needed by plugins)
-keep class androidx.lifecycle.** { *; }
