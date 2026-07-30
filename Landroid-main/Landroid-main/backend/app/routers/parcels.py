from fastapi import APIRouter, Depends, HTTPException, status

from app.models import ParcelCreateRequest, UserContext
from app.security import require_role
from app.services.geo import line_string_bbox_centroid, load_boundary

router = APIRouter(prefix="/parcels", tags=["parcels"])

PARCELS_DB: dict[str, dict] = {}


@router.post("")
def create_parcel(payload: ParcelCreateRequest, user: UserContext = Depends(require_role("consultant"))) -> dict:
    boundary = load_boundary(payload.boundary_geojson_path)
    bbox, centroid = line_string_bbox_centroid(boundary)
    parcel_id = f"parcel-{len(PARCELS_DB) + 1}"
    parcel = {
        "id": parcel_id,
        "name": payload.name,
        "owner_user_id": payload.owner_user_id,
        "bbox": bbox,
        "centroid": centroid,
        "ndvi_current": payload.ndvi_current,
        "ndvi_monthly_history": payload.ndvi_monthly_history,
        "ndvi_previous_survey": payload.ndvi_previous_survey,
        "area_acres": payload.area_acres,
    }
    PARCELS_DB[parcel_id] = parcel
    return parcel


@router.get("/{parcel_id}")
def get_parcel(parcel_id: str, user: UserContext = Depends(require_role("consultant", "landowner"))) -> dict:
    parcel = PARCELS_DB.get(parcel_id)
    if not parcel:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Parcel not found")
    if user.role == "landowner" and parcel["owner_user_id"] != user.uid:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Parcel not assigned to this owner")
    return parcel
