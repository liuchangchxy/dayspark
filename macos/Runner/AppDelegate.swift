import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
    override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    override func applicationDidFinishLaunching(_ notification: Notification) {
        if let controller = NSApp.windows
            .compactMap({ $0.contentViewController as? FlutterViewController })
            .first
        {
            registerWidgetCommandsChannel(messenger: controller.engine.binaryMessenger)
        }
    }

    private func registerWidgetCommandsChannel(messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: "com.dayspark.app/widget_commands", binaryMessenger: messenger)
        channel.setMethodCallHandler { call, result in
            let appGroupId = "group.com.dayspark.app"
            let defaults = UserDefaults(suiteName: appGroupId)
            switch call.method {
            case "getPendingCommands":
                var commands: [[String: Any]] = []
                if let dict = defaults?.dictionaryRepresentation() {
                    for (key, val) in dict {
                        if key.hasPrefix("widget_command_"), let str = val as? String,
                           let data = str.data(using: .utf8),
                           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            commands.append(obj)
                        }
                    }
                }
                result(commands)
            case "ackCommand":
                guard let args = call.arguments as? [String: Any],
                      let commandId = args["commandId"] as? String else {
                    result(FlutterError(code: "INVALID_ARGUMENT", message: "commandId required", details: nil))
                    return
                }
                defaults?.removeObject(forKey: "widget_command_\(commandId)")
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    // WHY: the macOS engine does not run deep links through the framework
    // (only the iOS engine does), so dayspark:// URLs from the widget's
    // quick-add Link would open the app and land nowhere. Forward each URL
    // into the navigation channel as route information — go_router's
    // redirect then translates it via widgetDeepLinkLocation, same single
    // scheme→path point as the other platforms.
    override func application(_ application: NSApplication, open urls: [URL]) {
        if let controller = NSApp.windows
            .compactMap({ $0.contentViewController as? FlutterViewController })
            .first
        {
            let navigation = FlutterMethodChannel(
                name: "flutter/navigation",
                binaryMessenger: controller.engine.binaryMessenger,
                codec: FlutterJSONMethodCodec.sharedInstance())
            for url in urls {
                navigation.invokeMethod(
                    "pushRouteInformation",
                    arguments: ["location": url.absoluteString])
            }
        }
        super.application(application, open: urls)
    }
}
