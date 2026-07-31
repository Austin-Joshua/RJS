"""Trains the yield model and writes every artifact `app/ml/yield_model.py`
and the analytics endpoints serve (TRD §5.2-5.4). Three protocols are run and
ALL THREE are reported in `metrics.json` — that is the whole point of FR-33:
no hardcoded metric, and the honest (lower) grouped/temporal numbers are
never hidden behind the flattering random-split number.
"""
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path

import lightgbm as lgb
import numpy as np
import pandas as pd
import shap
from sklearn.linear_model import Ridge
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
from sklearn.model_selection import GroupKFold, train_test_split

from app.core.config import get_settings
from app.ml.features import CATEGORICAL_FEATURES, FEATURE_COLUMNS, TEMPORAL_EXCLUDED_CATEGORICAL, build_feature_row
from scripts.build_training_set import CROPS, DISTRICTS, SEASONS, OUT_PATH as TRAINING_CSV

# Tuned for the real (small, n~600) training set — the previous
# n_estimators=1200/min_child_samples=40 pair was sized for the old
# 4200-row synthetic panel and overfit badly here (negative lift over the
# district-crop-mean baseline). Target is log1p(yield_t_ha) (see
# `_load_dataset`/expm1 below): sugarcane's 100+ t/ha scale otherwise
# dominates the L1 loss and drowns out the sub-5 t/ha crops.
LGBM_PARAMS = dict(
    objective="regression_l1",
    n_estimators=60,
    learning_rate=0.08,
    num_leaves=15,
    min_child_samples=20,
    subsample=0.8,
    colsample_bytree=0.8,
    reg_lambda=1.0,
    random_state=42,
    verbosity=-1,
)
TARGET_TRANSFORM = "log1p"
CATEGORIES = {"crop": CROPS, "district": DISTRICTS, "season": SEASONS}


def _load_dataset() -> pd.DataFrame:
    """Read the training CSV, which `build_training_set.py` already wrote in
    FEATURE_COLUMNS form via `build_feature_row`.

    Nothing is re-derived here. There was previously a second transformation at
    this point, which meant three separate places built a feature row and only
    two of them agreed — the drift that let whole-season totals be compared
    against season-to-date ones at inference. Reading the columns straight
    keeps `build_feature_row` the only implementation.
    """
    raw = pd.read_csv(TRAINING_CSV)
    missing = [c for c in FEATURE_COLUMNS if c not in raw.columns]
    if missing:
        raise SystemExit(
            f"Training CSV is missing {missing}. It predates the current feature set — "
            "re-run `python -m scripts.build_training_set` to regenerate it."
        )
    df = raw[FEATURE_COLUMNS].copy()
    df["year"] = raw["year"].values
    df["yield_t_ha"] = raw["yield_t_ha"].values
    return df


def _apply_categories(df: pd.DataFrame, categorical_cols: list[str]) -> pd.DataFrame:
    df = df.copy()
    for col in categorical_cols:
        df[col] = pd.Categorical(df[col], categories=CATEGORIES[col])
    return df


def _fit_lgbm(x_train: pd.DataFrame, y_train: pd.Series, **overrides) -> lgb.LGBMRegressor:
    model = lgb.LGBMRegressor(**{**LGBM_PARAMS, **overrides})
    model.fit(x_train, y_train)
    return model


def _eval(model, x_test: pd.DataFrame, y_test_real: pd.Series) -> dict:
    """y_test_real is always real t/ha — the model was fit on log1p(y)
    (TARGET_TRANSFORM), so its raw prediction is expm1'd back before scoring,
    keeping every reported metric in the same real units as the baselines."""
    pred = np.expm1(model.predict(x_test))
    return {
        "r2": round(float(r2_score(y_test_real, pred)), 4),
        "rmse": round(float(np.sqrt(mean_squared_error(y_test_real, pred))), 4),
        "mae": round(float(mean_absolute_error(y_test_real, pred)), 4),
    }


