"""
Landroid API — prefix `/api/v1`.

Run: `uvicorn app.main:app --reload --host 0.0.0.0 --port 8000` from `backend/`.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Annotated, Any

from dotenv import load_dotenv

# Load backend/.env before reading GEE_PROJECT_ID / credentials (gitignored).
_backend_root = Path(__file__).resolve().parent.parent
load_dotenv(_backend_root / ".env")

from fastapi import Depends, FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import Response
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, Field, model_validator

from .ai_signals import (
    build_land_health,
    build_plant_zones,
    build_valuation,
    map_layers_manifest,
)
from .auth_user import AuthUser, parse_bearer
from .birdscale_ndvi import (
    HARDCODED_ACTIVE_RELATIVE,
    resolve_dem_geotiff_path,
    resolve_dem_geotiff_path_for_parcel,
    resolve_ndvi_geotiff_path,
    resolve_ndvi_geotiff_path_for_parcel,
    write_active_ndvi_to_manifest,
)
from .config import DATA_DIR, LANDROID_ALLOW_SYNTHETIC_LAND_HEALTH
from .geo import parse_boundary_geojson_bytes
from .gee_auth import (
    ensure_gee_initialized,
    gee_credentials_configured,
    get_gee_last_error,
    resolve_gee_project_id,
)
from .gee_signals import compute_gee_land_signals
from .parcel_store import ParcelRecord, store
from .user_registry import resolve_owner_user_id
from .raster_eval import evaluate_raster_for_parcel
from .raster_layers_render import (
    render_parcel_dem_hillshade_png,
    render_parcel_ndvi_png,
    render_parcel_zones_png,
    render_placeholder_ndvi_png,
    render_placeholder_zones_png,
)
from .soilgrids_client import fetch_soil_at_point, summarize_soil_json

MAX_GEOTIFF_BYTES = 150 * 1024 * 1024

_log = logging.getLogger(__name__)

# Last Earth Engine compute failure (for /healthz); cleared on success.
_last_gee_signal_error: str | None = None

app = FastAPI(title="Landroid API", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

bearer_scheme = HTTPBearer(auto_error=False)


async def get_current_user(
    creds: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer_scheme)],
    request: Request,
) -> AuthUser:
    auth = request.headers.get("authorization")
    if creds:
        auth = f"Bearer {creds.credentials}"
    user = parse_bearer(auth)
    if user is None:
        raise HTTPException(status_code=401, detail="Unauthorized")
    return user


def _can_access_parcel(user: AuthUser, parcel: ParcelRecord) -> bool:
    if user.role == "consultant":
        return True
    return parcel.owner_user_id == user.sub


def get_parcel_or_404(parcel_id: str) -> ParcelRecord:
    p = store.get(parcel_id)
    if not p:
        raise HTTPException(status_code=404, detail="Parcel not found")
    return p


def _client_label(request: Request) -> str:
    """Optional Flutter hint: header ``X-Landroid-Client`` (e.g. ``map``, ``dashboard``)."""
    return (request.headers.get("x-landroid-client") or "").strip()


@app.on_event("startup")
async def _startup_seed() -> None:
    store.seed_default()
    if ensure_gee_initialized():
        _log.info(
            "Earth Engine ready (project=%s)",
            resolve_gee_project_id() or "(default)",
        )
    else:
        _log.warning(
            "Earth Engine not initialized — land health uses synthetic_demo until "
            "GEE_PROJECT_ID (or GOOGLE_CLOUD_PROJECT) and credentials are set. %s",
            get_gee_last_error() or "No credential file or CLI auth found.",
        )


@app.get("/healthz")
async def healthz() -> dict[str, Any]:
    uploads = Path(DATA_DIR) / "uploads" / "active_ndvi.tif"
    ee_ok = ensure_gee_initialized()
    return {
        "status": "ok",
        "earth_engine_configured": gee_credentials_configured(),
        "earth_engine_project": resolve_gee_project_id(),
        "earth_engine_initialized": ee_ok,
        "earth_engine_error": None if ee_ok else get_gee_last_error(),
        "earth_engine_last_signal_error": _last_gee_signal_error,
        "synthetic_land_health_allowed": LANDROID_ALLOW_SYNTHETIC_LAND_HEALTH,
        "data_dir": str(Path(DATA_DIR).resolve()),
        "active_upload_present": uploads.is_file(),
    }


@app.post("/api/v1/rasters/upload")
async def upload_geotiff(
    user: Annotated[AuthUser, Depends(get_current_user)],
    file: UploadFile = File(...),
    parcel_id: Annotated[str | None, Form()] = None,
    band: Annotated[int | None, Form()] = None,
) -> dict[str, Any]:
    """Land Consultant: save NDVI (or other) GeoTIFF and run evaluation."""
    if user.role != "consultant":
        raise HTTPException(status_code=403, detail="Consultant role required")
    fname = (file.filename or "").lower()
    if not fname.endswith((".tif", ".tiff")):
        raise HTTPException(status_code=400, detail="Only GeoTIFF (.tif / .tiff) is allowed")
    body = await file.read()
    if len(body) > MAX_GEOTIFF_BYTES:
        raise HTTPException(status_code=413, detail="File too large (max 150 MB)")
    if len(body) < 64:
        raise HTTPException(status_code=400, detail="File too small to be a valid GeoTIFF")

    uploads = Path(DATA_DIR) / "uploads"
    uploads.mkdir(parents=True, exist_ok=True)
    dest = uploads / "active_ndvi.tif"
    dest.write_bytes(body)
    write_active_ndvi_to_manifest(HARDCODED_ACTIVE_RELATIVE)

    parcel: ParcelRecord | None = None
    if parcel_id and parcel_id.strip():
        parcel = get_parcel_or_404(parcel_id.strip())

    b = band if band is not None else int(os.environ.get("LANDROID_NDVI_BAND", "1"))
    try:
        evaluation = await asyncio.to_thread(
            evaluate_raster_for_parcel,
            dest,
            parcel,
            b,
        )
    except RuntimeError as e:
        raise HTTPException(status_code=500, detail=str(e)) from e
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Evaluation failed: {e!s}") from e

    return {
        "saved_relative": HARDCODED_ACTIVE_RELATIVE,
        "saved_absolute": str(dest.resolve()),
        "evaluation": evaluation,
    }


@app.get("/api/v1/rasters/evaluate")
async def evaluate_geotiff(
    user: Annotated[AuthUser, Depends(get_current_user)],
    parcel_id: str | None = None,
    path: str | None = None,
    band: int | None = None,
) -> dict[str, Any]:
    """
    Analyze a GeoTIFF under ``data/``. Default path: manifest / ``uploads/active_ndvi.tif`` / env.
    Optional ``parcel_id`` adds zonal stats under the parcel polygon.
    """
    data_root = Path(DATA_DIR).resolve()
    if path and path.strip():
        rel = path.strip().replace("\\", "/")
        candidate = (data_root / rel).resolve()
        try:
            candidate.relative_to(data_root)
        except ValueError as e:
            raise HTTPException(status_code=400, detail="path must stay under data directory") from e
        if not candidate.is_file():
            raise HTTPException(status_code=404, detail=f"Not found: {rel}")
        tif_path = candidate
    else:
        from .birdscale_ndvi import resolve_ndvi_geotiff_path

        tif_path = resolve_ndvi_geotiff_path()
        if tif_path is None:
            raise HTTPException(
                status_code=404,
                detail="No GeoTIFF found. POST /api/v1/rasters/upload or set LANDROID_NDVI_GEOTIFF.",
            )

    parcel: ParcelRecord | None = None
    if parcel_id and parcel_id.strip():
        parcel = get_parcel_or_404(parcel_id.strip())
        if not _can_access_parcel(user, parcel):
            raise HTTPException(status_code=403, detail="Not assigned to this parcel")

    b = band if band is not None else int(os.environ.get("LANDROID_NDVI_BAND", "1"))
    try:
        return await asyncio.to_thread(evaluate_raster_for_parcel, tif_path, parcel, b)
    except RuntimeError as e:
        raise HTTPException(status_code=500, detail=str(e)) from e
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Evaluation failed: {e!s}") from e


async def _compute_land_health(
    parcel: ParcelRecord,
    *,
    caller: str = "unknown",
    client_hint: str = "",
) -> dict[str, Any]:
    global _last_gee_signal_error
    t0 = time.perf_counter()
    hint_txt = f" client={client_hint}" if client_hint else ""
    _log.info(
        "land_health.start caller=%s parcel_id=%s lat=%.5f lng=%.5f%s",
        caller,
        parcel.id,
        parcel.centroid["lat"],
        parcel.centroid["lng"],
        hint_txt,
    )
    soil_raw = await fetch_soil_at_point(parcel.centroid["lng"], parcel.centroid["lat"])
    soil = summarize_soil_json(soil_raw)
    gee_data: dict[str, Any] | None = None
    if ensure_gee_initialized():
        _log.info(
            "land_health.sentinel2_ee_begin caller=%s parcel_id=%s",
            caller,
            parcel.id,
        )
        try:
            gee_data = await asyncio.to_thread(compute_gee_land_signals, parcel)
            _last_gee_signal_error = None
        except Exception as e:
            _last_gee_signal_error = str(e)[:1200]
            _log.exception(
                "Earth Engine compute_gee_land_signals failed for parcel %s",
                parcel.id,
            )
            gee_data = None
    else:
        _log.info(
            "land_health.sentinel2_skipped caller=%s parcel_id=%s reason=earth_engine_not_initialized",
            caller,
            parcel.id,
        )
        hint = get_gee_last_error() or "Configure GEE_PROJECT_ID and GOOGLE_APPLICATION_CREDENTIALS"
        _last_gee_signal_error = f"Earth Engine not initialized: {hint}"[:1200]

    lh = build_land_health(parcel, soil, gee_data)
    elapsed_ms = (time.perf_counter() - t0) * 1000.0
    mode = str(lh.get("data_mode", "unknown"))
    meth = lh.get("methodology") if isinstance(lh.get("methodology"), dict) else {}
    ndvi_ds = meth.get("ndvi_source", "") if mode == "earth_engine" else ""
    _log.info(
        "land_health.done caller=%s parcel_id=%s data_mode=%s duration_ms=%.1f "
        "sentinel2_dataset=%s",
        caller,
        parcel.id,
        mode,
        elapsed_ms,
        ndvi_ds or ("synthetic_demo" if mode == "synthetic_demo" else "n/a"),
    )
    if (
        lh.get("data_mode") == "synthetic_demo"
        and not LANDROID_ALLOW_SYNTHETIC_LAND_HEALTH
    ):
        raise HTTPException(
            status_code=503,
            detail={
                "message": "Live Earth Engine land health required but unavailable.",
                "earth_engine_initialized": ensure_gee_initialized(),
                "last_error": _last_gee_signal_error or get_gee_last_error(),
                "hint": (
                    "Set GEE_PROJECT_ID (or GOOGLE_CLOUD_PROJECT), valid credentials, "
                    "enable Earth Engine API on the project, and register the service "
                    "account at https://code.earthengine.google.com/register — or set "
                    "LANDROID_ALLOW_SYNTHETIC_LAND_HEALTH=true for demo data."
                ),
            },
        )
    return lh


async def _warm_parcel_open_signals(parcel_id: str) -> None:
    """Prefetch land health, plant zones, and valuation in parallel after parcel create."""
    p = store.get(parcel_id)
    if not p:
        return
    try:
        lh_task = asyncio.create_task(
            _compute_land_health(p, caller="prefetch_warm", client_hint=""),
        )
        pz_task = asyncio.to_thread(build_plant_zones, p)
        lh, pz = await asyncio.gather(lh_task, pz_task)
        v = await asyncio.to_thread(build_valuation, p, lh)
        store.patch_meta(
            parcel_id,
            {
                "signals_warmed_at": datetime.now(timezone.utc).isoformat(),
                "prefetch_land_health": lh,
                "prefetch_plant_zones": pz,
                "prefetch_valuation": v,
            },
        )
    except Exception:
        store.patch_meta(
            parcel_id,
            {"signals_warm_failed": datetime.now(timezone.utc).isoformat()},
        )


class ParcelCreateBody(BaseModel):
    name: str = Field(..., min_length=1)
    owner_user_id: str | None = None
    owner_email: str | None = None
    owner_phone: str | None = None
    boundary_geojson: str | None = Field(
        default=None,
        description="Optional GeoJSON string (FeatureCollection or Feature, WGS84 or EPSG:32643).",
    )

    @model_validator(mode="after")
    def _require_owner(self) -> ParcelCreateBody:
        if not any(
            [
                self.owner_user_id and self.owner_user_id.strip(),
                self.owner_email and self.owner_email.strip(),
                self.owner_phone and self.owner_phone.strip(),
            ],
        ):
            raise ValueError("Provide owner_user_id, owner_email, or owner_phone")
        return self


@app.post("/api/v1/parcels")
async def create_parcel(
    body: ParcelCreateBody,
    user: Annotated[AuthUser, Depends(get_current_user)],
) -> dict[str, Any]:
    if user.role != "consultant":
        raise HTTPException(status_code=403, detail="Consultant role required")
    try:
        owner_uid = resolve_owner_user_id(
            owner_user_id=body.owner_user_id,
            owner_email=body.owner_email,
            owner_phone=body.owner_phone,
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e

    boundary_metrics: dict[str, Any] | None = None
    if body.boundary_geojson and body.boundary_geojson.strip():
        try:
            raw = body.boundary_geojson.strip().encode("utf-8")
            boundary_metrics = parse_boundary_geojson_bytes(raw)
        except ValueError as e:
            raise HTTPException(status_code=400, detail=f"Invalid boundary GeoJSON: {e}") from e

    n = len(store.list_ids()) + 1
    pid = f"parcel-{n}"
    p = store.create(
        parcel_id=pid,
        name=body.name.strip(),
        owner_user_id=owner_uid,
        boundary_metrics=boundary_metrics,
    )
    asyncio.create_task(_warm_parcel_open_signals(pid))
    return {"parcel": _parcel_summary(p)}


@app.get("/api/v1/parcels")
async def list_parcels(
    user: Annotated[AuthUser, Depends(get_current_user)],
) -> dict[str, Any]:
    out: list[dict[str, Any]] = []
    for pid in store.list_ids():
        p = store.get(pid)
        if p and _can_access_parcel(user, p):
            out.append(_parcel_summary(p))
    return {"parcels": out}


@app.get("/api/v1/parcels/{parcel_id}")
async def get_parcel(
    parcel_id: str,
    user: Annotated[AuthUser, Depends(get_current_user)],
) -> dict[str, Any]:
    """Single parcel summary (same shape as list items)."""
    p = get_parcel_or_404(parcel_id)
    if not _can_access_parcel(user, p):
        raise HTTPException(status_code=403, detail="Not assigned to this parcel")
    return {"parcel": _parcel_summary(p)}


@app.post("/api/v1/parcels/{parcel_id}/assets/orthomosaic-ndvi")
async def upload_parcel_orthomosaic_ndvi(
    parcel_id: str,
    user: Annotated[AuthUser, Depends(get_current_user)],
    file: UploadFile = File(...),
) -> dict[str, Any]:
    """Land Consultant: attach Birdscale orthomosaic / NDVI GeoTIFF to this parcel."""
    if user.role != "consultant":
        raise HTTPException(status_code=403, detail="Consultant role required")
    get_parcel_or_404(parcel_id)
    fname = (file.filename or "").lower()
    if not fname.endswith((".tif", ".tiff")):
        raise HTTPException(status_code=400, detail="Only GeoTIFF (.tif / .tiff) is allowed")
    body = await file.read()
    if len(body) > MAX_GEOTIFF_BYTES:
        raise HTTPException(status_code=413, detail="File too large (max 150 MB)")
    rel = f"uploads/{parcel_id}/orthomosaic_ndvi.tif"
    dest = Path(DATA_DIR) / rel.replace("/", os.sep)
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(body)
    store.patch_meta(parcel_id, {"ndvi_relpath": rel.replace("\\", "/")})
    write_active_ndvi_to_manifest(rel.replace("\\", "/"))
    return {"saved_relative": rel.replace("\\", "/"), "parcel_id": parcel_id}


@app.post("/api/v1/parcels/{parcel_id}/assets/dem")
async def upload_parcel_dem(
    parcel_id: str,
    user: Annotated[AuthUser, Depends(get_current_user)],
    file: UploadFile = File(...),
) -> dict[str, Any]:
    """Land Consultant: attach DEM GeoTIFF to this parcel."""
    if user.role != "consultant":
        raise HTTPException(status_code=403, detail="Consultant role required")
    get_parcel_or_404(parcel_id)
    fname = (file.filename or "").lower()
    if not fname.endswith((".tif", ".tiff")):
        raise HTTPException(status_code=400, detail="Only GeoTIFF (.tif / .tiff) is allowed")
    body = await file.read()
    if len(body) > MAX_GEOTIFF_BYTES:
        raise HTTPException(status_code=413, detail="File too large (max 150 MB)")
    rel = f"uploads/{parcel_id}/dem.tif"
    dest = Path(DATA_DIR) / rel.replace("/", os.sep)
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(body)
    store.patch_meta(parcel_id, {"dem_relpath": rel.replace("\\", "/")})
    return {"saved_relative": rel.replace("\\", "/"), "parcel_id": parcel_id}


@app.post("/api/v1/parcels/{parcel_id}/assets/boundary")
async def upload_parcel_boundary(
    parcel_id: str,
    user: Annotated[AuthUser, Depends(get_current_user)],
    file: UploadFile = File(...),
) -> dict[str, Any]:
    """Land Consultant: replace parcel boundary from GeoJSON file."""
    if user.role != "consultant":
        raise HTTPException(status_code=403, detail="Consultant role required")
    get_parcel_or_404(parcel_id)
    body = await file.read()
    if len(body) > 2 * 1024 * 1024:
        raise HTTPException(status_code=413, detail="Boundary file too large (max 2 MB)")
    try:
        metrics = parse_boundary_geojson_bytes(body)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e
    store.replace_boundary(parcel_id, metrics)
    asyncio.create_task(_warm_parcel_open_signals(parcel_id))
    return {"parcel_id": parcel_id, "area_acres_approx": metrics["area_acres_approx"]}


@app.get("/api/v1/parcels/{parcel_id}/documents")
async def list_parcel_documents(
    parcel_id: str,
    user: Annotated[AuthUser, Depends(get_current_user)],
) -> dict[str, Any]:
    p = get_parcel_or_404(parcel_id)
    if not _can_access_parcel(user, p):
        raise HTTPException(status_code=403, detail="Not assigned to this parcel")
    docs: list[dict[str, Any]] = [
        {
            "id": "capture-notes",
            "title": "Drone capture summary (Birdscale)",
            "mime": "text/plain",
        },
        {
            "id": "boundary-geojson",
            "title": "Parcel boundary (GeoJSON snapshot)",
            "mime": "application/geo+json",
        },
        {
            "id": "raster-manifest",
            "title": "Active raster manifest",
            "mime": "application/json",
        },
    ]
    return {"documents": docs}


@app.get("/api/v1/parcels/{parcel_id}/documents/{document_id}/download")
async def download_parcel_document(
    parcel_id: str,
    document_id: str,
    user: Annotated[AuthUser, Depends(get_current_user)],
) -> Response:
    p = get_parcel_or_404(parcel_id)
    if not _can_access_parcel(user, p):
        raise HTTPException(status_code=403, detail="Not assigned to this parcel")
    if document_id == "capture-notes":
        text = (
            f"Parcel: {p.name} ({p.id})\n"
            f"Area (approx acres): {p.area_acres_approx}\n"
            f"Centroid: {p.centroid['lat']:.6f}, {p.centroid['lng']:.6f}\n"
            "Source: consultant-uploaded Birdscale outputs.\n"
        )
        return Response(
            content=text.encode("utf-8"),
            media_type="text/plain; charset=utf-8",
            headers={
                "Content-Disposition": f'attachment; filename="capture-notes-{p.id}.txt"',
            },
        )
    if document_id == "boundary-geojson":
        payload = json.dumps(p.boundary, indent=2)
        return Response(
            content=payload.encode("utf-8"),
            media_type="application/geo+json",
            headers={
                "Content-Disposition": f'attachment; filename="boundary-{p.id}.geojson"',
            },
        )
    if document_id == "raster-manifest":
        from .birdscale_ndvi import read_raster_manifest

        payload = json.dumps(read_raster_manifest(), indent=2)
        return Response(
            content=payload.encode("utf-8"),
            media_type="application/json",
            headers={
                "Content-Disposition": f'attachment; filename="raster-manifest-{p.id}.json"',
            },
        )
    raise HTTPException(status_code=404, detail="Unknown document")


@app.get("/api/v1/parcels/{parcel_id}/gis-snapshot-report")
async def gis_snapshot_report(
    parcel_id: str,
    user: Annotated[AuthUser, Depends(get_current_user)],
    request: Request,
) -> Response:
    """Landowner/consultant: downloadable plain-text GIS intelligence snapshot."""
    p = get_parcel_or_404(parcel_id)
    if not _can_access_parcel(user, p):
        raise HTTPException(status_code=403, detail="Not assigned to this parcel")
    lh = await _compute_land_health(
        p,
        caller="gis_snapshot_report",
        client_hint=_client_label(request),
    )
    pz = build_plant_zones(p)
    v = build_valuation(p, lh)
    lines = [
        "LANDROID — GIS SNAPSHOT REPORT",
        f"Parcel: {p.name}",
        f"Parcel ID: {p.id}",
        f"Approx. acres: {p.area_acres_approx}",
        f"Centroid (WGS84): {p.centroid['lat']:.6f}, {p.centroid['lng']:.6f}",
        "",
        "--- Land health (summary) ---",
        str(lh.get("label", "")),
        f"Score: {lh.get('score', '')}",
        "",
        "--- Plant zones ---",
        str(pz.get("summary", pz)),
        "",
        "--- Valuation band ---",
        str(v),
        "",
        "Disclaimer: intelligence estimates only — not legal or cadastral fact.",
    ]
    body = "\n".join(lines).encode("utf-8")
    return Response(
        content=body,
        media_type="text/plain; charset=utf-8",
        headers={
            "Content-Disposition": f'attachment; filename="gis-snapshot-{p.id}.txt"',
        },
    )


def _parcel_summary(p: ParcelRecord) -> dict[str, Any]:
    return {
        "id": p.id,
        "name": p.name,
        "owner_user_id": p.owner_user_id,
        "centroid": p.centroid,
        "area_acres_approx": p.area_acres_approx,
    }


@app.get("/api/v1/parcels/{parcel_id}/layers/ndvi.png")
async def parcel_ndvi_png(
    parcel_id: str,
    user: Annotated[AuthUser, Depends(get_current_user)],
    request: Request,
    band: int | None = None,
) -> Response:
    """RGBA PNG overlay; bounds in ``X-Geo-Bounds: west,south,east,north`` (WGS84)."""
    p = get_parcel_or_404(parcel_id)
    if not _can_access_parcel(user, p):
        raise HTTPException(status_code=403, detail="Not assigned to this parcel")
    tif = resolve_ndvi_geotiff_path_for_parcel(p)
    synthetic = tif is None
    _log.info(
        "gis.layer_png layer=ndvi parcel_id=%s user_sub=%s role=%s overlay_source=%s client=%s",
        parcel_id,
        user.sub,
        user.role,
        "synthetic_placeholder" if synthetic else "geotiff",
        _client_label(request) or "—",
    )
    if synthetic:
        try:
            png, bounds = await asyncio.to_thread(render_placeholder_ndvi_png, p)
        except (OSError, RuntimeError, ValueError) as e:
            raise HTTPException(status_code=400, detail=str(e)) from e
    else:
        b = band if band is not None else int(os.environ.get("LANDROID_NDVI_BAND", "1"))
        try:
            png, bounds = await asyncio.to_thread(
                lambda: render_parcel_ndvi_png(p, tif, band=b),
            )
        except (OSError, RuntimeError, ValueError) as e:
            raise HTTPException(status_code=400, detail=str(e)) from e
    w, s, e, n = bounds
    return Response(
        content=png,
        media_type="image/png",
        headers={
            "X-Geo-Bounds": f"{w},{s},{e},{n}",
            "X-Landroid-Layer-Source": "synthetic" if synthetic else "geotiff",
            "Cache-Control": "public, max-age=300",
        },
    )


@app.get("/api/v1/parcels/{parcel_id}/layers/zones.png")
async def parcel_zones_png(
    parcel_id: str,
    user: Annotated[AuthUser, Depends(get_current_user)],
    request: Request,
    band: int | None = None,
) -> Response:
    """Plant health zone overlay (FR-25); same bounds header as NDVI PNG."""
    p = get_parcel_or_404(parcel_id)
    if not _can_access_parcel(user, p):
        raise HTTPException(status_code=403, detail="Not assigned to this parcel")
    tif = resolve_ndvi_geotiff_path_for_parcel(p)
    synthetic = tif is None
    _log.info(
        "gis.layer_png layer=plant_zones parcel_id=%s user_sub=%s role=%s overlay_source=%s client=%s",
        parcel_id,
        user.sub,
        user.role,
        "synthetic_placeholder" if synthetic else "geotiff",
        _client_label(request) or "—",
    )
    if synthetic:
        try:
            png, bounds = await asyncio.to_thread(render_placeholder_zones_png, p)
        except (OSError, RuntimeError, ValueError) as e:
            raise HTTPException(status_code=400, detail=str(e)) from e
    else:
        b = band if band is not None else int(os.environ.get("LANDROID_NDVI_BAND", "1"))
        try:
            png, bounds = await asyncio.to_thread(
                lambda: render_parcel_zones_png(p, tif, band=b),
            )
        except (OSError, RuntimeError, ValueError) as e:
            raise HTTPException(status_code=400, detail=str(e)) from e
    w, s, e, n = bounds
    return Response(
        content=png,
        media_type="image/png",
        headers={
            "X-Geo-Bounds": f"{w},{s},{e},{n}",
            "X-Landroid-Layer-Source": "synthetic" if synthetic else "geotiff",
            "Cache-Control": "public, max-age=300",
        },
    )


@app.get("/api/v1/parcels/{parcel_id}/layers/dem-raster.png")
async def parcel_dem_raster_png(
    parcel_id: str,
    user: Annotated[AuthUser, Depends(get_current_user)],
    request: Request,
    band: int | None = None,
) -> Response:
    """Hillshade PNG from local DEM GeoTIFF; bounds in ``X-Geo-Bounds``."""
    p = get_parcel_or_404(parcel_id)
    if not _can_access_parcel(user, p):
        raise HTTPException(status_code=403, detail="Not assigned to this parcel")
    dem = resolve_dem_geotiff_path_for_parcel(p)
    _log.info(
        "gis.layer_png layer=dem_hillshade parcel_id=%s user_sub=%s role=%s dem_available=%s client=%s",
        parcel_id,
        user.sub,
        user.role,
        dem is not None,
        _client_label(request) or "—",
    )
    if dem is None:
        raise HTTPException(status_code=404, detail="No DEM GeoTIFF in DATA_DIR")
    b = band if band is not None else int(os.environ.get("LANDROID_DEM_BAND", "1"))
    try:
        png, bounds = await asyncio.to_thread(
            lambda: render_parcel_dem_hillshade_png(p, dem, band=b),
        )
    except (OSError, RuntimeError, ValueError) as e:
        raise HTTPException(status_code=400, detail=str(e)) from e
    w, s, e, n = bounds
    return Response(
        content=png,
        media_type="image/png",
        headers={
            "X-Geo-Bounds": f"{w},{s},{e},{n}",
            "X-Landroid-Layer-Source": "local_geotiff",
            "Cache-Control": "public, max-age=300",
        },
    )


@app.get("/api/v1/parcels/{parcel_id}/map-manifest")
async def map_manifest(
    parcel_id: str,
    user: Annotated[AuthUser, Depends(get_current_user)],
    request: Request,
) -> dict[str, Any]:
    p = get_parcel_or_404(parcel_id)
    if not _can_access_parcel(user, p):
        raise HTTPException(status_code=403, detail="Not assigned to this parcel")
    hint = _client_label(request)
    lh = await _compute_land_health(
        p,
        caller="map_manifest",
        client_hint=hint,
    )
    manifest = map_layers_manifest(p, lh)
    layers = manifest.get("layers") or {}
    ndvi_layer = layers.get("ndvi") if isinstance(layers.get("ndvi"), dict) else {}
    ortho = layers.get("orthomosaic") if isinstance(layers.get("orthomosaic"), dict) else {}
    dem_l = layers.get("dem") if isinstance(layers.get("dem"), dict) else {}
    _log.info(
        "gis.map_manifest parcel_id=%s user_sub=%s role=%s data_mode=%s "
        "ndvi_png_overlay_source=%s orthomosaic_tiles=%s dem_layer_available=%s client=%s",
        parcel_id,
        user.sub,
        user.role,
        manifest.get("data_mode"),
        ndvi_layer.get("source"),
        ortho.get("available"),
        dem_l.get("available"),
        hint or "—",
    )
    return manifest


@app.get("/api/v1/ai/{parcel_id}/land-health")
async def ai_land_health(
    parcel_id: str,
    user: Annotated[AuthUser, Depends(get_current_user)],
    request: Request,
) -> dict[str, Any]:
    p = get_parcel_or_404(parcel_id)
    if not _can_access_parcel(user, p):
        raise HTTPException(status_code=403, detail="Not assigned to this parcel")
    lh = await _compute_land_health(
        p,
        caller="dashboard_land_health",
        client_hint=_client_label(request),
    )
    return {"land_health": lh}


@app.get("/api/v1/ai/{parcel_id}/plant-zones")
async def ai_plant_zones(
    parcel_id: str,
    user: Annotated[AuthUser, Depends(get_current_user)],
) -> dict[str, Any]:
    p = get_parcel_or_404(parcel_id)
    if not _can_access_parcel(user, p):
        raise HTTPException(status_code=403, detail="Not assigned to this parcel")
    return {"plant_zones": build_plant_zones(p)}


@app.get("/api/v1/ai/{parcel_id}/valuation")
async def ai_valuation(
    parcel_id: str,
    user: Annotated[AuthUser, Depends(get_current_user)],
    request: Request,
) -> dict[str, Any]:
    p = get_parcel_or_404(parcel_id)
    if not _can_access_parcel(user, p):
        raise HTTPException(status_code=403, detail="Not assigned to this parcel")
    lh = await _compute_land_health(
        p,
        caller="valuation",
        client_hint=_client_label(request),
    )
    v = build_valuation(p, lh)
    return {"valuation": v}
