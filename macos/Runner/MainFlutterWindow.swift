import Cocoa
import FlutterMacOS
import WidgetKit

class MainFlutterWindow: NSWindow {
    // Channel kept alive for the window's lifetime — a released channel
    // drops its handler.
    private var homeWidgetChannel: FlutterMethodChannel?

    override func awakeFromNib() {
        let flutterViewController = FlutterViewController()
        let windowFrame = self.frame
        self.contentViewController = flutterViewController
        self.setFrame(windowFrame, display: true)

        RegisterGeneratedPlugins(registry: flutterViewController)
        installHomeWidgetChannel(for: flutterViewController)

        super.awakeFromNib()
    }

    // WHY this shim: home_widget ships Android + iOS implementations only —
    // on macOS every HomeWidget.* call would raise MissingPluginException
    // and the widget snapshot would never reach the App Group suite. This
    // implements just the surface DaySpark uses, against the same
    // group.com.dayspark.app suite the widget extension reads.
    private func installHomeWidgetChannel(for controller: FlutterViewController) {
        let channel = FlutterMethodChannel(
            name: "home_widget",
            binaryMessenger: controller.engine.binaryMessenger)
        homeWidgetChannel = channel
        channel.setMethodCallHandler { call, result in
            switch call.method {
            case "setAppGroupId":
                result(true)
            case "saveWidgetData":
                guard let args = call.arguments as? [String: Any?],
                      let id = args["id"] as? String, !id.isEmpty
                else {
                    result(FlutterError(
                        code: "-2",
                        message: "InvalidArguments saveWidgetData must be called with id",
                        details: nil))
                    return
                }
                let defaults = UserDefaults(suiteName: "group.com.dayspark.app")
                let data = args["data"]
                if data == nil || data is NSNull {
                    defaults?.removeObject(forKey: id)
                } else {
                    defaults?.set(data, forKey: id)
                }
                result(true)
            case "getWidgetData":
                guard let args = call.arguments as? [String: Any?],
                      let id = args["id"] as? String, !id.isEmpty
                else {
                    result(FlutterError(
                        code: "-2",
                        message: "InvalidArguments getWidgetData must be called with id",
                        details: nil))
                    return
                }
                let defaults = UserDefaults(suiteName: "group.com.dayspark.app")
                result(defaults?.object(forKey: id))
            case "updateWidget":
                // No per-kind names on macOS — one flush reloads everything.
                WidgetCenter.shared.reloadAllTimelines()
                result(true)
            case "registerBackgroundCallback":
                // macOS has no broadcast interactivity path; quick-add goes
                // through the dayspark:// URL scheme instead.
                result(true)
            case "initiallyLaunchedFromHomeWidget":
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }
}