def _baseline_metrics(train: pd.DataFrame, test: pd.DataFrame) -> dict:
    global_mean = train["yield_t_ha"].mean()
    global_pred = np.full(len(test), global_mean)

    district_crop_mean = train.groupby(["district", "crop"], observed=True)["yield_t_ha"].mean()
    overall_mean = train["yield_t_ha"].mean()
    dc_pred = test.apply(
        lambda r: district_crop_mean.get((r["district"], r["crop"]), overall_mean), axis=1
    ).to_numpy()

    ridge_cols = [c for c in FEATURE_COLUMNS if c not in ("district",)]
    x_train_dummies = pd.get_dummies(train[ridge_cols], columns=["crop", "season"])
    x_test_dummies = pd.get_dummies(test[ridge_cols], columns=["crop", "season"]).reindex(
        columns=x_train_dummies.columns, fill_value=0
    )
    x_train_dummies = x_train_dummies.fillna(x_train_dummies.median(numeric_only=True))
    x_test_dummies = x_test_dummies.fillna(x_train_dummies.median(numeric_only=True))
    ridge = Ridge(alpha=1.0).fit(x_train_dummies, train["yield_t_ha"])
    ridge_pred = ridge.predict(x_test_dummies)

    def _metrics(pred: np.ndarray) -> dict:
        y = test["yield_t_ha"].to_numpy()
        return {
            "r2": round(float(r2_score(y, pred)), 4),
            "rmse": round(float(np.sqrt(mean_squared_error(y, pred))), 4),
            "mae": round(float(mean_absolute_error(y, pred)), 4),
        }

    return {
        "global_mean": _metrics(global_pred),
        "district_crop_mean": _metrics(dc_pred),
        "ridge": _metrics(ridge_pred),
    }


def _git_sha() -> str:
    try:
        return subprocess.check_output(["git", "rev-parse", "--short", "HEAD"], text=True).strip()
    except Exception:  # noqa: BLE001
        return "unknown"


