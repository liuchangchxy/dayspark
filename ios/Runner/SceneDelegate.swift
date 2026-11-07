import Flutter
import UIKit

// WHY: custom URL schemes are not routed by the Flutter engine on iOS the
// way path-based deep links are. Widget Links use dayspark://open/... and
// dayspark://quick-add; forward every incoming URL into the navigation
// channel exactly like the macOS host does, so go_router's single
// widgetDeepLinkLocation translator sees it either way.
class SceneDelegate: FlutterSceneDelegate {
  private var pendingURLs: [URL] = []

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    pendingURLs.append(contentsOf: connectionOptions.urlContexts.map(\.url))
    super.scene(scene, willConnectTo: session, options: connectionOptions)
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    flushPendingURLs()
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    forward(URLContexts.map(\.url))
    super.scene(scene, openURLContexts: URLContexts)
  }

  private func flushPendingURLs() {
    guard !pendingURLs.isEmpty else { return }
    let urls = pendingURLs
    pendingURLs.removeAll()
    forward(urls)
  }

  private func forward(_ urls: [URL]) {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      pendingURLs.append(contentsOf: urls)
      return
    }
    let navigation = FlutterMethodChannel(
      name: "flutter/navigation",
      binaryMessenger: controller.binaryMessenger,
      codec: FlutterJSONMethodCodec.sharedInstance()
    )
    for url in urls {
      navigation.invokeMethod(
        "pushRouteInformation",
        arguments: ["location": url.absoluteString]
      )
    }
  }
}
