import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens subscription management for the originating platform store.
///
/// Apple uses an in-app native sheet; Google uses its external Play management
/// page. Neither store-funded subscription is cancelled by Portraitor's server.
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
