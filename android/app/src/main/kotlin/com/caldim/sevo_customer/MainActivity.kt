package com.caldim.sevo_customer

import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.GeneratedPluginRegistrant

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        try {
            GeneratedPluginRegistrant.registerWith(flutterEngine)
        } catch (t: Throwable) {
            Log.e("MainActivity", "Failed to register plugins safely: ${t.message}", t)
        }
    }
}
