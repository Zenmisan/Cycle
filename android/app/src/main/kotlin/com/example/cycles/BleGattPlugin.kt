package com.example.cycles

import android.annotation.SuppressLint
import android.bluetooth.*
import android.bluetooth.le.*
import android.content.Context
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.zip.CRC32

/**
 * Native Android BLE GATT Plugin for Cycles.
 * Provides hardware-level BLE Advertising, Central Scanning, GATT Server, and GATT Client
 * for true off-network peer-to-peer task synchronization.
 */
class BleGattPlugin(
    private val context: Context,
    messenger: BinaryMessenger
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "CyclesBleGatt"
        private const val CHANNEL_NAME = "cycles/ble_gatt"

        val CYCLES_SERVICE_UUID: UUID = UUID.fromString("6379636c-6573-7379-6e63-000000000001")
        val CYCLES_CHAR_SYNC_UUID: UUID = UUID.fromString("6379636c-6573-7379-6e63-000000000002")
        val CLIENT_CONFIG_DESCRIPTOR_UUID: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

        private const val FRAME_HEADER_LEN = 6
        private const val FRAME_TRAILER_LEN = 4
        private const val MIN_FRAME_LEN = 10
        private const val DEFAULT_CHUNK_SIZE = 240
    }

    private val channel: MethodChannel = MethodChannel(messenger, CHANNEL_NAME)
    private val mainHandler = Handler(Looper.getMainLooper())

    private val bluetoothManager: BluetoothManager? =
        context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
    private val bluetoothAdapter: BluetoothAdapter? = bluetoothManager?.adapter

    private var bleAdvertiser: BluetoothLeAdvertiser? = null
    private var bleScanner: BluetoothLeScanner? = null
    private var gattServer: BluetoothGattServer? = null

    private var isAdvertising = false
    private var isScanning = false
    private var localDeviceId: String = ""
    private var localDisplayName: String = ""

    // GATT Server state
    private val serverIncomingFrames = ConcurrentHashMap<String, MutableMap<Int, ByteArray>>()
    private val serverOutgoingQueue = mutableListOf<ByteArray>()

    init {
        channel.setMethodCallHandler(this)
    }

    fun detach() {
        stopAdvertisingInternal()
        stopScanInternal()
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> {
                val supported = context.packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE) &&
                        bluetoothAdapter != null
                result.success(supported)
            }
            "isEnabled" -> {
                result.success(bluetoothAdapter?.isEnabled == true)
            }
            "startAdvertising" -> {
                val deviceId = call.argument<String>("deviceId") ?: ""
                val name = call.argument<String>("name") ?: "Cycles-${deviceId.take(8)}"
                startAdvertisingInternal(deviceId, name, result)
            }
            "stopAdvertising" -> {
                stopAdvertisingInternal()
                result.success(true)
            }
            "isAdvertising" -> {
                result.success(isAdvertising)
            }
            "startScan" -> {
                startScanInternal(result)
            }
            "stopScan" -> {
                stopScanInternal()
                result.success(true)
            }
            "isScanning" -> {
                result.success(isScanning)
            }
            "syncWithPeer" -> {
                val address = call.argument<String>("address") ?: ""
                val peerId = call.argument<String>("peerId") ?: ""
                val payload = call.argument<ByteArray>("payload") ?: ByteArray(0)
                syncWithPeerInternal(address, peerId, payload, result)
            }
            "enqueueServerResponse" -> {
                val payload = call.argument<ByteArray>("payload") ?: ByteArray(0)
                enqueueServerResponseInternal(payload)
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Advertising & GATT Server
    // ─────────────────────────────────────────────────────────────────────────────

    @SuppressLint("MissingPermission")
    private fun startAdvertisingInternal(deviceId: String, name: String, result: MethodChannel.Result) {
        if (bluetoothAdapter == null || !bluetoothAdapter.isEnabled) {
            result.error("BLUETOOTH_DISABLED", "Bluetooth adapter is off or unavailable", null)
            return
        }

        bleAdvertiser = bluetoothAdapter.bluetoothLeAdvertiser
        if (bleAdvertiser == null) {
            result.error("ADVERTISER_UNAVAILABLE", "BLE hardware advertising not supported on this device", null)
            return
        }

        localDeviceId = deviceId
        localDisplayName = name

        // Start GATT Server
        setupGattServer()

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setConnectable(true)
            .setTimeout(0)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .build()

        val data = AdvertiseData.Builder()
            .setIncludeDeviceName(true)
            .addServiceUuid(ParcelUuid(CYCLES_SERVICE_UUID))
            .build()

        bleAdvertiser?.startAdvertising(settings, data, advertiseCallback)
        isAdvertising = true
        result.success("BLE advertising started as $name")
    }

    @SuppressLint("MissingPermission")
    private fun stopAdvertisingInternal() {
        try {
            bleAdvertiser?.stopAdvertising(advertiseCallback)
        } catch (e: Exception) {
            Log.w(TAG, "Error stopping advertiser", e)
        }
        bleAdvertiser = null
        isAdvertising = false

        try {
            gattServer?.close()
        } catch (e: Exception) {
            Log.w(TAG, "Error closing GATT server", e)
        }
        gattServer = null
        serverIncomingFrames.clear()
        synchronized(serverOutgoingQueue) {
            serverOutgoingQueue.clear()
        }
    }

    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
            Log.i(TAG, "BLE advertising started successfully")
        }

        override fun onStartFailure(errorCode: Int) {
            Log.e(TAG, "BLE advertising start failed with error code: $errorCode")
            isAdvertising = false
        }
    }

    @SuppressLint("MissingPermission")
    private fun setupGattServer() {
        if (gattServer != null) return

        gattServer = bluetoothManager?.openGattServer(context, object : BluetoothGattServerCallback() {
            override fun onConnectionStateChange(device: BluetoothDevice?, status: Int, newState: Int) {
                Log.d(TAG, "GATT server connection state: ${device?.address} status=$status newState=$newState")
            }

            override fun onCharacteristicReadRequest(
                device: BluetoothDevice?,
                requestId: Int,
                offset: Int,
                characteristic: BluetoothGattCharacteristic?
            ) {
                if (characteristic?.uuid == CYCLES_CHAR_SYNC_UUID) {
                    val frameToSend = synchronized(serverOutgoingQueue) {
                        if (serverOutgoingQueue.isNotEmpty()) serverOutgoingQueue.removeAt(0) else ByteArray(0)
                    }
                    val chunk = if (offset < frameToSend.size) {
                        frameToSend.copyOfRange(offset, frameToSend.size)
                    } else {
                        ByteArray(0)
                    }
                    gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, chunk)
                } else {
                    gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_FAILURE, 0, null)
                }
            }

            override fun onCharacteristicWriteRequest(
                device: BluetoothDevice?,
                requestId: Int,
                characteristic: BluetoothGattCharacteristic?,
                preparedWrite: Boolean,
                responseNeeded: Boolean,
                offset: Int,
                value: ByteArray?
            ) {
                if (characteristic?.uuid == CYCLES_CHAR_SYNC_UUID && value != null) {
                    handleIncomingServerFrame(device?.address ?: "unknown", value)
                    if (responseNeeded) {
                        gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value)
                    }
                } else {
                    if (responseNeeded) {
                        gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_FAILURE, 0, null)
                    }
                }
            }
        })

        val service = BluetoothGattService(CYCLES_SERVICE_UUID, BluetoothGattService.SERVICE_TYPE_PRIMARY)
        val syncChar = BluetoothGattCharacteristic(
            CYCLES_CHAR_SYNC_UUID,
            BluetoothGattCharacteristic.PROPERTY_READ or
                    BluetoothGattCharacteristic.PROPERTY_WRITE or
                    BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE or
                    BluetoothGattCharacteristic.PROPERTY_NOTIFY,
            BluetoothGattCharacteristic.PERMISSION_READ or BluetoothGattCharacteristic.PERMISSION_WRITE
        )
        val ccc = BluetoothGattDescriptor(
            CLIENT_CONFIG_DESCRIPTOR_UUID,
            BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE
        )
        syncChar.addDescriptor(ccc)
        service.addCharacteristic(syncChar)
        gattServer?.addService(service)
    }

    private fun handleIncomingServerFrame(deviceAddress: String, frameBytes: ByteArray) {
        val decoded = decodeFrame(frameBytes) ?: return
        val framesMap = serverIncomingFrames.computeIfAbsent(deviceAddress) { ConcurrentHashMap() }
        framesMap[decoded.seq] = decoded.payload

        if (framesMap.size >= decoded.totalChunks) {
            val fullPayload = reassembleFrames(framesMap, decoded.totalChunks)
            serverIncomingFrames.remove(deviceAddress)
            if (fullPayload != null) {
                mainHandler.post {
                    channel.invokeMethod(
                        "onSyncMessageReceived",
                        mapOf(
                            "peerAddress" to deviceAddress,
                            "payload" to fullPayload
                        )
                    )
                }
            }
        }
    }

    private fun enqueueServerResponseInternal(payload: ByteArray) {
        val frames = chunkPayload(1, payload, DEFAULT_CHUNK_SIZE)
        synchronized(serverOutgoingQueue) {
            serverOutgoingQueue.clear()
            for (f in frames) {
                serverOutgoingQueue.add(encodeFrame(f))
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Central Scanning
    // ─────────────────────────────────────────────────────────────────────────────

    @SuppressLint("MissingPermission")
    private fun startScanInternal(result: MethodChannel.Result) {
        if (bluetoothAdapter == null || !bluetoothAdapter.isEnabled) {
            result.error("BLUETOOTH_DISABLED", "Bluetooth adapter is off or unavailable", null)
            return
        }

        bleScanner = bluetoothAdapter.bluetoothLeScanner
        if (bleScanner == null) {
            result.error("SCANNER_UNAVAILABLE", "BLE scanner unavailable", null)
            return
        }

        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()

        // Filter for Cycles service UUID
        val filters = listOf(
            ScanFilter.Builder().setServiceUuid(ParcelUuid(CYCLES_SERVICE_UUID)).build()
        )

        try {
            bleScanner?.startScan(filters, settings, scanCallback)
            isScanning = true
            result.success(true)
        } catch (e: Exception) {
            // Fallback to open scan if service UUID filter is strict on some OEM ROMs
            bleScanner?.startScan(scanCallback)
            isScanning = true
            result.success(true)
        }
    }

    @SuppressLint("MissingPermission")
    private fun stopScanInternal() {
        try {
            bleScanner?.stopScan(scanCallback)
        } catch (e: Exception) {
            Log.w(TAG, "Error stopping scan", e)
        }
        bleScanner = null
        isScanning = false
    }

    private val scanCallback = object : ScanCallback() {
        @SuppressLint("MissingPermission")
        override fun onScanResult(callbackType: Int, result: ScanResult?) {
            result ?: return
            val device = result.device ?: return
            val scanRecord = result.scanRecord
            val name = scanRecord?.deviceName ?: device.name ?: ""

            // Must match Cycles prefix or Service UUID
            val hasCyclesUuid = scanRecord?.serviceUuids?.any { it.uuid == CYCLES_SERVICE_UUID } == true
            val hasCyclesName = name.startsWith("Cycles-")

            if (hasCyclesUuid || hasCyclesName) {
                val shortId = if (name.startsWith("Cycles-")) {
                    name.removePrefix("Cycles-")
                } else {
                    device.address.replace(":", "").take(8).lowercase()
                }

                val displayName = if (name.isNotEmpty()) name else "Cycles-$shortId"

                mainHandler.post {
                    channel.invokeMethod(
                        "onPeerDiscovered",
                        mapOf(
                            "deviceId" to shortId,
                            "displayName" to displayName,
                            "address" to device.address,
                            "rssi" to result.rssi
                        )
                    )
                }
            }
        }

        override fun onScanFailed(errorCode: Int) {
            Log.e(TAG, "BLE scan failed with error: $errorCode")
            isScanning = false
        }
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Central GATT Client Sync
    // ─────────────────────────────────────────────────────────────────────────────

    @SuppressLint("MissingPermission")
    private fun syncWithPeerInternal(
        address: String,
        peerId: String,
        payload: ByteArray,
        flutterResult: MethodChannel.Result
    ) {
        val device = try {
            bluetoothAdapter?.getRemoteDevice(address)
        } catch (e: Exception) {
            flutterResult.error("INVALID_ADDRESS", "Bad device address: $address", null)
            return
        }

        if (device == null) {
            flutterResult.error("DEVICE_NOT_FOUND", "Device not found for $address", null)
            return
        }

        Thread {
            executeCentralSync(device, payload, flutterResult)
        }.start()
    }

    @SuppressLint("MissingPermission")
    private fun executeCentralSync(
        device: BluetoothDevice,
        payload: ByteArray,
        flutterResult: MethodChannel.Result
    ) {
        var gattInstance: BluetoothGatt? = null
        val lock = Object()
        var connectionSuccess = false
        var mtuReady = false
        var serviceFound = false
        var syncChar: BluetoothGattCharacteristic? = null
        var writeFinished = false
        var responsePayload: ByteArray? = null
        var errorMessage: String? = null

        val incomingResponseFrames = mutableMapOf<Int, ByteArray>()

        val gattCallback = object : BluetoothGattCallback() {
            override fun onConnectionStateChange(gatt: BluetoothGatt?, status: Int, newState: Int) {
                if (status == BluetoothGatt.GATT_SUCCESS && newState == BluetoothProfile.STATE_CONNECTED) {
                    connectionSuccess = true
                    gatt?.requestMtu(512)
                } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                    synchronized(lock) {
                        lock.notifyAll()
                    }
                }
            }

            override fun onMtuChanged(gatt: BluetoothGatt?, mtu: Int, status: Int) {
                mtuReady = true
                gatt?.discoverServices()
            }

            override fun onServicesDiscovered(gatt: BluetoothGatt?, status: Int) {
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    val service = gatt?.getService(CYCLES_SERVICE_UUID)
                    syncChar = service?.getCharacteristic(CYCLES_CHAR_SYNC_UUID)
                    serviceFound = syncChar != null
                }
                synchronized(lock) {
                    lock.notifyAll()
                }
            }

            override fun onCharacteristicWrite(
                gatt: BluetoothGatt?,
                characteristic: BluetoothGattCharacteristic?,
                status: Int
            ) {
                synchronized(lock) {
                    writeFinished = true
                    lock.notifyAll()
                }
            }

            override fun onCharacteristicRead(
                gatt: BluetoothGatt?,
                characteristic: BluetoothGattCharacteristic?,
                status: Int
            ) {
                if (status == BluetoothGatt.GATT_SUCCESS && characteristic?.value != null) {
                    val frameBytes = characteristic.value
                    val decoded = decodeFrame(frameBytes)
                    if (decoded != null) {
                        incomingResponseFrames[decoded.seq] = decoded.payload
                        if (incomingResponseFrames.size >= decoded.totalChunks) {
                            responsePayload = reassembleFrames(incomingResponseFrames, decoded.totalChunks)
                        }
                    }
                }
                synchronized(lock) {
                    lock.notifyAll()
                }
            }
        }

        try {
            gattInstance = device.connectGatt(context, false, gattCallback, BluetoothDevice.TRANSPORT_LE)

            // 1. Wait for connection & service discovery (up to 10s)
            synchronized(lock) {
                val start = System.currentTimeMillis()
                while (!serviceFound && System.currentTimeMillis() - start < 10000) {
                    lock.wait(500)
                }
            }

            val targetChar = syncChar
            if (!serviceFound || targetChar == null) {
                throw Exception("Cycles sync GATT service/characteristic not found on $device")
            }

            // 2. Chunk and transmit outgoing sync message
            val frames = chunkPayload(1, payload, DEFAULT_CHUNK_SIZE)
            for (frame in frames) {
                val encoded = encodeFrame(frame)
                targetChar.value = encoded
                targetChar.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT

                synchronized(lock) {
                    writeFinished = false
                    gattInstance.writeCharacteristic(targetChar)
                    val writeStart = System.currentTimeMillis()
                    while (!writeFinished && System.currentTimeMillis() - writeStart < 5000) {
                        lock.wait(500)
                    }
                }
            }

            // 3. Read response frames from peripheral
            var consecutiveEmptyReads = 0
            while (responsePayload == null && consecutiveEmptyReads < 3) {
                synchronized(lock) {
                    gattInstance.readCharacteristic(targetChar)
                    lock.wait(2000)
                }
                if (incomingResponseFrames.isEmpty()) {
                    consecutiveEmptyReads++
                } else {
                    consecutiveEmptyReads = 0
                }
            }

            val resultBytes = responsePayload ?: ByteArray(0)
            mainHandler.post {
                flutterResult.success(resultBytes)
            }
        } catch (e: Exception) {
            errorMessage = e.message ?: e.toString()
            mainHandler.post {
                flutterResult.error("BLE_SYNC_FAILED", errorMessage, null)
            }
        } finally {
            try {
                gattInstance?.disconnect()
                gattInstance?.close()
            } catch (ignored: Exception) {}
        }
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Wire Protocol Framing & Reassembly (Matching rust/src/ble/framing.rs)
    // ─────────────────────────────────────────────────────────────────────────────

    data class BleFrame(
        val msgId: Int,
        val seq: Int,
        val totalChunks: Int,
        val payload: ByteArray,
        val crc32: Long
    )

    private fun chunkPayload(msgId: Int, data: ByteArray, chunkSize: Int): List<BleFrame> {
        if (data.isEmpty()) {
            return listOf(BleFrame(msgId, 0, 1, ByteArray(0), calculateCrc32(ByteArray(0))))
        }
        val totalChunks = (data.size + chunkSize - 1) / chunkSize
        val frames = mutableListOf<BleFrame>()
        for (i in 0 until totalChunks) {
            val start = i * chunkSize
            val end = minOf(start + chunkSize, data.size)
            val chunk = data.copyOfRange(start, end)
            frames.add(BleFrame(msgId, i, totalChunks, chunk, calculateCrc32(chunk)))
        }
        return frames
    }

    private fun encodeFrame(frame: BleFrame): ByteArray {
        val buffer = ByteBuffer.allocate(MIN_FRAME_LEN + frame.payload.size)
        buffer.order(ByteOrder.BIG_ENDIAN)
        buffer.putShort(frame.msgId.toShort())
        buffer.putShort(frame.seq.toShort())
        buffer.putShort(frame.totalChunks.toShort())
        buffer.put(frame.payload)
        buffer.putInt(frame.crc32.toInt())
        return buffer.array()
    }

    private fun decodeFrame(bytes: ByteArray): BleFrame? {
        if (bytes.size < MIN_FRAME_LEN) return null
        val buffer = ByteBuffer.wrap(bytes)
        buffer.order(ByteOrder.BIG_ENDIAN)
        val msgId = buffer.short.toInt() and 0xFFFF
        val seq = buffer.short.toInt() and 0xFFFF
        val totalChunks = buffer.short.toInt() and 0xFFFF

        val payloadLen = bytes.size - MIN_FRAME_LEN
        val payload = ByteArray(payloadLen)
        buffer.get(payload)

        val expectedCrc = buffer.int.toLong() and 0xFFFFFFFFL
        val calculatedCrc = calculateCrc32(payload)

        if (expectedCrc != calculatedCrc) {
            Log.w(TAG, "CRC32 mismatch on frame seq=$seq: expected=$expectedCrc, calculated=$calculatedCrc")
            return null
        }

        return BleFrame(msgId, seq, totalChunks, payload, expectedCrc)
    }

    private fun reassembleFrames(framesMap: Map<Int, ByteArray>, totalChunks: Int): ByteArray? {
        var totalSize = 0
        for (i in 0 until totalChunks) {
            val chunk = framesMap[i] ?: return null
            totalSize += chunk.size
        }
        val out = ByteArray(totalSize)
        var offset = 0
        for (i in 0 until totalChunks) {
            val chunk = framesMap[i]!!
            System.arraycopy(chunk, 0, out, offset, chunk.size)
            offset += chunk.size
        }
        return out
    }

    private fun calculateCrc32(data: ByteArray): Long {
        val crc = CRC32()
        crc.update(data)
        return crc.value
    }
}
