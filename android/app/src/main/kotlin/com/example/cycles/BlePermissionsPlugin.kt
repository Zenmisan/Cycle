package com.example.cycles

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/**
 * Platform channel plugin handling BLE runtime permissions for Android 12+ (API 31+)
 * and legacy Android versions (API <= 30).
 */
class BlePermissionsPlugin(
    private val context: Context,
    private var activity: Activity?,
    messenger: BinaryMessenger
) : MethodChannel.MethodCallHandler, PluginRegistry.RequestPermissionsResultListener {

    private val channel: MethodChannel = MethodChannel(messenger, "cycles/ble_permissions")
    private var pendingResult: MethodChannel.Result? = null

    companion object {
        private const val BLE_PERMISSION_REQUEST_CODE = 47230
    }

    init {
        channel.setMethodCallHandler(this)
    }

    fun updateActivity(act: Activity?) {
        this.activity = act
    }

    fun detach() {
        channel.setMethodCallHandler(null)
        this.activity = null
        this.pendingResult = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "checkPermissions" -> {
                result.success(getPermissionsStatus())
            }
            "requestPermissions" -> {
                handleRequestPermissions(result)
            }
            else -> result.notImplemented()
        }
    }

    private fun getRequiredPermissions(): Array<String> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(
                Manifest.permission.BLUETOOTH_SCAN,
                Manifest.permission.BLUETOOTH_CONNECT,
                Manifest.permission.BLUETOOTH_ADVERTISE
            )
        } else {
            arrayOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.BLUETOOTH,
                Manifest.permission.BLUETOOTH_ADMIN
            )
        }
    }

    private fun getPermissionsStatus(): Map<String, Any> {
        val required = getRequiredPermissions()
        val denied = mutableListOf<String>()

        for (permission in required) {
            if (ContextCompat.checkSelfPermission(context, permission) != PackageManager.PERMISSION_GRANTED) {
                denied.add(permission)
            }
        }

        return mapOf(
            "granted" to denied.isEmpty(),
            "deniedPermissions" to denied,
            "apiLevel" to Build.VERSION.SDK_INT
        )
    }

    private fun handleRequestPermissions(result: MethodChannel.Result) {
        val currentActivity = activity
        if (currentActivity == null) {
            result.error("NO_ACTIVITY", "Cannot request permissions without active Activity", null)
            return
        }

        val required = getRequiredPermissions()
        val missing = required.filter {
            ContextCompat.checkSelfPermission(context, it) != PackageManager.PERMISSION_GRANTED
        }

        if (missing.isEmpty()) {
            result.success(mapOf(
                "granted" to true,
                "deniedPermissions" to emptyList<String>()
            ))
            return
        }

        pendingResult = result
        ActivityCompat.requestPermissions(
            currentActivity,
            missing.toTypedArray(),
            BLE_PERMISSION_REQUEST_CODE
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        if (requestCode != BLE_PERMISSION_REQUEST_CODE) {
            return false
        }

        val currentResult = pendingResult ?: return false
        pendingResult = null

        val denied = mutableListOf<String>()
        for (i in permissions.indices) {
            if (i < grantResults.size && grantResults[i] != PackageManager.PERMISSION_GRANTED) {
                denied.add(permissions[i])
            }
        }

        currentResult.success(mapOf(
            "granted" to denied.isEmpty(),
            "deniedPermissions" to denied
        ))
        return true
    }
}
