"""Load Birdscale boundary GeoJSON and expose WGS84 geometry + metrics."""

from __future__ import annotations

import json
import math
from pathlib import Path
from typing import Any

from pyproj import Transformer

from .config import BOUNDARY_FILENAME, DATA_DIR


def _ring_area_deg2(ring: list[list[float]]) -> float:
    """Shoelace area in degree² (approximate for small parcels)."""
    if len(ring) < 3:
        return 0.0
    s = 0.0
    for i in range(len(ring) - 1):
        x1, y1 = ring[i][0], ring[i][1]
        x2, y2 = ring[i + 1][0], ring[i + 1][1]
        s += x1 * y2 - x2 * y1
    return abs(s) * 0.5


def _linestring_to_closed_ring(coords: list[list[float]]) -> list[list[float]]:
    c = [[float(p[0]), float(p[1])] for p in coords]
    if len(c) >= 2 and (c[0][0] != c[-1][0] or c[0][1] != c[-1][1]):
        c = c + [c[0]]
    return c


def parse_geojson_object_to_boundary(raw: dict[str, Any]) -> dict[str, Any]:
    """Parse a GeoJSON FeatureCollection or single Feature (same output shape as [load_boundary_wgs84])."""
    crs_name = (
        raw.get("crs", {})
        .get("properties", {})
        .get("name", "urn:ogc:def:crs:EPSG::4326")
    )
    src_epsg = 4326
    if "32643" in crs_name:
        src_epsg = 32643
    transformer = Transformer.from_crs(
        f"EPSG:{src_epsg}", "EPSG:4326", always_xy=True
    )

    feats: list[dict[str, Any]]
    if raw.get("type") == "FeatureCollection":
        feats = raw.get("features") or []
    elif raw.get("type") == "Feature":
        feats = [raw]
    else:
        raise ValueError("GeoJSON must be a FeatureCollection or Feature")

    if not feats:
        raise ValueError("Boundary GeoJSON has no features")

    geom = feats[0].get("geometry") or {}
    gtype = geom.get("type")
    coords = geom.get("coordinates")

    rings_wgs84: list[list[list[float]]] = []

    if gtype == "Polygon" and coords:
        for ring in coords:
            rings_wgs84.append(
                [list(transformer.transform(p[0], p[1])) for p in ring]
            )
    elif gtype == "LineString" and coords:
        ring = _linestring_to_closed_ring(
            [list(transformer.transform(p[0], p[1])) for p in coords]
        )
        rings_wgs84.append(ring)
    else:
        raise ValueError(f"Unsupported geometry type: {gtype}")

    outer = rings_wgs84[0]
    xs = [p[0] for p in outer]
    ys = [p[1] for p in outer]
    min_lng, max_lng = min(xs), max(xs)
    min_lat, max_lat = min(ys), max(ys)
    centroid_lng = sum(xs) / len(xs)
    centroid_lat = sum(ys) / len(ys)

    area_deg2 = _ring_area_deg2(outer)
    lat_rad = math.radians(centroid_lat)
    m_per_deg_lat = 111_320.0
    m_per_deg_lng = 111_320.0 * math.cos(lat_rad)
    area_m2 = area_deg2 * m_per_deg_lat * m_per_deg_lng
    acres = area_m2 / 4046.8564224

    feature = {
        "type": "Feature",
        "properties": {"name": "parcel_boundary"},
        "geometry": {"type": "Polygon", "coordinates": rings_wgs84},
    }
    collection: dict[str, Any] = {
        "type": "FeatureCollection",
        "features": [feature],
    }

    return {
        "geojson": collection,
        "centroid": {"lng": centroid_lng, "lat": centroid_lat},
        "bbox": {
            "min_lng": min_lng,
            "min_lat": min_lat,
            "max_lng": max_lng,
            "max_lat": max_lat,
        },
        "area_acres_approx": round(acres, 4),
    }


def load_boundary_wgs84() -> dict[str, Any]:
    path = DATA_DIR / BOUNDARY_FILENAME
    if not path.is_file():
        raise FileNotFoundError(f"Boundary not found: {path}")

    raw = json.loads(path.read_text(encoding="utf-8"))
    return parse_geojson_object_to_boundary(raw)


def geodesic_boundary_metrics(geojson_fc: dict[str, Any]) -> dict[str, float]:
    """
    Geodesic area (m²) and perimeter (m) for the outer ring of the first polygon feature.
    Uses WGS84 (same ellipsoid as Google Earth Engine geometry operations).
    """
    from pyproj import Geod

    feats = geojson_fc.get("features") or []
    if not feats:
        return {"area_m2": 0.0, "perimeter_m": 0.0}
    geom = feats[0].get("geometry") or {}
    coords = geom.get("coordinates")
    if geom.get("type") != "Polygon" or not coords:
        return {"area_m2": 0.0, "perimeter_m": 0.0}
    ring = coords[0]
    lons = [float(p[0]) for p in ring]
    lats = [float(p[1]) for p in ring]
    geod = Geod(ellps="WGS84")
    area_m2, perim_m = geod.polygon_area_perimeter(lons, lats)
    return {
        "area_m2": abs(float(area_m2)),
        "perimeter_m": abs(float(perim_m)),
    }


def parse_boundary_geojson_bytes(raw: bytes) -> dict[str, Any]:
    try:
        obj = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as e:
        raise ValueError("boundary must be valid UTF-8 GeoJSON") from e
    if not isinstance(obj, dict):
        raise ValueError("GeoJSON root must be an object")
    return parse_geojson_object_to_boundary(obj)
