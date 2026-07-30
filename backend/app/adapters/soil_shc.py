"""Soil Health Card district baseline — offline-first (FR-20).

Runtime dependency: none. The portal is never called; `shc_districts.csv` is
scraped/cleaned once and committed (TRD §3.1).
"""
import csv
from datetime import datetime, timezone
from functools import lru_cache

from app.core.config import get_settings

RATING_BANDS = {
    "n_kg_ha": [(280, "Low"), (560, "Medium"), (float("inf"), "High")],
    "p_kg_ha": [(10, "Low"), (25, "Medium"), (float("inf"), "High")],
    "k_kg_ha": [(120, "Low"), (280, "Medium"), (float("inf"), "High")],
}


def _rate(nutrient: str, value: float) -> str:
    for threshold, label in RATING_BANDS[nutrient]:
        if value < threshold:
            return label
    return "High"


@lru_cache
def _load_csv() -> dict[str, dict]:
    settings = get_settings()
    path = settings.data_dir / "soil" / "shc_districts.csv"
    rows: dict[str, dict] = {}
    with open(path, encoding="utf-8") as f:
        for row in csv.DictReader(f):
            rows[row["district"]] = row
    return rows


def get_soil_baseline(district: str) -> dict | None:
    """Returns None (never raises) if the district isn't in the bundled table —
    the fusion service downgrades data_mode when this happens."""
    row = _load_csv().get(district)
    if row is None:
        return None

    n, p, k = float(row["n_kg_ha"]), float(row["p_kg_ha"]), float(row["k_kg_ha"])
    return {
        "n_kg_ha": n,
        "p_kg_ha": p,
        "k_kg_ha": k,
        "ph": float(row["ph"]),
        "oc_pct": float(row["oc_pct"]),
        "ec_ds_m": float(row["ec_ds_m"]),
        "n_class": _rate("n_kg_ha", n),
        "p_class": _rate("p_kg_ha", p),
        "k_class": _rate("k_kg_ha", k),
        "source": "district_shc",
        "source_url": row["source_url"],
        "year": row["year"],
        "fetched_at": datetime.now(timezone.utc).isoformat(),
    }


def rate_nutrient(nutrient: str, value: float) -> str:
    return _rate(nutrient, value)
