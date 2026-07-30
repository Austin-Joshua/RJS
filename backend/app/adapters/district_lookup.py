"""Offline centroid -> district/state resolution (FR-13). No network calls.

ponytail: `data/geo/district_boundaries.geojson` bundles simplified bounding
boxes for the five demo districts, not the full national shapefile the TRD
describes. Upgrade path: drop in the real simplified national
`district_boundaries.geojson` — the shapely `contains` lookup below is
already written against that contract and needs no changes.
"""
import json
from functools import lru_cache

from shapely.geometry import Point, shape

from app.core.config import get_settings


@lru_cache
def _load_districts() -> list[dict]:
    settings = get_settings()
    path = settings.data_dir / "geo" / "district_boundaries.geojson"
    with open(path, encoding="utf-8") as f:
        geojson = json.load(f)
    return [
        {
            "district": feat["properties"]["district"],
            "state": feat["properties"]["state"],
            "polygon": shape(feat["geometry"]),
        }
        for feat in geojson["features"]
    ]


def resolve_district(lat: float, lon: float) -> tuple[str, str] | None:
    """Return (district, state) for a centroid, or None if outside all bundled polygons."""
    point = Point(lon, lat)
    for entry in _load_districts():
        if entry["polygon"].contains(point):
            return entry["district"], entry["state"]

    # Fall back to nearest bundled district centroid rather than failing the
    # field-creation flow outright — the demo region is small and this keeps
    # onboarding usable near (but not inside) a bundled boundary.
    nearest = min(_load_districts(), key=lambda e: point.distance(e["polygon"].centroid))
    return nearest["district"], nearest["state"]
