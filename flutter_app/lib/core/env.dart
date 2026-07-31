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

  /// Matches backend `DEV_LOGIN_USER` — the seeded demo account id.
  static const demoUserId = String.fromEnvironment(
    'DEV_LOGIN_USER',
    defaultValue: 'demo-farmer',
  );

  /// Matches backend `DEV_LOGIN_TOKEN`. Default is the local/demo secret so
  /// "Try demo farms" works without a dart-define; override or clear in release
  /// builds that must not expose a shared account.
  static const devLoginToken = String.fromEnvironment(
    'DEV_LOGIN_TOKEN',
    defaultValue: 't8DldZzFcIWlNyBluc0aOdyLaXFMel0J',
  );

  static bool get isDevLogin =>
      const bool.fromEnvironment('FORCE_DEV_LOGIN', defaultValue: false) &&
      devLoginToken.isNotEmpty;

  static bool get hasDemoLogin => devLoginToken.isNotEmpty;

  static bool get isClerkConfigured => clerkPublishableKey.isNotEmpty;

  static bool get isApiConfigured => apiBaseUrl.isNotEmpty;

  static String get apiV1Base {
    final root = apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
    return '$root/api/v1';
  }
}
