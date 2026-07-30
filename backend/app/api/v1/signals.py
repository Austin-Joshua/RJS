"""Fused signals + NDVI overlay/series (FR-20..25)."""
from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from sqlalchemy.orm import Session

from app.adapters.ndvi_gee import get_ndvi_png, get_ndvi_series
from app.adapters.prices_agmarknet import get_price_rs_per_quintal
from app.api.v1.dependencies import get_db, get_owned_field
from app.db import models
from app.schemas.responses import NdviSeriesPoint, NdviSeriesResponse, SignalsResponse
from app.services.fusion import fuse_field, season_start

router = APIRouter(tags=["signals"])


def _active_raster_ndvi(field_id: str, db: Session) -> dict | None:
    asset = (
        db.query(models.RasterAsset)
        .filter(
            models.RasterAsset.field_id == field_id,
            models.RasterAsset.kind == "ndvi",
            models.RasterAsset.is_active.is_(True),
        )
        .first()
    )
    return asset.zonal_ndvi if asset else None


@router.get("/fields/{field_id}/signals", response_model=SignalsResponse)
async def get_signals(
    field: models.Field = Depends(get_owned_field), db: Session = Depends(get_db)
) -> SignalsResponse:
    fused = await fuse_field(
        district=field.district,
        lat=field.centroid_lat,
        lon=field.centroid_lon,
        sowing_date=field.sowing_date,
        boundary_geojson=field.boundary_geojson,
        soil_override=field.soil_override,
        active_raster_ndvi=_active_raster_ndvi(field.id, db),
    )
    return SignalsResponse(
        field_id=field.id,
        data_mode=fused["data_mode"],
        fetched_at=fused["fetched_at"],
        soil=fused["soil"],
        weather=fused["weather"],
        ndvi=fused["ndvi"],
        provenance=fused["provenance"],
    )


@router.get("/fields/{field_id}/layers/ndvi.png")
async def get_ndvi_layer(field: models.Field = Depends(get_owned_field)) -> Response:
    from datetime import date

    start = season_start(field.sowing_date)
    end = date.today().isoformat()
    result = get_ndvi_png(field.boundary_geojson, start, end)
    if result is None:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="NDVI layer unavailable (degraded)")
    png_bytes, bounds = result
    return Response(content=png_bytes, media_type="image/png", headers={"X-Geo-Bounds": ",".join(map(str, bounds))})


@router.get("/fields/{field_id}/ndvi-series", response_model=NdviSeriesResponse)
async def get_ndvi_series_endpoint(field: models.Field = Depends(get_owned_field)) -> NdviSeriesResponse:
    from datetime import date

    start = season_start(field.sowing_date)
    end = date.today().isoformat()
    series = get_ndvi_series(field.boundary_geojson, start, end)
    return NdviSeriesResponse(
        field_id=field.id,
        data_mode="live" if series is not None else "degraded",
        series=[NdviSeriesPoint(**pt) for pt in (series or [])],
    )


@router.get("/prices")
async def get_price(crop: str = Query(...), district: str = Query(...)) -> dict:
    price = get_price_rs_per_quintal(crop, district)
    if price is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No price found for crop/district")
    return {"crop": crop, "district": district, "modal_price_rs_per_quintal": price}
