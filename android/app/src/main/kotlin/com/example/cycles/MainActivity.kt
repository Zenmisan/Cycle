package com.example.cycles

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var wifiDirectPlugin: WifiDirectPlugin? = null
    private var blePermissionsPlugin: BlePermissionsPlugin? = null
    private var widgetDataPlugin: WidgetDataPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        val context = applicationContext

        wifiDirectPlugin = WifiDirectPlugin(context, messenger)
        blePermissionsPlugin = BlePermissionsPlugin(context, this, messenger)
        widgetDataPlugin = WidgetDataPlugin(context, messenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        wifiDirectPlugin?.detach()
        wifiDirectPlugin = null

        blePermissionsPlugin?.detach()
        blePermissionsPlugin = null

        widgetDataPlugin?.detach()
        widgetDataPlugin = null

        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        if (blePermissionsPlugin?.onRequestPermissionsResult(requestCode, permissions, grantResults) == true) {
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }
}
