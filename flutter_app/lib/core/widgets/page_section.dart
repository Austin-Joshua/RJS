import 'package:flutter/material.dart';

import '../theme.dart';

/// Page title + one-line explanation at the top of a tab.
class PageHero extends StatelessWidget {
  const PageHero({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(subtitle, style: textTheme.bodyMedium?.copyWith(color: AppColors.clay, height: 1.35)),
        ],
      ),
    );
  }
}

/// Numbered section with optional icon — keeps Report / Quantum tabs scannable.
class PageSection extends StatelessWidget {
  const PageSection({
    super.key,
    this.step,
    this.icon,
    required this.title,
    this.subtitle,
    required this.child,
  });

  final int? step;
  final IconData? icon;
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (step != null)
              Container(
                width: 26,
                height: 26,
                margin: const EdgeInsets.only(right: 10, top: 1),
                decoration: BoxDecoration(
                  color: AppColors.deepGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$step',
                  style: textTheme.labelLarge?.copyWith(
                    color: AppColors.deepGreen,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            else if (icon != null)
              Padding(
                padding: const EdgeInsets.only(right: 10, top: 2),
                child: Icon(icon, size: 22, color: AppColors.deepGreen),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: textTheme.bodySmall?.copyWith(color: AppColors.clay, height: 1.35),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

/// Compact label + value for summary grids.
class InfoTile extends StatelessWidget {
  const InfoTile({super.key, required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: textTheme.bodySmall?.copyWith(color: AppColors.clay, fontSize: 12)),
        const SizedBox(height: 2),
        Text(
          value,
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: valueColor ?? AppColors.soilBrown,
          ),
        ),
      ],
    );
  }
}
