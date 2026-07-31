"""Single source of truth for feature engineering (TRD §4).

The same `build_feature_row` builds both training rows
(`scripts/build_training_set.py`) and inference rows (`yield_service.py`).
Any divergence between the two call sites is a training/serving skew bug —
that is why there is only one function and it is imported, never
reimplemented, at either call site.

WINDOW-INVARIANT FEATURES
-------------------------
Training rows aggregate a *whole* crop year. Inference happens *mid-season* —
often 40-50 days after sowing. Cumulative features are therefore not
comparable between the two: a season-to-date rainfall of 77 mm and a
full-season 1,025 mm describe the same field at different times, but a tree
model reads them as different worlds and extrapolates off a cliff.

So every window-dependent quantity is stored as a **rate**, not a total:

    rainfall_mm_per_day   instead of  rainfall_cum_mm
    et0_mm_per_day        instead of  et0_cum_mm
    gdd_per_day           instead of  gdd
    ndvi_auc_per_day      instead of  ndvi_auc
    dry_spell_frac        instead of  dry_spell_max_days

Rates are comparable at any point in the season, which is what makes a model
trained on full seasons usable in July. `rainfall_last30_mm` stays absolute
because its window is already fixed at 30 days, and the temperature/humidity
means were never cumulative.
"""
from typing import Any

from app.services.crop_reference import load_crops

NUMERIC_FEATURES = [
    "n_kg_ha",
    "p_kg_ha",
    "k_kg_ha",
    "ph",
    "oc_pct",
    "rainfall_mm_per_day",
    "rainfall_last30_mm",
    "dry_spell_frac",
    "temp_mean_c",
    "temp_max_c",
    "gdd_per_day",
    "humidity_mean_pct",
    "et0_mm_per_day",
    "ndvi_mean",
    "ndvi_max",
    "ndvi_p90",
    "ndvi_slope_30d",
    "ndvi_auc_per_day",
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


def _per_day(total: float | None, days: int | None) -> float | None:
    """Convert a window total to a daily rate. None propagates as None —
    a missing observation must stay missing, not become a fabricated zero."""
    if total is None or not days or days <= 0:
        return None
    return round(float(total) / days, 4)


def observation_days(weather: dict[str, Any] | None) -> int | None:
    """Length of the weather window, in days.

    Adapters report it directly. The fallback counts the daily temperature
    series, so a payload from an older cache still normalises correctly
    instead of silently producing cumulative-scale features again.
    """
    if not weather:
        return None
    days = weather.get("observation_days")
    if days:
        return int(days)
    series = weather.get("daily_temp_mean_c")
    return len(series) if series else None


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

    Cumulative weather and NDVI quantities are divided by the observation
    window so the row means the same thing 45 days into a season as it does
    at harvest. See the module docstring.
    """
    crops = load_crops()
    t_base_c = crops.get(crop, {}).get("t_base_c", 10.0)

    ndvi = ndvi or {}
    days = observation_days(weather)
    gdd_total = weather.get("gdd") if weather.get("gdd") is not None else _crop_gdd(
        weather.get("daily_temp_mean_c"), t_base_c
    )

    dry_spell = weather.get("dry_spell_max_days")
    row = {
        "n_kg_ha": soil.get("n_kg_ha"),
        "p_kg_ha": soil.get("p_kg_ha"),
        "k_kg_ha": soil.get("k_kg_ha"),
        "ph": soil.get("ph"),
        "oc_pct": soil.get("oc_pct"),
        "rainfall_mm_per_day": _per_day(weather.get("rainfall_cum_mm"), days),
        # Already a fixed 30-day window, so it needs no normalisation.
        "rainfall_last30_mm": weather.get("rainfall_last30_mm"),
        # Longest dry run as a share of the window: 20 dry days out of 45 is a
        # drought, out of 365 it is a normal fortnight.
        "dry_spell_frac": _per_day(dry_spell, days),
        "temp_mean_c": weather.get("temp_mean_c"),
        "temp_max_c": weather.get("temp_max_c"),
        "gdd_per_day": _per_day(gdd_total, days),
        "humidity_mean_pct": weather.get("humidity_mean_pct"),
        "et0_mm_per_day": _per_day(weather.get("et0_cum_mm"), days),
        "ndvi_mean": ndvi.get("ndvi_mean"),
        "ndvi_max": ndvi.get("ndvi_max"),
        "ndvi_p90": ndvi.get("ndvi_p90"),
        "ndvi_slope_30d": ndvi.get("ndvi_slope_30d"),
        "ndvi_auc_per_day": _per_day(ndvi.get("ndvi_auc"), days),
        "area_ha": area_ha,
        "crop": crop,
        "district": district,
        "season": season,
    }
    return {col: row[col] for col in FEATURE_COLUMNS}
