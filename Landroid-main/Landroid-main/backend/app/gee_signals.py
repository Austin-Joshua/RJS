"""
FR-18–20: Land signals from Google Earth Engine using catalog datasets:

- NDVI: COPERNICUS/S2_SR_HARMONIZED (Sentinel-2 L2A SR). Cloud mask: QA60 bits 10/11
  plus SCL vegetation/bare (see dataset docs). NDVI = (NIR-Red)/(NIR+Red) = B8/B4.
  https://developers.google.com/earth-engine/datasets/catalog/COPERNICUS_S2_SR_HARMONIZED

- Rainfall: UCSB-CHG/CHIRPS/DAILY (~5.5 km). Point samples at parcel centroid (FR-19).
  https://developers.google.com/earth-engine/datasets/catalog/UCSB-CHG_CHIRPS_DAILY

- Temperature: ECMWF/ERA5_LAND/MONTHLY_AGGR and ECMWF/ERA5_LAND/DAILY_AGGR (~11 km).
  Regional aggregation over parcel bounding box (FR-20). Heat stress: daily Tmax > 35 °C
  at centroid (documented as coarse reanalysis, not in-situ parcel weather).
  https://developers.google.com/earth-engine/datasets/catalog/ECMWF_ERA5_LAND_MONTHLY_AGGR
  https://developers.google.com/earth-engine/datasets/catalog/ECMWF_ERA5_LAND_DAILY_AGGR

Limitations (must not be over-interpreted):
- CHIRPS / ERA5 cells are much larger than small parcels; values are neighborhood climate,
  not a ground-truth rain gauge or thermometer on the field.
- Sentinel-2 NDVI can be missing in persistent cloud season; we report confidence from
  usable image counts.

When a Birdscale / local NDVI GeoTIFF is available (see ``birdscale_ndvi``), the reported
``current`` NDVI can be blended with Sentinel-2 (``LANDROID_NDVI_BLEND_WEIGHT``).

**What is “validated” with periodic EE values?** The land-health API NDVI block
(``current``, ``two_year_mean``, ``monthly_trend``, confidence, granule counts) is
computed here from masked Sentinel-2 composites over time. The **map PNG** in the app
is a separate pipeline: it is colored from an uploaded/local GeoTIFF (``raster_layers_render``),
not from EE’s ``getMapId`` tiles—so the dashboard time series and the map image can differ
if the GeoTIFF is from another sensor/date.
"""

from __future__ import annotations

import math
from datetime import datetime, timedelta, timezone
from typing import Any

import ee

from .birdscale_ndvi import blend_ndvi_current, sample_parcel_mean_ndvi
from .parcel_store import ParcelRecord


def _parcel_polygon(parcel: ParcelRecord) -> ee.Geometry:
    gj = parcel.boundary["features"][0]["geometry"]
    return ee.Geometry(gj)


def _bbox_geom(parcel: ParcelRecord) -> ee.Geometry:
    b = parcel.bbox
    return ee.Geometry.Rectangle(
        [b["min_lng"], b["min_lat"], b["max_lng"], b["max_lat"]]
    )


def _centroid_point(parcel: ParcelRecord) -> ee.Geometry:
    c = parcel.centroid
    return ee.Geometry.Point([c["lng"], c["lat"]])


def _mask_s2_sr(image: ee.Image) -> ee.Image:
    """Cloud/cirrus mask from QA60; SCL excludes water and cloud/shadow/snow classes."""
    qa = image.select("QA60")
    cloud_bit_mask = 1 << 10
    cirrus_bit_mask = 1 << 11
    mask = qa.bitwiseAnd(cloud_bit_mask).eq(0).And(
        qa.bitwiseAnd(cirrus_bit_mask).eq(0)
    )
    scl = image.select("SCL")
    # Scene Classification: drop cloud shadow (3), water (6), med/high cloud (8,9), cirrus (10), snow (11).
    # Keeps veg (4), bare (5), and other land-ish classes (2,4,5,7) for fuller NDVI coverage vs. veg-only.
    bad = (
        scl.eq(3)
        .Or(scl.eq(6))
        .Or(scl.eq(8))
        .Or(scl.eq(9))
        .Or(scl.eq(10))
        .Or(scl.eq(11))
    )
    scl_ok = bad.Not()
    return image.updateMask(mask).updateMask(scl_ok).divide(10000)


def _add_ndvi(image: ee.Image) -> ee.Image:
    ndvi = image.normalizedDifference(["B8", "B4"]).rename("NDVI")
    return image.addBands(ndvi)


def _end_date() -> ee.Date:
    # ERA5/CHIRPS can lag; stay inside published range.
    dt = datetime.now(timezone.utc) - timedelta(days=10)
    return ee.Date(dt.isoformat()[:10])


