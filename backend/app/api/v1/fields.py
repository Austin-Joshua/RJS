"""Field CRUD (FR-10..15). Ownership enforced server-side via
`get_owned_field` — an officer sees fields read-only, a farmer only their own."""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.adapters.district_lookup import resolve_district
from app.api.v1.dependencies import CurrentUser, get_current_user, get_db, get_owned_field, get_writable_field, require_farmer
from app.db import models
from app.schemas.requests import FieldBoundaryUpdateRequest, FieldCreateRequest, SoilOverrideRequest
from app.schemas.responses import FieldResponse, PlotOut
from app.services.geo_utils import compute_centroid_and_area

router = APIRouter(prefix="/fields", tags=["fields"])


def _get_or_create_farmer(db: Session, user: CurrentUser) -> models.Farmer:
    farmer = db.get(models.Farmer, user.id)
    if farmer is None:
        farmer = models.Farmer(id=user.id, phone=user.id, role=user.role)
        db.add(farmer)
        db.commit()
    return farmer


def _to_response(field: models.Field) -> FieldResponse:
    return FieldResponse(
        id=field.id,
        name=field.name,
        centroid={"lat": field.centroid_lat, "lon": field.centroid_lon},
        area_ha=field.area_ha,
        district=field.district,
        state=field.state,
        sowing_date=field.sowing_date,
        plots=[PlotOut(id=p.id, label=p.label, area_ha=p.area_ha) for p in field.plots],
    )


@router.get("", response_model=list[FieldResponse])
async def list_fields(db: Session = Depends(get_db), user: CurrentUser = Depends(get_current_user)) -> list[FieldResponse]:
    query = db.query(models.Field)
    if user.role == "farmer":
        query = query.filter(models.Field.farmer_id == user.id)
    return [_to_response(f) for f in query.all()]


@router.post("", response_model=FieldResponse, status_code=status.HTTP_201_CREATED)
async def create_field(
    payload: FieldCreateRequest, db: Session = Depends(get_db), user: CurrentUser = Depends(require_farmer)
) -> FieldResponse:
    farmer = _get_or_create_farmer(db, user)
    lat, lon, area_ha = compute_centroid_and_area(payload.boundary_geojson)
    district, state = resolve_district(lat, lon) or ("Thanjavur", "Tamil Nadu")

    field = models.Field(
        farmer_id=farmer.id,
        name=payload.name,
        boundary_geojson=payload.boundary_geojson,
        centroid_lat=lat,
        centroid_lon=lon,
        area_ha=area_ha,
        district=district,
        state=state,
        sowing_date=payload.sowing_date,
    )
    db.add(field)
    db.flush()

    plots = payload.plots or [{"label": "Plot 1", "area_ha": area_ha, "geom_geojson": None}]
    for plot_in in plots:
        label = plot_in.label if hasattr(plot_in, "label") else plot_in["label"]
        plot_area = plot_in.area_ha if hasattr(plot_in, "area_ha") else plot_in["area_ha"]
        geom = plot_in.geom_geojson if hasattr(plot_in, "geom_geojson") else plot_in.get("geom_geojson")
        db.add(models.Plot(field_id=field.id, label=label, area_ha=plot_area, geom_geojson=geom))

    db.commit()
    db.refresh(field)
    return _to_response(field)


@router.get("/{field_id}", response_model=FieldResponse)
async def get_field(field: models.Field = Depends(get_owned_field)) -> FieldResponse:
    return _to_response(field)


@router.put("/{field_id}/boundary", response_model=FieldResponse)
async def update_boundary(
    payload: FieldBoundaryUpdateRequest,
    field: models.Field = Depends(get_writable_field),
    db: Session = Depends(get_db),
) -> FieldResponse:
    lat, lon, area_ha = compute_centroid_and_area(payload.boundary_geojson)
    district, state = resolve_district(lat, lon) or (field.district, field.state)
    field.boundary_geojson = payload.boundary_geojson
    field.centroid_lat, field.centroid_lon, field.area_ha = lat, lon, area_ha
    field.district, field.state = district, state
    db.commit()
    db.refresh(field)
    return _to_response(field)


@router.post("/{field_id}/soil-override", response_model=FieldResponse)
async def soil_override(
    payload: SoilOverrideRequest,
    field: models.Field = Depends(get_writable_field),
    db: Session = Depends(get_db),
) -> FieldResponse:
    field.soil_override = {**payload.model_dump(), "source": "farmer_shc"}
    db.commit()
    db.refresh(field)
    return _to_response(field)


@router.delete("/{field_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_field(field: models.Field = Depends(get_writable_field), db: Session = Depends(get_db)) -> None:
    db.delete(field)
    db.commit()
