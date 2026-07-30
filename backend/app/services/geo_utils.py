"""Boundary polygon -> centroid + area (FR-12). ponytail: uses a flat
equirectangular projection (fine at few-acre field scale) rather than a
proper UTM/geodesic area calc. Upgrade path: PostGIS `geography` type +
`ST_Area`/`ST_Centroid` once the deployment target is fixed to Postgres
(see the note in app/db/models.py)."""
import math
from typing import Any

from shapely.geometry import Polygon, shape

EARTH_RADIUS_M = 6_371_000.0


def compute_centroid_and_area(boundary_geojson: dict[str, Any]) -> tuple[float, float, float]:
    polygon = shape(boundary_geojson)
    centroid = polygon.centroid
    lat, lon = centroid.y, centroid.x

    lat_rad = math.radians(lat)

    def to_xy(pt: tuple[float, float]) -> tuple[float, float]:
        x = math.radians(pt[0]) * EARTH_RADIUS_M * math.cos(lat_rad)
        y = math.radians(pt[1]) * EARTH_RADIUS_M
        return x, y

    projected = Polygon([to_xy(pt) for pt in polygon.exterior.coords])
    area_ha = abs(projected.area) / 10_000
    return lat, lon, round(area_ha, 4)
