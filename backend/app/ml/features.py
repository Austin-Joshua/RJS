"""Single source of truth for feature engineering (TRD §4).

The same `build_feature_row` builds both training rows
(`scripts/build_training_set.py`) and inference rows (`yield_service.py`).
Any divergence between the two call sites is a training/serving skew bug —
that is why there is only one function and it is imported, never
reimplemented, at either call site.
"""
from typing import Any

from app.services.crop_reference import load_crops

NUMERIC_FEATURES = [
    "n_kg_ha",
    "p_kg_ha",
    "k_kg_ha",
    "ph",
    "oc_pct",
    "rainfall_cum_mm",
    "rainfall_last30_mm",
    "dry_spell_max_days",
    "temp_mean_c",
    "temp_max_c",
    "gdd",
    "humidity_mean_pct",
    "et0_cum_mm",
    "ndvi_mean",
    "ndvi_max",
    "ndvi_p90",
    "ndvi_slope_30d",
    "ndvi_auc",
    "area_ha",
]

# Excluded from the temporal-holdout (P3) model variant to prevent district
# memorisation (TRD §4, §5.3) — retained for P1/P2 where the ablation is
# reported instead of hidden.
CATEGORICAL_FEATURES = ["crop", "district", "season"]
TEMPORAL_EXCLUDED_CATEGORICAL = ["district"]

FEATURE_COLUMNS = NUMERIC_FEATURES + CATEGORICAL_FEATURES


def _crop_gdd(daily_temp_mean_c: list[float] | None, t_base_c: float) -> float | None:
    if not daily_temp_mean_c:
        return None
    return round(sum(max(0.0, t - t_base_c) for t in daily_temp_mean_c), 1)


def build_feature_row(
    *,
    soil: dict[str, Any],
    weather: dict[str, Any],
    ndvi: dict[str, Any] | None,
    area_ha: float,
    crop: str,
    district: str,
    season: str,
) -> dict[str, Any]:
    """Returns a flat dict keyed by FEATURE_COLUMNS. Missing NDVI/weather
    fields are emitted as None — LightGBM consumes NaN natively (FR-34);
    imputing here would fabricate a signal that was never observed.
    """
    crops = load_crops()
    t_base_c = crops.get(crop, {}).get("t_base_c", 10.0)

    ndvi = ndvi or {}
    gdd = weather.get("gdd") if weather.get("gdd") is not None else _crop_gdd(
        weather.get("daily_temp_mean_c"), t_base_c
    )

    row = {
        "n_kg_ha": soil.get("n_kg_ha"),
        "p_kg_ha": soil.get("p_kg_ha"),
        "k_kg_ha": soil.get("k_kg_ha"),
        "ph": soil.get("ph"),
        "oc_pct": soil.get("oc_pct"),
        "rainfall_cum_mm": weather.get("rainfall_cum_mm"),
        "rainfall_last30_mm": weather.get("rainfall_last30_mm"),
        "dry_spell_max_days": weather.get("dry_spell_max_days"),
        "temp_mean_c": weather.get("temp_mean_c"),
        "temp_max_c": weather.get("temp_max_c"),
        "gdd": gdd,
        "humidity_mean_pct": weather.get("humidity_mean_pct"),
        "et0_cum_mm": weather.get("et0_cum_mm"),
        "ndvi_mean": ndvi.get("ndvi_mean"),
        "ndvi_max": ndvi.get("ndvi_max"),
        "ndvi_p90": ndvi.get("ndvi_p90"),
        "ndvi_slope_30d": ndvi.get("ndvi_slope_30d"),
        "ndvi_auc": ndvi.get("ndvi_auc"),
        "area_ha": area_ha,
        "crop": crop,
        "district": district,
        "season": season,
    }
    return {col: row[col] for col in FEATURE_COLUMNS}
