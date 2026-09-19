package com.example.cycles

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.NetworkInfo
import android.net.wifi.p2p.WifiP2pConfig
import android.net.wifi.p2p.WifiP2pDevice
import android.net.wifi.p2p.WifiP2pDeviceList
import android.net.wifi.p2p.WifiP2pInfo
import android.net.wifi.p2p.WifiP2pManager
import android.net.wifi.WpsInfo
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Platform channel plugin exposing Android WifiP2pManager (Wi-Fi Direct) to Flutter.
 * Handles peer discovery, connection establishment, connection info queries, and teardown.
 */
class WifiDirectPlugin(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel: MethodChannel = MethodChannel(messenger, "cycles/wifi_direct")
    private val manager: WifiP2pManager? =
        context.getSystemService(Context.WIFI_P2P_SERVICE) as? WifiP2pManager
    private var p2pChannel: WifiP2pManager.Channel? = null
    private val receiver: BroadcastReceiver

    private var isP2pEnabled: Boolean = false
    private var cachedPeers: List<WifiP2pDevice> = emptyList()

    init {
        channel.setMethodCallHandler(this)
        p2pChannel = manager?.initialize(context, context.mainLooper, null)

        receiver = object : BroadcastReceiver() {
            override fun onReceive(c: Context?, intent: Intent?) {
                when (intent?.action) {
                    WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION -> {
                        val state = intent.getIntExtra(WifiP2pManager.EXTRA_WIFI_STATE, -1)
                        isP2pEnabled = state == WifiP2pManager.WIFI_P2P_STATE_ENABLED
                        channel.invokeMethod("onStateChanged", isP2pEnabled)
                    }
                    WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION -> {
                        p2pChannel?.let { ch ->
                            try {
                                manager?.requestPeers(ch) { peers: WifiP2pDeviceList? ->
                                    val list = peers?.deviceList?.toList() ?: emptyList()
                                    cachedPeers = list
                                    val mapped = list.map { mapDevice(it) }
                                    channel.invokeMethod("onPeersDiscovered", mapped)
                                }
                            } catch (_: SecurityException) {
                                // Missing runtime permission on Android 13+
                            }
                        }
                    }
                    WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION -> {
                        val networkInfo =
                            intent.getParcelableExtra<NetworkInfo>(WifiP2pManager.EXTRA_NETWORK_INFO)
                        if (networkInfo?.isConnected == true) {
                            p2pChannel?.let { ch ->
                                manager?.requestConnectionInfo(ch) { info: WifiP2pInfo? ->
                                    if (info != null) {
                                        channel.invokeMethod("onConnectionChanged", mapConnectionInfo(info))
                                    }
                                }
                            }
                        } else {
                            channel.invokeMethod("onConnectionChanged", mapOf("groupFormed" to false))
                        }
                    }
                }
            }
        }

        val intentFilter = IntentFilter().apply {
            addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION)
        }
        context.registerReceiver(receiver, intentFilter)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> {
                val supported = context.packageManager.hasSystemFeature(PackageManager.FEATURE_WIFI_DIRECT)
                result.success(supported)
            }
            "discoverPeers" -> {
                val ch = p2pChannel
                if (manager == null || ch == null) {
                    result.error("UNAVAILABLE", "Wi-Fi Direct manager not initialized", null)
                    return
                }
                try {
                    manager.discoverPeers(ch, object : WifiP2pManager.ActionListener {
                        override fun onSuccess() {
                            result.success(true)
                        }

                        override fun onFailure(reasonCode: Int) {
                            result.error("DISCOVERY_FAILED", "Failed with reason code: $reasonCode", null)
                        }
                    })
                } catch (e: SecurityException) {
                    result.error("PERMISSION_DENIED", "Missing location/nearby permission: ${e.message}", null)
                }
            }
            "getDiscoveredPeers" -> {
                val mapped = cachedPeers.map { mapDevice(it) }
                result.success(mapped)
            }
            "connect" -> {
                val address = call.argument<String>("deviceAddress")
                val ch = p2pChannel
                if (manager == null || ch == null) {
                    result.error("UNAVAILABLE", "Wi-Fi Direct manager not initialized", null)
                    return
                }
                if (address.isNullOrBlank()) {
                    result.error("INVALID_ARGUMENT", "deviceAddress is required", null)
                    return
                }
                val config = WifiP2pConfig().apply {
                    deviceAddress = address
                    wps.setup = WpsInfo.PBC
                }
                try {
                    manager.connect(ch, config, object : WifiP2pManager.ActionListener {
                        override fun onSuccess() {
                            result.success(true)
                        }

                        override fun onFailure(reasonCode: Int) {
                            result.error("CONNECT_FAILED", "Connection failed with reason: $reasonCode", null)
                        }
                    })
                } catch (e: SecurityException) {
                    result.error("PERMISSION_DENIED", "Missing location/nearby permission: ${e.message}", null)
                }
            }
            "getConnectionInfo" -> {
                val ch = p2pChannel
                if (manager == null || ch == null) {
                    result.error("UNAVAILABLE", "Wi-Fi Direct manager not initialized", null)
                    return
                }
                manager.requestConnectionInfo(ch) { info: WifiP2pInfo? ->
                    if (info == null) {
                        result.success(mapOf("groupFormed" to false))
                    } else {
                        result.success(mapConnectionInfo(info))
                    }
                }
            }
            "disconnect" -> {
                val ch = p2pChannel
                if (manager == null || ch == null) {
                    result.error("UNAVAILABLE", "Wi-Fi Direct manager not initialized", null)
                    return
                }
                manager.removeGroup(ch, object : WifiP2pManager.ActionListener {
                    override fun onSuccess() {
                        result.success(true)
                    }

                    override fun onFailure(reasonCode: Int) {
                        result.error("DISCONNECT_FAILED", "RemoveGroup failed with reason: $reasonCode", null)
                    }
                })
            }
            else -> result.notImplemented()
        }
    }

    private fun mapDevice(device: WifiP2pDevice): Map<String, Any?> {
        return mapOf(
            "deviceName" to device.deviceName,
            "deviceAddress" to device.deviceAddress,
            "primaryDeviceType" to (device.primaryDeviceType ?: ""),
            "status" to device.status
        )
    }

    private fun mapConnectionInfo(info: WifiP2pInfo): Map<String, Any?> {
        return mapOf(
            "groupFormed" to info.groupFormed,
            "isGroupOwner" to info.isGroupOwner,
            "groupOwnerAddress" to (info.groupOwnerAddress?.hostAddress ?: "")
        )
    }

    fun detach() {
        try {
            context.unregisterReceiver(receiver)
        } catch (_: Exception) {}
        channel.setMethodCallHandler(null)
    }
}
