import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Bundled Kallapuram sample field (from Boundary.geojson + Orthomosaic.tif).
class DemoFieldAssets {
  const DemoFieldAssets({
    required this.name,
    required this.citation,
    required this.centroid,
    required this.polygon,
    required this.orthoBounds,
  });

  final String name;
  final String citation;
  final LatLng centroid;
  final List<LatLng> polygon;
  final LatLngBounds orthoBounds;

  static const orthoAsset = 'assets/demo/orthomosaic_preview.png';
  static const demAsset = 'assets/demo/dem_hillshade_preview.png';
  static const citationsAsset = 'assets/demo/citations.json';

  static Future<DemoFieldAssets> load() async {
    final boundary = jsonDecode(await rootBundle.loadString('assets/demo/kallapuram_boundary.geojson')) as Map<String, dynamic>;
    final boundsJson = jsonDecode(await rootBundle.loadString('assets/demo/orthomosaic_bounds.json')) as Map<String, dynamic>;

    final ring = (boundary['geometry'] as Map)['coordinates'][0] as List;
    final polygon = [
      for (final c in ring) LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
    ];
    final c = boundary['centroid'] as Map<String, dynamic>;
    final props = boundary['properties'] as Map<String, dynamic>? ?? {};

    return DemoFieldAssets(
      name: (props['name'] as String?) ?? 'Kallapuram field',
      citation: (props['citation'] as String?) ?? 'Kallapuram_Actual.geojson',
      centroid: LatLng((c['lat'] as num).toDouble(), (c['lon'] as num).toDouble()),
      polygon: polygon,
      orthoBounds: LatLngBounds(
        LatLng((boundsJson['south'] as num).toDouble(), (boundsJson['west'] as num).toDouble()),
        LatLng((boundsJson['north'] as num).toDouble(), (boundsJson['east'] as num).toDouble()),
      ),
    );
  }

  static Future<List<({String label, String citation})>> loadCitations() async {
    final raw = jsonDecode(await rootBundle.loadString(citationsAsset)) as Map<String, dynamic>;
    final sources = raw['sources'] as List<dynamic>;
    return [
      for (final s in sources)
        (label: (s as Map)['label'] as String, citation: s['citation'] as String),
    ];
  }
}
