import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/widgets/glass.dart';
import '../../data/models/farm_models.dart';
import '../../data/repos/farm_repo.dart';
import '../quantum/quantum_lab_providers.dart';
import 'format.dart';
import 'land_charts.dart';
import 'ndvi_panel.dart';
import 'plan_timeline.dart';
import 'soil_card_view.dart';

/// One farm, end to end (brief §2.3 → §2.6). Everything on this screen is
/// computed from this farm's own soil card; nothing is shared with any other
/// farm on the account.
class FarmDetailScreen extends ConsumerStatefulWidget {
  const FarmDetailScreen({super.key, required this.farmId});

  final String farmId;

  @override
  ConsumerState<FarmDetailScreen> createState() => _FarmDetailScreenState();
}

class _FarmDetailScreenState extends ConsumerState<FarmDetailScreen> {
  RankResultOut? _result;
  bool _ranking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadExisting());
  }

  Future<void> _loadExisting() async {
    final saved = await ref.read(latestRankingProvider(widget.farmId).future);
    if (mounted && saved != null) setState(() => _result = saved);
  }

  Future<void> _rank() async {
    setState(() {
      _ranking = true;
      _error = null;
    });
    try {
      final result = await ref.read(farmRepositoryProvider).rank(widget.farmId);
      if (!mounted) return;
      setState(() => _result = result);
      ref.invalidate(farmsProvider);
      ref.invalidate(dashboardProvider);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _ranking = false);
    }
  }

  Future<void> _delete(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $name?'),
        content: const Text('Its soil cards and crop rankings will be removed too. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.terracotta)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(farmRepositoryProvider).delete(widget.farmId);
    ref.invalidate(farmsProvider);
    ref.invalidate(dashboardProvider);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final farmAsync = ref.watch(farmProvider(widget.farmId));
    final textTheme = Theme.of(context).textTheme;

    return AtmosphereBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(farmAsync.value?.name ?? 'Farm'),
          actions: [
            if (farmAsync.value != null)
              IconButton(
                tooltip: 'Delete farm',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _delete(farmAsync.value!.name),
              ),
          ],
        ),
        body: farmAsync.when(
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.deepGreen)),
          error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('$e'))),
          data: (farm) => RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(farmProvider(widget.farmId));
              ref.invalidate(soilCardProvider(widget.farmId));
              ref.invalidate(feasibleCropsProvider(widget.farmId));
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              children: [
                Text('${farm.district}, ${farm.state} · ${farm.areaHa.toStringAsFixed(2)} ha',
                    style: textTheme.bodyMedium?.copyWith(color: AppColors.clay)),
                const SizedBox(height: 16),

                _SectionHeader(
                  icon: Icons.science_outlined,
                  title: 'Soil card',
                  trailing: TextButton(
                    onPressed: () => _showSoilCard(farm),
                    child: const Text('View full card'),
                  ),
                ),
                ref.watch(soilCardProvider(widget.farmId)).when(
                      loading: () => const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
                      error: (e, _) => Text('Could not load soil card: $e',
                          style: textTheme.bodySmall?.copyWith(color: AppColors.terracotta)),
                      data: (card) => Column(
                        children: [
                          GlassPanel(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('In plain words: ${card.summary}', style: textTheme.bodyMedium),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    for (final e in card.classes.entries)
                                      NutrientChip(label: nutrientLabel(e.key), rating: e.value),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          LandVariableChart(card: card),
                          if (card.water['available_m3'] != null) ...[
                            const SizedBox(height: 12),
                            WaterSliderCard(
                              valueM3: (card.water['available_m3'] as num).toDouble(),
                              readOnly: true,
                              title: 'Water available on this farm',
                              subtitle: card.water['note'] as String? ??
                                  'From your soil card — open Quantum Lab to ask “mazhai varalana?”.',
                              onChanged: (_) {},
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: () {
                                ref.read(quantumLabFarmIdProvider.notifier).select(widget.farmId);
                                ref.read(homeTabIndexProvider.notifier).go(2);
                                Navigator.of(context).popUntil((r) => r.isFirst);
                              },
                              icon: const Icon(Icons.memory_outlined),
                              label: const Text('What if water / budget drops? → Quantum Lab'),
                            ),
                          ],
                        ],
                      ),
                    ),
                const SizedBox(height: 24),

                const _SectionHeader(icon: Icons.satellite_alt_outlined, title: 'How green is the crop now'),
                const SizedBox(height: 8),
                NdviPanel(farmId: widget.farmId),
                const SizedBox(height: 24),

                const _SectionHeader(icon: Icons.filter_alt_outlined, title: 'Which crops can grow here'),
                ref.watch(feasibleCropsProvider(widget.farmId)).when(
                      loading: () => const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
                      error: (e, _) => Text('$e', style: textTheme.bodySmall?.copyWith(color: AppColors.terracotta)),
                      data: (f) => _FeasibilityList(feasibility: f),
                    ),
                const SizedBox(height: 24),

                const _SectionHeader(icon: Icons.auto_awesome, title: 'Best crop order for the year'),
                const SizedBox(height: 4),
                Text(
                  'A quantum optimiser orders crops across the three seasons. '
                  'What you plant first changes what the next crop earns.',
                  style: textTheme.bodySmall?.copyWith(color: AppColors.clay),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _ranking ? null : _rank,
                    icon: _ranking
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.auto_awesome),
                    label: Text(_ranking
                        ? 'Running quantum optimiser…'
                        : _result == null
                            ? 'Rank my crops'
                            : 'Run again'),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: textTheme.bodyMedium?.copyWith(color: AppColors.terracotta)),
                ],
                if (_result?.error != null) ...[
                  const SizedBox(height: 10),
                  Text(_result!.error!, style: textTheme.bodyMedium?.copyWith(color: AppColors.terracotta)),
                ],
                if (_result?.note != null) ...[
                  const SizedBox(height: 12),
                  GlassPanel(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline, size: 18, color: AppColors.clay),
                        const SizedBox(width: 10),
                        Expanded(child: Text(_result!.note!, style: textTheme.bodySmall)),
                      ],
                    ),
                  ),
                ],
                if (_result?.ranking != null) ...[
                  const SizedBox(height: 16),
                  PlanTimeline(ranking: _result!.ranking!),
                  const SizedBox(height: 16),
                  if (_result!.ranking!.cropRanking.isNotEmpty) ...[
                    _CropRankingCard(ranking: _result!.ranking!),
                    const SizedBox(height: 16),
                  ],
                  _RankedList(ranking: _result!.ranking!),
                  const SizedBox(height: 24),
                  if (_result!.advisory != null) ...[
                    const _SectionHeader(icon: Icons.healing_outlined, title: 'What your soil needs'),
                    _AdvisoryCard(advisory: _result!.advisory!),
                    const SizedBox(height: 24),
                  ],
                  OutlinedButton.icon(
                    onPressed: () {
                      ref.read(quantumLabFarmIdProvider.notifier).select(widget.farmId);
                      ref.read(homeTabIndexProvider.notifier).go(2);
                      Navigator.of(context).popUntil((r) => r.isFirst);
                    },
                    icon: const Icon(Icons.compare_arrows),
                    label: const Text('Quantum comparisons & survival sliders'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSoilCard(FarmOut farm) {
    final card = ref.read(soilCardProvider(widget.farmId)).value;
    if (card == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cream,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        builder: (_, controller) =>
            SoilCardView(card: card, farmName: farm.name, scrollController: controller),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title, this.trailing});

  final IconData icon;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.deepGreen),
        const SizedBox(width: 8),
        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
        ?trailing,
      ],
    );
  }
}

