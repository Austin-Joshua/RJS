import 'package:clerk_flutter/clerk_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/demo_session.dart';
import '../../core/env.dart';
import '../../core/theme.dart';
import '../../core/widgets/glass.dart';

/// Google Sign-In plus an optional seeded demo account (brief §2.1).
///
/// Brand sits on the atmospheric background; Clerk lives only inside a
/// compact glass card — never stretched across the whole scaffold.
class SignInPage extends ConsumerWidget {
  const SignInPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;

    return AtmosphereBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.eco, size: 56, color: AppColors.deepGreen),
                    const SizedBox(height: 12),
                    Text('Crop Advisor', textAlign: TextAlign.center, style: textTheme.displayMedium),
                    const SizedBox(height: 8),
                    Text(
                      'Crop plans ordered by what will earn you the most.',
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium?.copyWith(color: AppColors.clay),
                    ),
                    const SizedBox(height: 28),

                    // Clerk only — contained card, not the whole page.
                    GlassPanel(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Sign in',
                            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Continue with Google. Your farms stay private to your account.',
                            style: textTheme.bodySmall?.copyWith(color: AppColors.clay),
                          ),
                          const SizedBox(height: 14),
                          Container(
                            height: 220,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.clay.withValues(alpha: 0.22)),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: const Material(
                              color: Colors.transparent,
                              child: ClerkErrorListener(
                                child: SingleChildScrollView(
                                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  child: ClerkAuthentication(),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (Env.hasDemoLogin) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(child: Divider(color: AppColors.clay.withValues(alpha: 0.35))),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text('or', style: textTheme.bodySmall?.copyWith(color: AppColors.clay)),
                          ),
                          Expanded(child: Divider(color: AppColors.clay.withValues(alpha: 0.35))),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _DemoCredentialsBox(
                        onContinue: () => ref.read(demoSessionProvider.notifier).start(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DemoCredentialsBox extends StatelessWidget {
  const _DemoCredentialsBox({required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Demo farms', style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            'Three Thanjavur farms already ranked — no Google needed.',
            style: textTheme.bodySmall?.copyWith(color: AppColors.clay),
          ),
          const SizedBox(height: 12),
          _CredRow(label: 'Account', value: Env.demoUserId),
          const SizedBox(height: 4),
          _CredRow(label: 'Token', value: Env.devLoginToken, mono: true),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onContinue,
              icon: const Icon(Icons.agriculture),
              label: const Text('Open demo farms'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CredRow extends StatelessWidget {
  const _CredRow({required this.label, required this.value, this.mono = false});

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(label, style: textTheme.bodySmall?.copyWith(color: AppColors.clay)),
        ),
        Expanded(
          child: SelectableText(
            value,
            maxLines: 1,
            style: textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              fontFamily: mono ? 'monospace' : null,
              fontSize: mono ? 11 : null,
              color: AppColors.soilBrown,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Copy',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          icon: const Icon(Icons.copy, size: 16, color: AppColors.clay),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: value));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$label copied'), duration: const Duration(seconds: 1)),
            );
          },
        ),
      ],
    );
  }
}
