"""Per-prediction and global SHAP (FR-32, TRD §5.4) — classical explanation,
never a quantum-flavoured substitute (PRD §5 explicitly forbids that claim)."""
import json
from functools import lru_cache

import shap

from app.core.config import get_settings
from app.ml.yield_model import YieldModel


def per_prediction_shap(model: YieldModel, row: dict) -> dict[str, float]:
    df = model.to_frame(row)
    explainer = shap.TreeExplainer(model.booster)
    values = explainer.shap_values(df)  # shape (1, n_features) for single-output regression
    row_values = values[0]
    return {col: round(float(v), 4) for col, v in zip(model.columns, row_values)}


@lru_cache
def load_global_shap() -> dict | None:
    settings = get_settings()
    path = settings.model_dir / "shap_global.json"
    if not path.exists():
        return None
    with open(path, encoding="utf-8") as f:
        return json.load(f)
