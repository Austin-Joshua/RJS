"""Seed a demo account with real farms, so the app has something to show.

    python -m scripts.seed_demo              # create/refresh the demo account
    python -m scripts.seed_demo --clean      # remove it and exit
    python -m scripts.seed_demo --user <id>  # seed a specific account instead

WHAT THIS IS NOT
----------------
It is not mock data. Nothing here is a canned API response or a hand-written
result. The script supplies only what a farmer would type — location, land size,
and soil readings off a Soil Health Card — and then runs the **real** pipeline:
live weather and Sentinel-2, the trained LightGBM model, the agronomic gates,
and the quantum sequencer. Every yield, rupee figure and crop order it stores
was computed by the same code that serves a live request.

The three profiles are chosen to exercise genuinely different paths through the
gates, so the demo shows the app reasoning rather than repeating itself.
"""
import argparse
import asyncio
import sys

from app.db import models
from app.db.session import SessionLocal, init_db
from app.ml.yield_model import get_yield_model
from app.services.crop_feasibility import shortlist
from app.services.fusion import fuse_field
from app.services.rotation_service import rank_crops_for_field
from app.services.soil_card import build_soil_card

DEFAULT_USER = "demo-farmer"

# Real Thanjavur-district coordinates, real Soil Health Card value ranges.
FARMS = [
    {
        "name": "Home field (delta alluvium)",
        "lat": 10.7550,
        "lon": 79.0550,
        "area_ha": 1.2,
        "sowing_date": "2026-06-15",
        "soil": {
            "soil_type": "alluvial",
            "n_kg_ha": 245.0,  # low — the common delta nitrogen deficit
            "p_kg_ha": 17.0,
            "k_kg_ha": 205.0,
            "ph": 6.7,
            "oc_pct": 0.58,
            "ec_ds_m": 0.5,
            "water_available_m3": 11000.0,
        },
    },
    {
        "name": "Canal plot (heavy clay)",
        "lat": 10.7890,
        "lon": 79.1380,
        "area_ha": 0.8,
        "sowing_date": "2026-06-20",
        "soil": {
            # Clay + good water: paddy country. Exercises the drainage gate,
            # which excludes groundnut and maize but keeps the rice-fallow pulse.
            "soil_type": "clay",
            "n_kg_ha": 300.0,
            "p_kg_ha": 22.0,
            "k_kg_ha": 260.0,
            "ph": 7.3,
            "oc_pct": 0.64,
            "ec_ds_m": 0.7,
            "water_available_m3": 9000.0,
        },
    },
    {
        "name": "Upland strip (red soil, low water)",
        "lat": 10.7100,
        "lon": 78.9800,
        "area_ha": 0.6,
        "sowing_date": "2026-07-01",
        "soil": {
            # Light soil, little water, mildly alkaline: paddy is out on water,
            # so the plan has to come from the pulses and oilseeds.
            "soil_type": "red",
            "n_kg_ha": 190.0,
            "p_kg_ha": 11.0,
            "k_kg_ha": 150.0,
            "ph": 7.8,
            "oc_pct": 0.41,
            "ec_ds_m": 0.9,
            "water_available_m3": 3000.0,
        },
    },
]


def _square_boundary(lat: float, lon: float, area_ha: float) -> dict:
    import math

    side_m = math.sqrt(area_ha * 10_000.0)
    d_lat = (side_m / 2.0) / 111_320.0
    d_lon = (side_m / 2.0) / (111_320.0 * max(0.2, math.cos(math.radians(lat))))
    return {
        "type": "Polygon",
        "coordinates": [[
            [lon - d_lon, lat - d_lat], [lon + d_lon, lat - d_lat],
            [lon + d_lon, lat + d_lat], [lon - d_lon, lat + d_lat],
            [lon - d_lon, lat - d_lat],
        ]],
    }


def clean(db, user_id: str) -> int:
    """Delete the demo account and everything under it. Cascades handle the rest."""
    fields = db.query(models.Field).filter(models.Field.farmer_id == user_id).all()
    for field in fields:
        db.delete(field)
    farmer = db.get(models.Farmer, user_id)
    if farmer is not None:
        db.delete(farmer)
    db.commit()
    return len(fields)


