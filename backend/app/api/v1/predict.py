"""Classical yield prediction (FR-30..34). Quantum never touches this path."""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.api.v1.dependencies import CurrentUser, get_current_user, get_db, load_owned_field
from app.schemas.requests import PredictYieldRequest
from app.schemas.responses import PredictYieldResponse, YieldPrediction
from app.services.fusion import fuse_field
from app.services.yield_service import predict_yields

router = APIRouter(prefix="/predict", tags=["prediction"])


@router.post("/yield", response_model=PredictYieldResponse)
async def predict_yield(
    payload: PredictYieldRequest, db: Session = Depends(get_db), user: CurrentUser = Depends(get_current_user)
) -> PredictYieldResponse:
    field = load_owned_field(payload.field_id, db, user)
    fused = await fuse_field(
        district=field.district,
        lat=field.centroid_lat,
        lon=field.centroid_lon,
        sowing_date=field.sowing_date,
        boundary_geojson=field.boundary_geojson,
        soil_override=field.soil_override,
    )
    predictions, model = predict_yields(
        fused_signals=fused, area_ha=field.area_ha, district=field.district, crops=payload.crops
    )
    if model is None:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="Yield model not trained yet")
    return PredictYieldResponse(
        field_id=field.id, data_mode=fused["data_mode"], predictions=[YieldPrediction(**p) for p in predictions]
    )
