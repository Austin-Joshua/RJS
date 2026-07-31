import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/widgets/glass.dart';
import '../../data/models/farm_models.dart';
import '../../data/repos/farm_repo.dart';
import '../farms/format.dart';
import '../farms/plan_timeline.dart';
import '../farms/quantum_panel.dart';
import 'quantum_lab_providers.dart';

/// Separate page: survival sliders + live QAOA re-rank + quantum vs classical comparisons.
class QuantumLabScreen extends ConsumerStatefulWidget {
  const QuantumLabScreen({super.key});

  @override
  ConsumerState<QuantumLabScreen> createState() => _QuantumLabScreenState();
}

class _QuantumLabScreenState extends ConsumerState<QuantumLabScreen> {
  String? _farmId;
  double _waterPct = 100;
  double _budgetPct = 100;
  double _waterMaxM3 = 12000;
  double _budgetMaxRs = 80000;
  double _baselineWaterM3 = 12000;

  RankResultOut? _result;
  RankResultOut? _baselineResult;
  bool _running = false;
  String? _error;
  Timer? _debounce;
  int _runToken = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _selectFarm(String farmId, {bool force = false}) async {
    if (!force && _farmId == farmId) return;
    setState(() {
      _farmId = farmId;
      _result = null;
      _baselineResult = null;
      _error = null;
      _waterPct = 100;
      _budgetPct = 100;
    });

    final repo = ref.read(farmRepositoryProvider);
    final farm = await repo.get(farmId);
    final card = await repo.soilCard(farmId);
    final stored = (card.water['available_m3'] as num?)?.toDouble();
    final area = farm.areaHa;
    final waterMax = [
      stored ?? 0,
      area * 8000,
      4000.0,
    ].reduce((a, b) => a > b ? a : b);
    final budgetMax = (area * 100000).clamp(20000.0, 500000.0);

    if (!mounted) return;
    setState(() {
      _waterMaxM3 = waterMax;
      _baselineWaterM3 = stored ?? waterMax;
      _budgetMaxRs = budgetMax;
      // Start at full supply so the jury sees paddy in, then drag down.
      _waterPct = 100;
      _budgetPct = 100;
    });

    await _rank(asBaseline: true);
  }

  double get _waterM3 => (_waterMaxM3 * _waterPct / 100).clamp(0, _waterMaxM3);
  double get _budgetRs => (_budgetMaxRs * _budgetPct / 100).clamp(0, _budgetMaxRs);

