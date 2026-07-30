/// Supabase URL and **anon** key: pass at build time so secrets stay out of source.
///
/// ```bash
/// flutter run --dart-define=SUPABASE_URL=https://YOUR_REF.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=eyJhbGciOi...
/// ```
///
/// The anon key is publishable with RLS; still avoid committing it in the repo for hackathon checks.
class SupabaseConstants {
  SupabaseConstants._();

  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  /// Google OAuth return URL for Android browser flow (`signInWithOAuth`).
  /// Add this exact string under Supabase → Authentication → URL Configuration → **Redirect URLs**.
  static const String oauthRedirectUrlAndroid =
      'com.landroid.flutter://login-callback';
}
