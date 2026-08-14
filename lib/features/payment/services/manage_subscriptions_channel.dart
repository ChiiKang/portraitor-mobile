import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

typedef ManagementUrlLauncher = Future<bool> Function(Uri uri, LaunchMode mode);

/// Opens subscription management for the originating platform store.
///
/// Apple uses an in-app native sheet; Google uses its external Play management
/// page. Neither store-funded subscription is cancelled by Portraitor's server.
class ManageSubscriptionsChannel {
  const ManageSubscriptionsChannel({this.platform, this.urlLauncher});

  final TargetPlatform? platform;
  final ManagementUrlLauncher? urlLauncher;

  static const channel = MethodChannel(
    'ai.portraitor.portraitorMobile/manage_subscriptions',
  );

  /// Throws [PlatformException] if the sheet cannot be presented. Callers
  /// surface that rather than pretending the subscription was managed.
  Future<void> show(String provider) async {
    final targetPlatform = platform ?? defaultTargetPlatform;
    if (provider == 'apple' && targetPlatform == TargetPlatform.iOS) {
      await channel.invokeMethod<void>('showManageSubscriptions');
      return;
    }
    final uri = switch (provider) {
      'apple' => Uri.parse('https://apps.apple.com/account/subscriptions'),
      'google' => Uri.parse(
        'https://play.google.com/store/account/subscriptions'
        '?package=ai.portraitor.portraitor_mobile',
      ),
      _ => null,
    };
    if (uri == null) {
      throw PlatformException(
        code: 'unsupported_billing_provider',
        message: 'Unsupported billing provider: $provider',
      );
    }
    final launcher =
        urlLauncher ??
        (Uri value, LaunchMode mode) => launchUrl(value, mode: mode);
    if (!await launcher(uri, LaunchMode.externalApplication)) {
      throw PlatformException(
        code: 'subscription_management_unavailable',
        message: 'Could not open $provider subscription management.',
      );
    }
  }
}
