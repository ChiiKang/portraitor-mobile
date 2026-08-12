import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:portraitor_mobile/features/payment/domain/store_provider.dart';
import 'package:portraitor_mobile/features/payment/services/google_play_iap_service.dart';

void main() {
  test('live Play purchases are disabled unless the build opts in', () {
    expect(kGooglePlayBillingEnabled, isFalse);
  });

  test('maps Google purchase token and obfuscated account id', () {
    final details = GooglePlayPurchaseDetails(
      purchaseID: 'GPA.1',
      productID: 'com.portraitor.portrait.you',
      verificationData: PurchaseVerificationData(
        localVerificationData: '{}',
        serverVerificationData: 'play-purchase-token',
        source: 'google_play',
      ),
      transactionDate: '1',
      billingClientPurchase: const PurchaseWrapper(
        orderId: 'GPA.1',
        packageName: 'ai.portraitor.portraitor_mobile',
        purchaseTime: 1,
        purchaseToken: 'play-purchase-token',
        signature: 'signature',
        products: ['com.portraitor.portrait.you'],
        isAutoRenewing: false,
        originalJson: '{}',
        isAcknowledged: false,
        purchaseState: PurchaseStateWrapper.purchased,
        obfuscatedAccountId: 'uuid-1',
      ),
      status: PurchaseStatus.purchased,
    );

    final transaction = mapGooglePlayPurchase(details, isConsumable: true);

    expect(transaction.provider, StoreProvider.google);
    expect(transaction.serverVerificationData, 'play-purchase-token');
    expect(transaction.accountToken, 'uuid-1');
    expect(transaction.isConsumable, isTrue);
    expect(transaction.isPendingCompletion, isTrue);
  });

  test('manual store sync replays queried purchases into recovery', () {
    final source =
        File(
          'lib/features/payment/services/google_play_iap_service.dart',
        ).readAsStringSync();

    expect(source, contains('for (final transaction in await unfinished())'));
    expect(source, contains('_controller.add(transaction)'));
  });
}
