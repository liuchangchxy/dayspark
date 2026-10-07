import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    if let controller = window?.rootViewController as? FlutterViewController {
      registerWidgetCommandsChannel(messenger: controller.binaryMessenger)
    }
    return result
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
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
}
