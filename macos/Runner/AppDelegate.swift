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