def main() -> None:
    settings = get_settings()
    settings.model_dir.mkdir(parents=True, exist_ok=True)

    df = _load_dataset()
    x_full = _apply_categories(df[FEATURE_COLUMNS], CATEGORICAL_FEATURES)
    y = df["yield_t_ha"]
    y_log = np.log1p(y)  # see TARGET_TRANSFORM note on LGBM_PARAMS

    # --- P1: random split ---------------------------------------------------
    x_train, x_test, y_train, y_test = train_test_split(x_full, y_log, test_size=0.2, random_state=42)
    p1_model = _fit_lgbm(x_train, y_train)
    p1 = _eval(p1_model, x_test, np.expm1(y_test))

    # --- P2: grouped CV by district ------------------------------------------
    gkf = GroupKFold(n_splits=5)
    p2_folds = []
    for train_idx, test_idx in gkf.split(x_full, y_log, groups=df["district"]):
        fold_model = _fit_lgbm(x_full.iloc[train_idx], y_log.iloc[train_idx])
        p2_folds.append(_eval(fold_model, x_full.iloc[test_idx], y.iloc[test_idx]))
    p2 = {k: round(float(np.mean([f[k] for f in p2_folds])), 4) for k in ("r2", "rmse", "mae")}

    # --- P3: temporal holdout (train <= 2020, test >= 2021) -----------------
    train_mask = df["year"] <= 2020
    test_mask = df["year"] >= 2021
    x_temporal_cols_with_district = FEATURE_COLUMNS
    x_temporal_cols_no_district = [c for c in FEATURE_COLUMNS if c not in TEMPORAL_EXCLUDED_CATEGORICAL]

    p3_with_district = _fit_lgbm(x_full.loc[train_mask, x_temporal_cols_with_district], y_log[train_mask])
    p3_with_metrics = _eval(p3_with_district, x_full.loc[test_mask, x_temporal_cols_with_district], y[test_mask])

    p3_no_district = _fit_lgbm(x_full.loc[train_mask, x_temporal_cols_no_district], y_log[train_mask])
    p3_no_metrics = _eval(p3_no_district, x_full.loc[test_mask, x_temporal_cols_no_district], y[test_mask])

    baselines = _baseline_metrics(df[train_mask], df[test_mask])
    rmse_lift_pct = round(
        100 * (baselines["district_crop_mean"]["rmse"] - p3_no_metrics["rmse"]) / baselines["district_crop_mean"]["rmse"],
        1,
    )

    # --- Final shipped model: full data, full feature set --------------------
    final_model = _fit_lgbm(x_full, y_log)
    final_model.booster_.save_model(str(settings.model_dir / "yield_lgbm.txt"))

    q10 = _fit_lgbm(x_full, y_log, objective="quantile", alpha=0.10)
    q90 = _fit_lgbm(x_full, y_log, objective="quantile", alpha=0.90)
    q10.booster_.save_model(str(settings.model_dir / "yield_q10.txt"))
    q90.booster_.save_model(str(settings.model_dir / "yield_q90.txt"))

    with open(settings.model_dir / "feature_list.json", "w", encoding="utf-8") as f:
        json.dump({"columns": FEATURE_COLUMNS, "categories": CATEGORIES, "target_transform": TARGET_TRANSFORM}, f, indent=2)

    # --- Global SHAP (FR-32, analytics feature importance) -------------------
    sample = x_full.sample(min(500, len(x_full)), random_state=42)
    explainer = shap.TreeExplainer(final_model.booster_)
    shap_values = explainer.shap_values(sample)
    global_shap = {
        col: round(float(np.mean(np.abs(shap_values[:, i]))), 4) for i, col in enumerate(FEATURE_COLUMNS)
    }
    with open(settings.model_dir / "shap_global.json", "w", encoding="utf-8") as f:
        json.dump(dict(sorted(global_shap.items(), key=lambda kv: -kv[1])), f, indent=2)

    # --- Yield-vs-rainfall chart data (FR-63) --------------------------------
    chart_sample = df.sample(min(600, len(df)), random_state=42)
    chart_points = [
        {
            "rainfall_mm_per_day": r["rainfall_mm_per_day"],
            "yield_t_ha": r["yield_t_ha"],
            "crop": r["crop"],
        }
        for _, r in chart_sample.iterrows()
    ]
    with open(settings.model_dir / "yield_vs_rainfall.json", "w", encoding="utf-8") as f:
        json.dump({"points": chart_points}, f)

    metrics = {
        "model_version": settings.model_version,
        "trained_at": datetime.now(timezone.utc).isoformat(),
        "git_sha": _git_sha(),
        "row_count": len(df),
        "training_data_source": "real_govt_district_apy",
        "training_data_note": (
            "Generated by scripts/build_training_set.py from real government data: district-crop-year "
            "Area/Production/Yield statistics from the Directorate of Economics & Statistics (DES), Ministry "
            "of Agriculture & Farmers Welfare (data.desagri.gov.in), joined with real Open-Meteo Archive "
            "(ERA5) weather and real NASA ORNL DAAC MODIS NDVI over each row's 1 Jul-30 Jun crop year. Soil "
            "N/P/K is the real Soil Health Card baseline applied per-district across years (no free bulk "
            "historical SHC series exists); area_ha is sampled from TN's real average smallholding band "
            "(Agriculture Census) since per-farm area isn't published at district grain. See "
            "scripts/build_training_set.py's module docstring for the full source-by-source breakdown."
        ),
        "protocols": {
            "p1_random_split": p1,
            "p2_grouped_cv_district": p2,
            "p3_temporal_holdout": p3_no_metrics,
            "p3_temporal_holdout_with_district_ablation": p3_with_metrics,
        },
        "baselines_temporal_holdout": baselines,
        "lift_over_district_crop_mean_pct": rmse_lift_pct,
        "targets": {"grouped_cv_r2": 0.75, "temporal_holdout_r2": 0.70, "lift_over_baseline_pct": 30.0},
    }
    with open(settings.model_dir / "metrics.json", "w", encoding="utf-8") as f:
        json.dump(metrics, f, indent=2)

    print(json.dumps(metrics["protocols"], indent=2))
    print(f"lift_over_district_crop_mean_pct: {rmse_lift_pct}%")
    print(f"Artifacts written to {settings.model_dir}")


if __name__ == "__main__":
    main()
