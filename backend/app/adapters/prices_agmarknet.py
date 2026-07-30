"""Crop modal prices — bundled CSV, farmer-overridable (FR-70/71, TRD §3.4)."""
import csv
from functools import lru_cache

from app.core.config import get_settings


@lru_cache
def _load_prices() -> dict[tuple[str, str], dict]:
    settings = get_settings()
    path = settings.data_dir / "prices" / "modal_prices.csv"
    rows: dict[tuple[str, str], dict] = {}
    with open(path, encoding="utf-8") as f:
        for row in csv.DictReader(f):
            rows[(row["crop"], row["district"])] = row
    return rows


def get_price_rs_per_quintal(crop: str, district: str) -> float | None:
    prices = _load_prices()
    row = prices.get((crop, district)) or prices.get((crop, "ALL"))
    return float(row["modal_price_rs_per_quintal"]) if row else None
