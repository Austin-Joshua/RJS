import 'package:clerk_flutter/clerk_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import 'demo_session.dart';

/// FR-01 sign-in. Clerk for real accounts; demo farmer for offline pitch.
class SignInPage extends ConsumerWidget {
  const SignInPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('FarmSync')),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Text(
                'Sign in to view your fields, plans, and advisories.',
                style: TextStyle(fontSize: 16, color: AppColors.soilBrown),
                textAlign: TextAlign.center,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => ref.read(demoSessionProvider.notifier).enter(),
                  icon: const Icon(Icons.agriculture),
                  label: const Text('Continue as Demo Farmer'),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Uses Kallapuram sample field + rasterized Orthomosaic/DEM',
                style: TextStyle(fontSize: 13, color: AppColors.clay),
                textAlign: TextAlign.center,
              ),
            ),
            const Divider(height: 1),
            const Expanded(
              child: ClerkErrorListener(child: ClerkAuthentication()),
            ),
          ],
        ),
      ),
    );
  }
}
