import Flutter
import StoreKit
import UIKit

/// Presents `AppStore.showManageSubscriptions(in:)`, which the in_app_purchase
/// plugin does not expose.
///
/// Deliberately the only native code in the payment feature. Apple owns
/// cancellation, payment-method changes and plan changes for a subscription it
/// billed, and there is no API to do any of it from the server, so routing the
/// user to Apple's own sheet is the whole job.
enum ManageSubscriptionsPlugin {
  private static let channelName = "ai.portraitor.portraitorMobile/manage_subscriptions"

  static func register(with registry: FlutterPluginRegistry) {
    let registrar = registry.registrar(forPlugin: "ManageSubscriptionsPlugin")
    guard let messenger = registrar?.messenger() else { return }

    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)

    channel.setMethodCallHandler { call, result in
      guard call.method == "showManageSubscriptions" else {
        result(FlutterMethodNotImplemented)
        return
      }

      // The project deploys to iOS 13, but this API and StoreKit 2 both need
      // iOS 15. Below that there is no in-app sheet to present, so the caller
      // is told plainly rather than left thinking it worked.
      guard #available(iOS 15.0, *) else {
        result(
          FlutterError(
            code: "unsupported_os",
            message: "Managing subscriptions in-app requires iOS 15 or later",
            details: nil
          )
        )
        return
      }

      guard let scene = UIApplication.shared.connectedScenes
        .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
      else {
        result(
          FlutterError(
            code: "no_scene",
            message: "No foreground window scene to present the sheet in",
            details: nil
          )
        )
        return
      }

      Task { @MainActor in
        do {
          try await AppStore.showManageSubscriptions(in: scene)
          result(nil)
        } catch {
          result(
            FlutterError(
              code: "sheet_failed",
              message: error.localizedDescription,
              details: nil
            )
          )
        }
      }
    }
  }
}
