import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/models/farm_models.dart';
import '../../data/repos/farm_repo.dart';
import 'add_farm_screen.dart';
import 'farm_detail_screen.dart';
import 'format.dart';

/// My Farms (brief §2.7): every farm on this account, added at any time.
class FarmListScreen extends ConsumerWidget {
  const FarmListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final farms = ref.watch(farmsProvider);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(farmsProvider),
        child: farms.when(
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.deepGreen)),
          error: (e, _) => _ErrorState(message: '$e', onRetry: () => ref.invalidate(farmsProvider)),
          data: (rows) => rows.isEmpty
              ? _EmptyState(onAdd: () => _openAddFarm(context, ref))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  itemCount: rows.length + 1,
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          '${rows.length} farm${rows.length == 1 ? '' : 's'} · '
                          '${rows.fold<double>(0, (a, f) => a + f.areaHa).toStringAsFixed(2)} ha total',
                          style: textTheme.bodyMedium?.copyWith(color: AppColors.clay),
                        ),
                      );
                    }
                    return _FarmCard(
                      farm: rows[i - 1],
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => FarmDetailScreen(farmId: rows[i - 1].id)),
                      ),
                    );
                  },
                ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddFarm(context, ref),
        backgroundColor: AppColors.terracotta,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add farm'),
      ),
    );
  }

  Future<void> _openAddFarm(BuildContext context, WidgetRef ref) async {
    final created = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const AddFarmScreen()),
    );
    ref.invalidate(farmsProvider);
    ref.invalidate(dashboardProvider);
    if (created != null && context.mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => FarmDetailScreen(farmId: created)),
      );
      ref.invalidate(farmsProvider);
    }
  }
}

class _FarmCard extends StatelessWidget {
  const _FarmCard({required this.farm, required this.onTap});

  final FarmOut farm;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final card = farm.soilCard;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(farm.name, style: textTheme.titleMedium)),
                  Text('${farm.areaHa.toStringAsFixed(2)} ha',
                      style: textTheme.bodyMedium?.copyWith(color: AppColors.clay)),
                ],
              ),
              const SizedBox(height: 2),
              Text('${farm.district}, ${farm.state}',
                  style: textTheme.bodySmall?.copyWith(color: AppColors.clay)),
              if (card != null) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final e in card.classes.entries)
                      if (e.key != 'oc_pct') NutrientChip(label: nutrientLabel(e.key), rating: e.value),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              if (farm.isRanked)
                Row(
                  children: [
                    const Icon(Icons.auto_awesome, size: 16, color: AppColors.deepGreen),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        farm.latestSequence.map(cropLabel).join(' → '),
                        style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (farm.latestValueRs != null)
                      Text(formatRs(farm.latestValueRs),
                          style: textTheme.bodyMedium?.copyWith(color: AppColors.deepGreen)),
                  ],
                )
              else
                Row(
                  children: [
                    Icon(Icons.pending_outlined, size: 16, color: AppColors.terracotta.withValues(alpha: 0.8)),
                    const SizedBox(width: 6),
                    Text(
                      farm.hasSoilCard ? 'Tap to rank crops' : 'Add soil readings to begin',
                      style: textTheme.bodyMedium?.copyWith(color: AppColors.terracotta),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 96, 32, 32),
      children: [
        const Icon(Icons.agriculture_outlined, size: 64, color: AppColors.clay),
        const SizedBox(height: 20),
        Text('No farms yet', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'Add your land and its soil readings, and you will get a ranked crop '
          'plan for the year along with what the soil needs.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.clay),
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Add your first farm')),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  static String _friendly(String message) {
    final s = message.toLowerCase();
    if (s.contains('404') || s.contains('not found')) {
      return 'The server is missing the farms API (often an old deploy). '
          'Pull the latest backend or point the app at a server that serves /api/v1/farms.\n\n$message';
    }
    if (s.contains('401') || s.contains('unauthorized')) {
      return 'Sign-in failed for this server. Use Open demo farms or Google sign-in again.\n\n$message';
    }
    return message;
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 96, 32, 32),
      children: [
        const Icon(Icons.cloud_off, size: 56, color: AppColors.terracotta),
        const SizedBox(height: 16),
        Text('Could not load your farms',
            textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(_friendly(message),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.clay)),
        const SizedBox(height: 20),
        OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    );
  }
}
