import Flutter
import UIKit
#if canImport(WidgetKit)
import WidgetKit
#endif

/**
 * Platform channel plugin synchronizing task snapshots from Flutter to the iOS WidgetKit extension.
 */
public class CyclesWidgetPlugin: NSObject, FlutterPlugin {

    private static let appGroupId = "group.com.example.cycles"

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "cycles/widget", binaryMessenger: registrar.messenger())
        let instance = CyclesWidgetPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "updateTasks":
            guard let args = call.arguments as? [String: Any],
                  let tasksJson = args["tasksJson"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "tasksJson required", details: nil))
                return
            }

            let openCount = args["openCount"] as? Int ?? 0

            if let defaults = UserDefaults(suiteName: Self.appGroupId) {
                defaults.set(tasksJson, forKey: "widget_tasks_json")
                defaults.set(openCount, forKey: "widget_open_count")
                defaults.synchronize()
            }

            #if canImport(WidgetKit)
            if #available(iOS 14.0, *) {
                WidgetCenter.shared.reloadAllTimelines()
            }
            #endif

            result(true)

        case "refreshWidget":
            #if canImport(WidgetKit)
            if #available(iOS 14.0, *) {
                WidgetCenter.shared.reloadAllTimelines()
            }
            #endif
            result(true)

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
