package com.example.cycles

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var wifiDirectPlugin: WifiDirectPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        wifiDirectPlugin = WifiDirectPlugin(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        wifiDirectPlugin?.detach()
        wifiDirectPlugin = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
