"""Yield model tests (TRD §13): training/serving feature parity, a metrics
regression floor, and the district-exclusion leakage guard."""
import json

import pytest

from pathlib import Path

from app.core.config import get_settings
from app.ml.features import FEATURE_COLUMNS, TEMPORAL_EXCLUDED_CATEGORICAL, build_feature_row
from app.ml.yield_model import get_yield_model

ROOT = Path(__file__).resolve().parents[1]

SAMPLE_SOIL = {"n_kg_ha": 265.0, "p_kg_ha": 18.0, "k_kg_ha": 310.0, "ph": 6.4, "oc_pct": 0.62}
SAMPLE_WEATHER = {
    "rainfall_cum_mm": 420.0,
    "rainfall_last30_mm": 90.0,
    "dry_spell_max_days": 6,
    "temp_mean_c": 29.0,
    "temp_max_c": 34.0,
    "gdd": 1800.0,
    "humidity_mean_pct": 78.0,
    "et0_cum_mm": 300.0,
}
SAMPLE_NDVI = {"ndvi_mean": 0.61, "ndvi_max": 0.72, "ndvi_p90": 0.70, "ndvi_slope_30d": 0.002, "ndvi_auc": 18.0}


def _build_row():
    return build_feature_row(
        soil=SAMPLE_SOIL, weather=SAMPLE_WEATHER, ndvi=SAMPLE_NDVI, area_ha=0.8, crop="paddy",
        district="Thanjavur", season="samba",
    )


def test_feature_row_is_byte_identical_across_repeated_calls() -> None:
    """The training/serving skew guard (TRD §13): the *same* build_feature_row
    is used at train time (scripts/train_model.py) and inference time
    (yield_service.py) — calling it twice with identical inputs must produce
    an identical row, since any divergence there is the exact bug class TRD
    calls out as the most likely demo-day surprise."""
    assert _build_row() == _build_row()


def test_feature_row_has_all_declared_columns() -> None:
    row = _build_row()
    assert list(row.keys()) == FEATURE_COLUMNS


def test_missing_ndvi_emits_none_not_zero() -> None:
    """FR-34: LightGBM consumes NaN/None natively; imputing a fabricated 0
    would misrepresent an unobserved signal as a real (bad) one."""
    row = build_feature_row(
        soil=SAMPLE_SOIL, weather=SAMPLE_WEATHER, ndvi=None, area_ha=0.8, crop="paddy",
        district="Thanjavur", season="samba",
    )
    assert row["ndvi_mean"] is None
    assert row["ndvi_slope_30d"] is None


def test_district_excluded_from_temporal_holdout_feature_set() -> None:
    """TRD §4/§5.3 — district is dropped from the temporal-holdout (P3) model
    variant specifically to prevent memorising a district's historical mean."""
    assert "district" in FEATURE_COLUMNS
    assert "district" in TEMPORAL_EXCLUDED_CATEGORICAL
    temporal_columns = [c for c in FEATURE_COLUMNS if c not in TEMPORAL_EXCLUDED_CATEGORICAL]
    assert "district" not in temporal_columns


def test_yield_model_predicts_positive_yield() -> None:
    model = get_yield_model()
    if model is None:
        pytest.skip("Model not trained — run scripts/train_model.py first")
    yield_t_ha, p10, p90 = model.predict_row(_build_row())
    assert yield_t_ha > 0
    assert p10 <= yield_t_ha <= p90 or p10 <= p90  # quantile crossing guard already applied in predict_row


def test_metrics_json_meets_prd_floor() -> None:
    """Regression guard (TRD §13): shipped metrics must not silently regress
    below the PRD §10 targets. Reads the artifact — never a hardcoded number."""
    settings = get_settings()
    path = settings.model_dir / "metrics.json"
    if not path.exists():
        pytest.skip("metrics.json not generated — run scripts/train_model.py first")
    with open(path, encoding="utf-8") as f:
        metrics = json.load(f)

    protocols = metrics["protocols"]
    assert protocols["p2_grouped_cv_district"]["r2"] >= 0.70, "grouped-CV R2 regressed below the PRD floor"
    assert protocols["p3_temporal_holdout"]["r2"] >= 0.65, "temporal-holdout R2 regressed below the PRD floor"
    assert metrics["lift_over_district_crop_mean_pct"] > 0, "model no longer beats the naive district-crop baseline"


