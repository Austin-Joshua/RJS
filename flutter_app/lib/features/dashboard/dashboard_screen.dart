import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/brand.dart';
import '../../core/theme.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/page_section.dart';
import '../../data/models/farm_models.dart';
import '../../data/repos/farm_repo.dart';
import '../farms/farm_detail_screen.dart';
import '../farms/format.dart';

/// Account-wide farm report — earnings, soil, and crop plans in plain language.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dash = ref.watch(dashboardProvider);
    final textTheme = Theme.of(context).textTheme;

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(dashboardProvider),
      color: AppColors.deepGreen,
      child: dash.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.deepGreen)),
        error: (e, _) => ListView(
          padding: AppBrand.pagePadding,
          children: [
            const SizedBox(height: 48),
            const Icon(Icons.cloud_off, size: 48, color: AppColors.terracotta),
            const SizedBox(height: 12),
            Text('Could not load your report', textAlign: TextAlign.center, style: textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('$e', textAlign: TextAlign.center, style: textTheme.bodySmall?.copyWith(color: AppColors.clay)),
          ],
        ),
        data: (d) => d.farms == 0
            ? ListView(
                padding: AppBrand.pagePadding,
                children: [
                  const SizedBox(height: 48),
                  const Icon(Icons.dashboard_outlined, size: 56, color: AppColors.clay),
                  const SizedBox(height: 16),
                  Text('No farms yet', textAlign: TextAlign.center, style: textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    'Add a farm on the Farms tab. Your earnings summary and soil charts will show up here.',
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium?.copyWith(color: AppColors.clay),
                  ),
                ],
              )
            : ListView(
                padding: AppBrand.pagePadding,
                children: [
                  const PageHero(
                    title: 'Farm report',
                    subtitle: 'A simple overview of all your land — how much you might earn, soil health, and what to plant.',
                  ),
                  const SizedBox(height: 16),
                  _SummaryHero(d: d),
                  if (d.landVariables.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    PageSection(
                      icon: Icons.grass_outlined,
                      title: 'Soil nutrients',
                      subtitle: 'Nitrogen, phosphorus and potassium across your farms. Orange means low.',
                      child: _LandCompareChart(rows: d.landVariables),
                    ),
                  ],
                  if (d.cropFrequency.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    PageSection(
                      icon: Icons.eco_outlined,
                      title: 'Crops in your plans',
                      subtitle: 'How often each crop appears in your recommended rotations.',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final e in (d.cropFrequency.entries.toList()
                            ..sort((a, b) => b.value.compareTo(a.value))))
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppColors.deepGreen.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: AppColors.deepGreen.withValues(alpha: 0.2)),
                              ),
                              child: Text(
                                '${cropLabel(e.key)} · ${e.value}×',
                                style: textTheme.bodyMedium?.copyWith(
                                  color: AppColors.deepGreen,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  if (d.quantum != null) ...[
                    const SizedBox(height: 24),
                    PageSection(
                      icon: Icons.auto_awesome_outlined,
                      title: 'Crop planner',
                      subtitle: 'How well the optimiser found profitable, legal crop orders.',
                      child: _QuantumDashCard(q: d.quantum!),
                    ),
                  ],
                  const SizedBox(height: 24),
                  PageSection(
                    icon: Icons.agriculture_outlined,
                    title: 'Your farms',
                    subtitle: 'Tap a farm for soil card, NDVI and the full plan.',
                    child: Column(
                      children: [for (final row in d.rows) _FarmRow(row: row)],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _SummaryHero extends StatelessWidget {
  const _SummaryHero({required this.d});

  final DashboardOut d;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('At a glance', style: textTheme.bodySmall?.copyWith(color: AppColors.clay)),
          if (d.farmsRanked > 0) ...[
            const SizedBox(height: 6),
            Text(
              'Expected earnings (ranked farms)',
              style: textTheme.bodySmall?.copyWith(color: AppColors.clay),
            ),
            Text(
              formatRs(d.combinedValueRs),
              style: textTheme.displayMedium?.copyWith(
                color: AppColors.deepGreen,
                fontWeight: FontWeight.w800,
              ),
            ),
          ] else ...[
            const SizedBox(height: 6),
            Text(
              'Run the crop planner on each farm to see expected earnings.',
              style: textTheme.bodyMedium?.copyWith(color: AppColors.clay),
            ),
          ],
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: InfoTile(label: 'Farms', value: '${d.farms}')),
              Container(width: 1, height: 36, color: AppColors.clay.withValues(alpha: 0.25)),
              Expanded(child: InfoTile(label: 'Total land', value: '${d.totalAreaHa.toStringAsFixed(1)} ha')),
              Container(width: 1, height: 36, color: AppColors.clay.withValues(alpha: 0.25)),
              Expanded(
                child: InfoTile(
                  label: 'Plans ready',
                  value: '${d.farmsRanked}/${d.farms}',
                  valueColor: d.farmsRanked == d.farms ? AppColors.deepGreen : AppColors.terracotta,
                ),
              ),
            ],
          ),
          if (d.farmsAwaiting > 0) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.terracotta.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 18, color: AppColors.terracotta),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${d.farmsAwaiting} farm${d.farmsAwaiting == 1 ? '' : 's'} still need a crop plan.',
                      style: textTheme.bodySmall?.copyWith(color: AppColors.soilBrown),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuantumDashCard extends StatelessWidget {
  const _QuantumDashCard({required this.q});

  final DashboardQuantumOut q;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final feasPct = ((q.avgFeasibleRate ?? 0) * 100).clamp(0, 100);

    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(q.plainSummary, style: textTheme.bodyMedium?.copyWith(height: 1.4)),
          const SizedBox(height: 16),
          _MetricRow(
            icon: Icons.check_circle_outline,
            label: 'Legal crop orders found',
            value: q.avgFeasibleRate == null ? '—' : '${feasPct.toStringAsFixed(0)}%',
            hint: 'Rotation rules respected',
          ),
          const SizedBox(height: 10),
          _MetricRow(
            icon: Icons.trending_up,
            label: 'Beat simple sorting',
            value: '${q.beatsSimpleSortCount} of ${q.farmsOptimised}',
            hint: q.extraValueVsSortRs > 0
                ? '+${formatRs(q.extraValueVsSortRs)} vs sorting by profit alone'
                : 'Times the smart order earned more',
          ),
          if (q.avgWallTimeS != null) ...[
            const SizedBox(height: 10),
            _MetricRow(
              icon: Icons.timer_outlined,
              label: 'Average run time',
              value: '${q.avgWallTimeS!.toStringAsFixed(1)} s',
              hint: 'Per farm optimisation',
            ),
          ],
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.hint,
  });

  final IconData icon;
  final String label;
  final String value;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppColors.deepGreen),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
              Text(hint, style: textTheme.bodySmall?.copyWith(color: AppColors.clay, fontSize: 11)),
            ],
          ),
        ),
        Text(
          value,
          style: textTheme.titleSmall?.copyWith(color: AppColors.deepGreen, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _LandCompareChart extends StatelessWidget {
  const _LandCompareChart({required this.rows});

  final List<LandVariableRow> rows;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final shown = rows.take(6).toList();
    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 200,
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
                      reservedSize: 40,
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= shown.length) return const SizedBox.shrink();
                        final name = shown[i].name;
                        final short = name.length > 10 ? '${name.substring(0, 9)}…' : name;
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            short,
                            style: textTheme.bodySmall?.copyWith(fontSize: 10, color: AppColors.clay),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < shown.length; i++)
                    BarChartGroupData(
                      x: i,
                      barsSpace: 3,
                      barRods: [
                        _rod(shown[i].nKgHa, 560, shown[i].classes['n_kg_ha']),
                        _rod(shown[i].pKgHa, 56, shown[i].classes['p_kg_ha']),
                        _rod(shown[i].kKgHa, 400, shown[i].classes['k_kg_ha']),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _legendDot(AppColors.deepGreen, 'N'),
              const SizedBox(width: 12),
              _legendDot(AppColors.clay, 'P'),
              const SizedBox(width: 12),
              _legendDot(AppColors.terracotta, 'K'),
              const Spacer(),
              Text(
                'Taller bar = higher level',
                style: textTheme.bodySmall?.copyWith(fontSize: 10, color: AppColors.clay),
              ),
            ],
          ),
        ],
      ),
    );
  }

  BarChartRodData _rod(double? value, double max, String? rating) {
    final y = value == null ? 0.0 : (value / max).clamp(0.05, 1.0);
    final base = rating == 'low'
        ? AppColors.terracotta
        : rating == 'high'
            ? AppColors.deepGreen
            : AppColors.clay;
    return BarChartRodData(
      toY: y,
      width: 8,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
      color: base,
    );
  }

  Widget _legendDot(Color c, String label) {
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.clay)),
      ],
    );
  }
}

