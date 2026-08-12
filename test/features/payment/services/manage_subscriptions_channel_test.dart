import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/payment/services/manage_subscriptions_channel.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(
      ManageSubscriptionsChannel.channel,
      null,
    );
  });

  test('invokes the native manage-subscriptions method', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(ManageSubscriptionsChannel.channel, (
      call,
    ) async {
      calls.add(call);
      return null;
    });

    await const ManageSubscriptionsChannel(
      platform: TargetPlatform.iOS,
    ).show('apple');

    expect(calls.single.method, 'showManageSubscriptions');
  });

  test('surfaces a native failure rather than swallowing it', () async {
    messenger.setMockMethodCallHandler(
      ManageSubscriptionsChannel.channel,
      (call) async => throw PlatformException(code: 'no_scene'),
    );

    expect(
      () => const ManageSubscriptionsChannel(
        platform: TargetPlatform.iOS,
      ).show('apple'),
      throwsA(isA<PlatformException>()),
    );
  });

  test('Apple-funded Pass opens Apple management outside iOS', () async {
    Uri? launched;
    LaunchMode? mode;

    await ManageSubscriptionsChannel(
      platform: TargetPlatform.android,
      urlLauncher: (uri, launchMode) async {
        launched = uri;
        mode = launchMode;
        return true;
      },
    ).show('apple');

    expect(launched, Uri.parse('https://apps.apple.com/account/subscriptions'));
    expect(mode, LaunchMode.externalApplication);
  });

  test('channel name is namespaced to the bundle id', () {
    expect(
      ManageSubscriptionsChannel.channel.name,
      'ai.portraitor.portraitorMobile/manage_subscriptions',
    );
  });
}