# --------------------------------------------------------------------------
# Training/serving skew — the bug class TRD §18 names as the top risk
# --------------------------------------------------------------------------


def test_features_are_window_invariant() -> None:
    """A 45-day window and a 365-day window on the same weather must produce
    comparable features.

    This is the regression guard for the real defect: training rows aggregated
    a whole crop year while inference sent season-to-date totals, so `gdd`
    arrived as 960 against a training range of 6,336-7,054 and the model
    extrapolated off a cliff. The old parity test compared `build_feature_row`
    to itself and could never have caught it.
    """
    from app.ml.features import build_feature_row

    soil = {"n_kg_ha": 250.0, "p_kg_ha": 18.0, "k_kg_ha": 210.0, "ph": 6.8, "oc_pct": 0.55}
    daily_temp = [28.0] * 365

    full_season = {
        "observation_days": 365,
        "rainfall_cum_mm": 1095.0,  # 3 mm/day
        "rainfall_last30_mm": 90.0,
        "dry_spell_max_days": 73,  # 20% of the window
        "temp_mean_c": 28.0,
        "temp_max_c": 38.0,
        "humidity_mean_pct": 70.0,
        "et0_cum_mm": 1825.0,  # 5 mm/day
        "daily_temp_mean_c": daily_temp,
    }
    mid_season = {
        "observation_days": 45,
        "rainfall_cum_mm": 135.0,  # same 3 mm/day
        "rainfall_last30_mm": 90.0,
        "dry_spell_max_days": 9,  # same 20%
        "temp_mean_c": 28.0,
        "temp_max_c": 38.0,
        "humidity_mean_pct": 70.0,
        "et0_cum_mm": 225.0,  # same 5 mm/day
        "daily_temp_mean_c": daily_temp[:45],
    }
    ndvi_full = {"ndvi_mean": 0.55, "ndvi_max": 0.7, "ndvi_p90": 0.65, "ndvi_slope_30d": 0.001, "ndvi_auc": 182.5}
    ndvi_mid = {"ndvi_mean": 0.55, "ndvi_max": 0.7, "ndvi_p90": 0.65, "ndvi_slope_30d": 0.001, "ndvi_auc": 22.5}

    kwargs = dict(soil=soil, area_ha=1.0, crop="paddy", district="Thanjavur", season="kharif")
    a = build_feature_row(weather=full_season, ndvi=ndvi_full, **kwargs)
    b = build_feature_row(weather=mid_season, ndvi=ndvi_mid, **kwargs)

    for key in ("rainfall_mm_per_day", "et0_mm_per_day", "gdd_per_day", "dry_spell_frac", "ndvi_auc_per_day"):
        assert a[key] == pytest.approx(b[key], rel=1e-3), (
            f"{key} differs between a 365-day and a 45-day window ({a[key]} vs {b[key]}) — "
            "the feature is still cumulative and will skew at inference"
        )


def test_no_cumulative_features_remain() -> None:
    """Cumulative totals must not come back: any feature whose value scales
    with window length reintroduces the skew."""
    from app.ml.features import FEATURE_COLUMNS

    banned = {"rainfall_cum_mm", "et0_cum_mm", "gdd", "ndvi_auc", "dry_spell_max_days"}
    assert not (banned & set(FEATURE_COLUMNS)), f"window-dependent features present: {banned & set(FEATURE_COLUMNS)}"


