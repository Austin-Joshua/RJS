import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models/farm_models.dart';
import 'format.dart';

/// Simple bar chart of the farmer's land readings — what the soil card numbers
/// look like as a picture, coloured by low / medium / high.
class LandVariableChart extends StatelessWidget {
  const LandVariableChart({super.key, required this.card});

  final SoilCardOut card;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final bars = <_Bar>[
      _Bar('Nitrogen', card.readings['n_kg_ha'], 560, card.classes['n_kg_ha'] ?? 'unknown', 'kg/ha'),
      _Bar('Phosphorus', card.readings['p_kg_ha'], 56, card.classes['p_kg_ha'] ?? 'unknown', 'kg/ha'),
      _Bar('Potassium', card.readings['k_kg_ha'], 400, card.classes['k_kg_ha'] ?? 'unknown', 'kg/ha'),
      _Bar('Org. carbon', card.readings['oc_pct'], 1.2, card.classes['oc_pct'] ?? 'unknown', '%'),
      _Bar('pH', card.readings['ph'], 14, _phBand(card.ph['category'] as String?), ''),
    ].where((b) => b.value != null).toList();

    if (bars.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your land at a glance',
                style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(
              'Red / orange = low or needs attention. Green = healthy level for crops.',
              style: textTheme.bodySmall?.copyWith(color: AppColors.clay),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 180,
              child: BarChart(
                BarChartData(
                  maxY: 1.05,
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 36,
                        getTitlesWidget: (v, _) {
                          final i = v.toInt();
                          if (i < 0 || i >= bars.length) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              bars[i].label.split(' ').first,
                              style: textTheme.bodySmall?.copyWith(fontSize: 11, color: AppColors.clay),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: [
                    for (var i = 0; i < bars.length; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: (bars[i].value! / bars[i].scaleMax).clamp(0.05, 1.0),
                            width: 22,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                            color: ratingColor(bars[i].rating),
                          ),
                        ],
                      ),
                  ],
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, _, rod, _) {
                        final b = bars[group.x];
                        final shown = b.unit == '%'
                            ? b.value!.toStringAsFixed(2)
                            : b.unit.isEmpty
                                ? b.value!.toStringAsFixed(1)
                                : b.value!.toStringAsFixed(0);
                        return BarTooltipItem(
                          '${b.label}\n$shown ${b.unit}\n${b.rating}',
                          const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _phBand(String? category) {
    if (category == null || category.isEmpty) return 'medium';
    if ({'strongly_acidic', 'sodic', 'strongly_alkaline'}.contains(category)) return 'low';
    if (category.contains('slightly') || category == 'neutral') return 'high';
    return 'medium';
  }
}

class _Bar {
  const _Bar(this.label, this.value, this.scaleMax, this.rating, this.unit);
  final String label;
  final double? value;
  final double scaleMax;
  final String rating;
  final String unit;
}
