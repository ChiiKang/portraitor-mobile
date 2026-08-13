import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:portraitor_mobile/core/api/api_service.dart';

/// A Pass use could not be reserved, or could not be handed back.
///
/// The two flags exist because the funnel reacts differently: an exhausted pool
/// is a wait-until-renewal message, an expired session means re-enter the Pass
/// code in Profile.
class PassGrantException implements Exception {
  const PassGrantException(
    this.message, {
    this.isExhausted = false,
    this.isSessionExpired = false,
  });

  final String message;
  final bool isExhausted;
  final bool isSessionExpired;

  @override
  String toString() => message;
}

/// Spends a use off a Pass, minting the voucher that authorizes one generation.
///
/// The voucher is a `subgrant_*` token. It travels in the same
/// `payment_session_id` slot a store purchase fills, which is why nothing
/// downstream of `/processing` needs to know a Pass was involved.
abstract class PassGrantApi {
  /// Returns the grant token, or throws [PassGrantException].
  ///
  /// [personCount] is how many people the run covers, NOT how many uses it
  /// costs. The server prices it via `UsageService::costForPortraitRequest`.
  Future<String> reserve({
    required String sessionToken,
    required String tier,
    required int personCount,
  });

  /// Hands a reserved use back. Best effort, never throws.
  ///
  /// No lease token: `usage.php` does not read one, and whether a refund is
  /// honest is the server's decision, not the client's. A failed release is
  /// recovered by the server's expiry sweep, so surfacing it would only alarm
  /// someone who cannot act on it.
  Future<void> release({
    required String sessionToken,
    required String grantToken,
  });
}

class HttpPassGrantApi implements PassGrantApi {
  HttpPassGrantApi({Dio? dio}) : _dio = dio ?? ApiService.instance.dio;

  static const _path = '/api/subscription/usage.php';

  final Dio _dio;

  @override
  Future<String> reserve({
    required String sessionToken,
    required String tier,
    required int personCount,
  }) async {
    late final Response<Map<String, dynamic>> response;
    try {
      response = await _dio.post<Map<String, dynamic>>(
        _path,
        data: {'tier': tier, 'family_count': personCount < 1 ? 1 : personCount},
        options: Options(headers: {'Authorization': 'Bearer $sessionToken'}),
      );
    } on DioException catch (error) {
      throw _exceptionFrom(
        error.response?.statusCode ?? 0,
        error.response?.data,
      );
    }

    // ApiService sets `validateStatus: (_) => true`, so a 4xx lands here as an
    // ordinary response and has to be checked rather than caught.
    final status = response.statusCode ?? 0;
    if (status >= 400) {
      throw _exceptionFrom(status, response.data);
    }

    final data = response.data?['data'];
    final token = data is Map ? data['grant_token'] : null;
    // A 200 without a usable grant is not funding. Letting it through only
    // moves the failure to queue admission, where the message is worse.
    if (token is! String || !token.startsWith('subgrant_')) {
      throw const PassGrantException(
        'The Pass could not authorize this portrait.',
      );
    }
    return token;
  }

  @override
  Future<void> release({
    required String sessionToken,
    required String grantToken,
  }) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        _path,
        data: {'release': true, 'grant_token': grantToken},
        options: Options(headers: {'Authorization': 'Bearer $sessionToken'}),
      );
    } catch (_) {
      // Swallowed by contract. The server sweeps grants that were never spent.
    }
  }

  static PassGrantException _exceptionFrom(int status, Object? body) {
    final raw = body is Map ? body['message'] ?? body['error'] : null;
    final message = raw is String && raw.trim().isNotEmpty
        ? raw
        : 'The Pass could not authorize this portrait.';
    return PassGrantException(
      message,
      isExhausted: status == 402,
      isSessionExpired: status == 401,
    );
  }
}

/// Test double.
class FakePassGrantApi implements PassGrantApi {
  FakePassGrantApi({this.grantToken = 'subgrant_test', this.failure});

  String grantToken;
  PassGrantException? failure;
  int reserveCount = 0;
  final List<String> releasedGrants = [];

  @override
  Future<String> reserve({
    required String sessionToken,
    required String tier,
    required int personCount,
  }) async {
    reserveCount++;
    final error = failure;
    if (error != null) throw error;
    return grantToken;
  }

  @override
  Future<void> release({
    required String sessionToken,
    required String grantToken,
  }) async {
    releasedGrants.add(grantToken);
  }
}

final passGrantApiProvider = Provider<PassGrantApi>((ref) => HttpPassGrantApi());
