"""Three-source data fusion — soil + weather + NDVI (FR-20..25, TRD §3).

Sources are fetched concurrently (NFR-03). `data_mode` is derived, never
hand-set: "demo" under DEMO_MODE, "live" when all three sources returned a
value, "degraded" otherwise — surfaced to the UI, never hidden (FR-23).
"""
import asyncio
import json
from datetime import date, datetime, timedelta, timezone
from typing import Any

from app.adapters import ndvi_gee, soil_shc, weather_openmeteo
from app.core.config import get_settings
from app.services import raster_ndvi


def determine_season(sowing_date: str | None) -> str:
    if not sowing_date:
        return "kharif"
    month = date.fromisoformat(sowing_date).month
    if month in (6, 7):
        return "kuruvai"
    if month in (8, 9):
        return "samba"
    if month in (10, 11, 12, 1):
        return "rabi"
    return "kharif"


def season_start(sowing_date: str | None) -> str:
    return sowing_date or (date.today() - timedelta(days=90)).isoformat()


def _load_demo_fixture() -> dict[str, Any]:
    settings = get_settings()
    path = settings.data_dir / "fixtures" / "signals_demo.json"
    with open(path, encoding="utf-8") as f:
        return json.load(f)


async def fuse_field(
    *,
    district: str,
    lat: float,
    lon: float,
    sowing_date: str | None,
    boundary_geojson: dict[str, Any],
    soil_override: dict[str, Any] | None = None,
    active_raster_ndvi: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """`active_raster_ndvi` is the cached `zonal_ndvi` JSON from the field's
    active uploaded raster (see app/db/models.py RasterAsset) — a ground-truth
    drone/orthomosaic NDVI blended with the satellite value, never a live
    rasterio recompute on this hot path."""
    settings = get_settings()
    if settings.demo_mode:
        fixture = _load_demo_fixture()
        fixture["data_mode"] = "demo"
        fixture["season"] = determine_season(sowing_date)
        fixture["fetched_at"] = datetime.now(timezone.utc).isoformat()
        return fixture

    start = season_start(sowing_date)
    end = date.today().isoformat()

    soil = soil_override or soil_shc.get_soil_baseline(district)

    weather, ndvi = await asyncio.gather(
        weather_openmeteo.get_weather_features(lat, lon, sowing_date),
        asyncio.to_thread(ndvi_gee.get_ndvi_features, boundary_geojson, start, end),
    )

    # data_mode reflects the three required sources only (FR-23) — an
    # uploaded raster is a value refinement on top of NDVI, not a fourth
    # required source, so its absence never degrades data_mode.
    data_mode = "live" if soil is not None and weather is not None and ndvi is not None else "degraded"

    ndvi_out = dict(ndvi) if ndvi else {}
    ndvi_provenance: dict[str, Any] = {
        "source": (ndvi or {}).get("source"),
        "fetched_at": (ndvi or {}).get("fetched_at"),
        "scene_count": (ndvi or {}).get("scene_count", 0),
    }
    if active_raster_ndvi is not None:
        gee_mean = (ndvi or {}).get("ndvi_mean")
        blended_mean, blend_meta = raster_ndvi.blend_ndvi(
            gee_mean, active_raster_ndvi, settings.raster_ndvi_blend_weight
        )
        if blended_mean is not None:
            ndvi_out["ndvi_mean_satellite"] = gee_mean
            ndvi_out["ndvi_mean_raster"] = active_raster_ndvi.get("mean_ndvi")
            ndvi_out["ndvi_mean"] = blended_mean
            ndvi_out["source"] = f"{ndvi_provenance['source'] or 'unavailable'}+drone_raster_blend"
        ndvi_provenance["blend_weight_raster"] = blend_meta["blend_weight_raster"]
        ndvi_provenance["raster"] = blend_meta["raster"]

    provenance = {
        "soil": {"source": (soil or {}).get("source"), "fetched_at": (soil or {}).get("fetched_at")},
        "weather": {"source": (weather or {}).get("source"), "fetched_at": (weather or {}).get("fetched_at")},
        "ndvi": ndvi_provenance,
    }

    return {
        "soil": soil or {},
        "weather": weather or {},
        "ndvi": ndvi_out,
        "data_mode": data_mode,
        "provenance": provenance,
        "season": determine_season(sowing_date),
        "fetched_at": datetime.now(timezone.utc).isoformat(),
    }
