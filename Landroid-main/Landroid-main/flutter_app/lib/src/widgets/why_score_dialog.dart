import 'package:flutter/material.dart';

import '../i18n/translations.dart';

/// Shows FR-22 composite weights and per-signal subscores from ``land_health.score_breakdown``.
void showWhyScoreDialog(
  BuildContext context, {
  required LocaleCode locale,
  required Map<String, dynamic> landHealth,
}) {
  final methodology = landHealth['methodology'] as Map<String, dynamic>?;
  final breakdown = landHealth['score_breakdown'] as Map<String, dynamic>?;
  final mode = landHealth['data_mode'] as String?;
  final weights = breakdown?['weights_percent'] as Map<String, dynamic>?;
  final sub = breakdown?['subscores_0_100'] as Map<String, dynamic>?;
  final wcontrib = breakdown?['weighted_contribution'] as Map<String, dynamic>?;

  showDialog<void>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final muted = theme.colorScheme.onSurfaceVariant;
      return AlertDialog(
        title: Text(t(locale, 'whyThisScoreTitle')),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (mode != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    '${t(locale, 'dataSourceLabel')}: $mode',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (methodology?['composite_fr22'] != null)
                Text(
                  methodology!['composite_fr22'] as String,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                ),
              if (methodology?['warning'] != null) ...[
                const SizedBox(height: 12),
                Text(
                  methodology!['warning'] as String,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: muted,
                    height: 1.35,
                  ),
                ),
              ],
              if (weights != null && weights.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  t(locale, 'whyScoreWeights'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                ...weights.entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${e.key}: ${e.value}%',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ),
                ),
              ],
              if (sub != null && sub.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  t(locale, 'whyScoreSubscores'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                ...sub.entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${e.key}: ${e.value}',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ),
                ),
              ],
              if (wcontrib != null && wcontrib.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  t(locale, 'whyScoreContributions'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                ...wcontrib.entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${e.key}: ${e.value} ${t(locale, 'pointsSuffix')}',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ),
                ),
              ],
              if (breakdown?['composite_0_100'] != null) ...[
                const SizedBox(height: 12),
                Text(
                  '${t(locale, 'compositeLabel')}: ${breakdown!['composite_0_100']}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(t(locale, 'dialogDismiss')),
          ),
        ],
      );
    },
  );
}