  void _scheduleRank() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 650), () => _rank());
  }

  Future<void> _rank({bool asBaseline = false}) async {
    final farmId = _farmId;
    if (farmId == null) return;
    final token = ++_runToken;
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final result = await ref.read(farmRepositoryProvider).rank(
            farmId,
            waterAvailableM3: _waterM3,
            budgetRs: _budgetRs,
            persist: false,
          );
      if (!mounted || token != _runToken) return;
      setState(() {
        _result = result;
        if (asBaseline) _baselineResult = result;
        _running = false;
      });
    } catch (e) {
      if (!mounted || token != _runToken) return;
      setState(() {
        _error = '$e';
        _running = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final farms = ref.watch(farmsProvider);
    final preselect = ref.watch(quantumLabFarmIdProvider);
    final textTheme = Theme.of(context).textTheme;

    ref.listen<String?>(quantumLabFarmIdProvider, (prev, next) {
      if (next != null && next != _farmId) {
        _selectFarm(next, force: true);
      }
    });

    return farms.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.deepGreen)),
      error: (e, _) => Center(child: Text('$e')),
      data: (list) {
        if (list.isEmpty) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(28, 80, 28, 40),
            children: [
              const Icon(Icons.memory, size: 48, color: AppColors.clay),
              const SizedBox(height: 12),
              Text('Add a farm first', textAlign: TextAlign.center, style: textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                'Quantum Lab needs a farm so the water and budget sliders can re-rank a real plan.',
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(color: AppColors.clay),
              ),
            ],
          );
        }

        final selectedId = _farmId ?? preselect ?? list.first.id;
        if (_farmId == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_farmId == null) _selectFarm(selectedId);
          });
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          children: [
            Text('Quantum Lab', style: textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Mazhai varalana? Uram vela eriducha? Move the sliders — QAOA re-plans instantly.',
              style: textTheme.bodyMedium?.copyWith(color: AppColors.clay),
            ),
            const SizedBox(height: 14),
            GlassPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Farm', style: textTheme.bodySmall?.copyWith(color: AppColors.clay)),
                  DropdownButtonFormField<String>(
                    key: ValueKey(selectedId),
                    initialValue: list.any((f) => f.id == selectedId) ? selectedId : list.first.id,
                    decoration: const InputDecoration(border: InputBorder.none, isDense: true),
                    items: [
                      for (final f in list)
                        DropdownMenuItem(
                          value: f.id,
                          child: Text(
                            '${f.name} · ${f.areaHa.toStringAsFixed(1)} ha',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (id) {
                      if (id == null) return;
                      ref.read(quantumLabFarmIdProvider.notifier).select(id);
                      _selectFarm(id, force: true);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            GlassPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Survival controls', style: textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Cut water from 100% → 40% and watch paddy leave the plan for drought-tough pulses.',
                    style: textTheme.bodySmall?.copyWith(color: AppColors.clay),
                  ),
                  const SizedBox(height: 12),
                  WaterSliderCard(
                    valueM3: _waterM3,
                    min: 0,
                    max: _waterMaxM3,
                    embedded: true,
                    title: 'Available water',
                    subtitle: '${_waterPct.round()}% of season supply · baseline ${_baselineWaterM3.round()} m³',
                    onChanged: (v) {
                      setState(() {
                        _waterPct =
                            (_waterMaxM3 <= 0 ? 100.0 : (v / _waterMaxM3) * 100).clamp(5.0, 100.0).toDouble();
                      });
                      _scheduleRank();
                    },
                  ),
                  const SizedBox(height: 12),
                  _BudgetSliderCard(
                    valueRs: _budgetRs,
                    maxRs: _budgetMaxRs,
                    pct: _budgetPct,
                    onChanged: (v) {
                      setState(() {
                        _budgetPct =
                            (_budgetMaxRs <= 0 ? 100.0 : (v / _budgetMaxRs) * 100).clamp(5.0, 100.0).toDouble();
                      });
                      _scheduleRank();
                    },
                  ),
                  if (_running) ...[
                    const SizedBox(height: 10),
                    const LinearProgressIndicator(color: AppColors.deepGreen),
                    const SizedBox(height: 4),
                    Text('Re-running quantum optimiser…',
                        style: textTheme.bodySmall?.copyWith(color: AppColors.deepGreen)),
                  ],
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: textTheme.bodyMedium?.copyWith(color: AppColors.terracotta)),
            ],
            if (_result != null) ...[
              const SizedBox(height: 16),
              _ShiftBanner(baseline: _baselineResult, current: _result!),
              const SizedBox(height: 12),
              _FeasibleStrip(feasibility: _result!.feasibility),
              if (_result!.error != null) ...[
                const SizedBox(height: 12),
                Text(_result!.error!, style: textTheme.bodyMedium?.copyWith(color: AppColors.terracotta)),
              ],
              if (_result!.ranking != null) ...[
                const SizedBox(height: 16),
                PlanTimeline(ranking: _result!.ranking!),
                const SizedBox(height: 16),
                _ComparisonBoard(result: _result!),
                if (_result!.quantum != null) ...[
                  const SizedBox(height: 12),
                  GlassPanel(
                    padding: EdgeInsets.zero,
                    child: Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        leading: const Icon(Icons.memory, color: AppColors.deepGreen),
                        title: Text('Quantum circuit details', style: textTheme.titleMedium),
                        subtitle: Text(
                          'Rates, measurements, circuit — tap to expand',
                          style: textTheme.bodySmall?.copyWith(color: AppColors.clay),
                        ),
                        children: [QuantumPanel(result: _result!)],
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ],
        );
      },
    );
  }
}

class _BudgetSliderCard extends StatelessWidget {
  const _BudgetSliderCard({
    required this.valueRs,
    required this.maxRs,
    required this.pct,
    required this.onChanged,
  });

  final double valueRs;
  final double maxRs;
  final double pct;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final fill = Color.lerp(AppColors.terracotta, AppColors.deepGreen, (pct / 100).clamp(0.0, 1.0))!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.account_balance_wallet_outlined, color: fill),
            const SizedBox(width: 8),
            Expanded(
              child: Text('My budget',
                  style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Cash for seed, fertiliser and labour this season. Lower it and expensive crops drop out.',
          style: textTheme.bodySmall?.copyWith(color: AppColors.clay),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                formatRs(valueRs),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.displayMedium?.copyWith(color: fill, fontSize: 28),
              ),
            ),
            const SizedBox(width: 8),
            Text('${pct.round()}%',
                style: textTheme.bodySmall?.copyWith(color: fill, fontWeight: FontWeight.w600)),
          ],
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
            value: valueRs.clamp(0, maxRs),
            min: 0,
            max: maxRs <= 0 ? 1 : maxRs,
            divisions: 40,
            label: formatRs(valueRs),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _ShiftBanner extends StatelessWidget {
  const _ShiftBanner({required this.baseline, required this.current});

  final RankResultOut? baseline;
  final RankResultOut current;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final before = baseline?.ranking?.sequence ?? const <String>[];
    final after = current.ranking?.sequence ?? const <String>[];
    final beforeSet = before.toSet();
    final afterSet = after.toSet();
    final dropped = beforeSet.difference(afterSet);
    final added = afterSet.difference(beforeSet);
    final heavyOut = dropped.contains('paddy') || dropped.contains('sugarcane') || dropped.contains('maize');
    final droughtIn = added.contains('black_gram') || added.contains('groundnut');

    String headline;
    if (before.isEmpty && after.isNotEmpty) {
      headline = 'Plan locked in: ${after.map(cropLabel).join(' → ')}';
    } else if (before.isNotEmpty && after.isEmpty) {
      headline = 'No crop clears these water/budget gates — raise a slider.';
    } else if (before.join() == after.join()) {
      headline = 'Same order under this scenario: ${after.map(cropLabel).join(' → ')}';
    } else if (heavyOut && droughtIn) {
      headline =
          'Water/budget cut shifted the plan — heavy crop out, drought-tough ${added.map(cropLabel).join(', ')} in.';
    } else {
      headline = '${before.map(cropLabel).join(' → ')}  →  ${after.map(cropLabel).join(' → ')}';
    }

    return GlassPanel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            heavyOut ? Icons.trending_down : Icons.auto_awesome,
            color: heavyOut ? AppColors.terracotta : AppColors.deepGreen,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Live re-plan', style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(headline, style: textTheme.bodySmall),
                if (current.quantum != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'QAOA · ${current.quantum!.nQubits} qubits · '
                    '${(current.quantum!.feasibleRate * 100).toStringAsFixed(0)}% valid · '
                    '${current.quantum!.wallTimeS.toStringAsFixed(1)}s',
                    style: textTheme.bodySmall?.copyWith(color: AppColors.deepGreen),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeasibleStrip extends StatelessWidget {
  const _FeasibleStrip({required this.feasibility});

  final FeasibilityOut feasibility;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final ok = feasibility.feasible.map((v) => v.crop).toList();
    final out = feasibility.excluded.map((v) => v.crop).toList();

    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Gates under this scenario', style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in ok)
                Chip(
                  label: Text(cropLabel(c)),
                  backgroundColor: AppColors.deepGreen.withValues(alpha: 0.12),
                  side: BorderSide(color: AppColors.deepGreen.withValues(alpha: 0.4)),
                  visualDensity: VisualDensity.compact,
                ),
              for (final c in out)
                Chip(
                  label: Text(cropLabel(c), style: const TextStyle(decoration: TextDecoration.lineThrough)),
                  backgroundColor: AppColors.terracotta.withValues(alpha: 0.1),
                  side: BorderSide(color: AppColors.terracotta.withValues(alpha: 0.35)),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Side-by-side quantum vs sort vs greedy — the jury comparison board.
class _ComparisonBoard extends StatelessWidget {
  const _ComparisonBoard({required this.result});

  final RankResultOut result;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final ranking = result.ranking;
    final sorted = result.sortedBaseline;
    final greedy = result.greedyBaseline;
    if (ranking == null) return const SizedBox.shrink();

    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Comparisons', style: textTheme.titleMedium),
          const SizedBox(height: 2),
          Text(
            'Same farm, same constraints — three search strategies. Quantum wins when order matters.',
            style: textTheme.bodySmall?.copyWith(color: AppColors.clay),
          ),
          const SizedBox(height: 14),
          _MethodCard(
            title: 'Quantum (QAOA / SPARQ)',
            sequence: ranking.sequence,
            valueRs: ranking.totalValueRs,
            accent: AppColors.deepGreen,
            badge: ranking.matchedExactOptimum ? 'Exact optimum' : 'Best sampled',
          ),
          const SizedBox(height: 8),
          if (sorted != null)
            _MethodCard(
              title: 'Sort by profit',
              sequence: sorted.sequence,
              valueRs: sorted.valueRs,
              accent: AppColors.clay,
              badge: sorted.isSuboptimal ? '−${formatRs(sorted.gapRs)}' : 'Tied',
            ),
          if (greedy != null) ...[
            const SizedBox(height: 8),
            _MethodCard(
              title: 'Greedy (one step ahead)',
              sequence: greedy.sequence,
              valueRs: greedy.valueRs,
              accent: AppColors.terracotta,
              badge: greedy.isSuboptimal ? '−${formatRs(greedy.gapRs)}' : 'Tied',
            ),
          ],
        ],
      ),
    );
  }
}

class _MethodCard extends StatelessWidget {
  const _MethodCard({
    required this.title,
    required this.sequence,
    required this.valueRs,
    required this.accent,
    required this.badge,
  });

  final String title;
  final List<String> sequence;
  final double valueRs;
  final Color accent;
  final String badge;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
        color: accent.withValues(alpha: 0.06),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: accent),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  badge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: textTheme.bodySmall?.copyWith(color: accent, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(sequence.map(cropLabel).join(' → '), style: textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
            formatRs(valueRs),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.titleMedium?.copyWith(color: accent),
          ),
        ],
      ),
    );
  }
}
