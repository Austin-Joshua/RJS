import 'package:maplibre_gl/maplibre_gl.dart' as m;
import 'package:maps_toolkit/maps_toolkit.dart' as mp;

/// Total geodesic length along the polyline (WGS84), in meters.
double polylineLengthMeters(List<m.LatLng> points) {
  if (points.length < 2) return 0;
  final pts = points.map((p) => mp.LatLng(p.latitude, p.longitude)).toList();
  return mp.SphericalUtil.computeLength(pts).toDouble();
}

/// Geodesic area inside the closed ring (WGS84), in m².
double polygonAreaM2(List<m.LatLng> points) {
  if (points.length < 3) return 0;
  var ring = points.map((p) => mp.LatLng(p.latitude, p.longitude)).toList();
  final first = ring.first;
  final last = ring.last;
  if (first.latitude != last.latitude || first.longitude != last.longitude) {
    ring = [...ring, first];
  }
  return mp.SphericalUtil.computeArea(ring).abs().toDouble();
}

String formatDistanceMeters(double m) {
  if (m < 1) {
    return '${(m * 100).toStringAsFixed(0)} cm';
  }
  if (m < 1000) {
    return '${m.toStringAsFixed(1)} m';
  }
  return '${(m / 1000).toStringAsFixed(2)} km';
}

String formatAreaM2(double m2) {
  if (m2 < 10000) {
    return '${m2.toStringAsFixed(0)} m²';
  }
  return '${(m2 / 10000).toStringAsFixed(2)} ha';
}
