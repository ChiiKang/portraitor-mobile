import 'package:dio/dio.dart';
import 'package:portraitor_mobile/core/api/api_service.dart';

/// What the server says this Pass currently is.
///
/// [fundingProvider] is the load-bearing field: it decides which controls the
/// app may show. Whoever took the money owns cancellation, so an Apple-funded
/// Pass is managed in Apple's own sheet and a Stripe-funded one through our API.
class Entitlement {
  const Entitlement({
    required this.state,
    required this.grantsAccess,
    required this.usesRemaining,
    required this.usesTotal,
    this.accessUntil,
    this.fundingProvider,
    this.cancelPending = false,
  });

  final String state;
  final bool grantsAccess;
  final int usesRemaining;
  final int usesTotal;
  final String? accessUntil;

  /// `'apple'`, `'stripe'`, later `'google'`, or null when nothing funds it.
  final String? fundingProvider;

  final bool cancelPending;

  /// Whether Portraitor may run billing operations against this Pass.
  ///
  /// Null means no live funding source, which is not the same as Stripe but is
  /// equally safe to show our own controls for: there is nothing external to
  /// defer to.
  bool get isSelfManaged => fundingProvider == null || fundingProvider == 'stripe';

  bool get isAppleFunded => fundingProvider == 'apple';

  factory Entitlement.fromJson(Map<String, dynamic> json) {
    return Entitlement(
      state: json['state'] as String? ?? 'none',
      grantsAccess: json['grants_access'] as bool? ?? false,
      usesRemaining: (json['uses_remaining'] as num?)?.toInt() ?? 0,
      usesTotal: (json['uses_total'] as num?)?.toInt() ?? 0,
      accessUntil: json['access_until'] as String?,
      fundingProvider: json['provider'] as String?,
      cancelPending: json['cancel_at_period_end'] as bool? ?? false,
    );
  }
}

abstract class EntitlementApi {
  /// Reads the current entitlement for the Pass behind [sessionToken].
  ///
  /// Returns null when the session is not a Pass session or has expired, which
  /// is an ordinary state rather than an error: a one-off buyer has no Pass.
  Future<Entitlement?> current({required String sessionToken});
}

class HttpEntitlementApi implements EntitlementApi {
  HttpEntitlementApi({Dio? dio}) : _dio = dio ?? ApiService.instance.dio;

  final Dio _dio;

  @override
  Future<Entitlement?> current({required String sessionToken}) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/entitlements/current.php',
        options: Options(headers: {'Authorization': 'Bearer $sessionToken'}),
      );
      // The payload sits under `entitlement`, not `data`. That endpoint predates
      // this work and has no frontend caller, so the key is easy to get wrong.
      final entitlement = response.data?['entitlement'];
      return entitlement is Map<String, dynamic>
          ? Entitlement.fromJson(entitlement)
          : null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) return null;
      rethrow;
    }
  }
}

/// Test double.
class FakeEntitlementApi implements EntitlementApi {
  FakeEntitlementApi({this.entitlement});

  Entitlement? entitlement;
  int callCount = 0;

  @override
  Future<Entitlement?> current({required String sessionToken}) async {
    callCount++;
    return entitlement;
  }
}
