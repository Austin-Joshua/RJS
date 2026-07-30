"""Uploaded GeoTIFF raster CRUD + NDVI layer rendering (Landroid-style raster
pipeline). Pixel bytes live in Supabase Storage; only metadata + the cached
zonal NDVI mean are persisted in `raster_assets` (see app/db/models.py)."""
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, File, Form, HTTPException, Response, UploadFile, status
from sqlalchemy.orm import Session

from app.adapters import raster_storage
from app.api.v1.dependencies import get_db, get_owned_field, get_writable_field
from app.core.config import get_settings
from app.db import models
from app.schemas.responses import RasterAssetResponse, RasterUploadResponse
from app.services import raster_ndvi

router = APIRouter(tags=["rasters"])

ALLOWED_SUFFIXES = (".tif", ".tiff")


def _active_asset(db: Session, field_id: str, kind: str) -> models.RasterAsset | None:
    return (
        db.query(models.RasterAsset)
        .filter(
            models.RasterAsset.field_id == field_id,
            models.RasterAsset.kind == kind,
            models.RasterAsset.is_active.is_(True),
        )
        .first()
    )


def _to_response(asset: models.RasterAsset) -> RasterAssetResponse:
    return RasterAssetResponse(
        id=asset.id,
        field_id=asset.field_id,
        kind=asset.kind,
        file_name=asset.file_name,
        band=asset.band,
        crs=asset.crs,
        width=asset.width,
        height=asset.height,
        bounds=asset.bounds,
        stats=asset.stats,
        zonal_ndvi=asset.zonal_ndvi,
        is_active=asset.is_active,
        uploaded_at=asset.uploaded_at.isoformat(),
    )


@router.post("/fields/{field_id}/rasters", response_model=RasterUploadResponse, status_code=status.HTTP_201_CREATED)
async def upload_raster(
    field: models.Field = Depends(get_writable_field),
    db: Session = Depends(get_db),
    file: UploadFile = File(...),
    kind: str = Form("ndvi"),
    band: int = Form(1),
) -> RasterUploadResponse:
    settings = get_settings()
    fname = (file.filename or "").lower()
    if not fname.endswith(ALLOWED_SUFFIXES):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Only GeoTIFF (.tif / .tiff) is allowed")

    content = await file.read()
    max_bytes = settings.raster_max_upload_mb * 1024 * 1024
    if len(content) > max_bytes:
        raise HTTPException(
            status_code=status.HTTP_413_CONTENT_TOO_LARGE,
            detail=f"File too large (max {settings.raster_max_upload_mb} MB)",
        )
    if len(content) < 64:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="File too small to be a valid GeoTIFF")

    try:
        analysis = raster_ndvi.analyze_geotiff(content)
    except Exception as e:  # noqa: BLE001 — surfaced to the uploader, not swallowed
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Invalid GeoTIFF: {e}") from e

    # Zonal NDVI only makes sense for an actual NDVI raster — an RGB
    # orthomosaic or a DEM would just normalize reflectance/elevation values
    # into a meaningless [-1, 1] number.
    zonal = raster_ndvi.zonal_mean_ndvi(content, field.boundary_geojson, band=band) if kind == "ndvi" else None

    asset_id = str(uuid.uuid4())
    storage_path = f"rasters/{field.id}/{asset_id}_{file.filename}"
    try:
        raster_storage.upload(settings.raster_bucket, storage_path, content)
    except RuntimeError as e:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(e)) from e

    # Only one active asset per (field, kind) — e.g. re-uploading a fresher
    # orthomosaic retires the old one as the base layer.
    db.query(models.RasterAsset).filter(
        models.RasterAsset.field_id == field.id,
        models.RasterAsset.kind == kind,
        models.RasterAsset.is_active.is_(True),
    ).update({"is_active": False})

    asset = models.RasterAsset(
        id=asset_id,
        field_id=field.id,
        kind=kind,
        file_name=file.filename or "upload.tif",
        storage_bucket=settings.raster_bucket,
        storage_path=storage_path,
        band=band,
        crs=analysis.get("crs"),
        width=analysis.get("width"),
        height=analysis.get("height"),
        bounds=analysis.get("bounds"),
        stats=analysis.get("stats"),
        zonal_ndvi=zonal,
        is_active=True,
        uploaded_at=datetime.now(timezone.utc),
    )
    db.add(asset)
    db.commit()
    db.refresh(asset)

    return RasterUploadResponse(asset=_to_response(asset), analysis=analysis)


@router.get("/fields/{field_id}/rasters", response_model=list[RasterAssetResponse])
async def list_rasters(
    field: models.Field = Depends(get_owned_field),
    db: Session = Depends(get_db),
) -> list[RasterAssetResponse]:
    rows = (
        db.query(models.RasterAsset)
        .filter(models.RasterAsset.field_id == field.id)
        .order_by(models.RasterAsset.uploaded_at.desc())
        .all()
    )
    return [_to_response(r) for r in rows]


