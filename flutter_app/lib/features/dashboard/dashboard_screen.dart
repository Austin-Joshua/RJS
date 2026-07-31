import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/models/farm_models.dart';
import '../../data/repos/farm_repo.dart';
import '../farms/farm_detail_screen.dart';
import '../farms/format.dart';

/// Analytical dashboard across every farm on the account (brief §2.8).
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dash = ref.watch(dashboardProvider);
    final textTheme = Theme.of(context).textTheme;

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(dashboardProvider),
      child: dash.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.deepGreen)),
        error: (e, _) => ListView(
          padding: const EdgeInsets.all(32),
          children: [
            const Icon(Icons.cloud_off, size: 48, color: AppColors.terracotta),
            const SizedBox(height: 12),
            Text('$e', textAlign: TextAlign.center, style: textTheme.bodySmall),
          ],
        ),
        data: (d) => d.farms == 0
            ? ListView(
                padding: const EdgeInsets.fromLTRB(32, 96, 32, 32),
                children: [
                  const Icon(Icons.dashboard_outlined, size: 56, color: AppColors.clay),
                  const SizedBox(height: 16),
                  Text('Nothing to summarise yet',
                      textAlign: TextAlign.center, style: textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text('Add a farm on the My Farms tab to see it here.',
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium?.copyWith(color: AppColors.clay)),
                ],
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                children: [
                  Text('Your farm report', style: textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    'Simple numbers for every farm on this account — land, money, soil, and the quantum crop order.',
                    style: textTheme.bodySmall?.copyWith(color: AppColors.clay),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _Stat(label: 'Farms', value: '${d.farms}'),
                      _Stat(label: 'Total land', value: '${d.totalAreaHa.toStringAsFixed(2)} ha'),
                      _Stat(label: 'Plans ready', value: '${d.farmsRanked}/${d.farms}'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (d.farmsRanked > 0)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Expected earnings this year (ranked farms)',
                                style: textTheme.bodySmall?.copyWith(color: AppColors.clay)),
                            const SizedBox(height: 4),
                            Text(formatRs(d.combinedValueRs),
                                style: textTheme.displayMedium?.copyWith(color: AppColors.deepGreen)),
                            if (d.farmsAwaiting > 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  '${d.farmsAwaiting} farm${d.farmsAwaiting == 1 ? '' : 's'} still need a crop ranking.',
                                  style: textTheme.bodySmall?.copyWith(color: AppColors.clay),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  if (d.landVariables.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text('Land nutrients across farms', style: textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text('Compare nitrogen, phosphorus and potassium. Orange bars mean low.',
                        style: textTheme.bodySmall?.copyWith(color: AppColors.clay)),
                    const SizedBox(height: 10),
                    _LandCompareChart(rows: d.landVariables),
                  ],
                  if (d.quantum != null) ...[
                    const SizedBox(height: 20),
                    Text('Quantum crop optimiser', style: textTheme.titleMedium),
                    const SizedBox(height: 8),
                    _QuantumDashCard(q: d.quantum!),
                  ],
                  if (d.cropFrequency.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text('Crops in your plans', style: textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final e in (d.cropFrequency.entries.toList()
                          ..sort((a, b) => b.value.compareTo(a.value))))
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: AppColors.deepGreen.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text('${cropLabel(e.key)} × ${e.value}',
                                style: textTheme.bodyMedium?.copyWith(color: AppColors.deepGreen)),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text('Each farm', style: textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final row in d.rows) _FarmRow(row: row),
                ],
              ),
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
    final simplexPct = ((q.avgSimplexRate ?? 0) * 100).clamp(0, 100);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(q.plainSummary, style: textTheme.bodyMedium),
            const SizedBox(height: 14),
            Row(
              children: [
                _QMetric(
                  label: 'Valid order rate',
                  value: q.avgFeasibleRate == null ? '—' : '${feasPct.toStringAsFixed(0)}%',
                  hint: 'How often the algorithm found a legal crop order',
                ),
                _QMetric(
                  label: 'One crop / season',
                  value: q.avgSimplexRate == null ? '—' : '${simplexPct.toStringAsFixed(0)}%',
                  hint: 'Built into the quantum circuit',
                ),
                _QMetric(
                  label: 'Beat simple sort',
                  value: '${q.beatsSimpleSortCount}/${q.farmsOptimised}',
                  hint: q.extraValueVsSortRs > 0
                      ? 'Extra ${formatRs(q.extraValueVsSortRs)} vs sorting by profit'
                      : 'Times quantum order won more money',
                ),
              ],
            ),
            if (q.avgFeasibleRate != null) ...[
              const SizedBox(height: 14),
              Text('Optimisation quality',
                  style: textTheme.bodySmall?.copyWith(color: AppColors.clay)),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (q.avgFeasibleRate ?? 0).clamp(0.0, 1.0),
                  minHeight: 10,
                  backgroundColor: AppColors.clay.withValues(alpha: 0.18),
                  valueColor: const AlwaysStoppedAnimation(AppColors.deepGreen),
                ),
              ),
              if (q.avgWallTimeS != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Average run time ${q.avgWallTimeS!.toStringAsFixed(1)} s',
                    style: textTheme.bodySmall?.copyWith(color: AppColors.clay, fontSize: 12),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QMetric extends StatelessWidget {
  const _QMetric({required this.label, required this.value, required this.hint});

  final String label;
  final String value;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: textTheme.bodySmall?.copyWith(color: AppColors.clay, fontSize: 11)),
            const SizedBox(height: 2),
            Text(value, style: textTheme.titleMedium?.copyWith(color: AppColors.deepGreen)),
            Text(hint, style: textTheme.bodySmall?.copyWith(color: AppColors.clay, fontSize: 10)),
          ],
        ),
      ),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
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
                            child: Text(short,
                                style: textTheme.bodySmall?.copyWith(fontSize: 10, color: AppColors.clay)),
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
            const SizedBox(height: 8),
            Row(
              children: [
                _legendDot(AppColors.deepGreen, 'N'),
                const SizedBox(width: 12),
                _legendDot(AppColors.clay, 'P'),
                const SizedBox(width: 12),
                _legendDot(AppColors.terracotta, 'K'),
                const Spacer(),
                Text('Height = level · colour tint = low/ok',
                    style: textTheme.bodySmall?.copyWith(fontSize: 10, color: AppColors.clay)),
              ],
            ),
          ],
        ),
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
        Container(width: 10, height: 10, color: c),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.clay)),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: textTheme.bodySmall?.copyWith(color: AppColors.clay)),
          const SizedBox(height: 2),
          Text(value, style: textTheme.titleLarge),
        ],
      ),
    );
  }
}

class _FarmRow extends StatelessWidget {
  const _FarmRow({required this.row});

  final DashboardFarmRow row;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => FarmDetailScreen(farmId: row.farmId)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(row.name, style: textTheme.titleMedium)),
                  if (row.totalValueRs != null)
                    Text(formatRs(row.totalValueRs),
                        style: textTheme.bodyMedium?.copyWith(color: AppColors.deepGreen)),
                ],
              ),
              Text('${row.district} · ${row.areaHa.toStringAsFixed(2)} ha',
                  style: textTheme.bodySmall?.copyWith(color: AppColors.clay)),
              if (row.soilSummary != null) ...[
                const SizedBox(height: 6),
                Text(row.soilSummary!, style: textTheme.bodySmall),
              ],
              if (row.sequenceNames.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('Plant: ${row.sequenceNames.join(' → ')}',
                    style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
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
                          color: AppColors.terracotta.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(issue,
                            style: textTheme.bodySmall
                                ?.copyWith(color: AppColors.terracotta, fontSize: 12)),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
