import 'dart:typed_data';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/api/farmsync_api.dart';

/// Greenness of the crop from satellite (NDVI).
///
/// Colour rule (same as the map overlay): **red = stressed / bare soil**,
/// yellow = okay, green = healthy growth. Low NDVI must never read as green.
class NdviPanel extends ConsumerWidget {
  const NdviPanel({super.key, required this.farmId});

  final String farmId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final signals = ref.watch(_signalsProvider(farmId));
    final series = ref.watch(_ndviSeriesProvider(farmId));
    final png = ref.watch(_ndviPngProvider(farmId));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Crop greenness (NDVI)',
                style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(
              'From satellite photos of your field. Red means the crop looks weak or the soil is bare. '
              'Green means the plants are growing well.',
              style: textTheme.bodySmall?.copyWith(color: AppColors.clay),
            ),
            const SizedBox(height: 12),
            const _NdviLegend(),
            const SizedBox(height: 14),
            signals.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Could not load greenness: $e',
                  style: textTheme.bodySmall?.copyWith(color: AppColors.terracotta)),
              data: (mean) {
                if (mean == null) {
                  return Text(
                    'No satellite reading yet for this field (cloudy days or sensor offline).',
                    style: textTheme.bodySmall?.copyWith(color: AppColors.clay),
                  );
                }
                final color = ndviColor(mean);
                final label = ndviLabel(mean);
                return Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppColors.soilBrown.withValues(alpha: 0.25)),
                      ),
                      child: Text(
                        mean.toStringAsFixed(2),
                        style: TextStyle(
                          color: mean < 0.45 ? Colors.white : AppColors.soilBrown,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label,
                              style: textTheme.titleMedium?.copyWith(color: color)),
                          Text(
                            mean < 0.3
                                ? 'Field looks stressed or bare — check water and crop stand.'
                                : mean < 0.55
                                    ? 'Growth is moderate — watch for dry spells.'
                                    : 'Crop cover looks healthy from above.',
                            style: textTheme.bodySmall?.copyWith(color: AppColors.clay),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            png.when(
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
              data: (bytes) {
                if (bytes == null || bytes.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Field colour map',
                        style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.memory(
                        Uint8List.fromList(bytes),
                        height: 160,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                );
              },
            ),
            series.when(
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
              data: (points) {
                if (points.length < 2) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Greenness over recent weeks',
                        style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 110,
                      child: LineChart(
                        LineChartData(
                          minY: 0,
                          maxY: 1,
                          gridData: const FlGridData(show: false),
                          borderData: FlBorderData(show: false),
                          titlesData: const FlTitlesData(show: false),
                          lineTouchData: const LineTouchData(enabled: false),
                          lineBarsData: [
                            LineChartBarData(
                              spots: [
                                for (var i = 0; i < points.length; i++)
                                  FlSpot(i.toDouble(), points[i].clamp(0.0, 1.0)),
                              ],
                              isCurved: true,
                              color: AppColors.deepGreen,
                              barWidth: 2,
                              dotData: const FlDotData(show: false),
                              belowBarData: BarAreaData(
                                show: true,
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [
                                    const Color(0xFFA50026).withValues(alpha: 0.35),
                                    const Color(0xFF1A9850).withValues(alpha: 0.25),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _NdviLegend extends StatelessWidget {
  const _NdviLegend();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _swatch(const Color(0xFFA50026), 'Weak / bare'),
        const SizedBox(width: 10),
        _swatch(const Color(0xFFFEE08B), 'Okay'),
        const SizedBox(width: 10),
        _swatch(const Color(0xFF1A9850), 'Healthy'),
      ],
    );
  }

  Widget _swatch(Color c, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 14, height: 14, color: c),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.clay)),
      ],
    );
  }
}

/// NDVI → colour. Stressed / low must be deep red (`a50026`), never green.
Color ndviColor(double v) {
  if (v < 0.3) return const Color(0xFFA50026);
  if (v < 0.45) return const Color(0xFFD73027);
  if (v < 0.55) return const Color(0xFFFEE08B);
  if (v < 0.7) return const Color(0xFF66BD63);
  return const Color(0xFF1A9850);
}

String ndviLabel(double v) {
  if (v < 0.3) return 'Stressed / bare';
  if (v < 0.45) return 'Weak growth';
  if (v < 0.55) return 'Moderate';
  if (v < 0.7) return 'Good';
  return 'Strong growth';
}

final _signalsProvider = FutureProvider.autoDispose.family<double?, String>((ref, farmId) async {
  try {
    final s = await ref.watch(farmSyncApiProvider).getSignals(farmId);
    final v = s.ndvi['ndvi_mean'];
    return (v as num?)?.toDouble();
  } catch (_) {
    return null;
  }
});

final _ndviSeriesProvider = FutureProvider.autoDispose.family<List<double>, String>((ref, farmId) async {
  try {
    final raw = await ref.watch(farmSyncApiProvider).ndviSeries(farmId);
    final series = raw['series'] as List<dynamic>? ?? const [];
    return [
      for (final p in series) ((p as Map)['ndvi_mean'] as num?)?.toDouble() ?? double.nan,
    ].where((v) => v.isFinite).toList();
  } catch (_) {
    return const [];
  }
});

final _ndviPngProvider = FutureProvider.autoDispose.family<List<int>?, String>((ref, farmId) async {
  try {
    final r = await ref.watch(farmSyncApiProvider).ndviPng(farmId);
    return r.bytes.isEmpty ? null : r.bytes;
  } catch (_) {
    return null;
  }
});
