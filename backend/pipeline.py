"""End-to-end smoke check (TRD §11/§13): field -> fusion -> yield prediction
-> QAOA plan -> advisory, in one process. Run with `python pipeline.py`.

Forces DEMO_MODE so this always succeeds offline, in CI, and without
Supabase/GEE credentials configured — the fastest possible "does the whole
stack still work" check after a change, per TRD's framing of this file.
"""
import os
import sys

os.environ.setdefault("DEMO_MODE", "true")

import asyncio  # noqa: E402

from app.db import models  # noqa: E402
from app.db.session import SessionLocal, init_db  # noqa: E402
from app.ml.yield_model import get_yield_model  # noqa: E402
from app.services.fusion import fuse_field  # noqa: E402
from app.services.plan_service import build_plan, persist_plan  # noqa: E402

BOUNDARY = {
    "type": "Polygon",
    "coordinates": [[[79.05, 10.75], [79.06, 10.75], [79.06, 10.76], [79.05, 10.76], [79.05, 10.75]]],
}


async def run() -> dict:
    init_db()
    if get_yield_model() is None:
        print("No trained model found. Run: python -m scripts.build_training_set && python -m scripts.train_model", file=sys.stderr)
        sys.exit(1)

    db = SessionLocal()
    try:
        farmer = db.merge(models.Farmer(id="pipeline-check", phone="pipeline-check", role="farmer"))
        db.commit()

        field = models.Field(
            farmer_id="pipeline-check",
            name="Pipeline check field",
            boundary_geojson=BOUNDARY,
            centroid_lat=10.755,
            centroid_lon=79.055,
            area_ha=1.2,
            district="Thanjavur",
            state="Tamil Nadu",
            sowing_date="2026-06-15",
        )
        db.add(field)
        db.flush()
        db.add_all(
            [
                models.Plot(field_id=field.id, label="Plot 1", area_ha=0.6),
                models.Plot(field_id=field.id, label="Plot 2", area_ha=0.6),
            ]
        )
        db.commit()
        db.refresh(field)

        fused = await fuse_field(
            district=field.district,
            lat=field.centroid_lat,
            lon=field.centroid_lon,
            sowing_date=field.sowing_date,
            boundary_geojson=field.boundary_geojson,
        )
        assert fused["data_mode"] == "demo", "DEMO_MODE fixture path did not engage"

        plots_in = [{"plot_id": p.id, "area_ha": p.area_ha} for p in field.plots]
        result = await build_plan(
            field=field,
            plots_in=plots_in,
            candidate_crops=["paddy", "black_gram"],
            water_m3=5000,
            budget_rs=60000,
            price_overrides=None,
            fused_signals=fused,
        )
        persist_plan(db, field_id=field.id, result=result, constraints={"water_m3": 5000, "budget_rs": 60000})

        assert result["plan"]["assignments"], "plan produced no assignments"
        assert result["advisory"]["fertilizer"]["urea_bags"] >= 0
        assert "data_mode" in result and "timings" in result

        db.delete(field)
        db.delete(farmer)
        db.commit()
        return result
    finally:
        db.close()


def main() -> None:
    result = asyncio.run(run())
    plan, bench, adv = result["plan"], result["benchmark"], result["advisory"]
    print(f"solver={plan['solver']} net_value_rs={plan['net_value_rs']}")
    print(f"benchmark: n_qubits={bench['n_qubits']} approximation_ratio={bench['approximation_ratio']}")
    print(f"advisory: urea_bags={adv['fertilizer']['urea_bags']} dap_bags={adv['fertilizer']['dap_bags']}")
    print("PIPELINE OK")


if __name__ == "__main__":
    main()
