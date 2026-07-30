"""Sentinel-2 NDVI via Google Earth Engine (FR-22, TRD §3.3).

Never raises to the caller: any import/auth/quota failure returns None and
the fusion service flips `data_mode` to "degraded" per FR-23. This is the
adapter most likely to be unusable in an environment without a provisioned
GEE service account — that is an accepted, designed-for failure mode, not a
bug.
"""
import math
from datetime import datetime, timezone
from functools import lru_cache

from app.core.cache import ndvi_cache
from app.core.config import get_settings

CLOUD_PIXEL_PCT_MAX = 40
MIN_CLEAR_SCENES = 2


@lru_cache
def _ee_module_or_none():
    try:
        import ee  # type: ignore

        return ee
    except ImportError:
        return None


@lru_cache
def _init_earth_engine() -> bool:
    ee = _ee_module_or_none()
    settings = get_settings()
    if ee is None or not settings.google_application_credentials or not settings.gee_project_id:
        return False
    try:
        credentials = ee.ServiceAccountCredentials(
            email=None, key_file=settings.google_application_credentials
        )
        ee.Initialize(credentials, project=settings.gee_project_id)
        return True
    except Exception:  # noqa: BLE001 — any GEE init failure just disables NDVI
        return False


def is_earth_engine_ready() -> bool:
    return _init_earth_engine()


def _cloud_masked_collection(ee, boundary, start_date: str, end_date: str):
    def mask_scl(image):
        scl = image.select("SCL")
        mask = scl.neq(3).And(scl.neq(8)).And(scl.neq(9)).And(scl.neq(10))
        ndvi = image.normalizedDifference(["B8", "B4"]).rename("NDVI")
        return image.addBands(ndvi).updateMask(mask)

    return (
        ee.ImageCollection("COPERNICUS/S2_SR_HARMONIZED")
        .filterBounds(boundary)
        .filterDate(start_date, end_date)
        .filter(ee.Filter.lt("CLOUDY_PIXEL_PERCENTAGE", CLOUD_PIXEL_PCT_MAX))
        .map(mask_scl)
    )


def get_ndvi_features(boundary_geojson: dict, start_date: str, end_date: str) -> dict | None:
    """Returns ndvi_mean/max/p90/slope_30d/auc, or None if degraded (FR-23/34)."""
    cache_key = (str(boundary_geojson), start_date, end_date)
    if cache_key in ndvi_cache:
        return ndvi_cache[cache_key]

    if not _init_earth_engine():
        return None

    ee = _ee_module_or_none()
    try:
        boundary = ee.Geometry(boundary_geojson)
        collection = _cloud_masked_collection(ee, boundary, start_date, end_date)
        scene_count = collection.size().getInfo()
        if scene_count < MIN_CLEAR_SCENES:
            return None

        def reduce_mean(image):
            stat = image.select("NDVI").reduceRegion(ee.Reducer.mean(), boundary, 20)
            return image.set("ndvi_mean", stat.get("NDVI"))

        series = collection.map(reduce_mean)
        values = series.aggregate_array("ndvi_mean").getInfo()
        dates = series.aggregate_array("system:time_start").getInfo()
        values = [v for v in values if v is not None]
        if len(values) < MIN_CLEAR_SCENES:
            return None

        recent = sorted(zip(dates, values))[-6:]  # ~last 30 days at 5-day revisit
        slope_30d = _ols_slope([t for t, _ in recent], [v for _, v in recent]) if len(recent) >= 2 else 0.0
        sorted_vals = sorted(values)
        p90_idx = max(0, int(0.9 * (len(sorted_vals) - 1)))

        result = {
            "ndvi_mean": round(sum(values) / len(values), 4),
            "ndvi_max": round(max(values), 4),
            "ndvi_p90": round(sorted_vals[p90_idx], 4),
            "ndvi_slope_30d": round(slope_30d, 6),
            "ndvi_auc": round(_trapezoidal_auc(dates, values), 2),
            "scene_count": scene_count,
            "source": "sentinel2_gee",
            "fetched_at": datetime.now(timezone.utc).isoformat(),
        }
        ndvi_cache[cache_key] = result
        return result
    except Exception:  # noqa: BLE001 — any GEE runtime error degrades, never raises
        return None


def get_ndvi_png(boundary_geojson: dict, start_date: str, end_date: str) -> tuple[bytes, list[float]] | None:
    """Renders a mean-NDVI thumbnail PNG for the boundary (FR-25). Returns
    (png_bytes, [west, south, east, north]) or None if degraded."""
    if not _init_earth_engine():
        return None
    ee = _ee_module_or_none()
    try:
        import httpx

        boundary = ee.Geometry(boundary_geojson)
        collection = _cloud_masked_collection(ee, boundary, start_date, end_date)
        mean_ndvi = collection.select("NDVI").mean().clip(boundary)
        vis_params = {"min": 0.0, "max": 0.9, "palette": ["a50026", "fee08b", "1a9850"]}
        url = mean_ndvi.getThumbURL({**vis_params, "region": boundary, "dimensions": 512, "format": "png"})
        resp = httpx.get(url, timeout=15.0)
        resp.raise_for_status()
        bounds = boundary.bounds().coordinates().getInfo()[0]
        lons = [c[0] for c in bounds]
        lats = [c[1] for c in bounds]
        return resp.content, [min(lons), min(lats), max(lons), max(lats)]
    except Exception:  # noqa: BLE001
        return None


def get_ndvi_series(boundary_geojson: dict, start_date: str, end_date: str) -> list[dict] | None:
    if not _init_earth_engine():
        return None
    ee = _ee_module_or_none()
    try:
        boundary = ee.Geometry(boundary_geojson)
        collection = _cloud_masked_collection(ee, boundary, start_date, end_date)

        def reduce_mean(image):
            stat = image.select("NDVI").reduceRegion(ee.Reducer.mean(), boundary, 20)
            return image.set("ndvi_mean", stat.get("NDVI")).set("date", image.date().format("YYYY-MM-dd"))

        series = collection.map(reduce_mean)
        dates = series.aggregate_array("date").getInfo()
        values = series.aggregate_array("ndvi_mean").getInfo()
        return [{"date": d, "ndvi_mean": v} for d, v in zip(dates, values)]
    except Exception:  # noqa: BLE001
        return None


def _ols_slope(xs: list[float], ys: list[float]) -> float:
    n = len(xs)
    if n < 2:
        return 0.0
    x0 = xs[0]
    xs = [(x - x0) / 86_400_000 for x in xs]  # ms -> days
    mean_x, mean_y = sum(xs) / n, sum(ys) / n
    num = sum((x - mean_x) * (y - mean_y) for x, y in zip(xs, ys))
    den = sum((x - mean_x) ** 2 for x in xs)
    return num / den if den else 0.0


def _trapezoidal_auc(dates_ms: list[int], values: list[float]) -> float:
    pairs = sorted(zip(dates_ms, values))
    auc = 0.0
    for (t0, v0), (t1, v1) in zip(pairs, pairs[1:]):
        dt_days = (t1 - t0) / 86_400_000
        auc += dt_days * (v0 + v1) / 2
    return auc if auc == auc else math.nan  # NaN-safe no-op guard
