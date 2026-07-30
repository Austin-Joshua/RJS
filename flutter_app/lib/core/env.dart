/// Build-time config. Values come from `--dart-define`, never hardcoded and
/// never committed (TRD NFR-07, §10 "Secrets").
class Env {
  const Env._();

  /// Clerk publishable key (`pk_...`) from Clerk Dashboard -> API Keys.
  static const clerkPublishableKey = String.fromEnvironment(
    'CLERK_PUBLISHABLE_KEY',
  );

  /// FastAPI origin only — no trailing slash, no `/api/v1` suffix.
  /// Example: `https://farmsync-xxx.up.railway.app`
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  static bool get isClerkConfigured => clerkPublishableKey.isNotEmpty;

  static bool get isApiConfigured => apiBaseUrl.isNotEmpty;

  static String get apiV1Base {
    final root = apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
    return '$root/api/v1';
  }
}