class _FeasibilityList extends StatelessWidget {
  const _FeasibilityList({required this.feasibility});

  final FeasibilityOut feasibility;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final c in feasibility.feasible) _row(context, c, true),
          if (feasibility.excluded.isNotEmpty) ...[
            const Divider(height: 20),
            Text('Not suitable for this farm',
                style: textTheme.bodySmall?.copyWith(color: AppColors.clay, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            for (final c in feasibility.excluded) _row(context, c, false),
          ],
        ],
      ),
    );
  }

  Widget _row(BuildContext context, CropVerdictOut c, bool ok) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ok ? Icons.check_circle : Icons.cancel_outlined,
              size: 18, color: ok ? AppColors.deepGreen : AppColors.terracotta),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.nameEn, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                // The first reason is always the deciding one — why it failed
                // for an excluded crop, what it cleared for a feasible one.
                if (c.reasons.isNotEmpty)
                  Text(c.reasons.first, style: textTheme.bodySmall?.copyWith(color: AppColors.clay)),
                for (final w in c.warnings)
                  Text('⚠ $w', style: textTheme.bodySmall?.copyWith(color: AppColors.terracotta)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Which crop is best for my land?" — feasible crops by profitability, best
/// first. Distinct from the planting order below it: a crop can be the most
/// profitable overall and still not belong in season one.
class _CropRankingCard extends StatelessWidget {
  const _CropRankingCard({required this.ranking});

  final RankingOut ranking;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Best crops for your land',
              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text('Ranked by what each is worth on its own, before rotation effects.',
              style: textTheme.bodySmall?.copyWith(color: AppColors.clay)),
          const SizedBox(height: 10),
          for (final c in ranking.cropRanking)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 22,
                    child: Text('${c.rank}.',
                        style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: c.inPlan ? AppColors.deepGreen : AppColors.clay)),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.nameEn,
                            style: textTheme.bodyMedium?.copyWith(
                                fontWeight: c.inPlan ? FontWeight.w600 : FontWeight.w400)),
                        Text(
                          c.inPlan
                              ? 'In your plan · ${c.seasonsInPlan.map(seasonLabel).join(', ')} · '
                                  '${c.yieldTHa.toStringAsFixed(2)} t/ha'
                              : 'Not in your plan this year · ${c.yieldTHa.toStringAsFixed(2)} t/ha',
                          style: textTheme.bodySmall?.copyWith(color: AppColors.clay, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Text(formatRs(c.standaloneValueRs),
                      style: textTheme.bodyMedium?.copyWith(
                          color: c.inPlan ? AppColors.deepGreen : AppColors.clay)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The planting order the optimiser chose, with why each crop sits where it does.
class _RankedList extends StatelessWidget {
  const _RankedList({required this.ranking});

  final RankingOut ranking;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final crop in ranking.rankedCrops)
          GlassPanel(
            margin: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 15,
                      backgroundColor: AppColors.deepGreen,
                      child: Text('${crop.rank}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(crop.nameEn, style: textTheme.titleMedium),
                          Text('${seasonLabel(crop.season)} · ${crop.yieldTHa.toStringAsFixed(2)} t/ha '
                              '(${crop.p10.toStringAsFixed(1)}–${crop.p90.toStringAsFixed(1)})',
                              style: textTheme.bodySmall?.copyWith(color: AppColors.clay)),
                        ],
                      ),
                    ),
                    Text(formatRs(crop.realisedValueRs),
                        style: textTheme.titleMedium?.copyWith(color: AppColors.deepGreen)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(crop.why, style: textTheme.bodySmall?.copyWith(color: AppColors.soilBrown)),
                if ((crop.rotationMultiplier - 1.0).abs() > 0.001)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'On its own ${formatRs(crop.standaloneValueRs)}; '
                      'in this slot ×${crop.rotationMultiplier.toStringAsFixed(3)}.',
                      style: textTheme.bodySmall?.copyWith(color: AppColors.clay, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _AdvisoryCard extends StatelessWidget {
  const _AdvisoryCard({required this.advisory});

  final Map<String, dynamic> advisory;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final fert = advisory['fertilizer'] as Map<String, dynamic>? ?? const {};
    final ph = advisory['ph'] as Map<String, dynamic>? ?? const {};
    final irr = advisory['irrigation'] as Map<String, dynamic>? ?? const {};

    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Fertiliser for the full rotation', style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(
            '${fert['urea_bags'] ?? 0} bags urea · ${fert['dap_bags'] ?? 0} bags DAP · '
            '${fert['mop_bags'] ?? 0} bags MOP',
            style: textTheme.bodyLarge,
          ),
          if (ph['amendment'] != null && (ph['dose_t_ha'] as num? ?? 0) > 0) ...[
            const Divider(height: 20),
            Text('Soil correction', style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('${ph['amendment']} — ${(ph['dose_t_ha'] as num).toStringAsFixed(1)} t/ha '
                '(soil is ${ph['category']})',
                style: textTheme.bodyMedium),
          ],
          if (irr['net_irrigation_mm'] != null) ...[
            const Divider(height: 20),
            Text('Irrigation', style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('About ${(irr['net_irrigation_mm'] as num).toStringAsFixed(0)} mm needed after rainfall.',
                style: textTheme.bodyMedium),
          ],
          if (ph['caveat'] != null) ...[
            const SizedBox(height: 12),
            Text(ph['caveat'] as String,
                style: textTheme.bodySmall?.copyWith(color: AppColors.clay, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}
