import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // Stripe SDK requires window access via UIApplication.shared.delegate?.window
  // Scene-based apps don't have this by default — bridge it from the active scene.
  override var window: UIWindow? {
    get {
      guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
        return nil
      }
      return scene.windows.first
    }
    set { }
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Apple's manage-subscriptions sheet is not exposed by in_app_purchase.
    ManageSubscriptionsPlugin.register(with: engineBridge.pluginRegistry)
  }
}
