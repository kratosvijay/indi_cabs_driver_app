package com.example.project_taxi_driver_app

import android.os.Bundle
import androidx.activity.enableEdgeToEdge
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import android.view.WindowManager

class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Enable edge-to-edge before super.onCreate
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        
        // Force layout to ignore limits (status/nav bars)
        window.setFlags(
            WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
        )

        // Ensure decor fits system windows is false (modern way)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        
        // Handle cutouts aggressively for all versions
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
            window.attributes.layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
    }
}
