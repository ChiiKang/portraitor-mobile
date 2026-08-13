import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/core/storage/storage_service.dart';
import 'package:portraitor_mobile/features/funnel/application/funnel_draft_provider.dart';
import 'package:portraitor_mobile/features/processing/application/processing_provider.dart';
import 'package:portraitor_mobile/features/processing/services/demo_portrait_factory.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  if (!kDemoIapPurchase) {
    test('demo processing suite is disabled in normal builds', () {
      expect(kDemoIapPurchase, isFalse);
    });
    return;
  }

  TestWidgetsFlutterBinding.ensureInitialized();

  late Database database;
  late ProviderContainer container;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: StorageService.dbVersion,
        onCreate: StorageService.onCreateSchema,
        onUpgrade: StorageService.onUpgradeSchema,
      ),
    );
    StorageService.instance.initForTesting(
      db: database,
      deviceId: 'demo-device',
    );
    container = ProviderContainer();
  });

  tearDown(() async {
    container.dispose();
    await StorageService.instance.resetForTesting();
  });

  test('completes a partner demo locally and saves a result', () async {
    final states = <ProcessingStatus>[];
    final subscription = container.listen(
      processingProvider,
      (_, next) => states.add(next.status),
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    await container
        .read(processingProvider.notifier)
        .startProcessing(
          conversationId: 'demo-conversation',
          paymentSessionId: 'demo-credit-local',
          normalizedText: 'Dan: Hello\nAlex: Hi there',
          targetName: 'Dan',
          deliveryEmail: 'demo@example.com',
          people: const ['Dan', 'Alex'],
          tier: 'partner',
          dateRange: 'Jan 2026',
        );

    final state = container.read(processingProvider);
    expect(state.status, ProcessingStatus.done);
    expect(state.percentage, 1);
    expect(state.error, isNull);
    expect(state.emailSent, isFalse);
    expect(state.paymentCaptured, isFalse);
    expect(state.resultMarkdown, contains('Demo preview'));
    expect(
      states,
      containsAllInOrder(<ProcessingStatus>[
        ProcessingStatus.queued,
        ProcessingStatus.processing,
        ProcessingStatus.validating,
        ProcessingStatus.done,
      ]),
    );

    final conversation = await StorageService.instance.getConversationById(
      'demo-conversation',
    );
    expect(conversation, isNotNull);
    expect(conversation!['status'], 'completed');
    expect(conversation['mode'], 'pack');
    expect(conversation['tier'], 'partner');
    expect(conversation['output_summary'], contains("Dan's communication"));
    expect(
      await StorageService.instance.getPendingJobById('demo-conversation'),
      isNull,
    );
  });

  test('sample output labels itself and never claims real analysis', () {
    final output = DemoPortraitFactory.build(targetName: 'Taylor');

    expect(output, contains("Taylor's communication portrait"));
    expect(output, contains('generated locally'));
    expect(output, contains('not an AI analysis'));
  });
}
