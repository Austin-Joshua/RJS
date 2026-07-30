"""Shared loader for the agronomic reference config (`crops.yaml`,
`fertilizers.yaml`) used by ml/features, quantum/qubo, and services/advisory —
one file each, per the ponytail "don't rewrite what exists" rule."""
from functools import lru_cache

import yaml

from app.core.config import get_settings


@lru_cache
def load_crops() -> dict:
    settings = get_settings()
    with open(settings.model_dir / "crops.yaml", encoding="utf-8") as f:
        return yaml.safe_load(f)


@lru_cache
def load_fertilizers() -> dict:
    settings = get_settings()
    with open(settings.model_dir / "fertilizers.yaml", encoding="utf-8") as f:
        return yaml.safe_load(f)
