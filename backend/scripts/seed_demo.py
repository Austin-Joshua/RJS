"""Seeds the Thanjavur demo field + one warm plan (TRD §16 T-24h runbook,
step 3) so the demo survives a service restart — the whole reason plans are
persisted to Postgres instead of an in-memory store (TRD §9)."""
import asyncio

from app.core.config import get_settings
from app.db import models
from app.db.session import SessionLocal, init_db
from app.services.fusion import fuse_field
from app.services.plan_service import build_plan, persist_plan

DEMO_FARMER_ID = "demo-farmer"
DEMO_BOUNDARY = {
    "type": "Polygon",
    "coordinates": [[[79.05, 10.75], [79.06, 10.75], [79.06, 10.76], [79.05, 10.76], [79.05, 10.75]]],
}


async def _seed() -> None:
    init_db()
    db = SessionLocal()
    try:
        farmer = db.get(models.Farmer, DEMO_FARMER_ID)
        if farmer is None:
            farmer = models.Farmer(id=DEMO_FARMER_ID, phone=DEMO_FARMER_ID, role="farmer", lang="ta")
            db.add(farmer)
            db.commit()

        field = db.query(models.Field).filter(models.Field.farmer_id == DEMO_FARMER_ID).first()
        if field is None:
            field = models.Field(
                farmer_id=DEMO_FARMER_ID,
                name="Murugan's field (Thanjavur demo)",
                boundary_geojson=DEMO_BOUNDARY,
                centroid_lat=10.755,
                centroid_lon=79.055,
                area_ha=1.2,
                district="Thanjavur",
                state="Tamil Nadu",
                sowing_date="2026-06-15",
            )
            db.add(field)
            db.flush()
            db.add(models.Plot(field_id=field.id, label="Plot 1", area_ha=0.5))
            db.add(models.Plot(field_id=field.id, label="Plot 2", area_ha=0.4))
            db.add(models.Plot(field_id=field.id, label="Plot 3", area_ha=0.3))
            db.commit()
            db.refresh(field)
        print(f"Demo field: {field.id} ({field.name})")

        fused = await fuse_field(
            district=field.district,
            lat=field.centroid_lat,
            lon=field.centroid_lon,
            sowing_date=field.sowing_date,
            boundary_geojson=field.boundary_geojson,
            soil_override=field.soil_override,
        )
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
        print(f"Warm plan generated: solver={result['plan']['solver']}, net_value_rs={result['plan']['net_value_rs']}")
    finally:
        db.close()


def main() -> None:
    get_settings()
    asyncio.run(_seed())


if __name__ == "__main__":
    main()
