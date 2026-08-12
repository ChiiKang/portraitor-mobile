import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:portraitor_mobile/features/payment/domain/store_provider.dart';

class PendingPurchaseContext {
  const PendingPurchaseContext({
    required this.provider,
    required this.productId,
    required this.publicUuid,
    required this.clientConversationRef,
    required this.deliveryEmail,
    required this.createdAt,
  });

  final StoreProvider provider;
  final String productId;
  final String publicUuid;
  final String clientConversationRef;
  final String deliveryEmail;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
    'provider': provider.name,
    'product_id': productId,
    'public_uuid': publicUuid,
    'client_conversation_ref': clientConversationRef,
    'delivery_email': deliveryEmail,
    'created_at': createdAt.toUtc().toIso8601String(),
  };

  factory PendingPurchaseContext.fromJson(Map<String, Object?> json) {
    return PendingPurchaseContext(
      provider: StoreProvider.parse(json['provider']! as String),
      productId: json['product_id']! as String,
      publicUuid: json['public_uuid']! as String,
      clientConversationRef: json['client_conversation_ref']! as String,
      deliveryEmail: json['delivery_email']! as String,
      createdAt: DateTime.parse(json['created_at']! as String).toUtc(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PendingPurchaseContext &&
      other.provider == provider &&
      other.productId == productId &&
      other.publicUuid == publicUuid &&
      other.clientConversationRef == clientConversationRef &&
      other.deliveryEmail == deliveryEmail &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(
    provider,
    productId,
    publicUuid,
    clientConversationRef,
    deliveryEmail,
    createdAt,
  );
}

abstract class PendingPurchaseStore {
  Future<void> write(PendingPurchaseContext context);
  Future<PendingPurchaseContext?> read(String publicUuid);
  Future<List<PendingPurchaseContext>> readAll();
  Future<void> remove(String publicUuid);
}

class SecurePendingPurchaseStore implements PendingPurchaseStore {
  SecurePendingPurchaseStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _storageKey = 'portraitor_pending_store_purchases_v1';
  final FlutterSecureStorage _storage;
  Future<void> _mutation = Future.value();

  Future<Map<String, PendingPurchaseContext>> _readMap() async {
    final value = await _storage.read(key: _storageKey);
    if (value == null || value.isEmpty) return {};
    final decoded = jsonDecode(value) as Map<String, Object?>;
    return decoded.map(
      (key, value) => MapEntry(
        key,
        PendingPurchaseContext.fromJson(
          Map<String, Object?>.from(value! as Map),
        ),
      ),
    );
  }

  Future<void> _mutate(
    Future<void> Function(Map<String, PendingPurchaseContext>) action,
  ) {
    final next = _mutation.then((_) async {
      final contexts = await _readMap();
      await action(contexts);
      await _storage.write(
        key: _storageKey,
        value: jsonEncode(
          contexts.map((key, value) => MapEntry(key, value.toJson())),
        ),
      );
    });
    _mutation = next.catchError((_) {});
    return next;
  }

  @override
  Future<void> write(PendingPurchaseContext context) =>
      _mutate((contexts) async => contexts[context.publicUuid] = context);

  @override
  Future<PendingPurchaseContext?> read(String publicUuid) async {
    await _mutation;
    return (await _readMap())[publicUuid];
  }

  @override
  Future<List<PendingPurchaseContext>> readAll() async {
    await _mutation;
    return (await _readMap()).values.toList(growable: false);
  }

  @override
  Future<void> remove(String publicUuid) =>
      _mutate((contexts) async => contexts.remove(publicUuid));
}

class InMemoryPendingPurchaseStore implements PendingPurchaseStore {
  final Map<String, PendingPurchaseContext> _contexts = {};

  @override
  Future<void> write(PendingPurchaseContext context) async {
    _contexts[context.publicUuid] = context;
  }

  @override
  Future<PendingPurchaseContext?> read(String publicUuid) async =>
      _contexts[publicUuid];

  @override
  Future<List<PendingPurchaseContext>> readAll() async =>
      List.unmodifiable(_contexts.values);

  @override
  Future<void> remove(String publicUuid) async {
    _contexts.remove(publicUuid);
  }
}
