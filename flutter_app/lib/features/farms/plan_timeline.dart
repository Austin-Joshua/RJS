import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/widgets/glass.dart';
import '../../data/models/farm_models.dart';
import 'format.dart';

/// Visual year plan: season strip + interactive earnings chart.
class PlanTimeline extends StatefulWidget {
  const PlanTimeline({super.key, required this.ranking});

  final RankingOut ranking;

  @override
  State<PlanTimeline> createState() => _PlanTimelineState();
}

class _PlanTimelineState extends State<PlanTimeline> {
  int? _touched;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final crops = widget.ranking.rankedCrops;
    if (crops.isEmpty) return const SizedBox.shrink();

    final maxV = crops.map((c) => c.realisedValueRs).fold<double>(0, (a, b) => a > b ? a : b);
    final touched = _touched != null && _touched! < crops.length ? crops[_touched!] : null;

    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your planting plan', style: textTheme.titleMedium),
          const SizedBox(height: 2),
          Text(
            'Tap a bar to see that season’s crop, yield band and earnings.',
            style: textTheme.bodySmall?.copyWith(color: AppColors.clay),
          ),
          const SizedBox(height: 16),
          // Season path — flexible widths so 3–4 nodes never overflow a phone.
          SizedBox(
            height: 92,
            child: Row(
              children: [
                for (var i = 0; i < crops.length; i++) ...[
                  if (i > 0)
                    Expanded(
                      flex: 1,
                      child: Container(
                        height: 3,
                        margin: const EdgeInsets.only(bottom: 28),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppColors.deepGreen.withValues(alpha: 0.5),
                              AppColors.terracotta.withValues(alpha: 0.6),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  Expanded(
                    flex: 3,
                    child: _SeasonNode(
                      crop: crops[i],
                      selected: _touched == i,
                      onTap: () => setState(() => _touched = i),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 190,
            child: BarChart(
              BarChartData(
                maxY: (maxV <= 0 ? 1 : maxV) * 1.15,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: AppColors.clay.withValues(alpha: 0.15),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= crops.length) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            seasonLabel(crops[i].season),
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
                  handleBuiltInTouches: true,
                  touchCallback: (event, response) {
                    if (!event.isInterestedForInteractions || response?.spot == null) {
                      return;
                    }
                    setState(() => _touched = response!.spot!.touchedBarGroupIndex);
                  },
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => AppColors.deepGreen.withValues(alpha: 0.92),
                    getTooltipItem: (group, _, rod, _) {
                      final c = crops[group.x];
                      return BarTooltipItem(
                        '${c.nameEn}\n${formatRs(c.realisedValueRs)}\n'
                        '${c.yieldTHa.toStringAsFixed(2)} t/ha',
                        const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                      );
                    },
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < crops.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: crops[i].realisedValueRs.clamp(0, double.infinity),
                          width: 28,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: _touched == i
                                ? [AppColors.terracotta, const Color(0xFFE8A06A)]
                                : [AppColors.deepGreen, const Color(0xFF6B9B74)],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          if (touched != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.deepGreen.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.deepGreen.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${seasonLabel(touched.season)} · ${touched.nameEn}',
                    style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Earns ${formatRs(touched.realisedValueRs)} · '
                    'yield ${touched.yieldTHa.toStringAsFixed(2)} t/ha '
                    '(${touched.p10.toStringAsFixed(1)}–${touched.p90.toStringAsFixed(1)})',
                    style: textTheme.bodySmall?.copyWith(color: AppColors.clay),
                  ),
                  const SizedBox(height: 4),
                  Text(touched.why, style: textTheme.bodySmall),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: Text('Total for the year', style: textTheme.titleMedium)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  formatRs(widget.ranking.totalValueRs),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: textTheme.titleLarge?.copyWith(color: AppColors.deepGreen),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SeasonNode extends StatelessWidget {
  const _SeasonNode({required this.crop, required this.selected, required this.onTap});

  final RankedCropOut crop;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.deepGreen.withValues(alpha: 0.14) : Colors.white.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.deepGreen : Colors.white.withValues(alpha: 0.7),
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Column(
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: selected ? AppColors.terracotta : AppColors.deepGreen,
              child: Text('${crop.rank}',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 4),
            Text(
              crop.nameEn,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, fontSize: 11),
            ),
            Text(
              seasonLabel(crop.season),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodySmall?.copyWith(color: AppColors.clay, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

/// Interactive water availability control (add-farm + detail).
class WaterSliderCard extends StatelessWidget {
  const WaterSliderCard({
    super.key,
    required this.valueM3,
    required this.onChanged,
    this.min = 0,
    this.max = 20000,
    this.readOnly = false,
    this.title = 'Irrigation water for the season',
    this.subtitle = 'Slide to set how much water you can give the land.',
    this.embedded = false,
  });

  final double valueM3;
  final ValueChanged<double> onChanged;
  final double min;
  final double max;
  final bool readOnly;
  final String title;
  final String subtitle;

  /// When true, skip the outer glass shell (already inside another panel).
  final bool embedded;

  String get _band {
    if (valueM3 < 3000) return 'Scarce — pulses & oilseeds';
    if (valueM3 < 7000) return 'Limited — dry crops';
    if (valueM3 < 12000) return 'Good — most rotations';
    return 'Abundant — paddy-friendly';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final t = ((valueM3 - min) / (max - min)).clamp(0.0, 1.0);
    final fill = Color.lerp(AppColors.terracotta, const Color(0xFF2F6F8F), t)!;

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.water_drop_outlined, color: fill),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700))),
          ],
        ),
        const SizedBox(height: 4),
        Text(subtitle, style: textTheme.bodySmall?.copyWith(color: AppColors.clay)),
        const SizedBox(height: 12),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: valueM3 >= 1000
                    ? '${(valueM3 / 1000).toStringAsFixed(1)}k'
                    : valueM3.toStringAsFixed(0),
                style: textTheme.displayMedium?.copyWith(color: fill, fontSize: 34),
              ),
              TextSpan(
                text: ' m³',
                style: textTheme.bodyMedium?.copyWith(color: AppColors.clay),
              ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          _band,
          style: textTheme.bodySmall?.copyWith(color: fill, fontWeight: FontWeight.w600),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: fill,
            inactiveTrackColor: fill.withValues(alpha: 0.18),
            thumbColor: fill,
            overlayColor: fill.withValues(alpha: 0.15),
            trackHeight: 6,
          ),
          child: Slider(
            value: valueM3.clamp(min, max),
            min: min,
            max: max,
            divisions: 40,
            label: '${valueM3.round()} m³',
            onChanged: readOnly ? null : onChanged,
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Dry', style: textTheme.bodySmall?.copyWith(color: AppColors.clay, fontSize: 11)),
            Text('Canal / well rich', style: textTheme.bodySmall?.copyWith(color: AppColors.clay, fontSize: 11)),
          ],
        ),
      ],
    );

    if (embedded) return body;
    return GlassPanel(child: body);
  }
}
