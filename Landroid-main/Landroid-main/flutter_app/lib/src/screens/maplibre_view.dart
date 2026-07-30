import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

/// WGS84 bounds for a PNG overlay (must match API ``X-Geo-Bounds`` when present).
class GeoLayerBounds {
  const GeoLayerBounds({
    required this.west,
    required this.south,
    required this.east,
    required this.north,
  });

  final double west;
  final double south;
  final double east;
  final double north;
}

class MapLibreView extends StatefulWidget {
  const MapLibreView({
    super.key,
    required this.manifest,
    required this.ndviBytes,
    required this.zonesBytes,
    required this.demBytes,
    required this.showSatellite,
    required this.showBoundary,
    required this.showNdvi,
    required this.showZones,
    required this.showOrtho,
    required this.showDem,
    required this.bounds,
    required this.center,
    this.measureActive = false,
    this.measurePoints = const [],
    this.onMeasureVertexAdded,
    this.ndviBounds,
    this.zonesBounds,
    this.demBounds,
  });

  final Map<String, dynamic> manifest;
  final Uint8List? ndviBytes;
  final Uint8List? zonesBytes;
  final Uint8List? demBytes;
  final bool showSatellite;
  final bool showBoundary;
  final bool showNdvi;
  final bool showZones;
  final bool showOrtho;
  final bool showDem;
  final LatLngBounds? bounds;
  final LatLng center;

  /// When set, NDVI raster is anchored to PNG bounds (not the manifest bbox).
  final GeoLayerBounds? ndviBounds;
  final GeoLayerBounds? zonesBounds;
  final GeoLayerBounds? demBounds;

  /// Tap-to-measure: when true, map taps add vertices (see [onMeasureVertexAdded]).
  final bool measureActive;
  final List<LatLng> measurePoints;
  final ValueChanged<LatLng>? onMeasureVertexAdded;

  @override
  State<MapLibreView> createState() => _MapLibreViewState();
}

class _MapLibreViewState extends State<MapLibreView> {
  final GlobalKey _mapRenderKey = GlobalKey();
  MapLibreMapController? _controller;
  bool _styleLoaded = false;
  /// Avoid resetting zoom whenever basemap style reloads (satellite ↔ OSM).
  bool _didFitInitialCamera = false;

  /// Serialize native add/remove source+layer work — concurrent syncs crash Android MapLibre.
  Future<void> _syncChain = Future<void>.value();

