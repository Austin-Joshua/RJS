import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models/farm_models.dart';
import 'format.dart';

/// The soil card (brief §2.3): the farmer's own readings handed straight back,
/// with each one classified so the numbers mean something.
class SoilCardView extends StatelessWidget {
  const SoilCardView({
    super.key,
    required this.card,
    required this.farmName,
    this.scrollController,
  });

  final SoilCardOut card;
  final String farmName;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        Text('Soil card', style: textTheme.titleLarge),
        Text(farmName, style: textTheme.bodyMedium?.copyWith(color: AppColors.clay)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.deepGreen.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.deepGreen.withValues(alpha: 0.3)),
          ),
          child: Text(card.summary, style: textTheme.bodyLarge),
        ),
        const SizedBox(height: 20),
        Text('Nutrients', style: textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final entry in card.classes.entries)
          _ReadingRow(
            label: fullNutrientName(entry.key),
            value: _formatReading(entry.key, card.readings[entry.key]),
            rating: entry.value,
          ),
        const SizedBox(height: 16),
        Text('Soil condition', style: textTheme.titleMedium),
        const SizedBox(height: 8),
        _NoteTile(
          title: 'pH ${card.readings['ph']?.toStringAsFixed(1) ?? '—'}',
          subtitle: card.ph['note'] as String? ?? '',
          category: card.ph['category'] as String? ?? '',
        ),
        if (card.ec['value'] != null)
          _NoteTile(
            title: 'Salinity ${(card.ec['value'] as num).toStringAsFixed(2)} dS/m',
            subtitle: card.ec['note'] as String? ?? '',
            category: card.ec['category'] as String? ?? '',
          ),
        if (card.water['per_ha_m3'] != null)
          _NoteTile(
            title: 'Water ${(card.water['per_ha_m3'] as num).toStringAsFixed(0)} m³/ha',
            subtitle: card.water['note'] as String? ?? '',
            category: card.water['category'] as String? ?? '',
          ),
        _NoteTile(title: 'Soil type', subtitle: card.soilTypeName, category: 'neutral'),
        if (card.warnings.isNotEmpty) ...[
          const SizedBox(height: 16),
          for (final w in card.warnings)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 16, color: AppColors.clay),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(w, style: textTheme.bodySmall?.copyWith(color: AppColors.clay)),
                  ),
                ],
              ),
            ),
        ],
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.clay.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.warning_amber_outlined, size: 18, color: AppColors.clay),
              const SizedBox(width: 10),
              Expanded(child: Text(card.caveat, style: textTheme.bodySmall?.copyWith(color: AppColors.soilBrown))),
            ],
          ),
        ),
      ],
    );
  }

  static String fullNutrientName(String key) => switch (key) {
        'n_kg_ha' => 'Nitrogen (N)',
        'p_kg_ha' => 'Phosphorus (P)',
        'k_kg_ha' => 'Potassium (K)',
        'oc_pct' => 'Organic carbon',
        _ => key,
      };

  String _formatReading(String key, double? value) {
    if (value == null) return 'not entered';
    return key == 'oc_pct' ? '${value.toStringAsFixed(2)} %' : '${value.toStringAsFixed(0)} kg/ha';
  }
}

class _ReadingRow extends StatelessWidget {
  const _ReadingRow({required this.label, required this.value, required this.rating});

  final String label;
  final String value;
  final String rating;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(flex: 4, child: Text(label, style: textTheme.bodyMedium)),
          Expanded(
            flex: 3,
            child: Text(value,
                textAlign: TextAlign.end,
                style: textTheme.bodyMedium?.copyWith(color: AppColors.clay)),
          ),
          const SizedBox(width: 10),
          if (rating != 'unknown') NutrientChip(label: '', rating: rating),
        ],
      ),
    );
  }
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({required this.title, required this.subtitle, required this.category});

  final String title;
  final String subtitle;
  final String category;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final bad = {'strongly_acidic', 'sodic', 'injurious', 'low'}.contains(category);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            bad ? Icons.error_outline : Icons.check_circle_outline,
            size: 18,
            color: bad ? AppColors.terracotta : AppColors.deepGreen,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                if (subtitle.isNotEmpty)
                  Text(subtitle, style: textTheme.bodySmall?.copyWith(color: AppColors.clay)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
