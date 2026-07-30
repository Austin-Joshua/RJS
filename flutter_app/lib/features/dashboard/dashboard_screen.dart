import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/env.dart';
import '../../core/theme.dart';
import '../../data/models/api_models.dart';
import '../../data/repos/field_repo.dart';
import '../../data/repos/plan_repo.dart';
import '../../data/repos/sync_worker.dart';
import '../map/demo_field_assets.dart';
import 'constraints_provider.dart';
import 'farm_scale_provider.dart';
import 'qaoa_chart.dart';
import 'tts_provider.dart';

final citationsProvider = FutureProvider((ref) => DemoFieldAssets.loadCitations());

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _generating = false;
  String? _error;
  PlanOut? _plan;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCached());
  }

  Future<void> _loadCached() async {
    final cached = await ref.read(latestPlanProvider.future);
    if (mounted && cached != null) setState(() => _plan = cached);
  }

  Future<void> _generatePlan() async {
    final field = await ref.read(activeFieldProvider.future);
    if (field == null) {
      setState(() => _error = Env.isApiConfigured
          ? 'No field yet — wait for bootstrap or check API_BASE_URL / auth.'
          : 'Set API_BASE_URL via --dart-define to generate a live plan.');
      return;
    }
    setState(() {
      _generating = true;
      _error = null;
    });
    ref.read(villageRoutingProvider.notifier).set(true);
    try {
      final plan = await ref.read(planRepositoryProvider).generate(
            field: field,
            constraints: ref.read(planConstraintsProvider),
          );
      if (!mounted) return;
      setState(() => _plan = plan);
      await ref.read(syncWorkerProvider).flush();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _generating = false);
        ref.read(villageRoutingProvider.notifier).set(false);
      }
    }
  }

  List<FlSpot> _chartPoints(PlanOut? plan) {
    if (plan == null) return QaoaConvergenceChart.demoPoints;
    final e = plan.benchmark.qaoaEnergy;
    final c = plan.benchmark.classicalOptimum;
    // Visualize approximation path toward classical optimum (not a real iteration log).
    final target = (e ?? c).abs();
    final start = target + 3.2;
    return [
      for (var i = 0; i < 9; i++)
        FlSpot(i.toDouble(), (start - (start - target) * (i / 8)).clamp(0, 8)),
    ];
  }

  String get _advisoryText {
    if (_plan != null) return _plan!.advisory.spokenSummary;
    return demoAdvisoryText;
  }

  @override
  Widget build(BuildContext context) {
    final constraints = ref.watch(planConstraintsProvider);
    final scale = ref.watch(farmScaleProvider);
    final routing = ref.watch(villageRoutingProvider) || _generating;
    final citations = ref.watch(citationsProvider);
    final fieldAsync = ref.watch(activeFieldProvider);
    final textTheme = Theme.of(context).textTheme;
    final plan = _plan;

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Text('Scale', style: textTheme.titleLarge),
            const SizedBox(height: 8),
            SegmentedButton<FarmScale>(
              segments: const [
                ButtonSegment(value: FarmScale.singleFarm, label: Text('Single Farm'), icon: Icon(Icons.agriculture)),
                ButtonSegment(value: FarmScale.villageCoop, label: Text('Village Co-Op'), icon: Icon(Icons.groups)),
              ],
              selected: {scale},
              onSelectionChanged: (next) async {
                final mode = next.first;
                ref.read(farmScaleProvider.notifier).set(mode);
                if (mode == FarmScale.villageCoop) {
                  await _generatePlan();
                }
              },
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith(
                  (s) => s.contains(WidgetState.selected) ? AppColors.deepGreen.withValues(alpha: 0.15) : null,
                ),
              ),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(child: Text('Constraints', style: textTheme.titleLarge)),
                IconButton(
                  tooltip: 'Read advisory aloud',
                  icon: const Icon(Icons.volume_up, color: AppColors.terracotta, size: 32),
                  onPressed: () => ref.read(ttsProvider).speak(_advisoryText),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Water ${constraints.waterPct.round()}%  ·  ${constraints.waterM3.round()} m³', style: textTheme.bodyLarge),
            Slider(
              value: constraints.waterPct,
              min: 0,
              max: 100,
              divisions: 20,
              label: '${constraints.waterPct.round()}%',
              onChanged: (v) => ref.read(planConstraintsProvider.notifier).setWaterPct(v),
            ),
            Text('Budget ₹${constraints.budgetRs.round()}', style: textTheme.bodyLarge),
            Slider(
              value: constraints.budgetRs,
              min: 0,
              max: 100000,
              divisions: 40,
              label: '₹${constraints.budgetRs.round()}',
              onChanged: (v) => ref.read(planConstraintsProvider.notifier).setBudgetRs(v),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _generating ? null : _generatePlan,
                icon: const Icon(Icons.auto_awesome),
                label: Text(_generating ? 'Optimizing…' : 'Generate QAOA plan'),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: textTheme.bodyMedium?.copyWith(color: AppColors.terracotta)),
            ],
            fieldAsync.when(
              data: (f) => f == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('Field: ${f.name} (${f.id.substring(0, 8)}…)', style: textTheme.bodyMedium),
                    ),
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 24),
            QaoaConvergenceChart(points: _chartPoints(plan)),
            if (plan != null) ...[
              const SizedBox(height: 8),
              Text(
                'Solver ${plan.plan.solver} · ${plan.dataMode} · '
                '₹${plan.plan.netValueRs.round()} '
                '(p10 ${plan.plan.netValueP10Rs.round()} / p90 ${plan.plan.netValueP90Rs.round()})',
                style: textTheme.bodyMedium?.copyWith(color: AppColors.clay),
              ),
              if (plan.benchmark.claim.isNotEmpty)
                Text(plan.benchmark.claim, style: textTheme.bodyMedium?.copyWith(fontSize: 12, color: AppColors.clay)),
            ],
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Latest advisory', style: textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(_advisoryText, style: textTheme.bodyMedium),
                    if (plan != null) ...[
                      const SizedBox(height: 12),
                      for (final a in plan.plan.assignments)
                        Text(
                          '${a.crop} on ${a.plotId}: ${a.yieldTHa.toStringAsFixed(2)} t/ha '
                          '(${a.p10.toStringAsFixed(1)}–${a.p90.toStringAsFixed(1)})',
                          style: textTheme.bodyMedium,
                        ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text('Data provenance', style: textTheme.titleLarge),
            const SizedBox(height: 8),
            citations.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(color: AppColors.deepGreen),
              ),
              error: (e, _) => Text('$e'),
              data: (rows) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      for (var i = 0; i < rows.length; i++) ...[
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(rows[i].label, style: textTheme.titleMedium),
                          subtitle: Text(rows[i].citation, style: textTheme.bodyMedium?.copyWith(color: AppColors.clay)),
                        ),
                        if (i < rows.length - 1) const Divider(height: 8),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        if (routing)
          ColoredBox(
            color: AppColors.soilBrown.withValues(alpha: 0.85),
            child: const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppColors.cream),
                    SizedBox(height: 24),
                    Text(
                      'Calculating crop allocations…\nRouting to QAOA Simulator.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.cream, fontSize: 20, fontWeight: FontWeight.w600, height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
