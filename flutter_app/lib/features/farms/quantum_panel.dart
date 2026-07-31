import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models/farm_models.dart';
import 'format.dart';

/// Makes the quantum contribution visible rather than asserted (brief §3):
/// the circuit that ran, the outcomes it measured, and the measured proof that
/// sorting would have given a different — and worse — answer.
class QuantumPanel extends StatelessWidget {
  const QuantumPanel({super.key, required this.result});

  final RankResultOut result;

  @override
  Widget build(BuildContext context) {
    final q = result.quantum;
    if (q == null) return const SizedBox.shrink();
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.memory, size: 20, color: AppColors.deepGreen),
            const SizedBox(width: 8),
            Expanded(child: Text('Quantum optimiser report', style: textTheme.titleMedium)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'How the crop order was searched: ${q.nQubits} quantum bits · ${q.layers} layers · '
          '${(q.feasibleRate * 100).toStringAsFixed(0)}% valid orders · '
          '${q.wallTimeS.toStringAsFixed(1)} s',
          style: textTheme.bodySmall?.copyWith(color: AppColors.clay),
        ),
        const SizedBox(height: 12),
        _OptRateBar(feasibleRate: q.feasibleRate, simplexRate: q.simplexRate),
        const SizedBox(height: 16),
        _WhyNotSort(result: result),
        const SizedBox(height: 20),
        _Measurements(quantum: q),
        const SizedBox(height: 20),
        _CircuitDiagram(quantum: q),
        if (q.convergence.length > 2) ...[
          const SizedBox(height: 20),
          _Convergence(values: q.convergence),
        ],
        const SizedBox(height: 20),
        _Claim(text: q.claim),
      ],
    );
  }
}

class _OptRateBar extends StatelessWidget {
  const _OptRateBar({required this.feasibleRate, required this.simplexRate});

  final double feasibleRate;
  final double simplexRate;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Optimisation rate',
                style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              'Share of quantum samples that are a real planting order (one crop per season).',
              style: textTheme.bodySmall?.copyWith(color: AppColors.clay),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: feasibleRate.clamp(0.0, 1.0),
                minHeight: 12,
                backgroundColor: AppColors.clay.withValues(alpha: 0.18),
                valueColor: const AlwaysStoppedAnimation(AppColors.deepGreen),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${(feasibleRate * 100).toStringAsFixed(0)}% valid · '
              '${(simplexRate * 100).toStringAsFixed(0)}% one-crop-per-season',
              style: textTheme.bodySmall?.copyWith(color: AppColors.deepGreen),
            ),
          ],
        ),
      ),
    );
  }
}

/// The measured answer to "why not just sort the crops by profit?".
class _WhyNotSort extends StatelessWidget {
  const _WhyNotSort({required this.result});

  final RankResultOut result;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final sorted = result.sortedBaseline;
    final greedy = result.greedyBaseline;
    final ranking = result.ranking;
    if (sorted == null || ranking == null) return const SizedBox.shrink();

    final beatsSort = sorted.isSuboptimal;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Why not just sort by profit?', style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            _row(context, 'Quantum order', ranking.sequence, ranking.totalValueRs, best: true),
            _row(context, 'Sorted by profit', sorted.sequence, sorted.valueRs),
            if (greedy != null) _row(context, 'Greedy, one step ahead', greedy.sequence, greedy.valueRs),
            const SizedBox(height: 10),
            Text(
              beatsSort
                  ? 'On this farm, sorting would have cost ${formatRs(sorted.gapRs)} over the year. '
                      'A crop\'s value depends on what came before it, so the best order is not the sorted order.'
                  : 'On this farm the sorted order happens to be optimal too. It is not always — the value of a '
                      'crop depends on what preceded it, which is why the order is searched rather than sorted.',
              style: textTheme.bodySmall?.copyWith(color: AppColors.clay),
            ),
            if (ranking.matchedExactOptimum)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    const Icon(Icons.verified_outlined, size: 15, color: AppColors.deepGreen),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('Matches the exact optimum from exhaustive search.',
                          style: textTheme.bodySmall?.copyWith(color: AppColors.deepGreen)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, List<String> seq, double value, {bool best = false}) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                    color: AppColors.clay, fontWeight: best ? FontWeight.w700 : FontWeight.w400)),
          ),
          Expanded(
            child: Text(seq.map(cropLabel).join(' → '),
                style: textTheme.bodySmall?.copyWith(
                    fontWeight: best ? FontWeight.w700 : FontWeight.w400,
                    color: best ? AppColors.deepGreen : AppColors.soilBrown)),
          ),
          const SizedBox(width: 6),
          Text(formatRs(value),
              style: textTheme.bodySmall?.copyWith(
                  fontWeight: best ? FontWeight.w700 : FontWeight.w400,
                  color: best ? AppColors.deepGreen : AppColors.clay)),
        ],
      ),
    );
  }
}

/// The measured outcome distribution — where the ranking literally comes from.
class _Measurements extends StatelessWidget {
  const _Measurements({required this.quantum});

