import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Presents Apple's manage-subscriptions sheet in-app.
///
/// Apple owns cancellation, payment-method changes, plan changes, and billing
/// recovery for a subscription it billed. There is no server-side cancel, so
/// this sheet is the only route — and `in_app_purchase` does not expose
/// `AppStore.showManageSubscriptions(in:)`, which is why this is the one piece
/// of native code in the payment feature.
class ManageSubscriptionsChannel {
  const ManageSubscriptionsChannel();

  static const channel = MethodChannel(
    'ai.portraitor.portraitorMobile/manage_subscriptions',
  );

  /// Throws [PlatformException] if the sheet cannot be presented. Callers
  /// surface that rather than pretending the subscription was managed.
  Future<void> show(String provider) async {
    if (provider == 'apple') {
      await channel.invokeMethod<void>('showManageSubscriptions');
      return;
    }
    if (provider == 'google') {
      final uri = Uri.parse(
        'https://play.google.com/store/account/subscriptions'
        '?package=ai.portraitor.portraitor_mobile',
      );
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw PlatformException(
          code: 'subscription_management_unavailable',
          message: 'Could not open Google Play subscription management.',
        );
      }
      return;
    }
    throw PlatformException(
      code: 'unsupported_billing_provider',
      message: 'Unsupported billing provider: $provider',
    );
  }
}
