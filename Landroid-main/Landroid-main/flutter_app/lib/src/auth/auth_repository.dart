import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../config/supabase_constants.dart';
import '../models/session.dart';

/// Google sign-in + Supabase session + optional `profiles` row sync.
class AuthRepository {
  AuthRepository()
    : _google = GoogleSignIn(
        scopes: const ['email', 'profile'],
        // Web: GIS requires a client ID (this or web/index.html meta tag).
        clientId: kIsWeb ? _serverClientIdOrNull : null,
        serverClientId: _serverClientIdOrNull,
      );

  static const String _serverClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue:
        '1000749168095-cumck2tqpkjd9kmqg90jl7qa7nt34evs.apps.googleusercontent.com',
  );

  static String? get _serverClientIdOrNull =>
      _serverClientId.isEmpty ? null : _serverClientId;

  final GoogleSignIn _google;

  static bool get isSupabaseConfigured =>
      SupabaseConstants.url.isNotEmpty &&
      SupabaseConstants.anonKey.isNotEmpty;

  SupabaseClient get _sb => Supabase.instance.client;

  /// Android: use Supabase-hosted Google OAuth in the system browser (PKCE).
  /// Avoids Google Play Services native sign-in [ApiException] 10 when GCP
  /// Android OAuth is mis-detected. iOS/Web keep native / GIS flows.
  static bool get _useBrowserGoogleOAuth =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Email/password sign-up. Returns a [Session] when the user is signed in
  /// immediately; returns `null` when Supabase requires email confirmation
  /// (no session until the user verifies the link).
  Future<Session?> signUpWithEmail({
    required String name,
    required String email,
    required String password,
    required String locale,
  }) async {
    if (!isSupabaseConfigured) {
      throw StateError(
        'Supabase is not configured. Set SupabaseConstants or dart-define.',
      );
    }
    final response = await _sb.auth.signUp(
      email: email.trim(),
      password: password,
      data: {'full_name': name.trim()},
    );
    final user = response.user;
    if (user == null) {
      throw StateError('Sign up failed');
    }
    if (response.session == null) {
      return null;
    }

    final meta = user.userMetadata;
    final displayName =
        meta?['full_name'] as String? ?? meta?['name'] as String? ?? name.trim();

    await _upsertProfile(
      locale: locale,
      appRole: Role.consultant,
      email: user.email,
      displayName: displayName,
      avatarUrl: meta?['avatar_url'] as String?,
    );

    final access = _sb.auth.currentSession?.accessToken;
    if (access == null || access.isEmpty) {
      throw StateError('No Supabase access token after sign-up');
    }

    return Session(
      token: access,
      role: Role.consultant,
      uid: user.id,
      email: user.email,
      displayName: displayName,
    );
  }

  /// Email/password sign-in for returning users.
  Future<Session?> signInWithEmail({
    required String email,
    required String password,
    required String locale,
  }) async {
    if (!isSupabaseConfigured) {
      throw StateError(
        'Supabase is not configured. Set SupabaseConstants or dart-define.',
      );
    }
    final response = await _sb.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    final user = response.user;
    if (user == null) {
      throw StateError('Sign in failed');
    }

    // Look up profile to get role
    Role role = Role.consultant; // default
    try {
      final profile = await _sb
          .from('profiles')
          .select('app_role')
          .eq('id', user.id)
          .maybeSingle();
      if (profile != null && profile['app_role'] is String) {
        final stored = profile['app_role'] as String;
        role = stored == 'landowner' ? Role.landowner : Role.consultant;
      }
    } catch (e) {
      debugPrint('Could not read profile role: $e');
    }

    final meta = user.userMetadata;
    final displayName =
        meta?['full_name'] as String? ?? meta?['name'] as String? ?? '';

    final access = _sb.auth.currentSession?.accessToken;
    if (access == null || access.isEmpty) {
      throw StateError('No Supabase access token after sign-in');
    }

    return Session(
      token: access,
      role: role,
      uid: user.id,
      email: user.email,
      displayName: displayName.isNotEmpty ? displayName : null,
    );
  }

  Future<Session?> signInWithGoogle({required String locale}) async {
    if (!isSupabaseConfigured) {
      throw StateError(
        'Supabase is not configured. Pass '
        '--dart-define=SUPABASE_URL=... and SUPABASE_ANON_KEY=...',
      );
    }

    if (_useBrowserGoogleOAuth) {
      return _signInWithGoogleBrowserOAuth(locale);
    }

    final account = await _google.signIn();
    if (account == null) {
      return null;
    }
    final auth = await account.authentication;
    final idToken = auth.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw StateError('Missing Google ID token — check OAuth client + SHA-1.');
    }

    await _sb.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: auth.accessToken,
    );

    return _sessionFromSignedInSupabaseUser(
      locale: locale,
      fallbackDisplayName: account.displayName,
      fallbackEmail: account.email,
    );
  }

  Future<Session?> _signInWithGoogleBrowserOAuth(String locale) async {
    final completer = Completer<Session?>();
    late final StreamSubscription<AuthState> sub;
    var oauthPending = false;

    sub = _sb.auth.onAuthStateChange.listen((data) async {
      if (!oauthPending) {
        return;
      }
      if (data.event != AuthChangeEvent.signedIn || data.session == null) {
        return;
      }
      final user = _sb.auth.currentUser;
      if (user == null) {
        return;
      }
      oauthPending = false;
      await sub.cancel();
      if (completer.isCompleted) {
        return;
      }
      try {
        final session = await _sessionFromSignedInSupabaseUser(
          locale: locale,
          fallbackDisplayName: user.userMetadata?['full_name'] as String? ??
              user.userMetadata?['name'] as String?,
          fallbackEmail: user.email,
        );
        completer.complete(session);
      } catch (e, st) {
        debugPrint('_signInWithGoogleBrowserOAuth: $e\n$st');
        completer.completeError(e, st);
      }
    });

    oauthPending = true;
    try {
      final launched = await _sb.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: SupabaseConstants.oauthRedirectUrlAndroid,
      );
      if (!launched) {
        oauthPending = false;
        await sub.cancel();
        return null;
      }
      return await completer.future.timeout(
        const Duration(minutes: 3),
        onTimeout: () async {
          oauthPending = false;
          await sub.cancel();
          return null;
        },
      );
    } catch (e, st) {
      oauthPending = false;
      await sub.cancel();
      debugPrint('signInWithOAuth failed: $e\n$st');
      rethrow;
    }
  }

  Future<Session?> _sessionFromSignedInSupabaseUser({
    required String locale,
    String? fallbackDisplayName,
    String? fallbackEmail,
  }) async {
    final user = _sb.auth.currentUser;
    if (user == null) {
      return null;
    }

    Role role = Role.consultant;
    try {
      final profile = await _sb
          .from('profiles')
          .select('app_role')
          .eq('id', user.id)
          .maybeSingle();
      if (profile != null && profile['app_role'] is String) {
        final stored = profile['app_role'] as String;
        role = stored == 'landowner' ? Role.landowner : Role.consultant;
      }
    } catch (e) {
      debugPrint('Could not read profile role: $e');
    }

    final meta = user.userMetadata;
    final displayName =
        meta?['full_name'] as String? ??
        meta?['name'] as String? ??
        fallbackDisplayName;
    final email = user.email ?? fallbackEmail;

    await _upsertProfile(
      locale: locale,
      appRole: role,
      email: email,
      displayName: displayName,
      avatarUrl: meta?['avatar_url'] as String? ?? meta?['picture'] as String?,
    );

    final access = _sb.auth.currentSession?.accessToken;
    if (access == null || access.isEmpty) {
      return null;
    }

    return Session(
      token: access,
      role: role,
      uid: user.id,
      email: email,
      displayName: displayName,
    );
  }

  /// Rebuild [Session] from Supabase’s persisted session (cold start).
  Future<Session?> restoreSessionIfSignedIn(String locale) async {
    if (!isSupabaseConfigured) {
      return null;
    }
    if (_sb.auth.currentSession == null || _sb.auth.currentUser == null) {
      return null;
    }
    return _sessionFromSignedInSupabaseUser(
      locale: locale,
      fallbackDisplayName: null,
      fallbackEmail: null,
    );
  }

  Future<void> syncProfileForSession(Session session, String locale) async {
    if (!isSupabaseConfigured) {
      return;
    }
    await _upsertProfile(
      locale: locale,
      appRole: session.role,
      email: session.email,
      displayName: session.displayName,
    );
  }

  Future<void> _upsertProfile({
    required String locale,
    required Role appRole,
    String? email,
    String? displayName,
    String? avatarUrl,
  }) async {
    final user = _sb.auth.currentUser;
    if (user == null) {
      return;
    }
    try {
      await _sb.from('profiles').upsert({
        'id': user.id,
        'email': email,
        'full_name': displayName,
        'avatar_url': avatarUrl,
        'locale': locale,
        'app_role': appRole.name,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e, st) {
      debugPrint('profiles upsert failed: $e\n$st');
    }
  }

  Future<void> signOut() async {
    if (isSupabaseConfigured) {
      try {
        await _sb.auth.signOut();
      } catch (e, st) {
        debugPrint('Supabase signOut failed: $e\n$st');
      }
    }
    try {
      await _google.signOut();
    } catch (e, st) {
      debugPrint('Google signOut failed: $e\n$st');
    }
  }
}
