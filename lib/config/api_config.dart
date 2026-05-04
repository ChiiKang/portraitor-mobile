/// API Configuration
///
/// Build-time constants for the Portraitor backend API.
/// The base URL is the only value set at build time via --dart-define.
/// Everything else (Stripe keys, pricing, model) is fetched at runtime
/// from GET /api/admin/config.php.
///
/// Usage:
///   flutter run --dart-define=API_URL=https://staging.portraitor.ai/api
library api_config;

/// Base URL of the Portraitor API, injected at build time.
///
/// Defaults to the local HTTPS dev server when not specified.
///
/// Environments:
///   local:      https://localhost:8443/api   (default)
///   staging:    https://staging.portraitor.ai/api
///   production: https://portraitor.ai/api
const String kApiBaseUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'https://localhost:8443/api',
);

/// Known environment identifiers, derived from [kApiBaseUrl].
enum ApiEnvironment { local, staging, production }

/// Resolve the current environment from [kApiBaseUrl].
ApiEnvironment get currentEnvironment {
  if (kApiBaseUrl.contains('localhost')) return ApiEnvironment.local;
  if (kApiBaseUrl.contains('staging')) return ApiEnvironment.staging;
  return ApiEnvironment.production;
}

// ─── Endpoint paths (relative to [kApiBaseUrl]) ──────────────────────────────

/// POST  → create PaymentIntent; returns client_secret, publishable_key, amount_cents
/// GET   → verify payment status by session_id query param
/// DELETE → cancel a payment by payment_intent_id body param
const String kPaymentEndpoint = '/payment.php';

/// POST → stream analysis chunks via SSE
const String kGeminiStreamEndpoint = '/gemini-proxy-stream.php';

/// GET  → check chunk progress for a job token
const String kJobStatusEndpoint = '/job-status.php';

/// GET  → public runtime config: pricing, active model, payment mode
const String kAdminConfigEndpoint = '/admin/config.php';

/// POST → GDPR data requests (request / verify / confirm)
const String kGdprEndpoint = '/gdpr.php';
