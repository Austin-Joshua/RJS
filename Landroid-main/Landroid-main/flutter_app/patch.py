import re

with open('lib/src/screens/map_screen.dart', 'r', encoding='utf-8') as f:
    code = f.read()

code = code.replace(
    "import 'package:flutter_map/flutter_map.dart';\nimport 'package:latlong2/latlong.dart';",
    "import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;\nimport 'maplibre_view.dart';"
)

code = code.replace('  final MapController _mapController = MapController();\n', '')

old_cb = '''  LatLngBounds? _cameraBounds(_MapPayload payload, Map<String, dynamic> m) {
    if (payload.ndvi != null) {
      return LatLngBounds(
        LatLng(payload.ndvi!.south, payload.ndvi!.west),
        LatLng(payload.ndvi!.north, payload.ndvi!.east),
      );
    }
    final bb = m['bbox'] as Map<String, dynamic>?;
    if (bb == null) {
      return null;
    }
    final west = (bb['min_lng'] as num).toDouble();
    final south = (bb['min_lat'] as num).toDouble();
    final east = (bb['max_lng'] as num).toDouble();
    final north = (bb['max_lat'] as num).toDouble();
    return LatLngBounds(LatLng(south, west), LatLng(north, east));
  }'''
new_cb = '''  maplibre.LatLngBounds? _cameraBounds(_MapPayload payload, Map<String, dynamic> m) {
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
  }'''
code = code.replace(old_cb, new_cb)

old_ring = '''  List<LatLng> _outerRing(Map<String, dynamic> manifest) {
    final bg = manifest['boundary_geojson'] as Map<String, dynamic>?;
    final feats = bg?['features'] as List<dynamic>?;
    if (feats == null || feats.isEmpty) {
      return [];
    }
    final geom = feats.first['geometry'] as Map<String, dynamic>?;
    final coords = geom?['coordinates'] as List<dynamic>?;
    if (coords == null || coords.isEmpty) {
      return [];
    }
    final ring = coords.first as List<dynamic>;
    return ring
        .map((p) {
          final c = p as List<dynamic>;
          return LatLng(
            (c[1] as num).toDouble(),
            (c[0] as num).toDouble(),
          );
        })
        .toList();
  }'''
new_ring = '''  List<maplibre.LatLng> _outerRing(Map<String, dynamic> manifest) {
    return []; // Handled internally by maplibre_view now using GeoJSON directly
  }'''
code = code.replace(old_ring, new_ring)

code = code.replace('final center = LatLng(lat, lng);', 'final center = maplibre.LatLng(lat, lng);')

old_body = '''        final mapChildren = <Widget>[
          TileLayer(
            urlTemplate: _showSatellite
                ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'landroid.flutter',
          ),
          if (orthoTile != null && _showOrtho)
            Opacity(
              opacity: 0.92,
              child: TileLayer(
                urlTemplate: orthoTile.urlTemplate,
                tms: orthoTile.tms,
                userAgentPackageName: 'landroid.flutter',
                tileBounds: parcelTileBounds,
              ),
            ),
          if (demTile != null && _showDem)
            Opacity(
              opacity: 0.72,
              child: TileLayer(
                urlTemplate: demTile.urlTemplate,
                tms: demTile.tms,
                userAgentPackageName: 'landroid.flutter',
                tileBounds: parcelTileBounds,
              ),
            ),
          if (payload.demLocal != null && _showDem && demTile == null)
            OverlayImageLayer(
              overlayImages: [
                OverlayImage(
                  bounds: LatLngBounds(
                    LatLng(payload.demLocal!.south, payload.demLocal!.west),
                    LatLng(payload.demLocal!.north, payload.demLocal!.east),
                  ),
                  imageProvider: MemoryImage(payload.demLocal!.bytes),
                  opacity: 0.78,
                ),
              ],
            ),
          if (payload.ndvi != null && _showNdvi)
            OverlayImageLayer(
              overlayImages: [
                OverlayImage(
                  bounds: LatLngBounds(
                    LatLng(payload.ndvi!.south, payload.ndvi!.west),
                    LatLng(payload.ndvi!.north, payload.ndvi!.east),
                  ),
                  imageProvider: MemoryImage(payload.ndvi!.bytes),
                  opacity: 0.92,
                ),
              ],
            ),
          if (payload.zones != null && _showZones)
            OverlayImageLayer(
              overlayImages: [
                OverlayImage(
                  bounds: LatLngBounds(
                    LatLng(payload.zones!.south, payload.zones!.west),
                    LatLng(payload.zones!.north, payload.zones!.east),
                  ),
                  imageProvider: MemoryImage(payload.zones!.bytes),
                  opacity: 0.88,
                ),
              ],
            ),
          if (ring.length >= 3 && _showBoundary)
            PolygonLayer(
              polygons: [
                Polygon(
                  points: ring,
                  color: theme.colorScheme.tertiary.withValues(alpha: 0.12),
                  borderColor: theme.colorScheme.tertiary,
                  borderStrokeWidth: 3,
                ),
              ],
            ),
          RichAttributionWidget(
            attributions: [
              TextSourceAttribution(
                _showSatellite ? 'Esri World Imagery' : 'OpenStreetMap',
                onTap: () {},
              ),
            ],
          ),
        ];'''
code = code.replace(old_body, '')

old_fmap = '''              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                  height: 360,
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: center,
                      initialZoom: 16,
                      initialCameraFit: fitBounds != null
                          ? CameraFit.bounds(
                              bounds: fitBounds,
                              padding: const EdgeInsets.all(28),
                              maxZoom: 18,
                            )
                          : null,
                      minZoom: 3,
                      maxZoom: 22,
                    ),
                    children: mapChildren,
                  ),
                ),
              ),'''
new_fmap = '''              child: MapLibreView(
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
              ),'''
code = code.replace(old_fmap, new_fmap)

with open('lib/src/screens/map_screen.dart', 'w', encoding='utf-8') as f:
    f.write(code)
print("done")
