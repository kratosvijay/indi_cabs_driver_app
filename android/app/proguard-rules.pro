# ============================================================
# Flutter Engine — core classes used by all Flutter plugins
# ============================================================
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**

# Flutter embedding (Activity, Fragment, engine lifecycle)
-keep class io.flutter.embedding.engine.** { *; }
-keep class io.flutter.embedding.android.** { *; }
-keep class io.flutter.plugin.common.** { *; }
-keep class io.flutter.plugin.platform.** { *; }
-keep class io.flutter.view.** { *; }

# ============================================================
# GeneratedPluginRegistrant
# The overlay isolate calls DartPluginRegistrant.ensureInitialized()
# which internally references this class. R8 must NOT remove or
# rename it, otherwise the overlay engine has no plugins at all.
# ============================================================
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }
# Wildcard form in case the generated class ends up in a sub-package
-keep class **.GeneratedPluginRegistrant { *; }

# ============================================================
# flutter_overlay_window
# ============================================================
-keep class flutter.overlay.window.** { *; }
-keep interface flutter.overlay.window.** { *; }
-dontwarn flutter.overlay.window.**

# ============================================================
# flutter_foreground_task (v9+)
# The ForegroundService is started by class name from the manifest;
# R8 must keep the full class and all its members.
# ============================================================
-keep class com.pravera.flutter_foreground_task.** { *; }
-keep interface com.pravera.flutter_foreground_task.** { *; }
-keepnames class * implements com.pravera.flutter_foreground_task.service.ForegroundServiceManager
-dontwarn com.pravera.flutter_foreground_task.**

# ============================================================
# Common AndroidX (lifecycle, work-manager used by plugins)
# ============================================================
-keep class androidx.lifecycle.** { *; }
-keep class androidx.work.** { *; }
-dontwarn androidx.work.**

# ============================================================
# Firebase / Crashlytics
# ============================================================
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# ============================================================
# Geolocator (background location updates)
# ============================================================
-keep class com.baseflow.geolocator.** { *; }
-dontwarn com.baseflow.geolocator.**

# ============================================================
# Google Maps / Navigation SDK
# ============================================================
-keep class com.google.android.libraries.navigation.** { *; }
-dontwarn com.google.android.libraries.navigation.**
-keep class com.google.maps.android.** { *; }
-dontwarn com.google.maps.android.**

# ============================================================
# Serialization safety (overlay passes Map<String,dynamic> data
# through platform channels; keep serializable helpers)
# ============================================================
-keepclassmembers class * implements java.io.Serializable {
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# ============================================================
# Dart VM / AOT entry-point bridge
# The JNI layer looks up Dart entry points by name; keep the
# native bridge so R8 does not inline or remove the lookup.
# ============================================================
-keep class io.flutter.embedding.engine.FlutterJNI { *; }
-keepclasseswithmembernames class io.flutter.embedding.engine.FlutterJNI {
    native <methods>;
}
