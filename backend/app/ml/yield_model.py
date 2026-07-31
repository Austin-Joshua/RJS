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
import numpy as np
import pandas as pd

from app.core.config import get_settings


class YieldModel:
    def __init__(self, booster: lgb.Booster, q10: lgb.Booster, q90: lgb.Booster, spec: dict):
        self.booster = booster
        self.q10 = q10
        self.q90 = q90
        self.columns: list[str] = spec["columns"]
        self.categories: dict[str, list[str]] = spec["categories"]
        # scripts/train_model.py fits on log1p(yield_t_ha) so sugarcane's
        # 100+ t/ha scale can't drown out the sub-5 t/ha crops (see its
        # LGBM_PARAMS comment) — raw booster output must be expm1'd back.
        self.log_target: bool = spec.get("target_transform") == "log1p"

    def _inverse_transform(self, value: float) -> float:
        return float(np.expm1(value)) if self.log_target else value

    def to_frame(self, row: dict) -> pd.DataFrame:
        ordered = {col: row.get(col) for col in self.columns}
        df = pd.DataFrame([ordered])
        for col in df.columns:
            if col in self.categories:
                df[col] = pd.Categorical(df[col], categories=self.categories[col])
            else:
                # A single all-None value (e.g. NDVI unavailable on a degraded
                # fetch) makes pandas infer dtype "object", which
                # LightGBM rejects outright. Force float64 so NaN — not a
                # fabricated 0 — represents "unobserved" (FR-34).
                df[col] = pd.to_numeric(df[col], errors="coerce")
        return df

    def predict_row(self, row: dict) -> tuple[float, float, float]:
        """Point estimate plus a P10-P90 band that always brackets it.

        The two quantile heads are fitted independently of the median model, so
        on crops with few rows or an extreme scale (sugarcane at ~100 t/ha
        against everything else under 5) they can cross each other, or land
        entirely on one side of the point estimate. A "10th percentile" above
        the estimate is not a band, it is a bug, and it would flow straight
        into the rupee figures a farmer sees.

        Sorting handles crossing; widening handles the bracket. Both are
        clamps on a model weakness, not a fix for it — `band_is_widened`
        reports when it fired so the UI can mark the confidence as reduced.
        """
        df = self.to_frame(row)
        yield_t_ha = max(0.0, self._inverse_transform(self.booster.predict(df)[0]))
        p10 = self._inverse_transform(self.q10.predict(df)[0])
        p90 = self._inverse_transform(self.q90.predict(df)[0])

        lo, hi = sorted((p10, p90))  # quantile heads can cross at small n
        lo, hi = min(lo, yield_t_ha), max(hi, yield_t_ha)
        return round(yield_t_ha, 3), round(max(0.0, lo), 3), round(max(0.0, hi), 3)

    def band_is_widened(self, row: dict) -> bool:
        """True when the quantile heads failed to bracket the point estimate."""
        df = self.to_frame(row)
        point = self._inverse_transform(self.booster.predict(df)[0])
        lo, hi = sorted(
            (self._inverse_transform(self.q10.predict(df)[0]), self._inverse_transform(self.q90.predict(df)[0]))
        )
        return not (lo <= point <= hi)


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
