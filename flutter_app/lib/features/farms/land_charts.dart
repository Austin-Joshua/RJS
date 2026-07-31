import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/widgets/glass.dart';
import '../../data/models/farm_models.dart';
import 'format.dart';

/// Interactive soil nutrient bars — tap a bar for the exact reading.
class LandVariableChart extends StatefulWidget {
  const LandVariableChart({super.key, required this.card});

  final SoilCardOut card;

  @override
  State<LandVariableChart> createState() => _LandVariableChartState();
}

class _LandVariableChartState extends State<LandVariableChart> {
  int? _touched;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final bars = <_Bar>[
      _Bar('Nitrogen', widget.card.readings['n_kg_ha'], 560, widget.card.classes['n_kg_ha'] ?? 'unknown', 'kg/ha'),
      _Bar('Phosphorus', widget.card.readings['p_kg_ha'], 56, widget.card.classes['p_kg_ha'] ?? 'unknown', 'kg/ha'),
      _Bar('Potassium', widget.card.readings['k_kg_ha'], 400, widget.card.classes['k_kg_ha'] ?? 'unknown', 'kg/ha'),
      _Bar('Org. carbon', widget.card.readings['oc_pct'], 1.2, widget.card.classes['oc_pct'] ?? 'unknown', '%'),
      _Bar('pH', widget.card.readings['ph'], 14, _phBand(widget.card.ph['category'] as String?), ''),
    ].where((b) => b.value != null).toList();

    if (bars.isEmpty) return const SizedBox.shrink();
    final picked = _touched != null && _touched! < bars.length ? bars[_touched!] : null;

    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your land at a glance',
              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(
            'Tap a bar — orange means low, green means healthy.',
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
                            style: textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                              fontWeight: _touched == i ? FontWeight.w700 : FontWeight.w400,
                              color: _touched == i ? AppColors.deepGreen : AppColors.clay,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barTouchData: BarTouchData(
                  enabled: true,
                  touchCallback: (event, response) {
                    if (!event.isInterestedForInteractions || response?.spot == null) return;
                    setState(() => _touched = response!.spot!.touchedBarGroupIndex);
                  },
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => AppColors.deepGreen.withValues(alpha: 0.92),
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
                barGroups: [
                  for (var i = 0; i < bars.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: (bars[i].value! / bars[i].scaleMax).clamp(0.05, 1.0),
                          width: _touched == i ? 28 : 22,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                          color: ratingColor(bars[i].rating),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          if (picked != null) ...[
            const SizedBox(height: 8),
            Text(
              '${picked.label}: ${picked.value!.toStringAsFixed(picked.unit == '%' ? 2 : 1)} ${picked.unit} · ${picked.rating}',
              style: textTheme.bodySmall?.copyWith(
                color: ratingColor(picked.rating),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
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