def compute_gee_land_signals(parcel: ParcelRecord) -> dict[str, Any]:
    """
    Run EE reducers. Raises on EE failure so caller can fall back.
    """
    poly = _parcel_polygon(parcel)
    bbox = _bbox_geom(parcel)
    point = _centroid_point(parcel)
    end = _end_date()

    out: dict[str, Any] = {
        "ndvi": {},
        "rainfall": {},
        "temperature": {},
        "meta": {
            "engine": "Google Earth Engine",
            "end_date_utc": end.format("YYYY-MM-dd").getInfo(),
        },
    }

    # --- FR-18 NDVI (Sentinel-2) ---
    s2 = (
        ee.ImageCollection("COPERNICUS/S2_SR_HARMONIZED")
        .filterBounds(poly)
        .filter(ee.Filter.lt("CLOUDY_PIXEL_PERCENTAGE", 45))
        .map(_mask_s2_sr)
        .map(_add_ndvi)
    )

    # Current: median NDVI over last ~4 months (captures recent season).
    cur_start = end.advance(-120, "day")
    s2_recent = s2.filterDate(cur_start, end)
    recent_med = s2_recent.select("NDVI").median()
    cur_stats = recent_med.reduceRegion(
        ee.Reducer.mean(),
        poly,
        scale=10,
        maxPixels=1e13,
        bestEffort=True,
    )
    gee_ndvi_current = float(cur_stats.get("NDVI").getInfo() or 0.0)
    n_recent = int(s2_recent.size().getInfo() or 0)

    bird_ndvi = sample_parcel_mean_ndvi(parcel)
    ndvi_current, ndvi_blend = blend_ndvi_current(gee_ndvi_current, bird_ndvi)

    # 2-year mean: mean composite NDVI over [end-2y, end-120d] to avoid overlap with "current".
    long_start = end.advance(-2, "year")
    long_end = end.advance(-120, "day")
    s2_long = s2.filterDate(long_start, long_end)
    long_mean_img = s2_long.select("NDVI").mean()
    long_stats = long_mean_img.reduceRegion(
        ee.Reducer.mean(),
        poly,
        scale=10,
        maxPixels=1e13,
        bestEffort=True,
    )
    ndvi_2y_mean = float(long_stats.get("NDVI").getInfo() or 0.0)
    n_long = int(s2_long.size().getInfo() or 0)

    # Monthly trend: last 12 calendar months, monthly median NDVI (one raster per month).
    monthly_vals: list[float] = []
    for i in range(12):
        m_end = end.advance(-i, "month")
        m_start = m_end.advance(-1, "month")
        sub = s2.filterDate(m_start, m_end)
        med = sub.select("NDVI").median()
        v = med.reduceRegion(
            ee.Reducer.mean(),
            poly,
            scale=10,
            maxPixels=1e13,
            bestEffort=True,
        ).get("NDVI")
        monthly_vals.append(float(v.getInfo() or float("nan")))
    monthly_vals = monthly_vals[::-1]  # chronological oldest -> newest
    monthly_clean = [round(x, 4) if not math.isnan(x) else 0.0 for x in monthly_vals]

    diff = ndvi_current - ndvi_2y_mean
    if diff > 0.02:
        ndvi_status = "Recovering"
    elif diff < -0.02:
        ndvi_status = "Degrading"
    else:
        ndvi_status = "Healthy"

    # Confidence: more clear S2 granules -> higher (heuristic).
    ndvi_conf = min(95.0, 45.0 + min(n_recent, 24) * 2.0 + min(n_long, 48) * 0.5)
    if ndvi_blend.get("birdscale"):
        ndvi_conf = min(98.0, ndvi_conf + 8.0)

    lim_ndvi = (
        "NDVI is from Sentinel-2 surface reflectance; clouds/shadows reduce usable "
        "observations. Values are polygon means, not plot-scale ground truth."
    )
    if ndvi_blend.get("birdscale"):
        lim_ndvi += (
            " Current value blends Birdscale drone NDVI raster (parcel zonal mean) with "
            "Sentinel-2 per LANDROID_NDVI_BLEND_WEIGHT."
        )

    out["ndvi"] = {
        "current": round(ndvi_current, 4),
        "two_year_mean": round(ndvi_2y_mean, 4),
        "monthly_trend": monthly_clean,
        "status": ndvi_status,
        "confidence": round(ndvi_conf, 1),
        "granules_recent_window": n_recent,
        "granules_two_year_window": n_long,
        "dataset": "COPERNICUS/S2_SR_HARMONIZED",
        "sentinel2_median_ndvi": ndvi_blend.get("sentinel2_median_ndvi"),
        "birdscale_ndvi": ndvi_blend.get("birdscale"),
        "blend_weight_birdscale": ndvi_blend.get("blend_weight_birdscale"),
        "trend_direction": "up" if diff > 0.01 else ("down" if diff < -0.01 else "flat"),
        "limitations": lim_ndvi,
    }

    # --- FR-19 CHIRPS at centroid ---
    chirps = ee.ImageCollection("UCSB-CHG/CHIRPS/DAILY").select("precipitation")
    # Last ~365 days total (rolling water year proxy).
    r_start = end.advance(-365, "day")
    annual_img = chirps.filterDate(r_start, end).sum()
    annual_mm = float(
        annual_img.reduceRegion(
            ee.Reducer.first(),
            point,
            scale=5566,
            maxPixels=1,
        )
        .get("precipitation")
        .getInfo()
        or 0.0
    )

    # Climatology: mean annual precip 1991–2020 at centroid (WMO-style window).
    years = range(1991, 2021)
    annual_images = []
    for y in years:
        ys = ee.Date.fromYMD(y, 1, 1)
        ye = ys.advance(1, "year")
        annual_images.append(chirps.filterDate(ys, ye).sum())

    mean_annual_coll = ee.ImageCollection.fromImages(annual_images)
    mean_annual = mean_annual_coll.mean()
    clim_mm = float(
        mean_annual.reduceRegion(
            ee.Reducer.first(),
            point,
            scale=5566,
            maxPixels=1,
        )
        .get("precipitation")
        .getInfo()
        or 0.0
    )

    deviation_pct = 0.0
    if clim_mm > 1.0:
        deviation_pct = round((annual_mm - clim_mm) / clim_mm * 100.0, 1)
    if deviation_pct > 5:
        rain_flag = "surplus"
    elif deviation_pct < -5:
        rain_flag = "deficit"
    else:
        rain_flag = "normal"

    # Last 12 months monthly totals (approximate calendar months).
    monthly_mm: list[float] = []
    for i in range(12):
        m_end = end.advance(-i, "month")
        m_start = m_end.advance(-1, "month")
        tot = chirps.filterDate(m_start, m_end).sum()
        mm = float(
            tot.reduceRegion(ee.Reducer.first(), point, scale=5566, maxPixels=1)
            .get("precipitation")
            .getInfo()
            or 0.0
        )
        monthly_mm.append(mm)
    monthly_mm = monthly_mm[::-1]

    rain_conf = 72.0  # CHIRPS well validated regionally; parcel point is coarse.

    out["rainfall"] = {
        "annual_mm": round(annual_mm, 1),
        "monthly_mm": [round(x, 1) for x in monthly_mm],
        "climatology_annual_mm_1991_2020": round(clim_mm, 1),
        "deviation_pct_from_normal": deviation_pct,
        "flag": rain_flag,
        "confidence": rain_conf,
        "dataset": "UCSB-CHG/CHIRPS/DAILY",
        "limitations": (
            "CHIRPS is ~5.5 km; sampled at parcel centroid. Use as regional rainfall "
            "context, not farm-gauge totals."
        ),
    }

    # --- FR-20 ERA5-Land monthly regional (bbox) ---
    monthly_ic = (
        ee.ImageCollection("ECMWF/ERA5_LAND/MONTHLY_AGGR")
        .filterBounds(bbox)
        .select("temperature_2m")
    )
    t_monthly_c: list[float] = []
    for i in range(12):
        m_end = end.advance(-i, "month")
        m_start = m_end.advance(-1, "month")
        img = monthly_ic.filterDate(m_start, m_end).mean()
        k_mean = img.reduceRegion(
            ee.Reducer.mean(),
            bbox,
            scale=11132,
            maxPixels=1e9,
            bestEffort=True,
        ).get("temperature_2m")
        k_val = float(k_mean.getInfo() or 273.15)
        t_monthly_c.append(round(k_val - 273.15, 2))
    t_monthly_c = t_monthly_c[::-1]

    # Heat stress: count days (centroid) with daily Tmax > 35 °C over last 365d.
    daily_t = (
        ee.ImageCollection("ECMWF/ERA5_LAND/DAILY_AGGR")
        .filterDate(r_start, end)
        .filterBounds(bbox)
        .select("temperature_2m_max")
    )

    def _mark_hot(img: ee.Image) -> ee.Image:
        return (
            img.select("temperature_2m_max")
            .gt(273.15 + 35.0)
            .rename("hot")
        )

    hot_sum = daily_t.map(_mark_hot).sum()
    heat_days = float(
        hot_sum.reduceRegion(
            ee.Reducer.first(),
            point,
            scale=11132,
            maxPixels=1,
        )
        .get("hot")
        .getInfo()
        or 0.0
    )

    out["temperature"] = {
        "regional_note": (
            "Regional ERA5-Land reanalysis (~11 km). Not parcel-level air temperature; "
            "compare only as coarse climate context."
        ),
        "monthly_c": t_monthly_c,
        "heat_stress_event_count": int(round(heat_days)),
        "confidence": 62.0,
        "dataset_monthly": "ECMWF/ERA5_LAND/MONTHLY_AGGR",
        "dataset_daily": "ECMWF/ERA5_LAND/DAILY_AGGR",
        "limitations": (
            "Reanalysis combines model + observations; known ECMWF packing issues can "
            "affect extremes (see dataset 'Known Issues'). Heat days use Tmax at sample scale."
        ),
    }

    return out