class _FarmRow extends StatelessWidget {
  const _FarmRow({required this.row});

  final DashboardFarmRow row;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hasPlan = row.sequenceNames.isNotEmpty;

    return GlassPanel(
      margin: const EdgeInsets.only(bottom: 10),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => FarmDetailScreen(farmId: row.farmId)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(row.name, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (hasPlan ? AppColors.deepGreen : AppColors.terracotta).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  hasPlan ? 'Plan ready' : 'Needs plan',
                  style: textTheme.labelSmall?.copyWith(
                    color: hasPlan ? AppColors.deepGreen : AppColors.terracotta,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _FarmFact(icon: Icons.place_outlined, text: '${row.district} · ${row.areaHa.toStringAsFixed(1)} ha'),
          if (row.soilSummary != null)
            _FarmFact(icon: Icons.science_outlined, text: row.soilSummary!),
          if (hasPlan) ...[
            _FarmFact(
              icon: Icons.calendar_today_outlined,
              text: row.sequenceNames.join(' → '),
              bold: true,
            ),
            if (row.totalValueRs != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Expected ${formatRs(row.totalValueRs)}',
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.deepGreen,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
          if (row.issues.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final issue in row.issues)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.terracotta.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      issue,
                      style: textTheme.bodySmall?.copyWith(color: AppColors.terracotta, fontSize: 11),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _FarmFact extends StatelessWidget {
  const _FarmFact({required this.icon, required this.text, this.bold = false});

  final IconData icon;
  final String text;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.clay),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: (bold ? textTheme.bodyMedium : textTheme.bodySmall)?.copyWith(
                fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
                color: bold ? AppColors.soilBrown : AppColors.clay,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