  @override
  void didUpdateWidget(covariant MapLibreView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.manifest['parcel_id'] != widget.manifest['parcel_id']) {
      _didFitInitialCamera = false;
    }
    if (_styleLoaded) {
      unawaited(_syncLayers());
    }
  }

  String _getStyleString() {
    final rasterUrl = widget.showSatellite
        ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
        : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
    return '''
{
  "version": 8,
  "sources": {
    "basemap": {
      "type": "raster",
      "tiles": [ "$rasterUrl" ],
      "tileSize": 256
    }
  },
  "layers": [
    {
      "id": "basemap-layer",
      "type": "raster",
      "source": "basemap",
      "paint": {
        "raster-resampling": "linear"
      }
    }
  ]
}''';
  }

  LatLngQuad? _quadFromLayerOrManifest(GeoLayerBounds? layerBb) {
    if (layerBb != null) {
      final w = layerBb.west;
      final s = layerBb.south;
      final e = layerBb.east;
      final n = layerBb.north;
      return LatLngQuad(
        topLeft: LatLng(n, w),
        topRight: LatLng(n, e),
        bottomRight: LatLng(s, e),
        bottomLeft: LatLng(s, w),
      );
    }
    final bb = widget.manifest['bbox'] as Map<String, dynamic>?;
    if (bb == null || bb.isEmpty) return null;
    final w = (bb['min_lng'] as num).toDouble();
    final s = (bb['min_lat'] as num).toDouble();
    final e = (bb['max_lng'] as num).toDouble();
    final n = (bb['max_lat'] as num).toDouble();
    return LatLngQuad(
      topLeft: LatLng(n, w),
      topRight: LatLng(n, e),
      bottomRight: LatLng(s, e),
      bottomLeft: LatLng(s, w),
    );
  }

  Future<void> _syncLayers() {
    _syncChain = _syncChain.then((_) async {
      try {
        await _syncLayersImpl();
      } catch (e, st) {
        debugPrint('MapLibre layer sync failed: $e\n$st');
      }
    });
    return _syncChain;
  }

  Future<void> _syncLayersImpl() async {
    if (_controller == null || !_styleLoaded) return;

    // Boundary
    if (widget.showBoundary) {
      final bg = widget.manifest['boundary_geojson'] as Map<String, dynamic>?;
      if (bg != null) {
        try {
          await _controller!.removeLayer('boundary-layer');
          await _controller!.removeSource('boundary');
        } catch (_) {}
        await _controller!.addGeoJsonSource('boundary', bg);
        await _controller!.addLineLayer(
          'boundary',
          'boundary-layer',
          LineLayerProperties(
            lineColor: '#2E7D32',
            lineWidth: 3.0,
            lineJoin: 'round',
          ),
        );
      }
    } else {
      try {
        await _controller!.removeLayer('boundary-layer');
        await _controller!.removeSource('boundary');
      } catch (_) {}
    }

    Future<void> syncImageOverlay(
      String id,
      bool show,
      Uint8List? bytes,
      GeoLayerBounds? layerBb,
    ) async {
      try {
        await _controller!.removeLayer('$id-layer');
        await _controller!.removeSource(id);
      } catch (_) {}

      if (show && bytes != null) {
        final quad = _quadFromLayerOrManifest(layerBb);
        if (quad != null) {
          await _controller!.addImageSource(id, bytes, quad);
          await _controller!.addRasterLayer(
            id,
            '$id-layer',
            RasterLayerProperties(rasterOpacity: 0.92),
          );
        }
      }
    }

    await syncImageOverlay('ndvi', widget.showNdvi, widget.ndviBytes, widget.ndviBounds);
    await syncImageOverlay('zones', widget.showZones, widget.zonesBytes, widget.zonesBounds);
    await syncImageOverlay('dem', widget.showDem, widget.demBytes, widget.demBounds);

    await _syncMeasureOverlays();
  }

  Future<void> _syncMeasureOverlays() async {
    if (_controller == null) return;
    try {
      await _controller!.removeLayer('measure-path-layer');
      await _controller!.removeLayer('measure-fill-layer');
      await _controller!.removeLayer('measure-outline-layer');
      await _controller!.removeLayer('measure-points-layer');
      await _controller!.removeSource('measure-line');
      await _controller!.removeSource('measure-poly');
      await _controller!.removeSource('measure-points');
    } catch (_) {}

    if (!widget.measureActive || widget.measurePoints.isEmpty) return;

    final pts = widget.measurePoints;
    final coords = pts.map((p) => [p.longitude, p.latitude]).toList();

    // Two corners: open line only. Three+: closed polygon (outline + fill).
    if (pts.length == 2) {
      await _controller!.addGeoJsonSource('measure-line', {
        'type': 'Feature',
        'geometry': {
          'type': 'LineString',
          'coordinates': coords,
        },
      });
      await _controller!.addLineLayer(
        'measure-line',
        'measure-path-layer',
        LineLayerProperties(
          lineColor: '#FFA000',
          lineWidth: 4.0,
        ),
      );
    }
    if (pts.length >= 3) {
      final polyCoords = [...coords, coords.first];
      await _controller!.addGeoJsonSource('measure-poly', {
        'type': 'Feature',
        'geometry': {
          'type': 'Polygon',
          'coordinates': [polyCoords],
        },
      });
      await _controller!.addFillLayer(
        'measure-poly',
        'measure-fill-layer',
        FillLayerProperties(
          fillColor: '#FFA000',
          fillOpacity: 0.35,
        ),
      );
      await _controller!.addLineLayer(
        'measure-poly',
        'measure-outline-layer',
        LineLayerProperties(
          lineColor: '#FFA000',
          lineWidth: 2.0,
        ),
      );
    }

    await _controller!.addGeoJsonSource('measure-points', {
      'type': 'FeatureCollection',
      'features': coords
          .map(
            (c) => {
              'type': 'Feature',
              'geometry': {
                'type': 'Point',
                'coordinates': c,
              },
            },
          )
          .toList(),
    });
    await _controller!.addCircleLayer(
      'measure-points',
      'measure-points-layer',
      CircleLayerProperties(
        circleColor: '#FFFFFF',
        circleRadius: 6.0,
        circleStrokeColor: '#FFA000',
        circleStrokeWidth: 2.0,
      ),
    );
  }

  void _onMapClick(math.Point<double> point, LatLng coordinates) {
    if (!widget.measureActive || widget.onMeasureVertexAdded == null) return;
    widget.onMeasureVertexAdded!(coordinates);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 360,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            KeyedSubtree(
              key: _mapRenderKey,
              child: MapLibreMap(
                    initialCameraPosition: CameraPosition(
                      target: widget.center,
                      zoom: 16.0,
                    ),
                    styleString: _getStyleString(),
                    // Pinch/pan vs parent ListView. Each [Factory] must use a *concrete*
                    // recognizer type — `Factory.type` is the generic T; using
                    // `Factory<OneSequenceGestureRecognizer>(...)` for every entry makes
                    // duplicate types and triggers a platform_view assertion crash.
                    gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                      // Pan + scale: required for one-finger pan and pinch-zoom inside ListView.
                      Factory<PanGestureRecognizer>(() => PanGestureRecognizer()),
                      Factory<ScaleGestureRecognizer>(() => ScaleGestureRecognizer()),
                      Factory<VerticalDragGestureRecognizer>(
                        () => VerticalDragGestureRecognizer(),
                      ),
                      Factory<HorizontalDragGestureRecognizer>(
                        () => HorizontalDragGestureRecognizer(),
                      ),
                    },
                    minMaxZoomPreference: const MinMaxZoomPreference(2.0, 22.0),
                    onMapCreated: (c) {
                      _controller = c;
                    },
                    onStyleLoadedCallback: () {
                      _styleLoaded = true;
                      unawaited(_syncLayers());
                      if (!_didFitInitialCamera && widget.bounds != null) {
                        _didFitInitialCamera = true;
                        _controller?.animateCamera(
                          CameraUpdate.newLatLngBounds(widget.bounds!),
                        );
                      }
                    },
                    onMapClick: _onMapClick,
                    // Avoid permission / native my-location crashes when not using device GPS.
                    myLocationEnabled: false,
                  ),
                ),
              ],
            ),
          ),
        );
  }
}
