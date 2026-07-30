import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;

import '../api/client.dart';

/// Builds PNG overlays in-app when the API layer images are unavailable (e.g. wrong
/// ``API_BASE_URL``, USB reverse not set, or offline). Uses the same WGS84 bbox
/// as the map manifest so toggles and [OverlayImageLayer] still work.
Future<ParcelLayerOverlay?> buildLocalNdviPlaceholder({
  required double west,
  required double south,
  required double east,
  required double north,
}) async {
  const w = 256;
  const h = 256;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  for (var x = 0; x < w; x++) {
    final t = x / (w - 1);
    final c = Color.lerp(const Color(0xFFB71C1C), const Color(0xFF1B5E20), t)!;
    final paint = Paint()..color = c.withValues(alpha: 0.85);
    canvas.drawRect(Rect.fromLTWH(x.toDouble(), 0, 1, h.toDouble()), paint);
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(w, h);
  final bd = await image.toByteData(format: ui.ImageByteFormat.png);
  if (bd == null) {
    return null;
  }
  return ParcelLayerOverlay(
    bytes: bd.buffer.asUint8List(),
    west: west,
    south: south,
    east: east,
    north: north,
    source: 'local_fallback',
  );
}

Future<ParcelLayerOverlay?> buildLocalZonesPlaceholder({
  required double west,
  required double south,
  required double east,
  required double north,
}) async {
  const w = 256;
  const h = 256;
  const colors = <Color>[
    Color(0xFF8B0000),
    Color(0xFFDAA520),
    Color(0xFF32CD32),
    Color(0xFF006400),
  ];
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final bh = h ~/ 4;
  for (var i = 0; i < 4; i++) {
    final y0 = i * bh;
    final y1 = i == 3 ? h : (i + 1) * bh;
    final paint = Paint()..color = colors[i].withValues(alpha: 0.85);
    canvas.drawRect(
      Rect.fromLTWH(0, y0.toDouble(), w.toDouble(), (y1 - y0).toDouble()),
      paint,
    );
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(w, h);
  final bd = await image.toByteData(format: ui.ImageByteFormat.png);
  if (bd == null) {
    return null;
  }
  return ParcelLayerOverlay(
    bytes: bd.buffer.asUint8List(),
    west: west,
    south: south,
    east: east,
    north: north,
    source: 'local_fallback',
  );
}

/// Parcel bounding box for restricting XYZ tile loading (optional).
maplibre.LatLngBounds? latLngBoundsFromManifest(Map<String, dynamic> manifest) {
  final b = manifestBBox(manifest);
  if (b == null) {
    return null;
  }
  return maplibre.LatLngBounds(
    southwest: maplibre.LatLng(b.south, b.west),
    northeast: maplibre.LatLng(b.north, b.east),
  );
}

/// Orthomosaic / DEM entry from ``map-manifest`` ``layers.*``.
class ManifestTileLayer {
  const ManifestTileLayer({
    required this.urlTemplate,
    required this.tms,
  });

  final String urlTemplate;
  final bool tms;
}

ManifestTileLayer? parseManifestTileLayer(Map<String, dynamic>? layer) {
  if (layer == null) {
    return null;
  }
  if (layer['available'] != true) {
    return null;
  }
  final url = layer['cog_tile_url_template'];
  if (url is! String || url.isEmpty) {
    return null;
  }
  final scheme = (layer['tile_scheme'] as String? ?? 'xyz').toLowerCase();
  return ManifestTileLayer(
    urlTemplate: url,
    tms: scheme == 'tms',
  );
}

/// Reads [manifest] ``bbox`` from map-manifest JSON.
({double west, double south, double east, double north})? manifestBBox(
  Map<String, dynamic> manifest,
) {
  final bb = manifest['bbox'];
  if (bb is! Map<String, dynamic>) {
    return null;
  }
  final west = (bb['min_lng'] as num?)?.toDouble();
  final south = (bb['min_lat'] as num?)?.toDouble();
  final east = (bb['max_lng'] as num?)?.toDouble();
  final north = (bb['max_lat'] as num?)?.toDouble();
  if (west == null || south == null || east == null || north == null) {
    return null;
  }
  return (west: west, south: south, east: east, north: north);
}
