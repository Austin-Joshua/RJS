"""
SRS FR-18–24: Land health from Google Earth Engine (when configured) + ISRIC SoilGrids,
with explicit methodology metadata. Synthetic fallback only when EE is unavailable
(so demos still run without cloud credentials).
"""

from __future__ import annotations

import hashlib
import math
from typing import Any

import os

from .birdscale_ndvi import sample_parcel_mean_ndvi
from .parcel_store import ParcelRecord


def _raster_tile_layer_manifest(env_key: str) -> dict[str, Any]:
    """Orthomosaic / DEM as XYZ or TMS from env (FR-12 COG-style tile templates)."""
    url = os.environ.get(f"LANDROID_{env_key}_TILE_URL_TEMPLATE", "").strip()
    if not url:
        return {
            "available": False,
            "cog_tile_url_template": None,
            "tile_scheme": "xyz",
        }
    scheme = os.environ.get(f"LANDROID_{env_key}_TILE_SCHEME", "xyz").strip().lower()
    if scheme not in ("xyz", "tms"):
        scheme = "xyz"
    return {
        "available": True,
        "cog_tile_url_template": url,
        "tile_scheme": scheme,
    }


def _digest_seed(parcel_id: str, salt: str) -> int:
    h = hashlib.sha256(f"{parcel_id}:{salt}".encode()).hexdigest()
    return int(h[:8], 16)


def health_badge_from_score(score: float) -> str:
    if score >= 75:
        return "Healthy"
    if score >= 50:
        return "Moderate"
    return "At Risk"


def _ndvi_component_score(ndvi: float) -> float:
    """Map typical crop NDVI (roughly 0–1) to 0–100 suitability."""
    v = max(-0.15, min(0.95, ndvi))
    return min(100.0, max(0.0, (v - 0.05) / 0.75 * 100.0))


def _rain_component_score(deviation_pct: float) -> float:
    return min(100.0, max(0.0, 100.0 - min(abs(deviation_pct), 45.0) * 1.8))


def _temp_component_score(heat_stress_days: float) -> float:
    return min(100.0, max(0.0, 100.0 - min(heat_stress_days, 90.0) * 1.1))


def _soil_component_score(soil: dict[str, Any]) -> float:
    ph = soil.get("ph")
    soc = soil.get("organic_carbon_g_kg")
    soil_component = 52.0
    if ph is not None:
        soil_component += max(0.0, 18.0 - abs(float(ph) - 6.5) * 3.0)
    if soc is not None:
        soil_component += min(28.0, float(soc) * 1.2)
    return min(100.0, soil_component)


def _fr22_score_breakdown(
    ndvi_s: float,
    rain_s: float,
    soil_s: float,
    temp_s: float,
    score: float,
) -> dict[str, Any]:
    """Transparent weights for dashboard “Why this score?” (FR-22 composite)."""
    w_ndvi, w_rain, w_soil, w_temp = 0.40, 0.30, 0.20, 0.10
    return {
        "weights_percent": {
            "ndvi_suitability": 40,
            "rainfall_adequacy": 30,
            "soil": 20,
            "temperature": 10,
        },
        "subscores_0_100": {
            "ndvi_suitability": round(ndvi_s, 2),
            "rainfall_adequacy": round(rain_s, 2),
            "soil": round(soil_s, 2),
            "temperature": round(temp_s, 2),
        },
        "weighted_contribution": {
            "ndvi": round(w_ndvi * ndvi_s, 2),
            "rainfall": round(w_rain * rain_s, 2),
            "soil": round(w_soil * soil_s, 2),
            "temperature": round(w_temp * temp_s, 2),
        },
        "composite_0_100": round(score, 1),
    }


def _composite_score(
    ndvi_s: float,
    rain_s: float,
    soil_s: float,
    temp_s: float,
) -> float:
    return round(
        min(
            100.0,
            max(
                0.0,
                0.40 * ndvi_s
                + 0.30 * rain_s
                + 0.20 * soil_s
                + 0.10 * temp_s,
            ),
        ),
        1,
    )


