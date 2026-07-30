import 'package:clerk_flutter/clerk_flutter.dart';
import 'package:flutter/material.dart';

import 'core/env.dart';
import 'core/theme.dart';
import 'features/auth/sign_in_page.dart';
import 'features/auth/signed_in_placeholder.dart';

void main() {
  runApp(const FarmSyncApp());
}

class FarmSyncApp extends StatelessWidget {
  const FarmSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Env.isClerkConfigured) {
      return MaterialApp(
        theme: buildAppTheme(),
        debugShowCheckedModeBanner: false,
        home: const _MissingClerkKeyScreen(),
      );
    }

    return ClerkAuth(
      config: ClerkAuthConfig(publishableKey: Env.clerkPublishableKey),
      child: MaterialApp(
        title: 'FarmSync',
        theme: buildAppTheme(),
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: ClerkErrorListener(
            child: ClerkAuthBuilder(
              signedInBuilder: (context, authState) => const SignedInPlaceholder(),
              signedOutBuilder: (context, authState) => const SignInPage(),
            ),
          ),
        ),
      ),
    );
  }
}

class _MissingClerkKeyScreen extends StatelessWidget {
  const _MissingClerkKeyScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Missing CLERK_PUBLISHABLE_KEY.\n\n'
            'Run with:\n'
            'flutter run --dart-define=CLERK_PUBLISHABLE_KEY=pk_...',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      ),
    );
  }
}
