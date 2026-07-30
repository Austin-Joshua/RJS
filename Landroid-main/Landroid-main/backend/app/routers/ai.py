from fastapi import APIRouter, Depends, HTTPException, status

from app.models import UserContext
from app.routers.parcels import PARCELS_DB
from app.security import require_role
from app.services.ai import compute_land_health, compute_land_valuation, compute_ndvi_zones
from app.services.external_apis import ExternalAPIService

router = APIRouter(prefix="/ai", tags=["ai"])
external_service = ExternalAPIService()


def _authorized_parcel(parcel_id: str, user: UserContext) -> dict:
    parcel = PARCELS_DB.get(parcel_id)
    if not parcel:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Parcel not found")
    if user.role == "landowner" and parcel["owner_user_id"] != user.uid:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Parcel not assigned to this owner")
    return parcel


@router.get("/{parcel_id}/soil")
async def soil_probe(parcel_id: str, user: UserContext = Depends(require_role("consultant", "landowner"))) -> dict:
    parcel = _authorized_parcel(parcel_id, user)
    x, y = parcel["centroid"]
    # In this prototype, centroid from provided file is projected; map to plausible lat/lon for API query.
    lat, lon = 10.97, 78.71
    payload = await external_service.fetch_soilgrids(lat=lat, lon=lon)
    return {"parcel_id": parcel_id, "centroid_xy": [x, y], "soilgrids": payload}


@router.get("/{parcel_id}/land-health")
async def land_health(parcel_id: str, user: UserContext = Depends(require_role("consultant", "landowner"))) -> dict:
    parcel = _authorized_parcel(parcel_id, user)
    soil_quality = 68.0
    rainfall_adequacy = 61.0
    temperature_suitability = 58.0
    result = compute_land_health(
        ndvi_current=parcel["ndvi_current"],
        ndvi_history=parcel["ndvi_monthly_history"],
        rainfall_adequacy=rainfall_adequacy,
        soil_quality=soil_quality,
        temperature_suitability=temperature_suitability,
    )
    return {"parcel_id": parcel_id, "land_health": result.model_dump()}


@router.get("/{parcel_id}/plant-zones")
async def plant_zones(parcel_id: str, user: UserContext = Depends(require_role("consultant", "landowner"))) -> dict:
    parcel = _authorized_parcel(parcel_id, user)
    zones = compute_ndvi_zones(
        current_ndvi=parcel["ndvi_current"],
        previous_ndvi=parcel["ndvi_previous_survey"],
    )
    return {"parcel_id": parcel_id, "plant_zones": zones.model_dump()}


@router.get("/{parcel_id}/valuation")
async def valuation(parcel_id: str, user: UserContext = Depends(require_role("consultant", "landowner"))) -> dict:
    parcel = _authorized_parcel(parcel_id, user)
    health = compute_land_health(
        ndvi_current=parcel["ndvi_current"],
        ndvi_history=parcel["ndvi_monthly_history"],
        rainfall_adequacy=61.0,
        soil_quality=68.0,
        temperature_suitability=58.0,
    )
    location_signals = await external_service.fetch_location_signals(10.97, 78.71, parcel["bbox"])
    valuation_result = compute_land_valuation(
        health_score=health.score,
        soil_quality=68.0,
        rainfall_adequacy=61.0,
        location_score=72.0,
        night_lights_index=location_signals["night_lights_index"],
    )
    return {"parcel_id": parcel_id, "valuation": valuation_result.model_dump()}
