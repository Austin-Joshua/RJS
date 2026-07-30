import 'package:clerk_flutter/clerk_flutter.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// FR-01 sign-in screen. Clerk handles the actual auth flow (OTP/password/
/// SSO per Dashboard config); this just hosts its widget and branding.
class SignInPage extends StatelessWidget {
  const SignInPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('FarmSync')),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 32, 24, 8),
              child: Text(
                'Sign in to view your fields, plans, and advisories.',
                style: TextStyle(fontSize: 16, color: AppColors.soilBrown),
                textAlign: TextAlign.center,
              ),
            ),
            const Expanded(
              child: ClerkErrorListener(child: ClerkAuthentication()),
            ),
          ],
        ),
      ),
    );
  }
}
