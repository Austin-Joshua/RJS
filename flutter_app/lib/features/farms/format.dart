import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Indian digit grouping — ₹1,42,000, not ₹142,000. The farmer reads these
/// numbers; western grouping is harder to parse at a glance.
String formatRs(double? v) {
  if (v == null) return '—';
  final digits = v.round().abs().toString();
  final sign = v < 0 ? '-' : '';
  if (digits.length <= 3) return '$sign₹$digits';

  final last3 = digits.substring(digits.length - 3);
  var rest = digits.substring(0, digits.length - 3);
  final groups = <String>[];
  while (rest.length > 2) {
    groups.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) groups.insert(0, rest);
  return '$sign₹${groups.join(',')},$last3';
}

String cropLabel(String code) => switch (code) {
      'paddy' => 'Paddy',
      'black_gram' => 'Black gram',
      'groundnut' => 'Groundnut',
      'sugarcane' => 'Sugarcane',
      'maize' => 'Maize',
      _ => code.replaceAll('_', ' '),
    };

String nutrientLabel(String key) => switch (key) {
      'n_kg_ha' => 'N',
      'p_kg_ha' => 'P',
      'k_kg_ha' => 'K',
      'oc_pct' => 'OC',
      _ => key,
    };

String seasonLabel(String code) => switch (code) {
      'kharif' => 'Kharif',
      'rabi' => 'Rabi',
      'summer' => 'Summer',
      _ => code,
    };

Color ratingColor(String rating) => switch (rating) {
      'low' => AppColors.terracotta,
      'high' => AppColors.deepGreen,
      'medium' => AppColors.clay,
      _ => AppColors.clay,
    };

/// Low / Medium / High chip for a soil nutrient (§2.3 — classes, not raw
/// numbers, are what a farmer can act on).
class NutrientChip extends StatelessWidget {
  const NutrientChip({super.key, required this.label, required this.rating});

  final String label;
  final String rating;

  @override
  Widget build(BuildContext context) {
    final color = ratingColor(rating);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        '$label · ${rating[0].toUpperCase()}${rating.substring(1)}',
        style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }
}