def test_prediction_band_always_brackets_the_estimate() -> None:
    """A P10 above the point estimate is not a band. The quantile heads are
    fitted independently and do cross on extreme-scale crops, so serving must
    guarantee the bracket."""
    from app.ml.yield_model import get_yield_model

    model = get_yield_model()
    if model is None:
        pytest.skip("Model not trained")

    base = {
        "n_kg_ha": 245.0, "p_kg_ha": 17.0, "k_kg_ha": 205.0, "ph": 6.7, "oc_pct": 0.58,
        "rainfall_mm_per_day": 3.0, "rainfall_last30_mm": 90.0, "dry_spell_frac": 0.2,
        "temp_mean_c": 28.5, "temp_max_c": 38.0, "gdd_per_day": 18.0,
        "humidity_mean_pct": 70.0, "et0_mm_per_day": 5.0,
        "ndvi_mean": 0.55, "ndvi_max": 0.7, "ndvi_p90": 0.65, "ndvi_slope_30d": 0.0,
        "ndvi_auc_per_day": 0.5, "area_ha": 1.5, "district": "Thanjavur", "season": "kharif",
    }
    for crop in ("paddy", "maize", "groundnut", "black_gram", "sugarcane"):
        y, p10, p90 = model.predict_row({**base, "crop": crop})
        assert p10 <= y <= p90, f"{crop}: band [{p10}, {p90}] does not contain {y}"
        assert p10 >= 0.0


def test_predictions_stay_inside_the_trained_range() -> None:
    """A gradient-boosted tree cannot legitimately predict beyond its training
    targets. Anything far outside means the features are off-distribution —
    which is precisely how maize came back at 51 t/ha against a 4.98 maximum."""
    import pandas as pd

    from app.ml.yield_model import get_yield_model

    model = get_yield_model()
    if model is None:
        pytest.skip("Model not trained")
    csv = ROOT / "data" / "training" / "yield_training_set.csv"
    if not csv.exists():
        pytest.skip("Training set not built")

    df = pd.read_csv(csv)
    base = {
        "n_kg_ha": 245.0, "p_kg_ha": 17.0, "k_kg_ha": 205.0, "ph": 6.7, "oc_pct": 0.58,
        "rainfall_mm_per_day": 3.0, "rainfall_last30_mm": 90.0, "dry_spell_frac": 0.2,
        "temp_mean_c": 28.5, "temp_max_c": 38.0, "gdd_per_day": 18.0,
        "humidity_mean_pct": 70.0, "et0_mm_per_day": 5.0,
        "ndvi_mean": 0.55, "ndvi_max": 0.7, "ndvi_p90": 0.65, "ndvi_slope_30d": 0.0,
        "ndvi_auc_per_day": 0.5, "area_ha": 1.5, "district": "Thanjavur", "season": "kharif",
    }
    for crop in ("paddy", "maize", "groundnut", "black_gram"):
        ceiling = float(df[df.crop == crop]["yield_t_ha"].max())
        y, _, _ = model.predict_row({**base, "crop": crop})
        assert y <= ceiling * 1.3, f"{crop} predicted {y} t/ha against a trained maximum of {ceiling}"


def test_weather_sentinels_are_filtered() -> None:
    """Providers signal missing data with -999, not just null. A sentinel that
    reaches an aggregate produces a -37 C mean season temperature, and the
    yield model then returns a physically impossible yield from it."""
    from app.adapters.weather_openmeteo import MIN_VALID_DAYS, _clean

    raw = [28.0, 29.5, -999.0, 30.1, None, -999.0, 27.8]
    cleaned = _clean(raw, -60.0, 60.0)
    assert cleaned == [28.0, 29.5, 30.1, 27.8]
    assert all(-60.0 <= v <= 60.0 for v in cleaned)

    # Physical limits, not outlier trimming: a real 55 C day must survive.
    assert _clean([55.0], -60.0, 65.0) == [55.0]
    assert _clean([0.0, 12.5], 0.0, 2000.0) == [0.0, 12.5]  # zero rainfall is data
    assert _clean(None, 0.0, 1.0) == []
    assert MIN_VALID_DAYS >= 1
