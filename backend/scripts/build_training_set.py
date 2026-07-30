"""Generates the yield training set (TRD §5.1).

ponytail: TRD specifies the ICRISAT District Level Database + an Open-Meteo
archive backfill as the real training source. That archive isn't fetchable
from this environment, so this script generates a structured *synthetic*
panel instead — same schema, same feature relationships (nutrient adequacy,
rainfall, NDVI, heat stress all move yield the way they should agronomically)
— purely so the rest of the pipeline (features.py -> train_model.py ->
metrics.json) runs end-to-end on real numbers rather than placeholders.
`metrics.json` records `training_data_source: "synthetic_placeholder"` so
this is never presented as real. Upgrade path: replace
`generate_synthetic_panel()` with a real ICRISAT CSV load + Open-Meteo
archive join; `build_feature_row` and every downstream consumer are already
written against the final schema and need no changes.
"""
import csv
import random
from pathlib import Path

from app.services.crop_reference import load_crops

OUT_PATH = Path(__file__).resolve().parents[1] / "data" / "training" / "yield_training_set.csv"

DISTRICTS = ["Thanjavur", "Tiruvarur", "Nagapattinam", "Tiruchirappalli", "Madurai"]
CROPS = ["paddy", "black_gram", "groundnut", "sugarcane", "maize"]
BASE_YIELD_T_HA = {"paddy": 4.5, "black_gram": 0.85, "groundnut": 1.8, "sugarcane": 68.0, "maize": 3.1}
YEARS = list(range(2010, 2024))
SEASONS = ["kharif", "rabi", "samba", "kuruvai"]
SAMPLES_PER_CELL = 12


def generate_synthetic_panel(seed: int = 42) -> list[dict]:
    rng = random.Random(seed)
    crops_cfg = load_crops()
    rows: list[dict] = []
    district_effect = {d: rng.uniform(-0.08, 0.08) for d in DISTRICTS}

    for district in DISTRICTS:
        for crop in CROPS:
            for year in YEARS:
                # Kept small relative to the nutrient/rainfall/NDVI effects below:
                # a district shift this size mostly reflects real, feature-correlated
                # agro-climatic differences, not an unlearnable random offset that
                # would make the temporal-holdout ablation meaningless either way.
                year_effect = rng.uniform(-0.06, 0.06)
                for _ in range(SAMPLES_PER_CELL):
                    n_kg_ha = rng.uniform(180, 400)
                    p_kg_ha = rng.uniform(8, 30)
                    k_kg_ha = rng.uniform(100, 350)
                    ph = rng.uniform(5.8, 8.3)
                    oc_pct = rng.uniform(0.3, 0.9)
                    rainfall_cum = rng.uniform(150, 900)
                    rainfall_last30 = rainfall_cum * rng.uniform(0.05, 0.25)
                    dry_spell = rng.randint(0, 25)
                    temp_mean = rng.uniform(24, 33)
                    temp_max = temp_mean + rng.uniform(3, 8)
                    humidity = rng.uniform(55, 90)
                    et0_cum = rng.uniform(150, 500)
                    t_base = crops_cfg[crop]["t_base_c"]
                    gdd = max(0.0, temp_mean - t_base) * 120 + rng.uniform(-50, 50)
                    area_ha = rng.uniform(0.4, 2.5)
                    season = rng.choice(SEASONS)

                    has_ndvi = year >= 2015  # Sentinel-2 exists only from 2015 (TRD §5.1)
                    ndvi_mean = round(rng.uniform(0.35, 0.78), 3) if has_ndvi else None
                    ndvi_max = round(ndvi_mean + rng.uniform(0.02, 0.1), 3) if has_ndvi else None
                    ndvi_p90 = round(ndvi_mean + rng.uniform(0.01, 0.06), 3) if has_ndvi else None
                    ndvi_slope_30d = round(rng.uniform(-0.01, 0.01), 5) if has_ndvi else None
                    ndvi_auc = round((ndvi_mean or 0) * 90, 2) if has_ndvi else None

                    nutrient_adequacy = (
                        min(1.2, n_kg_ha / 300) * 0.4 + min(1.2, p_kg_ha / 20) * 0.3 + min(1.2, k_kg_ha / 250) * 0.3
                    )
                    rainfall_factor = 1.0 - abs(rainfall_cum - 500) / 1500
                    ndvi_factor = 1.0 + ((ndvi_mean - 0.55) * 0.6 if has_ndvi else 0.0)
                    temp_penalty = 1.0 - max(0.0, temp_max - 36) * 0.02
                    dry_spell_penalty = 1.0 - min(0.3, dry_spell / 100)

                    yield_t_ha = (
                        BASE_YIELD_T_HA[crop]
                        * (0.55 + 0.45 * nutrient_adequacy)
                        * rainfall_factor
                        * ndvi_factor
                        * temp_penalty
                        * dry_spell_penalty
                        * (1 + district_effect[district])
                        * (1 + year_effect)
                        * rng.uniform(0.92, 1.08)
                    )
                    yield_t_ha = max(0.1, round(yield_t_ha, 3))

                    rows.append(
                        {
                            "year": year,
                            "district": district,
                            "crop": crop,
                            "season": season,
                            "n_kg_ha": round(n_kg_ha, 1),
                            "p_kg_ha": round(p_kg_ha, 1),
                            "k_kg_ha": round(k_kg_ha, 1),
                            "ph": round(ph, 2),
                            "oc_pct": round(oc_pct, 2),
                            "rainfall_cum_mm": round(rainfall_cum, 1),
                            "rainfall_last30_mm": round(rainfall_last30, 1),
                            "dry_spell_max_days": dry_spell,
                            "temp_mean_c": round(temp_mean, 2),
                            "temp_max_c": round(temp_max, 2),
                            "gdd": round(gdd, 1),
                            "humidity_mean_pct": round(humidity, 2),
                            "et0_cum_mm": round(et0_cum, 1),
                            "ndvi_mean": ndvi_mean,
                            "ndvi_max": ndvi_max,
                            "ndvi_p90": ndvi_p90,
                            "ndvi_slope_30d": ndvi_slope_30d,
                            "ndvi_auc": ndvi_auc,
                            "area_ha": round(area_ha, 3),
                            "yield_t_ha": yield_t_ha,
                        }
                    )
    return rows


def main() -> None:
    rows = generate_synthetic_panel()
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT_PATH, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)
    print(f"Wrote {len(rows)} rows to {OUT_PATH}")


if __name__ == "__main__":
    main()
