import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/payment/services/manage_subscriptions_channel.dart';

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

    await const ManageSubscriptionsChannel().show('apple');

    expect(calls.single.method, 'showManageSubscriptions');
  });

  test('surfaces a native failure rather than swallowing it', () async {
    messenger.setMockMethodCallHandler(
      ManageSubscriptionsChannel.channel,
      (call) async => throw PlatformException(code: 'no_scene'),
    );

    expect(
      () => const ManageSubscriptionsChannel().show('apple'),
      throwsA(isA<PlatformException>()),
    );
  });

  test('channel name is namespaced to the bundle id', () {
    expect(
      ManageSubscriptionsChannel.channel.name,
      'ai.portraitor.portraitorMobile/manage_subscriptions',
    );
  });
}
