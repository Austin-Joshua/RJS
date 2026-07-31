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


@lru_cache
def load_rotation() -> dict:
    """Pairwise rotation-effect table (`rotation.yaml`).

    Separate from crops.yaml because it is indexed by (previous family, next
    family), not by crop. This table is what makes crop sequencing a genuine
    combinatorial problem rather than a sort — see the file's own header.
    """
    settings = get_settings()
    with open(settings.model_dir / "rotation.yaml", encoding="utf-8") as f:
        return yaml.safe_load(f)


def rotation_cfg(crop: str) -> dict:
    """Per-crop rotation block, with defaults for crops that predate it."""
    entry = load_crops().get(crop, {}).get("rotation")
    if not entry:
        return {
            "family": "cereal",
            "n_credit_kg_ha": 0.0,
            "rotation_eligible": True,
            "seasons": ["kharif", "rabi", "summer"],
            "ph_min": 5.5,
            "ph_max": 8.0,
        }
    return entry