async def seed(user_id: str) -> None:
    init_db()
    if get_yield_model() is None:
        print("No trained model. Run: python -m scripts.build_training_set && python -m scripts.train_model",
              file=sys.stderr)
        sys.exit(1)

    db = SessionLocal()
    try:
        removed = clean(db, user_id)
        if removed:
            print(f"Removed {removed} existing farm(s) for {user_id}\n")

        db.add(models.Farmer(id=user_id, phone=user_id, role="farmer", lang="en"))
        db.commit()

        for spec in FARMS:
            print(f"{spec['name']}")
            field = models.Field(
                farmer_id=user_id,
                name=spec["name"],
                boundary_geojson=_square_boundary(spec["lat"], spec["lon"], spec["area_ha"]),
                centroid_lat=spec["lat"],
                centroid_lon=spec["lon"],
                area_ha=spec["area_ha"],
                district="Thanjavur",
                state="Tamil Nadu",
                sowing_date=spec["sowing_date"],
                soil_override={**{k: spec["soil"][k] for k in
                                  ("n_kg_ha", "p_kg_ha", "k_kg_ha", "ph", "oc_pct", "ec_ds_m")},
                               "source": "farmer_entry"},
            )
            db.add(field)
            db.flush()
            db.add(models.Plot(field_id=field.id, label="Plot 1", area_ha=spec["area_ha"]))
            db.commit()
            db.refresh(field)

            card = build_soil_card(field_id=field.id, area_ha=field.area_ha, **spec["soil"])
            db.add(models.SoilCard(
                field_id=field.id, version=1, soil_type=spec["soil"]["soil_type"],
                readings=card.readings, classes=card.classes, card=card.to_dict(),
            ))
            db.commit()
            print(f"  soil card : {card.summary}")

            gates = shortlist(soil_card=card.to_dict(), area_ha=field.area_ha)
            print(f"  feasible  : {gates['counts']['feasible']}/{gates['counts']['assessed']} crops"
                  f"  ({', '.join(gates['rotation_candidates']) or 'none'})")

            fused = await fuse_field(
                district=field.district, lat=field.centroid_lat, lon=field.centroid_lon,
                sowing_date=field.sowing_date, boundary_geojson=field.boundary_geojson,
                soil_override=field.soil_override,
            )
            result = await rank_crops_for_field(
                field=field, soil_card=card.to_dict(), fused_signals=fused
            )

            ranking = result.get("ranking")
            if ranking is None:
                print(f"  ranking   : none - {result.get('error', '')[:70]}\n")
                continue

            db.add(models.RotationPlan(
                field_id=field.id, soil_card_id=None, version=1,
                solver=ranking["solver"],
                seasons={"seasons": ranking["seasons"]},
                sequence={"sequence": ranking["sequence"]},
                ranked_crops={"ranked_crops": ranking["ranked_crops"],
                              "crop_ranking": ranking["crop_ranking"]},
                total_value_rs=ranking["total_value_rs"],
                matched_exact_optimum=ranking["matched_exact_optimum"],
                feasibility=result["feasibility"],
                baselines=result.get("baselines") or {},
                quantum=result.get("quantum") or {},
                rotation_model=result.get("rotation_model") or {},
                advisory=result.get("advisory"),
            ))
            db.commit()

            q = result.get("quantum") or {}
            print(f"  plan      : {' -> '.join(ranking['sequence'])}"
                  f"  Rs{ranking['total_value_rs']:,.0f}  ({ranking['solver']})")
            if q:
                print(f"  quantum   : {q['n_qubits']} qubits, one-hot {q['simplex_rate']:.0%}, "
                      f"{len(q.get('measurements', []))} outcomes measured")
            adv = (result.get("advisory") or {}).get("fertilizer", {})
            if adv:
                print(f"  treatment : {adv.get('urea_bags', 0)} urea / {adv.get('dap_bags', 0)} DAP "
                      f"/ {adv.get('mop_bags', 0)} MOP bags")
            print(f"  data_mode : {result['data_mode']}\n")

        total = db.query(models.Field).filter(models.Field.farmer_id == user_id).count()
        print(f"Seeded {total} farm(s) for '{user_id}'.")
        print("\nTo sign in as this account, set in backend/.env:")
        print(f"  DEV_LOGIN_USER={user_id}")
        print("  DEV_LOGIN_TOKEN=<choose a secret>")
        print("then run the app with --dart-define=DEV_LOGIN_TOKEN=<the same secret>")
    finally:
        db.close()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--user", default=DEFAULT_USER, help="account id to seed")
    parser.add_argument("--clean", action="store_true", help="delete the account and exit")
    args = parser.parse_args()

    if args.clean:
        init_db()
        db = SessionLocal()
        try:
            print(f"Removed {clean(db, args.user)} farm(s) for '{args.user}'.")
        finally:
            db.close()
        return

    asyncio.run(seed(args.user))


if __name__ == "__main__":
    main()
