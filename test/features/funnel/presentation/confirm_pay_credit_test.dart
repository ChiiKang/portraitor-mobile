import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:portraitor_mobile/core/config/runtime_config_provider.dart';
import 'package:portraitor_mobile/core/storage/pending_job.dart';
import 'package:portraitor_mobile/core/storage/storage_service.dart';
import 'package:portraitor_mobile/features/funnel/application/funnel_draft_provider.dart';
import 'package:portraitor_mobile/features/funnel/presentation/confirm_pay_screen.dart';
import 'package:portraitor_mobile/features/import/services/chat_normalizer.dart';
import 'package:portraitor_mobile/features/payment/application/iap_provider.dart';
import 'package:portraitor_mobile/features/payment/application/portrait_credit_provider.dart';
import 'package:portraitor_mobile/features/payment/services/billing_api.dart';
import 'package:portraitor_mobile/features/payment/services/iap_service.dart';
import 'package:portraitor_mobile/features/payment/services/pass_credential_store.dart';

const _deviceId = 'device_test';
const _creditRef = 'conv_freed_1';
const _paymentReference = 'apl_0123456789abcdef0123456789abcdef';

/// Nothing loads from a store, so the freed credit is the only thing deciding
/// what the CTA offers.
class _QuietIapNotifier extends IapNotifier {
  _QuietIapNotifier()
    : super(
        iap: FakeIapService(products: const {}),
        api: FakeBillingApi(),
        store: InMemoryPassCredentialStore(),
      );

  @override
  Future<void> loadPrices() async {}
}

PendingJob _credit({String tier = 'you'}) {
  final now = DateTime.utc(2026, 8, 13);
  return PendingJob(
    id: _creditRef,
    deviceId: _deviceId,
    clientConversationRef: _creditRef,
    inputText: '',
    paymentSessionId: _paymentReference,
    publicUuid: 'uuid-buyer-1',
    deliveryEmail: 'buyer@example.com',
    status: pendingJobCreditStatus,
    chunksCompleted: 0,
    chunksTotal: 0,
    chunkResults: const [],
    tier: tier,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  late List<Object?> processingExtras;
  late Database db;

  // Opened here rather than inside a test: setUp runs outside the widget
  // tester's fake clock, and sqflite's real I/O never completes inside it.
  setUp(() async {
    processingExtras = [];
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: StorageService.dbVersion,
        onCreate: StorageService.onCreateSchema,
        onUpgrade: StorageService.onUpgradeSchema,
      ),
    );
    StorageService.instance.initForTesting(db: db, deviceId: _deviceId);
  });

  tearDown(() => StorageService.instance.resetForTesting());

  Future<void> pumpConfirm(
    WidgetTester tester,
    FunnelTier tier, {
    List<PendingJob> credits = const [],
  }) async {
    final container = ProviderContainer(
      overrides: [
        iapProvider.overrideWith((ref) => _QuietIapNotifier()),
        runtimeEntitlementsProvider.overrideWithValue(
          const RuntimeEntitlements(),
        ),
        // Overridden rather than read from sqflite: a widget test runs in a
        // fake-async zone, where a real database read never completes.
        portraitCreditsProvider.overrideWith((ref) async => credits),
      ],
    );
    addTearDown(container.dispose);

    container.read(funnelDraftProvider.notifier)
      ..setFromImport(
        normalized: const NormalizationResult(
          text: 'Dan: Hello',
          format: ChatFormat.whatsapp,
          detectedNames: ['Dan'],
          messageCount: 1,
        ),
        dateRange: null,
        tokenEstimate: 10,
      )
      ..selectTier(tier)
      ..setSelectedNames(const ['Dan']);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: GoRouter(
            initialLocation: '/funnel/confirm',
            routes: [
              GoRoute(
                path: '/funnel/confirm',
                builder: (_, __) => const ConfirmPayScreen(),
              ),
              GoRoute(
                path: '/processing',
                builder: (_, state) {
                  processingExtras.add(state.extra);
                  return const Scaffold(body: Text('PROCESSING'));
                },
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the funnel offers a freed purchase', () {
    testWidgets('the CTA spends it instead of asking to pay again', (
      tester,
    ) async {
      await pumpConfirm(tester, FunnelTier.you, credits: [_credit()]);

      expect(
        find.text('Use your paid portrait'),
        findsOneWidget,
        reason:
            'a purchase the customer already made must not sit idle behind a '
            'button that asks them to pay again',
      );
      expect(find.textContaining('Pay '), findsNothing);
    });

    testWidgets('a credit for another tier is left alone', (tester) async {
      await pumpConfirm(
        tester,
        FunnelTier.you,
        credits: [_credit(tier: 'family')],
      );

      expect(find.text('Use your paid portrait'), findsNothing);
    });

    testWidgets('spending it routes to processing on the purchase it kept', (
      tester,
    ) async {
      await pumpConfirm(tester, FunnelTier.you, credits: [_credit()]);
      await tester.enterText(find.byType(TextField).first, 'buyer@example.com');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Use your paid portrait'));
      await tester.pump();
      // The handler writes to sqflite, which only completes on the real event
      // loop; the fake clock a widget test runs under never delivers it.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)),
      );
      await tester.pumpAndSettle();

      final extra = processingExtras.single! as Map<String, dynamic>;
      expect(
        extra['conversationId'],
        _creditRef,
        reason:
            'the queue refuses a payment whose stored reference does not '
            'match the run being queued, so the freed ref has to be reused',
      );
      expect(extra['paymentReference'], _paymentReference);
      expect(extra['normalizedText'], 'Dan: Hello');
    });
  });

  group('staging a credit run', () {
    test(
      'turns the credit into a runnable job and stops offering it',
      () async {
        await StorageService.instance.savePendingJobRecord(_credit());

        await stageCreditRun(
          credit: _credit(),
          payload: {
            'normalizedText': 'Dan: Hello',
            'targetName': 'Dan',
            'deliveryEmail': 'buyer@example.com',
            'people': const <String>['Dan'],
            'tier': 'you',
            'dateRange': null,
          },
        );

        final job = await StorageService.instance.getPendingJobById(_creditRef);
        expect(job!.status, 'ready');
        expect(job.inputText, 'Dan: Hello');
        expect(job.paymentSessionId, _paymentReference);
        expect(
          job.publicUuid,
          'uuid-buyer-1',
          reason:
              'cancelling this run in turn has to be able to free the purchase '
              'again',
        );
        expect(
          await StorageService.instance.getSpendablePortraitCredits(),
          isEmpty,
          reason: 'a spent credit must not be offered to a second portrait',
        );
      },
    );
  });
}
