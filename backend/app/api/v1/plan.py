"""The money endpoint (FR-40..46) plus the advisory read (FR-50..55)."""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.api.v1.dependencies import CurrentUser, get_current_user, get_db, get_owned_field, load_owned_field
from app.db import models
from app.schemas.requests import PlanRequest
from app.schemas.responses import PlanResponse
from app.services.fusion import fuse_field
from app.services.plan_service import build_plan, persist_plan

router = APIRouter(tags=["plan"])


@router.post("/plan", response_model=PlanResponse)
async def create_plan(
    payload: PlanRequest, db: Session = Depends(get_db), user: CurrentUser = Depends(get_current_user)
) -> PlanResponse:
    field = load_owned_field(payload.field_id, db, user)
    fused = await fuse_field(
        district=field.district,
        lat=field.centroid_lat,
        lon=field.centroid_lon,
        sowing_date=field.sowing_date,
        boundary_geojson=field.boundary_geojson,
        soil_override=field.soil_override,
    )
    try:
        result = await build_plan(
            field=field,
            plots_in=[p.model_dump() for p in payload.plots],
            candidate_crops=payload.candidate_crops,
            water_m3=payload.constraints.water_m3,
            budget_rs=payload.constraints.budget_rs,
            price_overrides=payload.price_overrides,
            fused_signals=fused,
        )
    except RuntimeError as exc:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(exc)) from exc

    persist_plan(db, field_id=field.id, result=result, constraints=payload.constraints.model_dump())
    return PlanResponse(**result)


@router.get("/fields/{field_id}/advisory")
async def get_latest_advisory(field: models.Field = Depends(get_owned_field), db: Session = Depends(get_db)) -> dict:
    plan_row = (
        db.query(models.Plan)
        .filter(models.Plan.field_id == field.id)
        .order_by(models.Plan.created_at.desc())
        .first()
    )
    if plan_row is None or plan_row.advisory is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No plan generated for this field yet")
    adv = plan_row.advisory
    return {"fertilizer": adv.fertilizer, "ph": adv.ph, "irrigation": adv.irrigation, "why": adv.why}