@router.delete("/fields/{field_id}/rasters/{asset_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_raster(
    asset_id: str,
    field: models.Field = Depends(get_writable_field),
    db: Session = Depends(get_db),
) -> None:
    asset = db.get(models.RasterAsset, asset_id)
    if asset is None or asset.field_id != field.id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Raster asset not found")
    try:
        raster_storage.delete(asset.storage_bucket, asset.storage_path)
    except RuntimeError as e:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(e)) from e
    db.delete(asset)
    db.commit()


def _png_response(rendered: tuple[bytes, tuple[float, ...]] | None, *, not_found_detail: str) -> Response:
    if rendered is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=not_found_detail)
    png_bytes, bounds = rendered
    return Response(content=png_bytes, media_type="image/png", headers={"X-Geo-Bounds": ",".join(map(str, bounds))})


@router.get("/fields/{field_id}/layers/raster-ndvi.png")
async def get_raster_ndvi_layer(
    field: models.Field = Depends(get_owned_field),
    db: Session = Depends(get_db),
) -> Response:
    """Toggleable NDVI overlay from an uploaded raster (drone/orthomosaic NDVI)."""
    asset = _active_asset(db, field.id, "ndvi")
    if asset is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No active NDVI raster for this field")
    try:
        content = raster_storage.download(asset.storage_bucket, asset.storage_path)
    except RuntimeError as e:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(e)) from e

    rendered = raster_ndvi.render_ndvi_png(content, field.boundary_geojson, band=asset.band)
    return _png_response(rendered, not_found_detail="Raster NDVI layer unavailable")


@router.get("/fields/{field_id}/layers/orthomosaic.png")
async def get_orthomosaic_layer(
    field: models.Field = Depends(get_owned_field),
    db: Session = Depends(get_db),
) -> Response:
    """The base map layer — a true-color crop of the uploaded orthomosaic,
    masked to the field boundary. NDVI/DEM overlays sit on top of this."""
    asset = _active_asset(db, field.id, "orthomosaic")
    if asset is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No active orthomosaic for this field")
    try:
        content = raster_storage.download(asset.storage_bucket, asset.storage_path)
    except RuntimeError as e:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(e)) from e

    rendered = raster_ndvi.render_true_color_png(content, field.boundary_geojson, bands=(1, 2, 3))
    return _png_response(rendered, not_found_detail="Orthomosaic layer unavailable")


@router.get("/fields/{field_id}/layers/dem-hillshade.png")
async def get_dem_hillshade_layer(
    field: models.Field = Depends(get_owned_field),
    db: Session = Depends(get_db),
) -> Response:
    """Optional relief overlay — grayscale hillshade from the uploaded DEM, masked to the field boundary."""
    asset = _active_asset(db, field.id, "dem")
    if asset is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No active DEM for this field")
    try:
        content = raster_storage.download(asset.storage_bucket, asset.storage_path)
    except RuntimeError as e:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(e)) from e

    rendered = raster_ndvi.render_hillshade_png(content, field.boundary_geojson, band=asset.band)
    return _png_response(rendered, not_found_detail="DEM hillshade layer unavailable")


@router.get("/fields/{field_id}/map-manifest")
async def get_map_manifest(
    field: models.Field = Depends(get_owned_field),
    db: Session = Depends(get_db),
) -> dict:
    """Single source of truth for the map UI: which layers exist for this
    field right now, so the frontend can render a base layer + a checklist of
    toggleable overlays instead of guessing which endpoints will 404."""
    base = f"/api/v1/fields/{field.id}"
    has_orthomosaic = _active_asset(db, field.id, "orthomosaic") is not None
    has_raster_ndvi = _active_asset(db, field.id, "ndvi") is not None
    has_dem = _active_asset(db, field.id, "dem") is not None

    return {
        "field_id": field.id,
        "base_layer": {
            "id": "orthomosaic",
            "name": "Orthomosaic (true color)",
            "url": f"{base}/layers/orthomosaic.png" if has_orthomosaic else None,
            "available": has_orthomosaic,
        },
        "overlays": [
            {
                "id": "ndvi_satellite",
                "name": "NDVI (Sentinel-2 / GEE)",
                "url": f"{base}/layers/ndvi.png",
                "available": True,  # ndvi_gee degrades to a 503 at request time, not listing time
                "default_on": True,
            },
            {
                "id": "ndvi_raster",
                "name": "NDVI (uploaded raster)",
                "url": f"{base}/layers/raster-ndvi.png" if has_raster_ndvi else None,
                "available": has_raster_ndvi,
                "default_on": has_raster_ndvi,
            },
            {
                "id": "dem_hillshade",
                "name": "Elevation (hillshade)",
                "url": f"{base}/layers/dem-hillshade.png" if has_dem else None,
                "available": has_dem,
                "default_on": False,
            },
        ],
    }
