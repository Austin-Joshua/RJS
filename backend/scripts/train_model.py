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

LGBM_PARAMS = dict(
    objective="regression_l1",
    n_estimators=1200,
    learning_rate=0.03,
    num_leaves=31,
    min_child_samples=40,
    subsample=0.8,
    colsample_bytree=0.8,
    reg_lambda=1.0,
    random_state=42,
    verbosity=-1,
)
CATEGORIES = {"crop": CROPS, "district": DISTRICTS, "season": SEASONS}


def _row_to_features(row: pd.Series) -> dict:
    soil = {k: row[k] for k in ("n_kg_ha", "p_kg_ha", "k_kg_ha", "ph", "oc_pct")}
    weather = {
        "rainfall_cum_mm": row["rainfall_cum_mm"],
        "rainfall_last30_mm": row["rainfall_last30_mm"],
        "dry_spell_max_days": row["dry_spell_max_days"],
        "temp_mean_c": row["temp_mean_c"],
        "temp_max_c": row["temp_max_c"],
        "gdd": row["gdd"],  # pre-computed in the training CSV -> skips recompute-from-daily-series path
        "humidity_mean_pct": row["humidity_mean_pct"],
        "et0_cum_mm": row["et0_cum_mm"],
    }
    ndvi = None
    if pd.notna(row["ndvi_mean"]):
        ndvi = {k: row[k] for k in ("ndvi_mean", "ndvi_max", "ndvi_p90", "ndvi_slope_30d", "ndvi_auc")}
    return build_feature_row(
        soil=soil, weather=weather, ndvi=ndvi, area_ha=row["area_ha"], crop=row["crop"],
        district=row["district"], season=row["season"],
    )


def _load_dataset() -> pd.DataFrame:
    raw = pd.read_csv(TRAINING_CSV)
    feature_rows = [_row_to_features(row) for _, row in raw.iterrows()]
    df = pd.DataFrame(feature_rows)
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


def _eval(model, x_test: pd.DataFrame, y_test: pd.Series) -> dict:
    pred = model.predict(x_test)
    return {
        "r2": round(float(r2_score(y_test, pred)), 4),
        "rmse": round(float(np.sqrt(mean_squared_error(y_test, pred))), 4),
        "mae": round(float(mean_absolute_error(y_test, pred)), 4),
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

    # --- P1: random split ---------------------------------------------------
    x_train, x_test, y_train, y_test = train_test_split(x_full, y, test_size=0.2, random_state=42)
    p1_model = _fit_lgbm(x_train, y_train)
    p1 = _eval(p1_model, x_test, y_test)

    # --- P2: grouped CV by district ------------------------------------------
    gkf = GroupKFold(n_splits=5)
    p2_folds = []
    for train_idx, test_idx in gkf.split(x_full, y, groups=df["district"]):
        fold_model = _fit_lgbm(x_full.iloc[train_idx], y.iloc[train_idx], n_estimators=400)
        p2_folds.append(_eval(fold_model, x_full.iloc[test_idx], y.iloc[test_idx]))
    p2 = {k: round(float(np.mean([f[k] for f in p2_folds])), 4) for k in ("r2", "rmse", "mae")}

    # --- P3: temporal holdout (train <= 2020, test >= 2021) -----------------
    train_mask = df["year"] <= 2020
    test_mask = df["year"] >= 2021
    x_temporal_cols_with_district = FEATURE_COLUMNS
    x_temporal_cols_no_district = [c for c in FEATURE_COLUMNS if c not in TEMPORAL_EXCLUDED_CATEGORICAL]

    p3_with_district = _fit_lgbm(
        x_full.loc[train_mask, x_temporal_cols_with_district], y[train_mask], n_estimators=600
    )
    p3_with_metrics = _eval(p3_with_district, x_full.loc[test_mask, x_temporal_cols_with_district], y[test_mask])

    p3_no_district = _fit_lgbm(
        x_full.loc[train_mask, x_temporal_cols_no_district], y[train_mask], n_estimators=600
    )
    p3_no_metrics = _eval(p3_no_district, x_full.loc[test_mask, x_temporal_cols_no_district], y[test_mask])

    baselines = _baseline_metrics(df[train_mask], df[test_mask])
    rmse_lift_pct = round(
        100 * (baselines["district_crop_mean"]["rmse"] - p3_no_metrics["rmse"]) / baselines["district_crop_mean"]["rmse"],
        1,
    )

    # --- Final shipped model: full data, full feature set --------------------
    final_model = _fit_lgbm(x_full, y)
    final_model.booster_.save_model(str(settings.model_dir / "yield_lgbm.txt"))

    q10 = _fit_lgbm(x_full, y, objective="quantile", alpha=0.10)
    q90 = _fit_lgbm(x_full, y, objective="quantile", alpha=0.90)
    q10.booster_.save_model(str(settings.model_dir / "yield_q10.txt"))
    q90.booster_.save_model(str(settings.model_dir / "yield_q90.txt"))

    with open(settings.model_dir / "feature_list.json", "w", encoding="utf-8") as f:
        json.dump({"columns": FEATURE_COLUMNS, "categories": CATEGORIES}, f, indent=2)

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
        {"rainfall_cum_mm": r["rainfall_cum_mm"], "yield_t_ha": r["yield_t_ha"], "crop": r["crop"]}
        for _, r in chart_sample.iterrows()
    ]
    with open(settings.model_dir / "yield_vs_rainfall.json", "w", encoding="utf-8") as f:
        json.dump({"points": chart_points}, f)

    metrics = {
        "model_version": settings.model_version,
        "trained_at": datetime.now(timezone.utc).isoformat(),
        "git_sha": _git_sha(),
        "row_count": len(df),
        "training_data_source": "synthetic_placeholder",
        "training_data_note": (
            "Generated by scripts/build_training_set.py — a structured synthetic panel standing in for the "
            "ICRISAT District Level Database (TRD SS5.1), which this environment cannot fetch at build time. "
            "Swap in the real ICRISAT CSV + Open-Meteo backfill without touching features.py or this script's "
            "evaluation logic."
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
