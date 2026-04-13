package com.example.project_taxi_driver_app

import android.os.Bundle
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsControllerCompat
import android.view.WindowInsets
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Enable edge-to-edge
        WindowCompat.setDecorFitsSystemWindows(window, false)

        val controller = WindowInsetsControllerCompat(window, window.decorView)
        // Hide both status bar and navigation bar (Immersive Mode)
        controller.hide(WindowInsets.Type.systemBars())
        controller.systemBarsBehavior =
            WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
    }
}
