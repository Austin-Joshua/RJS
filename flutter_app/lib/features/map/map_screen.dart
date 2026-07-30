import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/env.dart';
import '../../core/theme.dart';
import '../../data/models/api_models.dart';
import '../../data/repos/field_repo.dart';
import 'demo_field_assets.dart';

final demoFieldProvider = FutureProvider<DemoFieldAssets>((ref) => DemoFieldAssets.load());

final mapManifestProvider = FutureProvider<MapManifestOut?>((ref) async {
  if (!Env.isApiConfigured) return null;
  final field = await ref.watch(activeFieldProvider.future);
  if (field == null) return null;
  try {
    return await ref.read(farmSyncApiProvider).mapManifest(field.id);
  } catch (_) {
    return null;
  }
});

class _AuthLayerImage {
  const _AuthLayerImage({required this.bytes, required this.bounds});

  final Uint8List bytes;
  final LatLngBounds bounds;
}

LatLngBounds? _boundsFromHeader(String? header) {
  if (header == null) return null;
  final parts = header.split(',').map((e) => double.tryParse(e.trim())).toList();
  if (parts.length != 4 || parts.any((e) => e == null)) return null;
  // X-Geo-Bounds: west,south,east,north (see backend rasters/signals)
  return LatLngBounds(LatLng(parts[1]!, parts[0]!), LatLng(parts[3]!, parts[2]!));
}

final authLayerProvider = FutureProvider.family<_AuthLayerImage?, String>((ref, relativeUrl) async {
  if (!Env.isApiConfigured || relativeUrl.isEmpty) return null;
  try {
    final fetched = await ref.read(farmSyncApiProvider).layerBytes(relativeUrl);
    final bounds = _boundsFromHeader(fetched.geoBounds);
    if (bounds == null || fetched.bytes.isEmpty) return null;
    return _AuthLayerImage(bytes: Uint8List.fromList(fetched.bytes), bounds: bounds);
  } catch (_) {
    return null;
  }
});

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  double _ndviDay = 15;
  bool _showOrtho = true;
  bool _showDem = false;
  bool _showNdvi = true;

  @override
  Widget build(BuildContext context) {
    final asyncDemo = ref.watch(demoFieldProvider);
    final asyncField = ref.watch(activeFieldProvider);
    final asyncManifest = ref.watch(mapManifestProvider);
    final ndviAlpha = 0.15 + (_ndviDay / 30) * 0.45;

    return asyncDemo.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.deepGreen)),
      error: (e, _) => Center(child: Text('Demo field failed to load:\n$e', textAlign: TextAlign.center)),
      data: (demo) {
        final field = asyncField.value;
        final manifest = asyncManifest.value;
        final center = field != null ? LatLng(field.lat, field.lon) : demo.centroid;
        final title = field?.name ?? demo.name;
        final subtitle = field != null
            ? '${field.district}, ${field.state} · ${field.areaHa.toStringAsFixed(2)} ha'
            : demo.citation;

        final orthoUrl = manifest?.baseLayer.available == true ? manifest!.baseLayer.url : null;
        final demOverlay = manifest?.overlays.where((o) => o.id == 'dem_hillshade' && o.available).firstOrNull;
        final ndviOverlay = manifest?.overlays.where((o) => o.id == 'ndvi_satellite' && o.available).firstOrNull;

        final orthoLayer = orthoUrl != null ? ref.watch(authLayerProvider(orthoUrl)) : null;
        final demLayer = demOverlay?.url != null ? ref.watch(authLayerProvider(demOverlay!.url!)) : null;
        final ndviLayer = ndviOverlay?.url != null ? ref.watch(authLayerProvider(ndviOverlay!.url!)) : null;

        final orthoImg = orthoLayer?.value;
        final demImg = demLayer?.value;
        final ndviImg = ndviLayer?.value;

        return Column(
          children: [
            Expanded(
              child: FlutterMap(
                options: MapOptions(initialCenter: center, initialZoom: 17.5),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.farmsync.app',
                    errorTileCallback: (_, error, stackTrace) {},
                  ),
                  if (_showDem)
                    OverlayImageLayer(
                      overlayImages: [
                        if (demImg != null)
                          OverlayImage(
                            bounds: demImg.bounds,
                            opacity: 0.55,
                            imageProvider: MemoryImage(demImg.bytes),
                          )
                        else
                          OverlayImage(
                            bounds: demo.orthoBounds,
                            opacity: 0.55,
                            imageProvider: const AssetImage(DemoFieldAssets.demAsset),
                          ),
                      ],
                    ),
                  if (_showOrtho)
                    OverlayImageLayer(
                      overlayImages: [
                        if (orthoImg != null)
                          OverlayImage(
                            bounds: orthoImg.bounds,
                            opacity: 0.75,
                            imageProvider: MemoryImage(orthoImg.bytes),
                          )
                        else
                          OverlayImage(
                            bounds: demo.orthoBounds,
                            opacity: 0.75,
                            imageProvider: const AssetImage(DemoFieldAssets.orthoAsset),
                          ),
                      ],
                    ),
                  if (_showNdvi && ndviImg != null)
                    OverlayImageLayer(
                      overlayImages: [
                        OverlayImage(
                          bounds: ndviImg.bounds,
                          opacity: ndviAlpha,
                          imageProvider: MemoryImage(ndviImg.bytes),
                        ),
                      ],
                    ),
                  PolygonLayer(
                    polygons: [
                      Polygon(
                        points: demo.polygon,
                        color: AppColors.deepGreen.withValues(alpha: ndviImg == null ? ndviAlpha : 0.05),
                        borderColor: AppColors.terracotta,
                        borderStrokeWidth: 3,
                      ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: center,
                        width: 40,
                        height: 40,
                        child: const Icon(Icons.agriculture, color: AppColors.terracotta, size: 36),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Material(
              color: AppColors.cream,
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    Text(subtitle, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13, color: AppColors.clay)),
                    if (Env.isApiConfigured && field == null)
                      Text(
                        'Connecting to API…',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.terracotta),
                      ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilterChip(
                          label: const Text('Orthomosaic'),
                          selected: _showOrtho,
                          onSelected: (v) => setState(() => _showOrtho = v),
                          selectedColor: AppColors.deepGreen.withValues(alpha: 0.2),
                        ),
                        FilterChip(
                          label: const Text('DEM'),
                          selected: _showDem,
                          onSelected: (v) => setState(() => _showDem = v),
                          selectedColor: AppColors.soilBrown.withValues(alpha: 0.2),
                        ),
                        FilterChip(
                          label: const Text('NDVI'),
                          selected: _showNdvi,
                          onSelected: (v) => setState(() => _showNdvi = v),
                          selectedColor: AppColors.deepGreen.withValues(alpha: 0.2),
                        ),
                      ],
                    ),
                    Text(
                      'NDVI opacity · day ${_ndviDay.round()} / 30',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Slider(
                      value: _ndviDay,
                      min: 1,
                      max: 30,
                      divisions: 29,
                      label: 'Day ${_ndviDay.round()}',
                      onChanged: (v) => setState(() => _ndviDay = v),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
