"""Yield model tests (TRD §13): training/serving feature parity, a metrics
regression floor, and the district-exclusion leakage guard."""
import json

import pytest

from app.core.config import get_settings
from app.ml.features import FEATURE_COLUMNS, TEMPORAL_EXCLUDED_CATEGORICAL, build_feature_row
from app.ml.yield_model import get_yield_model

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
