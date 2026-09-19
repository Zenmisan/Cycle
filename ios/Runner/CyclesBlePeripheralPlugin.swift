import Flutter
import UIKit
import CoreBluetooth

/**
 * Platform channel plugin hosting a CoreBluetooth GATT Server (CBPeripheralManager) on iOS.
 * Advertises the Cycles sync service and characteristic for peer-to-peer sync.
 */
public class CyclesBlePeripheralPlugin: NSObject, FlutterPlugin, CBPeripheralManagerDelegate {

    private static let serviceUUID = CBUUID(string: "6379636c-6573-7379-6e63-000000000001")
    private static let characteristicUUID = CBUUID(string: "6379636c-6573-7379-6e63-000000000002")

    private var channel: FlutterMethodChannel?
    private var peripheralManager: CBPeripheralManager?
    private var syncCharacteristic: CBMutableCharacteristic?
    private var isAdvertising: Bool = false
    private var localName: String = "Cycles-iOS"
    private var outgoingQueue: [Data] = []

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "cycles/ble_peripheral", binaryMessenger: registrar.messenger())
        let instance = CyclesBlePeripheralPlugin()
        instance.channel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startAdvertising":
            guard let args = call.arguments as? [String: Any],
                  let name = args["name"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Name required", details: nil))
                return
            }
            self.localName = name
            startPeripheral()
            result("Peripheral advertising started for \(name)")

        case "stopAdvertising":
            stopPeripheral()
            result("Peripheral advertising stopped")

        case "isAdvertising":
            result(isAdvertising)

        case "enqueueResponse":
            if let args = call.arguments as? [String: Any],
               let data = args["data"] as? FlutterStandardTypedData {
                outgoingQueue.append(data.data)
                result(true)
            } else {
                result(false)
            }

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func startPeripheral() {
        if peripheralManager == nil {
            peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
        } else if peripheralManager?.state == .poweredOn {
            setupServiceAndAdvertise()
        }
    }

    private func stopPeripheral() {
        if isAdvertising {
            peripheralManager?.stopAdvertising()
            peripheralManager?.removeAllServices()
            isAdvertising = false
            channel?.invokeMethod("onAdvertisingStateChanged", false)
        }
    }

    private func setupServiceAndAdvertise() {
        guard let manager = peripheralManager, manager.state == .poweredOn else { return }

        manager.removeAllServices()

        let characteristic = CBMutableCharacteristic(
            type: Self.characteristicUUID,
            properties: [.read, .write, .writeWithoutResponse, .notify],
            value: nil,
            permissions: [.readable, .writeable]
        )
        self.syncCharacteristic = characteristic

        let service = CBMutableService(type: Self.serviceUUID, primary: true)
        service.characteristics = [characteristic]
        manager.add(service)

        let advertisementData: [String: Any] = [
            CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID],
            CBAdvertisementDataLocalNameKey: localName
        ]
        manager.startAdvertising(advertisementData)
        isAdvertising = true
        channel?.invokeMethod("onAdvertisingStateChanged", true)
    }

    // MARK: - CBPeripheralManagerDelegate

    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            if !isAdvertising {
                setupServiceAndAdvertise()
            }
        case .poweredOff, .unauthorized, .unsupported, .resetting:
            stopPeripheral()
        @unknown default:
            break
        }
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            if request.characteristic.uuid == Self.characteristicUUID {
                if let value = request.value {
                    channel?.invokeMethod("onFrameReceived", ["data": FlutterStandardTypedData(bytes: value)])
                }
                peripheral.respond(to: request, withResult: .success)
            } else {
                peripheral.respond(to: request, withResult: .attributeNotFound)
            }
        }
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        if request.characteristic.uuid == Self.characteristicUUID {
            if !outgoingQueue.isEmpty {
                let nextChunk = outgoingQueue.removeFirst()
                request.value = nextChunk
                peripheral.respond(to: request, withResult: .success)
            } else {
                request.value = Data()
                peripheral.respond(to: request, withResult: .success)
            }
        } else {
            peripheral.respond(to: request, withResult: .attributeNotFound)
        }
    }
}
