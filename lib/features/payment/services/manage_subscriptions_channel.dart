import 'package:flutter/services.dart';

/// Presents Apple's manage-subscriptions sheet in-app.
///
/// Apple owns cancellation, payment-method changes, plan changes, and billing
/// recovery for a subscription it billed. There is no server-side cancel, so
/// this sheet is the only route — and `in_app_purchase` does not expose
/// `AppStore.showManageSubscriptions(in:)`, which is why this is the one piece
/// of native code in the payment feature.
class ManageSubscriptionsChannel {
  const ManageSubscriptionsChannel();

  static const channel =
      MethodChannel('ai.portraitor.portraitorMobile/manage_subscriptions');

  /// Throws [PlatformException] if the sheet cannot be presented. Callers
  /// surface that rather than pretending the subscription was managed.
  Future<void> show() => channel.invokeMethod<void>('showManageSubscriptions');
}