def _gee_ndvi_is_usable(gee: dict[str, Any]) -> bool:
    """True when EE returned a finite NDVI current (0.0 is valid live data)."""
    nd = gee.get("ndvi")
    if not isinstance(nd, dict):
        return False
    cur = nd.get("current")
    if cur is None:
        return False
    try:
        v = float(cur)
    except (TypeError, ValueError):
        return False
    return not math.isnan(v) and not math.isinf(v)


def build_land_health(
    parcel: ParcelRecord,
    soil: dict[str, Any],
    gee: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """
    If ``gee`` contains EE outputs (from ``gee_signals.compute_gee_land_signals``),
    use them. Otherwise use deterministic synthetic signals for UI development.
    """
    if gee and _gee_ndvi_is_usable(gee):
        try:
            return _land_health_from_earth_engine(parcel, soil, gee)
        except (KeyError, TypeError, ValueError):
            pass
    return _land_health_synthetic(parcel, soil)


def _land_health_from_earth_engine(
    parcel: ParcelRecord,
    soil: dict[str, Any],
    gee: dict[str, Any],
) -> dict[str, Any]:
    gn = gee["ndvi"]
    gr = gee["rainfall"]
    gt = gee["temperature"]

    ndvi_current = float(gn["current"])
    ndvi_2y = float(gn["two_year_mean"])
    monthly_ndvi = [float(x) for x in gn["monthly_trend"]]

    annual_mm = float(gr["annual_mm"])
    monthly_mm = [float(x) for x in gr["monthly_mm"]]
    deviation_pct = float(gr["deviation_pct_from_normal"])
    rain_flag = str(gr["flag"])
    heat_days = float(gt["heat_stress_event_count"])
    temp_monthly = [float(x) for x in gt["monthly_c"]]

    ph = soil.get("ph")
    soc = soil.get("organic_carbon_g_kg")
    texture = str(soil.get("texture", "unknown"))
    soil_conf = float(soil.get("confidence", 55))

    ndvi_s = _ndvi_component_score(ndvi_current)
    rain_s = _rain_component_score(deviation_pct)
    soil_s = _soil_component_score(soil)
    temp_s = _temp_component_score(heat_days)
    score = _composite_score(ndvi_s, rain_s, soil_s, temp_s)
    badge = health_badge_from_score(score)

    overall_conf = round(
        (
            float(gn["confidence"])
            + float(gr["confidence"])
            + float(gt["confidence"])
            + soil_conf
        )
        / 4.0,
        1,
    )

    diff = ndvi_current - ndvi_2y
    trend_arrow = "↑" if diff > 0.01 else ("↓" if diff < -0.01 else "→")

    land_health: dict[str, Any] = {
        "score": score,
        "label": badge,
        "confidence": overall_conf,
        "data_mode": "earth_engine",
        "parcel_id": parcel.id,
        "methodology": {
            "composite_fr22": "40% NDVI suitability + 30% rainfall adequacy + 20% soil + 10% temperature",
            "ndvi_source": gn.get("dataset"),
            "rainfall_source": gr.get("dataset"),
            "temperature_monthly_source": gt.get("dataset_monthly"),
            "temperature_heat_source": gt.get("dataset_daily"),
            "soil_source": soil.get("source", "isric_soilgrids"),
        },
        "ndvi": {
            "current": round(ndvi_current, 4),
            "two_year_mean": round(ndvi_2y, 4),
            "monthly_trend": monthly_ndvi,
            "status": gn["status"],
            "confidence": float(gn["confidence"]),
            "trend_direction": gn.get("trend_direction", "flat"),
            "trend_indicator": trend_arrow,
            "granules_recent_window": gn.get("granules_recent_window"),
            "limitations": gn.get("limitations", ""),
        },
        "rainfall": {
            "annual_mm": annual_mm,
            "monthly_mm": monthly_mm,
            "deviation_pct_from_normal": deviation_pct,
            "flag": rain_flag,
            "confidence": float(gr["confidence"]),
            "climatology_note": "1991–2020 mean annual CHIRPS at centroid",
            "limitations": gr.get("limitations", ""),
        },
        "temperature": {
            "regional_note": gt["regional_note"],
            "monthly_c": temp_monthly,
            "heat_stress_event_count": int(heat_days),
            "confidence": float(gt["confidence"]),
            "limitations": gt.get("limitations", ""),
        },
        "soil": {
            "ph": ph,
            "organic_carbon_g_kg": soc,
            "texture": texture,
            "confidence": soil_conf,
            "source": soil.get("source", "unknown"),
            "limitations": (
                "ISRIC SoilGrids are modelled soil properties at 250 m; not a field soil test."
            ),
        },
        "signal_cards": _signal_cards_fr24(
            ndvi_current=ndvi_current,
            ndvi_monthly=monthly_ndvi,
            ndvi_conf=float(gn["confidence"]),
            ndvi_trend=trend_arrow,
            annual_mm=annual_mm,
            monthly_mm=monthly_mm,
            rain_conf=float(gr["confidence"]),
            deviation_pct=deviation_pct,
            temp_monthly=temp_monthly,
            temp_conf=float(gt["confidence"]),
            heat_days=int(heat_days),
            ph=ph,
            soc=soc,
            soil_conf=soil_conf,
            texture=texture,
        ),
        "score_breakdown": _fr22_score_breakdown(ndvi_s, rain_s, soil_s, temp_s, score),
    }
    return land_health


def _signal_cards_fr24(
    *,
    ndvi_current: float,
    ndvi_monthly: list[float],
    ndvi_conf: float,
    ndvi_trend: str,
    annual_mm: float,
    monthly_mm: list[float],
    rain_conf: float,
    deviation_pct: float,
    temp_monthly: list[float],
    temp_conf: float,
    heat_days: int,
    ph: Any,
    soc: Any,
    soil_conf: float,
    texture: str,
) -> list[dict[str, Any]]:
    """FR-24: four cards with chart series + confidence."""
    return [
        {
            "id": "ndvi",
            "title": "NDVI (Sentinel-2)",
            "current_value": round(ndvi_current, 4),
            "value_label": "median NDVI (recent window)",
            "trend_indicator": ndvi_trend,
            "historical_chart": ndvi_monthly,
            "chart_x_labels": [str(i + 1) for i in range(12)],
            "confidence": ndvi_conf,
        },
        {
            "id": "rainfall",
            "title": "Rainfall (CHIRPS)",
            "current_value": round(annual_mm, 1),
            "value_label": "rolling 365 d total (mm)",
            "trend_indicator": "→" if abs(deviation_pct) < 5 else ("↑" if deviation_pct > 0 else "↓"),
            "historical_chart": monthly_mm,
            "chart_x_labels": [str(i + 1) for i in range(12)],
            "confidence": rain_conf,
            "context": f"vs 1991–2020 normal: {deviation_pct:+.1f}%",
        },
        {
            "id": "temperature",
            "title": "Temperature (ERA5-Land)",
            "current_value": heat_days,
            "value_label": "heat days (Tmax > 35 °C, ~365 d, regional)",
            "trend_indicator": "—",
            "historical_chart": temp_monthly,
            "chart_x_labels": [str(i + 1) for i in range(12)],
            "confidence": temp_conf,
        },
        {
            "id": "soil",
            "title": "Soil (SoilGrids)",
            "current_value": ph if ph is not None else "—",
            "value_label": "pH (0–5 cm)",
            "trend_indicator": "—",
            "historical_chart": [],
            "confidence": soil_conf,
            "context": f"texture: {texture}, SOC: {soc if soc is not None else '—'} g/kg",
        },
    ]


def _land_health_synthetic(parcel: ParcelRecord, soil: dict[str, Any]) -> dict[str, Any]:
    """Hash-based stand-in when Earth Engine is not configured."""
    seed = _digest_seed(parcel.id, "ndvi")
    ndvi_current = 0.15 + (seed % 7000) / 10000.0
    ndvi_current += min(0.15, parcel.area_acres_approx / 50000.0)
    ndvi_current = max(0.05, min(0.92, ndvi_current))
    bird_override = sample_parcel_mean_ndvi(parcel)
    bird_note = None
    if bird_override:
        # Prefer real drone NDVI for "current" (FR-18) when GeoTIFF is present; historical
        # slices remain synthetic until Earth Engine is enabled.
        ndvi_current = max(-1.0, min(1.0, float(bird_override["mean_ndvi"])))
        bird_note = bird_override["file"]
    ndvi_2y_mean = ndvi_current - 0.02 + (seed % 500) / 10000.0
    ndvi_status = (
        "Recovering"
        if ndvi_current > ndvi_2y_mean + 0.02
        else ("Degrading" if ndvi_current < ndvi_2y_mean - 0.02 else "Healthy")
    )
    monthly_trend = [
        round(ndvi_2y_mean + 0.03 * math.sin(i / 2.0) + (seed % 50) / 5000.0, 4)
        for i in range(12)
    ]
    rain_seed = _digest_seed(parcel.id, "rain")
    annual_mm = 800 + (rain_seed % 600)
    monthly_rain = [
        annual_mm / 12 * (0.7 + (rain_seed >> i) % 10 / 50.0) for i in range(12)
    ]
    hist = annual_mm * 1.08
    deviation_pct = round((annual_mm - hist) / hist * 100, 1)
    rain_flag = (
        "surplus" if deviation_pct > 3 else ("deficit" if deviation_pct < -3 else "normal")
    )
    temp_seed = _digest_seed(parcel.id, "temp")
    heat_stress_days = 4 + (temp_seed % 12)
    temp_monthly = [
        26.0 + 3 * math.sin(i / 2.0) + (temp_seed % 7) / 10.0 for i in range(12)
    ]
    ph = soil.get("ph")
    soc = soil.get("organic_carbon_g_kg")
    texture = soil.get("texture", "unknown")
    ndvi_s = _ndvi_component_score(ndvi_current)
    rain_s = _rain_component_score(deviation_pct)
    soil_s = _soil_component_score(soil)
    temp_s = _temp_component_score(float(heat_stress_days))
    score = _composite_score(ndvi_s, rain_s, soil_s, temp_s)
    badge = health_badge_from_score(score)
    soil_conf = float(soil.get("confidence", 50))
    ndvi_sig_conf = 45.0
    rain_sig_conf = 45.0
    temp_sig_conf = 45.0
    overall_conf = round(
        (ndvi_sig_conf + rain_sig_conf + temp_sig_conf + soil_conf) / 4.0,
        1,
    )
    diff = ndvi_current - ndvi_2y_mean
    trend_arrow = "↑" if diff > 0.01 else ("↓" if diff < -0.01 else "→")

    return {
        "score": score,
        "label": badge,
        "confidence": overall_conf,
        "data_mode": "synthetic_demo",
        "parcel_id": parcel.id,
        "methodology": {
            "composite_fr22": (
                "40% NDVI suitability + 30% rainfall adequacy + 20% soil + 10% temperature"
            ),
            "warning": (
                "Earth Engine not configured or unavailable — placeholder signals for UI. "
                "Set GEE_SERVICE_ACCOUNT_KEY_PATH for FR-18–20 satellite/climate data."
            ),
            "birdscale_ndvi_file": bird_note,
        },
        "ndvi": {
            "current": round(ndvi_current, 4),
            "two_year_mean": round(ndvi_2y_mean, 4),
            "monthly_trend": monthly_trend,
            "status": ndvi_status,
            "confidence": ndvi_sig_conf,
            "trend_indicator": trend_arrow,
            "limitations": (
                "Synthetic — configure Earth Engine for Sentinel-2 NDVI."
                + (
                    f" Current NDVI from Birdscale GeoTIFF ({bird_note})."
                    if bird_note
                    else ""
                )
            ),
        },
        "rainfall": {
            "annual_mm": annual_mm,
            "monthly_mm": [round(x, 1) for x in monthly_rain],
            "deviation_pct_from_normal": deviation_pct,
            "flag": rain_flag,
            "confidence": rain_sig_conf,
            "limitations": "Synthetic — configure Earth Engine for CHIRPS.",
        },
        "temperature": {
            "regional_note": "regional ERA5-style aggregate (not parcel precision)",
            "monthly_c": [round(x, 2) for x in temp_monthly],
            "heat_stress_event_count": heat_stress_days,
            "confidence": temp_sig_conf,
            "limitations": "Synthetic — configure Earth Engine for ERA5-Land.",
        },
        "soil": {
            "ph": ph,
            "organic_carbon_g_kg": soc,
            "texture": texture,
            "confidence": soil_conf,
            "source": soil.get("source", "unknown"),
        },
        "signal_cards": _signal_cards_fr24(
            ndvi_current=ndvi_current,
            ndvi_monthly=monthly_trend,
            ndvi_conf=ndvi_sig_conf,
            ndvi_trend=trend_arrow,
            annual_mm=float(annual_mm),
            monthly_mm=[float(x) for x in monthly_rain],
            rain_conf=rain_sig_conf,
            deviation_pct=float(deviation_pct),
            temp_monthly=[float(x) for x in temp_monthly],
            temp_conf=temp_sig_conf,
            heat_days=int(heat_stress_days),
            ph=ph,
            soc=soc,
            soil_conf=soil_conf,
            texture=str(texture),
        ),
        "score_breakdown": _fr22_score_breakdown(ndvi_s, rain_s, soil_s, temp_s, score),
    }


def build_plant_zones(parcel: ParcelRecord) -> dict[str, Any]:
    seed = _digest_seed(parcel.id, "zones")
    bare = 5 + (seed % 12)
    sparse = 18 + (seed >> 3) % 15
    healthy = 35 + (seed >> 5) % 20
    dense = max(5, 100 - bare - sparse - healthy)
    s = bare + sparse + healthy + dense
    bare, sparse, healthy, dense = (
        round(bare / s * 100, 1),
        round(sparse / s * 100, 1),
        round(healthy / s * 100, 1),
        round(dense / s * 100, 1),
    )
    change_note = None
    if bare + sparse > 40:
        change_note = (
            "Lower health zones cover a notable share; compare with previous survey when available."
        )
    return {
        "zones": {
            "bare_stressed_pct": bare,
            "sparse_pct": sparse,
            "healthy_pct": healthy,
            "dense_pct": dense,
        },
        "legend": [
            {"label": "Bare / stressed", "ndvi_max": 0.2, "color": "#8B0000"},
            {"label": "Sparse", "ndvi_range": "0.2–0.4", "color": "#DAA520"},
            {"label": "Healthy", "ndvi_range": "0.4–0.6", "color": "#32CD32"},
            {"label": "Dense", "ndvi_min": 0.6, "color": "#006400"},
        ],
        "change_summary": change_note,
        "confidence": 70.0 + (seed % 25) / 10.0,
    }


def build_valuation(parcel: ParcelRecord, land_health: dict[str, Any]) -> dict[str, Any]:
    seed = _digest_seed(parcel.id, "val")
    lhs = float(land_health["score"])
    soil = land_health["soil"]
    rain = land_health["rainfall"]
    ph = soil.get("ph") or 6.5
    soc = soil.get("organic_carbon_g_kg") or 12.0
    soil_q = min(100.0, 40.0 + abs(float(ph) - 6.0) * 5.0 + min(40.0, float(soc)))
    rain_ad = min(
        100.0,
        100.0 - abs(float(rain["deviation_pct_from_normal"])) * 1.5,
    )
    osm_proxy = 45.0 + (seed % 40)
    night_light = 40.0 + (seed >> 4) % 35
    est = (
        0.30 * lhs
        + 0.20 * soil_q
        + 0.15 * rain_ad
        + 0.25 * osm_proxy
        + 0.10 * night_light
    )
    base_inr = 120_000 + est * 800 + (seed % 5000)
    low = round(base_inr * 0.85 / 1000.0) * 1000
    high = round(base_inr * 1.15 / 1000.0) * 1000
    factors_up = [
        "Land health score supports mid-to-upper range",
        (
            "Soil organic carbon within a workable band"
            if float(soc) > 10
            else "Rainfall near historical norms"
        ),
        "Parcel extent suitable for plantation analytics",
    ]
    factors_down = [
        "Heat-stress count reduces suitability slightly",
        "OSM proximity signals are model estimates only",
        "Not a legal or guideline valuation (FR-36)",
    ]
    return {
        "low_per_acre_inr": low,
        "mid_per_acre_inr": round((low + high) / 2 / 1000.0) * 1000,
        "high_per_acre_inr": high,
        "confidence": round(55 + (seed % 30), 1),
        "disclaimer": "Estimated intelligence range — not legal or government guideline valuation.",
        "factors_positive": factors_up[:3],
        "factors_negative": factors_down[:3],
    }


def _dem_layer_manifest(parcel: ParcelRecord) -> dict[str, Any]:
    """Remote DEM tiles (env) or local GeoTIFF hillshade PNG under ``DATA_DIR``."""
    from .birdscale_ndvi import resolve_dem_geotiff_path_for_parcel

    remote = _raster_tile_layer_manifest("DEM")
    if remote.get("available"):
        return {**remote, "source": "tiles"}
    if resolve_dem_geotiff_path_for_parcel(parcel) is not None:
        return {
            "available": True,
            "source": "local_geotiff",
            "cog_tile_url_template": None,
            "tile_scheme": "xyz",
            "png_path": f"parcels/{parcel.id}/layers/dem-raster.png",
        }
    return {
        "available": False,
        "source": None,
        "cog_tile_url_template": None,
        "tile_scheme": "xyz",
    }


def map_layers_manifest(
    parcel: ParcelRecord,
    health: dict[str, Any],
) -> dict[str, Any]:
    from .birdscale_ndvi import resolve_ndvi_geotiff_path_for_parcel
    from .geo import geodesic_boundary_metrics

    c = parcel.centroid
    pid = parcel.id
    tif = resolve_ndvi_geotiff_path_for_parcel(parcel)
    has_raster = tif is not None
    raster_source = "geotiff" if has_raster else "synthetic"
    gm = geodesic_boundary_metrics(parcel.boundary)
    return {
        "parcel_id": parcel.id,
        "centroid": c,
        "bbox": parcel.bbox,
        "boundary_geojson": parcel.boundary,
        "parcel_metrics": {
            "area_m2": round(gm["area_m2"], 2),
            "perimeter_m": round(gm["perimeter_m"], 2),
            "area_ha": round(gm["area_m2"] / 10000.0, 6),
        },
        "health_badge": health["label"],
        "health_score": health["score"],
        "data_mode": health.get("data_mode", "unknown"),
        # Clarifies GEE time-series vs map PNG (GeoTIFF) for API/UI.
        "ndvi_engine_notes": (
            "Dashboard NDVI (when Earth Engine is configured) uses Sentinel-2 "
            "COPERNICUS/S2_SR_HARMONIZED in EE: QA60+SCL masks, ~120-day median composite "
            "for “current”, a 2-year mean, and 12 monthly median values (see gee_signals). "
            "The map overlay PNG is rendered from the parcel NDVI GeoTIFF (or synthetic demo), "
            "not live EE map tiles."
        ),
        "layers": {
            "satellite": {
                "available": True,
                "label": "Satellite (Esri World Imagery)",
            },
            "orthomosaic": _raster_tile_layer_manifest("ORTHOMOSAIC"),
            "dem": _dem_layer_manifest(parcel),
            "boundary": {
                "available": True,
                "source": "consultant GeoJSON",
            },
            "ndvi": {
                "available": True,
                "source": raster_source,
                "path": f"parcels/{pid}/layers/ndvi.png",
                "description": (
                    "NDVI from GeoTIFF (red–green ramp)"
                    if has_raster
                    else "Demo NDVI ramp over parcel extent (upload GeoTIFF for real data)"
                ),
            },
            "plant_health_zones": {
                "available": True,
                "source": raster_source,
                "path": f"parcels/{pid}/layers/zones.png",
                "style": "ndvi_threshold_zones",
                "legend": [
                    {"label": "Bare / stressed", "ndvi_max": 0.2, "color": "#8B0000"},
                    {"label": "Sparse", "ndvi_range": "0.2–0.4", "color": "#DAA520"},
                    {"label": "Healthy", "ndvi_range": "0.4–0.6", "color": "#32CD32"},
                    {"label": "Dense", "ndvi_min": 0.6, "color": "#006400"},
                ],
            },
        },
        "maplibre_notes": {
            "base": "satellite",
            "fr11": "Use MapLibre GL with raster satellite base; toggle layers per FR-12.",
        },
    }
