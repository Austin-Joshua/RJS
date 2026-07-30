/// Build-time config. Values come from `--dart-define`, never hardcoded and
/// never committed (TRD NFR-07, §10 "Secrets") — except client-safe defaults
/// (publishable key + public API URL) so local `flutter run` works.
class Env {
  const Env._();

  /// Clerk publishable key (`pk_...`) from Clerk Dashboard -> API Keys.
  static const clerkPublishableKey = String.fromEnvironment(
    'CLERK_PUBLISHABLE_KEY',
    defaultValue: 'pk_test_c2V0dGxpbmctaGFnZmlzaC05MC5jbGVyay5hY2NvdW50cy5kZXYk',
  );

  /// FastAPI origin only — no trailing slash, no `/api/v1` suffix.
  /// Override with `--dart-define=API_BASE_URL=...` when needed.
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://rjs-production.up.railway.app',
  );

  static bool get isClerkConfigured => clerkPublishableKey.isNotEmpty;

  static bool get isApiConfigured => apiBaseUrl.isNotEmpty;

  static String get apiV1Base {
    final root = apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
    return '$root/api/v1';
  }
}
