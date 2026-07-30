"""Loads trained LightGBM artifacts once at startup and serves predictions
(FR-30/31, TRD §5.4). Booster + two quantile boosters (P10/P90) share one
`feature_list.json`, which also pins the categorical code mapping so a
single-row inference frame can't silently drift from the training-time
category codes — that drift is the exact "training/serving skew" bug TRD
§13 calls out as the most likely demo-day surprise.
"""
import json
from functools import lru_cache

import lightgbm as lgb
import pandas as pd

from app.core.config import get_settings


class YieldModel:
    def __init__(self, booster: lgb.Booster, q10: lgb.Booster, q90: lgb.Booster, spec: dict):
        self.booster = booster
        self.q10 = q10
        self.q90 = q90
        self.columns: list[str] = spec["columns"]
        self.categories: dict[str, list[str]] = spec["categories"]

    def to_frame(self, row: dict) -> pd.DataFrame:
        ordered = {col: row.get(col) for col in self.columns}
        df = pd.DataFrame([ordered])
        for col in df.columns:
            if col in self.categories:
                df[col] = pd.Categorical(df[col], categories=self.categories[col])
            else:
                # A single all-None value (e.g. NDVI/gdd unavailable in DEMO_MODE
                # or a degraded fetch) makes pandas infer dtype "object", which
                # LightGBM rejects outright. Force float64 so NaN — not a
                # fabricated 0 — represents "unobserved" (FR-34).
                df[col] = pd.to_numeric(df[col], errors="coerce")
        return df

    def predict_row(self, row: dict) -> tuple[float, float, float]:
        df = self.to_frame(row)
        yield_t_ha = float(self.booster.predict(df)[0])
        p10 = float(self.q10.predict(df)[0])
        p90 = float(self.q90.predict(df)[0])
        lo, hi = sorted((p10, p90))  # guard quantile crossing at small demo-scale n
        return round(max(0.0, yield_t_ha), 3), round(max(0.0, lo), 3), round(max(0.0, hi), 3)


@lru_cache
def get_yield_model() -> "YieldModel | None":
    """Returns None (never raises) if artifacts aren't trained yet — callers
    (yield_service) surface this as a 503/degraded response rather than a
    crash, so the API can boot before `scripts/train_model.py` has run."""
    settings = get_settings()
    model_dir = settings.model_dir
    try:
        with open(model_dir / "feature_list.json", encoding="utf-8") as f:
            spec = json.load(f)
        booster = lgb.Booster(model_file=str(model_dir / "yield_lgbm.txt"))
        q10 = lgb.Booster(model_file=str(model_dir / "yield_q10.txt"))
        q90 = lgb.Booster(model_file=str(model_dir / "yield_q90.txt"))
    except (FileNotFoundError, lgb.basic.LightGBMError):
        return None
    return YieldModel(booster, q10, q90, spec)
