import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;
import 'maplibre_view.dart';

import '../api/client.dart';
import '../cache/landroid_disk_cache.dart';
import '../i18n/translations.dart';
import '../map/map_layer_placeholders.dart';
import '../map/map_measure.dart';
import '../models/session.dart';
import '../widgets/app_card.dart';
import '../widgets/staggered_entrance.dart';

class _MapPayload {
  const _MapPayload({
    required this.manifest,
    this.ndvi,
    this.zones,
    this.demLocal,
    this.fromCache = false,
  });

  final Map<String, dynamic> manifest;
  final ParcelLayerOverlay? ndvi;
  final ParcelLayerOverlay? zones;
  /// Hillshade from local DEM GeoTIFF when manifest ``dem.source == local_geotiff``.
  final ParcelLayerOverlay? demLocal;
  final bool fromCache;
}

class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    required this.locale,
    required this.session,
    required this.apiClient,
  });

  final LocaleCode locale;
  final Session session;
  final ApiClient apiClient;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late Future<_MapPayload> _future;

  bool _showSatellite = true;
  bool _showBoundary = true;
  bool _showNdvi = true;
  bool _showZones = true;
  bool _showOrtho = true;
  bool _showDem = true;

  /// Tap map to draw a path; 2+ points → path length, 3+ → enclosed area.
  bool _tapMeasureOn = false;
  final List<maplibre.LatLng> _tapMeasurePoints = [];
  String? _parcelIdForTapMeasure;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.token != widget.session.token ||
        oldWidget.apiClient.resolvedApiBaseUrl !=
            widget.apiClient.resolvedApiBaseUrl) {
      _future = _load();
    }
  }

  Future<_MapPayload> _load({bool forceNetwork = false}) async {
    final api = widget.apiClient.resolvedApiBaseUrl;

    if (!forceNetwork) {
      final fromDisk = await _tryLoadMapFromDisk(api);
      if (fromDisk != null) {
        return fromDisk;
      }
    }

    await widget.apiClient.refreshParcels(widget.session);
    if (!widget.apiClient.hasSelectedParcel) {
      return _MapPayload(
        manifest: {
          'parcel_id': '',
          'bbox': {},
          'layers': {},
        },
        fromCache: false,
      );
    }
    final manifest = await widget.apiClient.mapManifest(widget.session);
    final pid =
        manifest['parcel_id'] as String? ?? widget.apiClient.parcelId;
    widget.apiClient.setParcelId(pid);
    final demMetaEarly = manifest['layers']?['dem'] as Map<String, dynamic>?;
    final fetched = await Future.wait([
      widget.apiClient.fetchParcelLayerPng(widget.session, pid, 'ndvi'),
      widget.apiClient.fetchParcelLayerPng(widget.session, pid, 'zones'),
      demMetaEarly?['source'] == 'local_geotiff'
          ? widget.apiClient.fetchParcelLayerPng(
              widget.session,
              pid,
              'dem-raster',
            )
          : Future<ParcelLayerOverlay?>.value(null),
    ]);
    var ndvi = fetched[0];
    var zones = fetched[1];
    ParcelLayerOverlay? demLocal = fetched[2];
    final box = manifestBBox(manifest);
    if (ndvi == null && box != null) {
      ndvi = await buildLocalNdviPlaceholder(
        west: box.west,
        south: box.south,
        east: box.east,
        north: box.north,
      );
    }
    if (zones == null && box != null) {
      zones = await buildLocalZonesPlaceholder(
        west: box.west,
        south: box.south,
        east: box.east,
        north: box.north,
      );
    }
    await _persistMapCache(api, pid, manifest, ndvi, zones, demLocal);
    return _MapPayload(
      manifest: manifest,
      ndvi: ndvi,
      zones: zones,
      demLocal: demLocal,
      fromCache: false,
    );
  }

  Future<_MapPayload?> _tryLoadMapFromDisk(String api) async {
    var parcelId = await ParcelMapDiskCache.findAnyParcelIdWithManifest(api);
    parcelId ??= widget.apiClient.parcelId;
    var manifest = await ParcelMapDiskCache.readManifest(api, parcelId);
    if (manifest == null && parcelId != widget.apiClient.parcelId) {
      parcelId = widget.apiClient.parcelId;
      manifest = await ParcelMapDiskCache.readManifest(api, parcelId);
    }
    if (manifest == null) {
      return null;
    }

    widget.apiClient.setParcelId(
      manifest['parcel_id'] as String? ?? parcelId,
    );
    final id = widget.apiClient.parcelId;

    var ndvi = await ParcelMapDiskCache.readLayer(api, id, 'ndvi');
    var zones = await ParcelMapDiskCache.readLayer(api, id, 'zones');
    final demMeta = manifest['layers']?['dem'] as Map<String, dynamic>?;
    ParcelLayerOverlay? demLocal;
    if (demMeta?['source'] == 'local_geotiff') {
      demLocal = await ParcelMapDiskCache.readLayer(api, id, 'dem-raster');
    }
    final box = manifestBBox(manifest);
    if (ndvi == null && box != null) {
      ndvi = await buildLocalNdviPlaceholder(
        west: box.west,
        south: box.south,
        east: box.east,
        north: box.north,
      );
    }
    if (zones == null && box != null) {
      zones = await buildLocalZonesPlaceholder(
        west: box.west,
        south: box.south,
        east: box.east,
        north: box.north,
      );
    }
    return _MapPayload(
      manifest: manifest,
      ndvi: ndvi,
      zones: zones,
      demLocal: demLocal,
      fromCache: true,
    );
  }

  Future<void> _persistMapCache(
    String api,
    String parcelId,
    Map<String, dynamic> manifest,
    ParcelLayerOverlay? ndvi,
    ParcelLayerOverlay? zones,
    ParcelLayerOverlay? demLocal,
  ) async {
    await ParcelMapDiskCache.writeManifest(api, parcelId, manifest);
    if (ndvi != null && ndvi.source != 'local_fallback') {
      await ParcelMapDiskCache.writeLayer(api, parcelId, 'ndvi', ndvi);
    }
    if (zones != null && zones.source != 'local_fallback') {
      await ParcelMapDiskCache.writeLayer(api, parcelId, 'zones', zones);
    }
    if (demLocal != null) {
      await ParcelMapDiskCache.writeLayer(
        api,
        parcelId,
        'dem-raster',
        demLocal,
      );
    }
  }

  void _reloadMapFromDisk() {
    setState(() {
      _future = _load(forceNetwork: false);
    });
  }

  void _syncMapFromServer() {
    setState(() {
      _future = _load(forceNetwork: true);
    });
  }

  void _onTapMeasureVertex(maplibre.LatLng ll) {
    setState(() => _tapMeasurePoints.add(ll));
  }

  maplibre.LatLngBounds? _cameraBounds(_MapPayload payload, Map<String, dynamic> m) {
    if (payload.ndvi != null) {
      return maplibre.LatLngBounds(
        southwest: maplibre.LatLng(payload.ndvi!.south, payload.ndvi!.west),
        northeast: maplibre.LatLng(payload.ndvi!.north, payload.ndvi!.east),
      );
    }
    final bb = m['bbox'] as Map<String, dynamic>?;
    if (bb == null) return null;
    return maplibre.LatLngBounds(
      southwest: maplibre.LatLng((bb['min_lat'] as num).toDouble(), (bb['min_lng'] as num).toDouble()),
      northeast: maplibre.LatLng((bb['max_lat'] as num).toDouble(), (bb['max_lng'] as num).toDouble()),
    );
  }

  Color _badgeColor(String? label, ThemeData theme) {
    switch (label) {
      case 'Healthy':
        return Colors.green.shade700;
      case 'Moderate':
        return Colors.orange.shade800;
      case 'At Risk':
        return Colors.red.shade800;
      default:
        return theme.colorScheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return FutureBuilder<_MapPayload>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Center(
            child: AppCard(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    t(widget.locale, 'loading'),
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          final err = snapshot.hasError ? snapshot.error.toString() : '';
          return Center(
            child: AppCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    t(widget.locale, 'mapLoadError'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                  if (err.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    SelectableText(
                      err,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: muted,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _syncMapFromServer,
                    icon: const Icon(Icons.cloud_download_rounded),
                    label: Text(t(widget.locale, 'syncFromServer')),
                  ),
                ],
              ),
            ),
          );
        }

        final payload = snapshot.data!;
        final m = payload.manifest;
        if ((m['parcel_id'] as String?) == '') {
          return Center(
            child: AppCard(
              padding: const EdgeInsets.all(24),
              child: Text(
                t(widget.locale, 'mapNoParcel'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
            ),
          );
        }
        final parcelIdStable = (m['parcel_id'] as String?) ?? '';
        if (_parcelIdForTapMeasure != parcelIdStable) {
          _parcelIdForTapMeasure = parcelIdStable;
          Future.microtask(() {
            if (!mounted) return;
            setState(() {
              _tapMeasurePoints.clear();
              _tapMeasureOn = false;
            });
          });
        }
        final centroid = m['centroid'] as Map<String, dynamic>?;
        final lat = (centroid?['lat'] as num?)?.toDouble() ?? 10.43;
        final lng = (centroid?['lng'] as num?)?.toDouble() ?? 77.30;
        final center = maplibre.LatLng(lat, lng);
        final badge = m['health_badge'] as String?;
        final score = m['health_score'];
        final layers = m['layers'] as Map<String, dynamic>?;
        final zoneLegend =
            (layers?['plant_health_zones'] as Map<String, dynamic>?)?['legend']
                as List<dynamic>?;
        final ndviLayerMeta = layers?['ndvi'] as Map<String, dynamic>?;
        final showOfflineNotice = payload.ndvi?.source == 'local_fallback' ||
            payload.zones?.source == 'local_fallback';
        final showDemoNotice = !showOfflineNotice &&
            ((ndviLayerMeta?['source'] as String?) == 'synthetic' ||
                payload.ndvi?.source == 'synthetic' ||
                payload.zones?.source == 'synthetic');

        final orthoTile = parseManifestTileLayer(
          layers?['orthomosaic'] as Map<String, dynamic>?,
        );
        final demTile = parseManifestTileLayer(
          layers?['dem'] as Map<String, dynamic>?,
        );
        final fitBounds = _cameraBounds(payload, m);



        return RefreshIndicator(
          onRefresh: () async {
            setState(() {
              _future = _load(forceNetwork: true);
            });
            await _future;
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
            children: [
            StaggeredEntrance(
              index: 0,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    t(widget.locale, 'map'),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (widget.session.isLandowner) ...[
                    const SizedBox(height: 8),
                    Material(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.visibility_rounded,
                              size: 18,
                              color: Color(0xFF2E7D32),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                t(widget.locale, 'readOnlyMapHint'),
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: const Color(0xFF2E7D32),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (payload.fromCache)
              StaggeredEntrance(
                index: 1,
                child: AppCard(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.storage_rounded,
                        color: theme.colorScheme.secondary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          t(widget.locale, 'mapCachedHint'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (payload.fromCache) const SizedBox(height: 12),
            StaggeredEntrance(
              index: 2,
              child: AppCard(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.health_and_safety_rounded, color: theme.colorScheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t(widget.locale, 'parcelHealth'),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${badge ?? '—'} · ${t(widget.locale, 'score')}: ${score ?? '—'}',
                            style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _badgeColor(badge, theme).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        badge ?? '—',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: _badgeColor(badge, theme),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            StaggeredEntrance(
              index: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MapLibreView(
                    key: ValueKey(m['parcel_id'] as String? ?? ''),
                    manifest: m,
                    ndviBytes: payload.ndvi?.bytes,
                    zonesBytes: payload.zones?.bytes,
                    demBytes: payload.demLocal?.bytes,
                    showSatellite: _showSatellite,
                    showBoundary: _showBoundary,
                    showNdvi: _showNdvi,
                    showZones: _showZones,
                    showOrtho: _showOrtho,
                    showDem: _showDem,
                    bounds: fitBounds,
                    center: center,
                    ndviBounds: payload.ndvi != null
                        ? GeoLayerBounds(
                            west: payload.ndvi!.west,
                            south: payload.ndvi!.south,
                            east: payload.ndvi!.east,
                            north: payload.ndvi!.north,
                          )
                        : null,
                    zonesBounds: payload.zones != null
                        ? GeoLayerBounds(
                            west: payload.zones!.west,
                            south: payload.zones!.south,
                            east: payload.zones!.east,
                            north: payload.zones!.north,
                          )
                        : null,
                    demBounds: payload.demLocal != null
                        ? GeoLayerBounds(
                            west: payload.demLocal!.west,
                            south: payload.demLocal!.south,
                            east: payload.demLocal!.east,
                            north: payload.demLocal!.north,
                          )
                        : null,
                    measureActive: _tapMeasureOn,
                    measurePoints: _tapMeasurePoints,
                    onMeasureVertexAdded:
                        _tapMeasureOn ? _onTapMeasureVertex : null,
                  ),
                ],
              ),
            ),
            if (showOfflineNotice) ...[
              const SizedBox(height: 10),
              StaggeredEntrance(
                index: 4,
                child: AppCard(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.wifi_off_rounded, color: Colors.amber.shade700),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Builder(
                          builder: (context) {
                            final apiUri = Uri.parse(widget.apiClient.resolvedApiBaseUrl);
                            final port = apiUri.hasPort
                                ? apiUri.port
                                : (apiUri.scheme == 'https' ? 443 : 80);
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t(widget.locale, 'layerOfflinePreviewTitle'),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: muted,
                                    height: 1.35,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SelectableText(
                                  widget.apiClient.resolvedApiBaseUrl,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  t(widget.locale, 'layerOfflinePreviewAdb')
                                      .replaceAll('{port}', '$port'),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: muted,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else if (showDemoNotice) ...[
              const SizedBox(height: 10),
              StaggeredEntrance(
                index: 4,
                child: AppCard(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded, color: theme.colorScheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          t(widget.locale, 'layerDemoRaster'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            StaggeredEntrance(
              index: 5,
              child: AppCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.layers_rounded, color: theme.colorScheme.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            t(widget.locale, 'layersLabel'),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (widget.session.isConsultant) ...[
                          IconButton.filledTonal(
                            tooltip: t(widget.locale, 'refreshLayersCache'),
                            onPressed: _reloadMapFromDisk,
                            icon: const Icon(Icons.storage_rounded),
                          ),
                          IconButton.filledTonal(
                            tooltip: t(widget.locale, 'syncFromServer'),
                            onPressed: _syncMapFromServer,
                            icon: const Icon(Icons.cloud_download_rounded),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: Icon(
                        Icons.touch_app_rounded,
                        color: theme.colorScheme.primary,
                      ),
                      title: Text(t(widget.locale, 'tapMeasureTitle')),
                      subtitle: Text(
                        t(widget.locale, 'tapMeasureSubtitle'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                          height: 1.35,
                        ),
                      ),
                      value: _tapMeasureOn,
                      onChanged: (v) {
                        setState(() {
                          _tapMeasureOn = v;
                          if (!v) {
                            _tapMeasurePoints.clear();
                          }
                        });
                      },
                    ),
                    if (_tapMeasureOn) ...[
                      if (_tapMeasurePoints.length >= 2)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            '${t(widget.locale, 'tapMeasurePathLength')}: '
                            '${formatDistanceMeters(polylineLengthMeters(_tapMeasurePoints))}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      if (_tapMeasurePoints.length >= 3)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '${t(widget.locale, 'tapMeasureEnclosedArea')}: '
                            '${formatAreaM2(polygonAreaM2(_tapMeasurePoints))}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      if (_tapMeasurePoints.isEmpty)
                        Text(
                          t(widget.locale, 'tapMeasureHintFirst'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                            height: 1.35,
                          ),
                        )
                      else if (_tapMeasurePoints.length == 1)
                        Text(
                          t(widget.locale, 'tapMeasureHintSecond'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                            height: 1.35,
                          ),
                        )
                      else if (_tapMeasurePoints.length == 2)
                        Text(
                          t(widget.locale, 'tapMeasureHintThird'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                            height: 1.35,
                          ),
                        ),
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: _tapMeasurePoints.isEmpty
                                ? null
                                : () {
                                    setState(() => _tapMeasurePoints.clear());
                                  },
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            label: Text(t(widget.locale, 'tapMeasureClear')),
                          ),
                          TextButton.icon(
                            onPressed: _tapMeasurePoints.isEmpty
                                ? null
                                : () {
                                    setState(() {
                                      if (_tapMeasurePoints.isNotEmpty) {
                                        _tapMeasurePoints.removeLast();
                                      }
                                    });
                                  },
                            icon: const Icon(Icons.undo_rounded, size: 18),
                            label: Text(t(widget.locale, 'tapMeasureUndo')),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    const Divider(height: 20),
                    ..._boundaryMetricsRows(
                      widget.locale,
                      m,
                      theme,
                      muted,
                    ),
                    const Divider(height: 24),
                    Text(
                      t(widget.locale, 'gisBasemap'),
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<bool>(
                      segments: [
                        ButtonSegment<bool>(
                          value: true,
                          label: Text(t(widget.locale, 'layerSatellite')),
                          icon: const Icon(Icons.satellite_alt_rounded, size: 18),
                        ),
                        ButtonSegment<bool>(
                          value: false,
                          label: Text(t(widget.locale, 'layerStreet')),
                          icon: const Icon(Icons.map_rounded, size: 18),
                        ),
                      ],
                      selected: {_showSatellite},
                      onSelectionChanged: (s) {
                        setState(() => _showSatellite = s.first);
                      },
                      emptySelectionAllowed: false,
                      showSelectedIcon: false,
                      style: ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: Icon(
                        Icons.polyline_rounded,
                        color: theme.colorScheme.tertiary,
                      ),
                      title: Text(t(widget.locale, 'layerBoundary')),
                      value: _showBoundary,
                      onChanged: (v) => setState(() => _showBoundary = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: Icon(
                        Icons.grass_rounded,
                        color: theme.colorScheme.primary,
                      ),
                      title: Text(t(widget.locale, 'layerNdvi')),
                      subtitle: Text(
                        t(widget.locale, 'layerNdviSubtitle'),
                        style: theme.textTheme.bodySmall?.copyWith(color: muted),
                      ),
                      value: payload.ndvi != null && _showNdvi,
                      onChanged: payload.ndvi == null
                          ? null
                          : (v) => setState(() => _showNdvi = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: Icon(
                        Icons.grid_view_rounded,
                        color: theme.colorScheme.secondary,
                      ),
                      title: Text(t(widget.locale, 'layerZones')),
                      subtitle: Text(
                        t(widget.locale, 'layerZonesSubtitle'),
                        style: theme.textTheme.bodySmall?.copyWith(color: muted),
                      ),
                      value: payload.zones != null && _showZones,
                      onChanged: payload.zones == null
                          ? null
                          : (v) => setState(() => _showZones = v),
                    ),
                    const Divider(height: 20),
                    if (orthoTile != null)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        secondary: Icon(
                          Icons.image_outlined,
                          color: theme.colorScheme.primary,
                        ),
                        title: Text(t(widget.locale, 'layerOrtho')),
                        subtitle: Text(
                          t(widget.locale, 'layerTileLayerActiveHint'),
                          style: theme.textTheme.bodySmall?.copyWith(color: muted),
                        ),
                        value: _showOrtho,
                        onChanged: (v) => setState(() => _showOrtho = v),
                      )
                    else
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: Icon(Icons.image_outlined, color: muted, size: 22),
                        title: Text(t(widget.locale, 'layerOrtho')),
                        subtitle: Text(
                          t(widget.locale, 'orthoDemSubtitle'),
                          style: theme.textTheme.bodySmall?.copyWith(color: muted),
                        ),
                        trailing: Icon(Icons.lock_outline_rounded, size: 18, color: muted),
                      ),
                    if (demTile != null || payload.demLocal != null)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        secondary: Icon(
                          Icons.terrain_rounded,
                          color: theme.colorScheme.secondary,
                        ),
                        title: Text(t(widget.locale, 'layerDem')),
                        subtitle: Text(
                          demTile != null
                              ? t(widget.locale, 'layerTileLayerActiveHint')
                              : t(widget.locale, 'layerDemLocalHint'),
                          style: theme.textTheme.bodySmall?.copyWith(color: muted),
                        ),
                        value: _showDem,
                        onChanged: (v) => setState(() => _showDem = v),
                      )
                    else
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: Icon(Icons.terrain_rounded, color: muted, size: 22),
                        title: Text(t(widget.locale, 'layerDem')),
                        subtitle: Text(
                          t(widget.locale, 'orthoDemSubtitle'),
                          style: theme.textTheme.bodySmall?.copyWith(color: muted),
                        ),
                        trailing: Icon(Icons.lock_outline_rounded, size: 18, color: muted),
                      ),
                    const SizedBox(height: 6),
                    Text(
                      t(widget.locale, 'boundaryHint'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: muted,
                        height: 1.4,
                      ),
                    ),
                    if (zoneLegend != null && zoneLegend.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        t(widget.locale, 'layerZones'),
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ...zoneLegend.map((e) {
                        final row = e as Map<String, dynamic>;
                        final col = row['color'] as String? ?? '#888';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: _parseHexColor(col),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${row['label'] ?? ''} ${row['ndvi_range'] ?? row['ndvi_max'] ?? row['ndvi_min'] ?? ''}',
                                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
        );
      },
    );
  }
}

/// Read-only boundary perimeter + area from API ``parcel_metrics`` (geodesic WGS84).
List<Widget> _boundaryMetricsRows(
  LocaleCode locale,
  Map<String, dynamic> manifest,
  ThemeData theme,
  Color muted,
) {
  final pm = manifest['parcel_metrics'] as Map<String, dynamic>?;
  if (pm == null) {
    return [
      Text(
        t(locale, 'boundaryMetricsUnavailable'),
        style: theme.textTheme.bodySmall?.copyWith(color: muted, height: 1.35),
      ),
    ];
  }
  final perimeterM = (pm['perimeter_m'] as num?)?.toDouble();
  final areaHa = (pm['area_ha'] as num?)?.toDouble();
  final areaM2 = (pm['area_m2'] as num?)?.toDouble();
  if (perimeterM == null || areaHa == null) {
    return [
      Text(
        t(locale, 'boundaryMetricsUnavailable'),
        style: theme.textTheme.bodySmall?.copyWith(color: muted, height: 1.35),
      ),
    ];
  }
  final m2Line = areaM2 != null
      ? ' (${areaM2.toStringAsFixed(0)} ${t(locale, 'squareMetersSuffix')})'
      : '';
  return [
    Align(
      alignment: Alignment.centerLeft,
      child: Text(
        t(locale, 'boundaryMetricsTitle'),
        style: theme.textTheme.labelLarge?.copyWith(
          color: muted,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    const SizedBox(height: 6),
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.straighten_rounded, size: 18, color: theme.colorScheme.tertiary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${t(locale, 'boundaryDistanceLabel')}: '
            '${perimeterM.toStringAsFixed(1)} ${t(locale, 'metersSuffix')}',
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
    const SizedBox(height: 6),
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.crop_square_rounded, size: 18, color: theme.colorScheme.secondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${t(locale, 'boundaryAreaLabel')}: '
            '${areaHa.toStringAsFixed(2)} ${t(locale, 'hectaresSuffix')}$m2Line',
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
    const SizedBox(height: 6),
    Text(
      t(locale, 'boundaryMetricsFootnote'),
      style: theme.textTheme.bodySmall?.copyWith(color: muted, height: 1.35),
    ),
  ];
}

Color _parseHexColor(String hex) {
  var h = hex.replaceFirst('#', '');
  if (h.length == 6) {
    h = 'ff$h';
  }
  return Color(int.parse(h, radix: 16));
}
