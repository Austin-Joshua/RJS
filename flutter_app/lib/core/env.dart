/// Build-time config. Values come from `--dart-define`, never hardcoded and
/// never committed (TRD NFR-07, §10 "Secrets").
class Env {
  const Env._();

  /// Clerk publishable key (`pk_...`) from Clerk Dashboard -> API Keys.
  static const clerkPublishableKey = String.fromEnvironment(
    'CLERK_PUBLISHABLE_KEY',
  );

  static bool get isClerkConfigured => clerkPublishableKey.isNotEmpty;
}
