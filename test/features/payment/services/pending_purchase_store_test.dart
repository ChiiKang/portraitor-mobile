import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/payment/domain/store_provider.dart';
import 'package:portraitor_mobile/features/payment/services/pending_purchase_store.dart';

void main() {
  group('InMemoryPendingPurchaseStore', () {
    test('round-trips the exact crash recovery context', () async {
      final store = InMemoryPendingPurchaseStore();
      final context = PendingPurchaseContext(
        provider: StoreProvider.google,
        productId: 'com.portraitor.portrait.you',
        publicUuid: 'uuid-1',
        clientConversationRef: 'conv-1',
        deliveryEmail: 'buyer@example.com',
        createdAt: DateTime.utc(2026, 8, 12),
      );

      await store.write(context);

      expect(await store.read('uuid-1'), context);
    });

    test(
      'keeps independent purchases instead of overwriting by product',
      () async {
        final store = InMemoryPendingPurchaseStore();
        final first = PendingPurchaseContext(
          provider: StoreProvider.google,
          productId: 'com.portraitor.portrait.you',
          publicUuid: 'uuid-1',
          clientConversationRef: 'conv-1',
          deliveryEmail: 'one@example.com',
          createdAt: DateTime.utc(2026, 8, 12),
        );
        final second = PendingPurchaseContext(
          provider: StoreProvider.google,
          productId: 'com.portraitor.portrait.you',
          publicUuid: 'uuid-2',
          clientConversationRef: 'conv-2',
          deliveryEmail: 'two@example.com',
          createdAt: DateTime.utc(2026, 8, 12, 0, 1),
        );

        await store.write(first);
        await store.write(second);

        expect(await store.read('uuid-1'), first);
        expect(await store.read('uuid-2'), second);
      },
    );

    test('remove deletes only the completed purchase', () async {
      final store = InMemoryPendingPurchaseStore();
      await store.write(
        PendingPurchaseContext(
          provider: StoreProvider.apple,
          productId: 'one',
          publicUuid: 'uuid-1',
          clientConversationRef: 'conv-1',
          deliveryEmail: 'one@example.com',
          createdAt: DateTime.utc(2026, 8, 12),
        ),
      );
      await store.write(
        PendingPurchaseContext(
          provider: StoreProvider.google,
          productId: 'two',
          publicUuid: 'uuid-2',
          clientConversationRef: 'conv-2',
          deliveryEmail: 'two@example.com',
          createdAt: DateTime.utc(2026, 8, 12),
        ),
      );

      await store.remove('uuid-1');

      expect(await store.read('uuid-1'), isNull);
      expect(await store.read('uuid-2'), isNotNull);
    });
  });
}
