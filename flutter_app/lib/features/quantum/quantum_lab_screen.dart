import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/brand.dart';
import '../../core/theme.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/page_section.dart';
import '../../data/models/farm_models.dart';
import '../../data/repos/farm_repo.dart';
import '../farms/format.dart';
import '../farms/plan_timeline.dart';
import '../farms/quantum_panel.dart';
import 'quantum_lab_providers.dart';

/// What-if crop planner — adjust water/budget and see the plan update live.
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
      final msg = '$e';
      setState(() {
        _error = msg.contains('404') || msg.contains('scenario')
            ? '$msg — if sliders never change the plan, redeploy the backend.'
            : msg;
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
          padding: AppBrand.pagePadding,
          children: [
            const PageHero(
              title: 'Crop planner',
              subtitle:
                  'Pick a farm, drag water or budget, and see which crops still fit — and what you might earn.',
            ),
            const SizedBox(height: 16),
            PageSection(
              step: 1,
              title: 'Choose your farm',
              child: GlassPanel(
                child: DropdownButtonFormField<String>(
                  key: ValueKey(selectedId),
                  isExpanded: true,
                  initialValue: list.any((f) => f.id == selectedId) ? selectedId : list.first.id,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  selectedItemBuilder: (context) => [
                    for (final f in list)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${f.name} · ${f.areaHa.toStringAsFixed(1)} ha',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodyMedium,
                        ),
                      ),
                  ],
                  items: [
                    for (final f in list)
                      DropdownMenuItem(
                        value: f.id,
                        child: Text(
                          '${f.name} · ${f.areaHa.toStringAsFixed(1)} ha',
                          maxLines: 1,
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
              ),
            ),
            const SizedBox(height: 20),
            PageSection(
              step: 2,
              title: 'Set your limits',
              subtitle: 'Less water removes thirsty crops like paddy. Less budget removes expensive ones.',
              child: GlassPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    WaterSliderCard(
                      valueM3: _waterM3,
                      min: 0,
                      max: _waterMaxM3,
                      embedded: true,
                      title: 'Water available',
                      subtitle:
                          '${_waterPct.round()}% of season supply · stored ${_baselineWaterM3.round()} m³',
                      onChanged: (v) {
                        setState(() {
                          _waterPct =
                              (_waterMaxM3 <= 0 ? 100.0 : (v / _waterMaxM3) * 100).clamp(5.0, 100.0).toDouble();
                        });
                        _scheduleRank();
                      },
                    ),
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 16),
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
                      const SizedBox(height: 14),
                      const LinearProgressIndicator(color: AppColors.deepGreen),
                      const SizedBox(height: 6),
                      Text(
                        'Updating your plan…',
                        style: textTheme.bodySmall?.copyWith(color: AppColors.deepGreen),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              GlassPanel(
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: AppColors.terracotta, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(_error!, style: textTheme.bodySmall?.copyWith(color: AppColors.terracotta)),
                    ),
                  ],
                ),
              ),
            ],
            if (_result != null) ...[
              const SizedBox(height: 24),
              PageSection(
                step: 3,
                title: 'What changed',
                subtitle: 'Compared to when you opened this screen, or after you tap Reset baseline.',
                child: Column(
                  children: [
                    _ScenarioBar(result: _result!, waterM3: _waterM3, budgetRs: _budgetRs),
                    const SizedBox(height: 10),
                    _ShiftBanner(baseline: _baselineResult, current: _result!),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _result == null ? null : () => setState(() => _baselineResult = _result),
                        child: const Text('Reset baseline'),
                      ),
                    ),
                  ],
                ),
              ),
              if (_result!.ranking != null) ...[
                const SizedBox(height: 20),
                PageSection(
                  step: 4,
                  title: 'Your crop order',
                  subtitle: 'Season by season — tap a bar in the chart for details.',
                  child: PlanTimeline(
                    key: ValueKey(
                      '${_result!.ranking!.sequence.join('-')}-'
                      '${_result!.feasibility.rotationCandidates.join('-')}',
                    ),
                    ranking: _result!.ranking!,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              PageSection(
                step: 5,
                title: 'Which crops qualify',
                subtitle: 'Green = passes soil and water checks at these slider settings.',
                child: Column(
                  children: [
                    _FeasibleStrip(result: _result!),
                    if (_result!.pipeline?.excludedCrops.isNotEmpty == true) ...[
                      const SizedBox(height: 10),
                      _ExcludedReasons(excluded: _result!.pipeline!.excludedCrops),
                    ],
                  ],
                ),
              ),
              if (_result!.error != null) ...[
                const SizedBox(height: 12),
                Text(_result!.error!, style: textTheme.bodyMedium?.copyWith(color: AppColors.terracotta)),
              ],
              if (_result!.ranking != null) ...[
                const SizedBox(height: 20),
                PageSection(
                  step: 6,
                  title: 'Expected earnings',
                  subtitle: 'How this plan compares to simpler sorting — includes rotation bonuses.',
                  child: _ComparisonBoard(result: _result!, baseline: _baselineResult),
                ),
                if (_result!.quantum != null) ...[
                  const SizedBox(height: 16),
                  GlassPanel(
                    padding: EdgeInsets.zero,
                    child: Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        leading: const Icon(Icons.memory, color: AppColors.deepGreen),
                        title: Text('Technical details', style: textTheme.titleMedium),
                        subtitle: Text(
                          'Quantum circuit stats — for advanced users',
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

class _ScenarioBar extends StatelessWidget {
  const _ScenarioBar({required this.result, required this.waterM3, required this.budgetRs});

  final RankResultOut result;
  final double waterM3;
  final double budgetRs;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scenario = result.scenario;
    final band = result.pipeline?.waterCategory ?? '—';
    final water = scenario?.waterAvailableM3 ?? waterM3;
    return GlassPanel(
      child: Row(
        children: [
          const Icon(Icons.tune, size: 18, color: AppColors.deepGreen),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Right now: ${water.round()} m³ water ($band) · ${formatRs(scenario?.budgetRs ?? budgetRs)} budget',
              style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExcludedReasons extends StatelessWidget {
  const _ExcludedReasons({required this.excluded});

  final List<ExcludedCropOut> excluded;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Why some crops were removed', style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          for (final e in excluded.take(4))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${cropLabel(e.crop)}: ${e.reason}',
                style: textTheme.bodySmall?.copyWith(color: AppColors.terracotta),
              ),
            ),
        ],
      ),
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

    final valueDelta = (baseline?.ranking != null && current.ranking != null)
        ? current.ranking!.totalValueRs - baseline!.ranking!.totalValueRs
        : null;

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
                Text('Plan update', style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(headline, style: textTheme.bodySmall),
                if (valueDelta != null && valueDelta.abs() > 1) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Plan value ${valueDelta >= 0 ? '+' : ''}${formatRs(valueDelta)} vs baseline',
                    style: textTheme.bodySmall?.copyWith(
                      color: valueDelta >= 0 ? AppColors.deepGreen : AppColors.terracotta,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
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
  const _FeasibleStrip({required this.result});

  final RankResultOut result;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final feasibility = result.feasibility;
    final ok = result.pipeline?.rotationCandidates ?? feasibility.rotationCandidates;
    final out = result.pipeline?.excludedCrops.map((e) => e.crop).toList() ??
        feasibility.excluded.map((v) => v.crop).toList();

    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Crops that qualify', style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            'Strikethrough = ruled out at this water or budget level.',
            style: textTheme.bodySmall?.copyWith(color: AppColors.clay, fontSize: 11),
          ),
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

/// Quantum vs classical strategies — bars, ₹ gaps, rotation economics.
class _ComparisonBoard extends StatelessWidget {
  const _ComparisonBoard({required this.result, this.baseline});

  final RankResultOut result;
  final RankResultOut? baseline;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final ranking = result.ranking;
    final sorted = result.sortedBaseline;
    final greedy = result.greedyBaseline;
    final standalone = result.standaloneBaseline;
    if (ranking == null) return const SizedBox.shrink();

    final quantumRs = ranking.totalValueRs;

    final methods = <_CompareRow>[
      _CompareRow(
        label: 'Recommended plan',
        sublabel: ranking.sequence.map(cropLabel).join(' → '),
        valueRs: quantumRs,
        color: AppColors.deepGreen,
        isBest: true,
      ),
      if (sorted != null && sorted.sequence.isNotEmpty)
        _CompareRow(
          label: 'Sort by profit',
          sublabel: sorted.sequence.map(cropLabel).join(' → '),
          valueRs: sorted.valueRs,
          color: AppColors.clay,
          gapRs: quantumRs - sorted.valueRs,
        ),
      if (greedy != null && greedy.sequence.isNotEmpty)
        _CompareRow(
          label: 'Greedy look-ahead',
          sublabel: greedy.sequence.map(cropLabel).join(' → '),
          valueRs: greedy.valueRs,
          color: AppColors.terracotta,
          gapRs: quantumRs - greedy.valueRs,
        ),
      if (standalone != null)
        _CompareRow(
          label: 'Solo profit total',
          sublabel: 'Adds each crop alone — no rotation order',
          valueRs: standalone.valueRs,
          color: AppColors.soilBrown,
          gapRs: quantumRs - standalone.valueRs,
        ),
    ];
    final maxRs = methods.map((m) => m.valueRs).fold<double>(0, (a, b) => a > b ? a : b);
    final allSameOrder = methods
        .where((m) => m.sublabel.contains('→'))
        .map((m) => m.sublabel)
        .toSet()
        .length <=
        1;

    final baselineRs = baseline?.ranking?.totalValueRs;
    final scenarioDelta = baselineRs != null ? quantumRs - baselineRs : null;

    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Compare strategies', style: textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Each row is a different way to pick crops. The ₹ gap shows what rotation order is worth.',
            style: textTheme.bodySmall?.copyWith(color: AppColors.clay),
          ),
          if (allSameOrder && methods.length > 1) ...[
            const SizedBox(height: 8),
            Text(
              'Sort and greedy picked the same order here — compare the solo total to see rotation value.',
              style: textTheme.bodySmall?.copyWith(color: AppColors.clay, fontStyle: FontStyle.italic),
            ),
          ],
          if (scenarioDelta != null && scenarioDelta.abs() > 1) ...[
            const SizedBox(height: 10),
            _DeltaChip(
              label: 'vs slider baseline',
              deltaRs: scenarioDelta,
              before: baselineRs!,
              after: quantumRs,
            ),
          ],
          const SizedBox(height: 14),
          for (final m in methods) ...[
            _CompareBar(row: m, maxRs: maxRs),
            const SizedBox(height: 10),
          ],
          if (ranking.rankedCrops.isNotEmpty) ...[
            const Divider(height: 1),
            const SizedBox(height: 10),
            Text('Per-season detail', style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            for (final row in ranking.rankedCrops)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _SeasonEconomicsRow(crop: row),
              ),
          ],
          if (result.quantum != null && result.quantum!.measurements.length > 1) ...[
            const SizedBox(height: 8),
            Text('Other sampled plans', style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            for (final m in result.quantum!.measurements.skip(1).take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${m.sequence.map(cropLabel).join(' → ')} · ${formatRs(m.valueRs)} · ${(m.probability * 100).toStringAsFixed(0)}%',
                  style: textTheme.bodySmall?.copyWith(color: AppColors.clay),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _CompareRow {
  const _CompareRow({
    required this.label,
    required this.sublabel,
    required this.valueRs,
    required this.color,
    this.gapRs,
    this.isBest = false,
  });

  final String label;
  final String sublabel;
  final double valueRs;
  final Color color;
  final double? gapRs;
  final bool isBest;
}

class _CompareBar extends StatelessWidget {
  const _CompareBar({required this.row, required this.maxRs});

  final _CompareRow row;
  final double maxRs;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final frac = maxRs <= 0 ? 0.0 : (row.valueRs / maxRs).clamp(0.0, 1.0);
    final gap = row.gapRs ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                row.label,
                style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: row.color),
              ),
            ),
            Text(
              formatRs(row.valueRs),
              style: textTheme.titleSmall?.copyWith(color: row.color, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          row.sublabel,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: textTheme.bodySmall?.copyWith(color: AppColors.clay),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: frac,
            minHeight: 10,
            backgroundColor: row.color.withValues(alpha: 0.12),
            color: row.color,
          ),
        ),
        if (gap.abs() > 1 && !row.isBest)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              gap > 0
                  ? 'Recommended plan earns ${formatRs(gap)} more'
                  : 'This path earns ${formatRs(-gap)} more (unusual)',
              style: textTheme.bodySmall?.copyWith(
                color: gap > 0 ? AppColors.deepGreen : AppColors.terracotta,
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        else if (row.isBest)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Best rotation order for your soil',
              style: textTheme.bodySmall?.copyWith(color: AppColors.deepGreen),
            ),
          )
        else if (gap.abs() <= 1 && row.sublabel.contains('→'))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Same ₹ as recommended — different order may still matter at other water levels',
              style: textTheme.bodySmall?.copyWith(color: AppColors.clay, fontSize: 11),
            ),
          ),
      ],
    );
  }
}

class _DeltaChip extends StatelessWidget {
  const _DeltaChip({
    required this.label,
    required this.deltaRs,
    required this.before,
    required this.after,
    this.compact = false,
  });

  final String label;
  final double deltaRs;
  final double before;
  final double after;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final up = deltaRs >= 0;
    final pct = before.abs() > 1 ? (deltaRs / before.abs() * 100) : 0.0;
    final color = up ? AppColors.deepGreen : AppColors.terracotta;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12, vertical: compact ? 8 : 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(up ? Icons.trending_up : Icons.trending_down, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                Text(
                  '${up ? '+' : ''}${formatRs(deltaRs)} (${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(1)}%)',
                  style: textTheme.bodyMedium?.copyWith(color: color, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          if (!compact)
            Text(
              '${formatRs(before)} → ${formatRs(after)}',
              style: textTheme.bodySmall?.copyWith(color: AppColors.clay),
            ),
        ],
      ),
    );
  }
}

class _SeasonEconomicsRow extends StatelessWidget {
  const _SeasonEconomicsRow({required this.crop});

  final RankedCropOut crop;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final diff = crop.realisedValueRs - crop.standaloneValueRs;
    final hasEffect = crop.rotationMultiplier != 1.0 || crop.nCreditRs.abs() > 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.clay.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${seasonLabel(crop.season)} · ${cropLabel(crop.crop)}',
                  style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Text(formatRs(crop.realisedValueRs), style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          if (hasEffect)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Solo ${formatRs(crop.standaloneValueRs)}'
                '${diff.abs() > 1 ? ' · ${diff >= 0 ? '+' : ''}${formatRs(diff)} rotation' : ''}'
                '${crop.nCreditRs.abs() > 1 ? ' · N ${formatRs(crop.nCreditRs)}' : ''}',
                style: textTheme.bodySmall?.copyWith(color: AppColors.clay, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}
