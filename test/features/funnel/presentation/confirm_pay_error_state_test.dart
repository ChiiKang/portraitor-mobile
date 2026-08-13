import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/core/config/runtime_config_provider.dart';
import 'package:portraitor_mobile/features/funnel/application/funnel_draft_provider.dart';
import 'package:portraitor_mobile/features/funnel/presentation/confirm_pay_screen.dart';
import 'package:portraitor_mobile/features/import/services/chat_normalizer.dart';
import 'package:portraitor_mobile/features/payment/application/iap_provider.dart';
import 'package:portraitor_mobile/features/payment/domain/iap_product.dart';
import 'package:portraitor_mobile/features/payment/services/billing_api.dart';
import 'package:portraitor_mobile/features/payment/services/iap_service.dart';
import 'package:portraitor_mobile/features/payment/services/pass_credential_store.dart';

const _youSku = 'com.portraitor.portrait.you';

void main() {
  testWidgets('purchase failures render inline without raw Dio text', (
    tester,
  ) async {
    final notifier = _FailedIapNotifier();
    final container = ProviderContainer(
      overrides: [
        iapProvider.overrideWith((ref) => notifier),
        runtimeEntitlementsProvider.overrideWithValue(
          const RuntimeEntitlements(),
        ),
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
      ..selectTier(FunnelTier.you)
      ..setSelectedNames(const ['Dan']);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ConfirmPayScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('purchase-error')), findsOneWidget);
    expect(find.text('Purchase did not continue'), findsOneWidget);
    expect(find.textContaining('No charge was made'), findsOneWidget);
    expect(find.textContaining('DioException'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });
}

class _FailedIapNotifier extends IapNotifier {
  _FailedIapNotifier()
    : super(
        iap: FakeIapService(products: const {_youSku: r'$29.00'}),
        api: FakeBillingApi(),
        store: InMemoryPassCredentialStore(),
      ) {
    state = const IapState(
      status: IapStatus.failed,
      products: {
        _youSku: IapProduct(
          productId: _youSku,
          title: 'You',
          localizedPrice: r'$29.00',
          isSubscription: false,
        ),
      },
      error:
          'We could not prepare this purchase. No charge was made. Please try again.',
    );
  }

  @override
  Future<void> loadPrices() async {}
}
