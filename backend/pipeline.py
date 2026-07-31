"""End-to-end smoke check of the farm flow, in one process.

    add farm -> soil card -> feasible crops -> quantum-ranked rotation -> advice

Run with `python pipeline.py`. This is the fastest "does the whole stack still
work" check after a change.

No fixture mode: weather and NDVI are fetched for real, and if a source is
unreachable the run continues with `data_mode: degraded` and says so. A green
run therefore means the real pipeline works, not that the canned JSON parsed.
"""
import asyncio
import sys

from app.db import models
from app.db.session import SessionLocal, init_db
from app.ml.yield_model import get_yield_model
from app.services.crop_feasibility import shortlist
from app.services.fusion import fuse_field
from app.services.rotation_service import rank_crops_for_field
from app.services.soil_card import build_soil_card

# A real smallholder profile: low nitrogen, near-neutral pH, delta alluvium.
SOIL = {
    "soil_type": "alluvial",
    "n_kg_ha": 245.0,
    "p_kg_ha": 17.0,
    "k_kg_ha": 205.0,
    "ph": 6.7,
    "oc_pct": 0.58,
    "ec_ds_m": 0.5,
    "water_available_m3": 11000.0,
}


async def run() -> dict:
    init_db()
    if get_yield_model() is None:
        print(
            "No trained model found. Run: python -m scripts.build_training_set && python -m scripts.train_model",
            file=sys.stderr,
        )
        sys.exit(1)

    db = SessionLocal()
    try:
        db.merge(models.Farmer(id="pipeline-check", phone="pipeline-check", role="farmer"))
        db.commit()

        field = models.Field(
            farmer_id="pipeline-check",
            name="Pipeline check farm",
            boundary_geojson={
                "type": "Polygon",
                "coordinates": [
                    [[79.05, 10.75], [79.06, 10.75], [79.06, 10.76], [79.05, 10.76], [79.05, 10.75]]
                ],
            },
            centroid_lat=10.755,
            centroid_lon=79.055,
            area_ha=1.5,
            district="Thanjavur",
            state="Tamil Nadu",
            sowing_date="2026-06-15",
        )
        db.add(field)
        db.commit()
        db.refresh(field)

        card = build_soil_card(field_id=field.id, area_ha=field.area_ha, **SOIL)
        field.soil_override = {**{k: SOIL[k] for k in ("n_kg_ha", "p_kg_ha", "k_kg_ha", "ph", "oc_pct")},
                               "source": "farmer_entry"}
        db.commit()

        gates = shortlist(soil_card=card.to_dict(), area_ha=field.area_ha)

        fused = await fuse_field(
            district=field.district,
            lat=field.centroid_lat,
            lon=field.centroid_lon,
            sowing_date=field.sowing_date,
            boundary_geojson=field.boundary_geojson,
            soil_override=field.soil_override,
        )

        result = await rank_crops_for_field(
            field=field, soil_card=card.to_dict(), fused_signals=fused
        )

        assert result.get("ranking"), result.get("error", "no ranking produced")
        assert result["quantum"]["simplex_rate"] == 1.0, "one crop per season must be structural"

        db.delete(field)
        db.commit()
        return {"card": card.to_dict(), "gates": gates, "result": result}
    finally:
        db.close()


def main() -> None:
    out = asyncio.run(run())
    card, gates, result = out["card"], out["gates"], out["result"]
    ranking, q, base = result["ranking"], result["quantum"], result["baselines"]

    print(f"\nSOIL CARD  ({card['soil_type']})")
    print(f"  {card['summary']}")
    print(f"  classes: {card['classes']}")

    print(f"\nFEASIBLE CROPS  ({gates['counts']['feasible']}/{gates['counts']['assessed']} passed)")
    for row in gates["feasible"]:
        print(f"  + {row['name_en']:<16} {row['reasons'][0]}")
    for row in gates["excluded"]:
        print(f"  - {row['name_en']:<16} {row['reasons'][0]}")

    print(f"\nQUANTUM-RANKED ROTATION  (solver={ranking['solver']})")
    for row in ranking["ranked_crops"]:
        print(
            f"  #{row['rank']}  {row['season']:<8} {row['name_en']:<16} "
            f"x{row['rotation_multiplier']:<6} Rs{row['realised_value_rs']:>10,.0f}"
        )
        print(f"        {row['why']}")
    print(f"  total: Rs{ranking['total_value_rs']:,.0f}   matched exact optimum: {ranking['matched_exact_optimum']}")

    print("\nWHY NOT JUST SORT?")
    srt, myo = base["sorted_by_yield"], base["greedy_with_lookback"]
    print(f"  sort by predicted profit : {' -> '.join(srt['sequence'])}")
    print(f"                             Rs{srt['value_rs']:,.0f}  (gap Rs{srt['gap_rs']:,.0f})")
    print(f"  greedy with lookback     : {' -> '.join(myo['sequence'])}")
    print(f"                             Rs{myo['value_rs']:,.0f}  (gap Rs{myo['gap_rs']:,.0f})")

    print("\nQUANTUM")
    print(f"  {q['n_qubits']} qubits ({q['encoding']}, 0 slack)  p={q['layers']}  {q['qubo_terms']} QUBO terms")
    print(f"  one crop per season : {q['simplex_rate']:.1%}  (structural, XY-ring mixer)")
    print(f"  circuit             : {q['circuit']['gate_counts']['total']} gates, "
          f"{q['circuit']['gate_counts']['entangling_mixer']} entangling")
    print(f"  convergence trace   : {len(q['convergence'])} COBYLA evaluations")
    print("  top measured outcomes:")
    for m in q["measurements"][:3]:
        seq = " -> ".join(m["label"]["sequence"]) if m.get("label") else m["bitstring"]
        print(f"    {m['probability']:>6.1%}  {seq}")

    adv = result["advisory"]["fertilizer"]
    print(f"\nTREATMENT: {adv['urea_bags']} bags urea, {adv['dap_bags']} DAP, {adv['mop_bags']} MOP")
    print(f"data_mode={result['data_mode']}  timings={result['timings']}")
    print("\nPIPELINE OK")


if __name__ == "__main__":
    main()