  final QuantumOut quantum;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final rows = quantum.measurements.take(6).toList();
    if (rows.isEmpty) return const SizedBox.shrink();
    final top = rows.first.probability;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('What the circuit measured', style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(
          'The crop order above is the most frequently measured outcome — read straight off the quantum '
          'distribution, not re-sorted afterwards.',
          style: textTheme.bodySmall?.copyWith(color: AppColors.clay),
        ),
        const SizedBox(height: 12),
        for (final m in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 46,
                  child: Text('${(m.probability * 100).toStringAsFixed(1)}%',
                      style: textTheme.bodySmall?.copyWith(
                          fontWeight: m.rank == 1 ? FontWeight.w700 : FontWeight.w400,
                          color: m.rank == 1 ? AppColors.deepGreen : AppColors.clay)),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: top > 0 ? (m.probability / top).clamp(0.0, 1.0) : 0,
                          minHeight: 7,
                          backgroundColor: AppColors.clay.withValues(alpha: 0.18),
                          valueColor: AlwaysStoppedAnimation(
                              m.rank == 1 ? AppColors.deepGreen : AppColors.clay.withValues(alpha: 0.7)),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        m.sequence.isEmpty ? m.bitstring : m.sequence.map(cropLabel).join(' → '),
                        style: textTheme.bodySmall?.copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 4),
        Text(
          'One crop per season in ${(quantum.simplexRate * 100).toStringAsFixed(0)}% of samples — '
          'guaranteed by the mixer, not by filtering.',
          style: textTheme.bodySmall?.copyWith(color: AppColors.deepGreen, fontSize: 12),
        ),
      ],
    );
  }
}

/// Gate-level view of the circuit that actually ran.
class _CircuitDiagram extends StatelessWidget {
  const _CircuitDiagram({required this.quantum});

  final QuantumOut quantum;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    if (quantum.operations.isEmpty) return const SizedBox.shrink();

    // Group by stage so the diagram reads as: prepare → (cost, mix) × layers.
    final init = quantum.operations.where((o) => o.stage == 'init').length;
    final byLayer = <int, List<CircuitOp>>{};
    for (final op in quantum.operations.where((o) => o.layer != null)) {
      byLayer.putIfAbsent(op.layer!, () => []).add(op);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('The circuit', style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _stage(context, 'Prepare', '$init gates',
                  'One excitation per season block,\nweighted by predicted value', AppColors.terracotta),
              for (final layer in byLayer.keys.toList()..sort())
                _stage(
                  context,
                  'Layer $layer',
                  '${byLayer[layer]!.length} gates',
                  'Cost rotation, then XY-ring\nmixing inside each season',
                  AppColors.deepGreen,
                ),
              _stage(context, 'Measure', '${quantum.nQubits} qubits',
                  '${quantum.measurements.length} distinct\noutcomes recorded', AppColors.clay),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            for (final e in quantum.gateCounts.entries)
              Text('${e.key.replaceAll('_', ' ')}: ${e.value}',
                  style: textTheme.bodySmall?.copyWith(color: AppColors.clay, fontSize: 12)),
          ],
        ),
        if (quantum.invariant.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(quantum.invariant,
              style: textTheme.bodySmall?.copyWith(color: AppColors.clay, fontSize: 12, height: 1.4)),
        ],
      ],
    );
  }

  Widget _stage(BuildContext context, String title, String count, String detail, Color color) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: 150,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: color)),
          Text(count, style: textTheme.bodySmall?.copyWith(color: AppColors.clay, fontSize: 12)),
          const SizedBox(height: 6),
          Text(detail, style: textTheme.bodySmall?.copyWith(fontSize: 11, height: 1.35)),
        ],
      ),
    );
  }
}

class _Convergence extends StatelessWidget {
  const _Convergence({required this.values});

  final List<double> values;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final minY = values.reduce((a, b) => a < b ? a : b);
    final maxY = values.reduce((a, b) => a > b ? a : b);
    final pad = ((maxY - minY).abs() * 0.15).clamp(0.001, double.infinity);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Optimisation trace', style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        Text('${values.length} real evaluations from this run',
            style: textTheme.bodySmall?.copyWith(color: AppColors.clay)),
        const SizedBox(height: 10),
        SizedBox(
          height: 120,
          child: LineChart(
            LineChartData(
              minY: minY - pad,
              maxY: maxY + pad,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: const FlTitlesData(show: false),
              lineTouchData: const LineTouchData(enabled: false),
              lineBarsData: [
                LineChartBarData(
                  spots: [for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i])],
                  isCurved: false,
                  color: AppColors.deepGreen,
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(show: true, color: AppColors.deepGreen.withValues(alpha: 0.12)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Claim extends StatelessWidget {
  const _Claim({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.clay.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.clay.withValues(alpha: 0.35)),
      ),
      child: Text(text,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: AppColors.soilBrown, fontSize: 12, height: 1.5)),
    );
  }
}
