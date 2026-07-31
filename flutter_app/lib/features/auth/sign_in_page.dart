import 'package:clerk_flutter/clerk_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/demo_session.dart';
import '../../core/env.dart';
import '../../core/theme.dart';

/// Google Sign-In plus an optional seeded demo account (brief §2.1).
class SignInPage extends ConsumerWidget {
  const SignInPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.clay.withValues(alpha: 0.45), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.soilBrown.withValues(alpha: 0.08),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.eco, size: 48, color: AppColors.deepGreen),
                    const SizedBox(height: 12),
                    Text('Crop Advisor', textAlign: TextAlign.center, style: textTheme.displayMedium),
                    const SizedBox(height: 8),
                    Text(
                      'See what your land can grow, and the crop order that earns the most this year.',
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium?.copyWith(color: AppColors.clay),
                    ),
                    const SizedBox(height: 22),
                    const Divider(height: 1),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 280,
                      child: ClipRect(
                        child: ClerkErrorListener(child: ClerkAuthentication()),
                      ),
                    ),
                    if (Env.hasDemoLogin) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Expanded(child: Divider()),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text('or try the demo',
                                style: textTheme.bodySmall?.copyWith(color: AppColors.clay)),
                          ),
                          const Expanded(child: Divider()),
                        ],
                      ),
                      const SizedBox(height: 14),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.deepGreen.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Demo farms (pre-loaded)',
              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            'Three Thanjavur farms with soil cards and crop rankings already filled in.',
            style: textTheme.bodySmall?.copyWith(color: AppColors.clay),
          ),
          const SizedBox(height: 12),
          _CredRow(label: 'Account', value: Env.demoUserId),
          const SizedBox(height: 6),
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Text(label, style: textTheme.bodySmall?.copyWith(color: AppColors.clay)),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              fontFamily: mono ? 'monospace' : null,
              color: AppColors.soilBrown,
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
