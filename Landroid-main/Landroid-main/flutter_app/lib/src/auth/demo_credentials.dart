import '../models/session.dart';

/// Temporary hackathon / dev identities — replace with real auth before production.
///
/// **Consultant**
/// - Email: [consultantEmail]
/// - Password: [sharedPassword]
///
/// **Landowner**
/// - Email: [landownerEmail]
/// - Password: [sharedPassword]
class DemoCredentials {
  DemoCredentials._();

  static const String consultantEmail = 'consultant.demo@landroid.local';
  static const String landownerEmail = 'landowner.demo@landroid.local';

  /// Shared demo password (both roles). Rotate or disable via [kDemoLoginEnabled].
  static const String sharedPassword = 'LandroidDemo!2026';

  /// Set to `false` in release builds via `--dart-define=DEMO_LOGIN=false` if needed.
  static const bool kDemoLoginEnabled = bool.fromEnvironment(
    'DEMO_LOGIN',
    defaultValue: true,
  );

  static const String _consultantUid =
      '00000000-0000-4000-8000-0000000000c1';
  static const String _landownerUid =
      '00000000-0000-4000-8000-0000000000b1';

  /// Returns the app [Session] for UI + API `Authorization: Bearer` (demo tokens).
  static Session sessionFor(Role role) {
    return switch (role) {
      Role.consultant => Session(
          token: 'demo-consultant',
          role: Role.consultant,
          uid: _consultantUid,
          email: consultantEmail,
          displayName: 'Demo Consultant',
        ),
      Role.landowner => Session(
          token: 'demo-owner',
          role: Role.landowner,
          uid: _landownerUid,
          email: landownerEmail,
          displayName: 'Demo Landowner',
        ),
    };
  }

  /// Non-null [Role] when [email]/[password] match a demo pair and demo login is enabled.
  static Role? roleIfValid(String email, String password) {
    if (!kDemoLoginEnabled) {
      return null;
    }
    final e = email.trim().toLowerCase();
    final p = password;
    if (p != sharedPassword) {
      return null;
    }
    if (e == consultantEmail.toLowerCase()) {
      return Role.consultant;
    }
    if (e == landownerEmail.toLowerCase()) {
      return Role.landowner;
    }
    return null;
  }
}
