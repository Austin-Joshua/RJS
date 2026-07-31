"""Public ops dashboard API — metrics, live SSE log, demo rank."""
from __future__ import annotations

import json
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.api.v1.analytics import _read_json_artifact
from app.api.v1.dependencies import get_db
from app.core.config import get_settings
from app.db import models
from app.ops.journal import emit, recent, subscribe
from app.services.fusion import fuse_field
from app.services.rotation_service import rank_crops_for_field

router = APIRouter(prefix="/ops", tags=["ops"])


class DemoRankRequest(BaseModel):
    water_available_m3: float | None = Field(None, ge=0)
    budget_rs: float | None = Field(None, ge=0)


def _latest_soil_card(field: models.Field) -> models.SoilCard:
    if not field.soil_cards:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Farm has no soil card")
    return field.soil_cards[0]


def _demo_field(db: Session) -> models.Field:
    settings = get_settings()
    farmer_id = settings.dev_login_user or "demo-farmer"
    field = (
        db.query(models.Field)
        .filter(models.Field.farmer_id == farmer_id)
        .order_by(models.Field.created_at.asc())
        .first()
    )
    if field is None:
        raise HTTPException(
            status.HTTP_404_NOT_FOUND,
            detail=f"No demo farm for account '{farmer_id}'. Run scripts/seed_demo.py.",
        )
    return field


@router.get("/summary")
async def ops_summary() -> dict[str, Any]:
    """Aggregate yield + quantum benchmark metrics and recent journal events."""
    try:
        metrics = _read_json_artifact("metrics.json")
    except HTTPException:
        metrics = {}
    try:
        benchmark = _read_json_artifact("benchmark.json")
    except HTTPException:
        benchmark = {}

    temporal = (metrics.get("protocols") or {}).get("p3_temporal_holdout") or {}
    sparq = benchmark.get("sparq") or benchmark
    legacy = benchmark.get("baseline_qaoa") or {}

    return {
        "yield": {
            "r2": temporal.get("r2"),
            "rmse": temporal.get("rmse"),
            "mae": temporal.get("mae"),
            "row_count": metrics.get("row_count"),
        },
        "quantum": {
            "sparq": {
                "optimum_match_rate": sparq.get("optimum_match_rate"),
                "mean_feasible_rate": sparq.get("mean_feasible_rate"),
                "mean_simplex_rate": sparq.get("mean_simplex_rate"),
                "mean_uplift_vs_feasible_uniform": sparq.get("mean_uplift_vs_feasible_uniform"),
                "mean_t_s": sparq.get("mean_t_s"),
                "mean_n_qubits": sparq.get("mean_n_qubits"),
            },
            "legacy_qaoa": {
                "optimum_match_rate": legacy.get("optimum_match_rate"),
                "mean_feasible_rate": legacy.get("mean_feasible_rate"),
                "mean_uplift_vs_feasible_uniform": legacy.get("mean_uplift_vs_feasible_uniform"),
                "mean_t_s": legacy.get("mean_t_s"),
                "mean_n_qubits": legacy.get("mean_n_qubits"),
            },
        },
        "events": recent(80),
    }


@router.get("/events")
async def ops_events() -> StreamingResponse:
    """Server-Sent Events stream of pipeline journal entries."""

    async def stream():
        async for event in subscribe():
            yield f"data: {json.dumps(event)}\n\n"

    return StreamingResponse(stream(), media_type="text/event-stream")


@router.post("/demo-rank")
async def ops_demo_rank(payload: DemoRankRequest, db: Session = Depends(get_db)) -> dict[str, Any]:
    """Run rank on the seeded demo farm — powers the public ops dashboard sliders."""
    field = _demo_field(db)
    card = _latest_soil_card(field)

    emit(
        "demo_rank",
        f"Demo rank requested for {field.name}",
        data={
            "farm_id": field.id,
            "water_available_m3": payload.water_available_m3,
            "budget_rs": payload.budget_rs,
        },
    )

    fused = await fuse_field(
        district=field.district,
        lat=field.centroid_lat,
        lon=field.centroid_lon,
        sowing_date=field.sowing_date,
        boundary_geojson=field.boundary_geojson,
        soil_override=field.soil_override,
    )

    try:
        result = await rank_crops_for_field(
            field=field,
            soil_card=card.card,
            fused_signals=fused,
            water_available_m3=payload.water_available_m3,
            budget_rs=payload.budget_rs,
        )
    except RuntimeError as exc:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(exc)) from exc

    result["scenario"] = {
        "water_available_m3": payload.water_available_m3
        if payload.water_available_m3 is not None
        else (card.card.get("water") or {}).get("available_m3"),
        "budget_rs": payload.budget_rs,
        "persisted": False,
        "farm_name": field.name,
    }
    return result
