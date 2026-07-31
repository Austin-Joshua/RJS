import 'package:clerk_flutter/clerk_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/brand.dart';
import '../../core/demo_session.dart';
import '../../core/env.dart';
import '../../core/theme.dart';
import '../../core/widgets/glass.dart';

/// FarmSync sign-in — brand hero + compact Clerk card + optional demo.
class SignInPage extends ConsumerWidget {
  const SignInPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;

    return AtmosphereBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight - 56),
                  child: Column(
                    children: [
                      const SizedBox(height: 12),
                      const _BrandHero(),
                      const SizedBox(height: 28),
                      GlassPanel(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Sign in',
                              style: textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppColors.deepGreen,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Google account — your farms stay private.',
                              style: textTheme.bodySmall?.copyWith(color: AppColors.clay),
                            ),
                            const SizedBox(height: 16),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.62),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppColors.clay.withValues(alpha: 0.18)),
                              ),
                              child: ClipRRect(
                                borderRadius: const BorderRadius.all(Radius.circular(14)),
                                child: Material(
                                  color: Colors.transparent,
                                  child: ClerkErrorListener(
                                    child: SizedBox(
                                      height: 200,
                                      child: SingleChildScrollView(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                        child: ClerkAuthentication(),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (Env.hasDemoLogin) ...[
                        const SizedBox(height: 20),
                        _DemoSection(onContinue: () => ref.read(demoSessionProvider.notifier).start()),
                      ],
                      const SizedBox(height: 16),
                      Text(
                        'FarmSync Quantum 2.0',
                        style: textTheme.bodySmall?.copyWith(
                          color: AppColors.clay.withValues(alpha: 0.85),
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _BrandHero extends StatelessWidget {
  const _BrandHero();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.deepGreen.withValues(alpha: 0.15),
                AppColors.terracotta.withValues(alpha: 0.12),
              ],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.7), width: 2),
            boxShadow: [
              BoxShadow(
                color: AppColors.deepGreen.withValues(alpha: 0.12),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.grass_rounded, size: 44, color: AppColors.deepGreen),
        ),
        const SizedBox(height: 18),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [AppColors.deepGreen, Color(0xFF3D6B4A)],
          ).createShader(bounds),
          child: Text(
            AppBrand.name,
            textAlign: TextAlign.center,
            style: textTheme.displayMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            AppBrand.tagline,
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(color: AppColors.clay, height: 1.4),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: const [
            _FeatureChip(icon: Icons.water_drop_outlined, label: 'Water gates'),
            _FeatureChip(icon: Icons.show_chart, label: 'LightGBM'),
            _FeatureChip(icon: Icons.memory_outlined, label: 'SPARQ'),
          ],
        ),
      ],
    );
  }
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.deepGreen.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.deepGreen),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.soilBrown,
                  fontSize: 12,
                ),
          ),
        ],
      ),
    );
  }
}

class _DemoSection extends StatefulWidget {
  const _DemoSection({required this.onContinue});

  final VoidCallback onContinue;

  @override
  State<_DemoSection> createState() => _DemoSectionState();
}

class _DemoSectionState extends State<_DemoSection> {
  bool _showCreds = false;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return GlassPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.terracotta.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.agriculture, color: AppColors.terracotta, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Demo farms', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    Text(
                      'Three Thanjavur fields — no sign-in',
                      style: textTheme.bodySmall?.copyWith(color: AppColors.clay),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: widget.onContinue,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.deepGreen,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Open demo'),
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _showCreds = !_showCreds),
            child: Text(_showCreds ? 'Hide credentials' : 'Show demo credentials'),
          ),
          if (_showCreds) ...[
            _CredRow(label: 'Account', value: Env.demoUserId),
            const SizedBox(height: 6),
            _CredRow(label: 'Token', value: Env.devLoginToken, mono: true),
          ],
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
          width: 58,
          child: Text(label, style: textTheme.bodySmall?.copyWith(color: AppColors.clay, fontSize: 12)),
        ),
        Expanded(
          child: SelectableText(
            value,
            maxLines: 1,
            style: textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              fontFamily: mono ? 'monospace' : null,
              fontSize: mono ? 10 : 12,
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
