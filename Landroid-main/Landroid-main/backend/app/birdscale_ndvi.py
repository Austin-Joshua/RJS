"""
Birdscale / local NDVI GeoTIFF — FR-18 “current” from drone raster when available.

Place a file under LANDROID_DATA_DIR (e.g. data/ndvi.tif) or set LANDROID_NDVI_GEOTIFF
to an absolute path. Zonal mean NDVI is computed under the parcel polygon (WGS84 → raster CRS).

Value scaling (LANDROID_NDVI_VALUE_SCALE):
  - auto: infer from data range (prefer -1..1, else 0..1, else 0..255 byte)
  - minus1_1: clip to [-1, 1]
  - zero_one: map [0, 1] → [-1, 1] as 2*x-1
  - byte255: map [0, 255] → [-1, 1] as (x/255)*2 - 1

Requires: rasterio (+ numpy). If rasterio is missing, functions return None.
"""

from __future__ import annotations

import json
import math
import os
from pathlib import Path
from typing import Any

from .parcel_store import ParcelRecord

MANIFEST_NAME = "raster_manifest.json"
# Default location after consultant upload (see POST /api/v1/rasters/upload).
HARDCODED_ACTIVE_RELATIVE = "uploads/active_ndvi.tif"


def _looks_like_dem_filename(name: str) -> bool:
    """Filenames we treat as elevation / DEM (not NDVI)."""
    n = name.lower()
    keys = (
        "elevation",
        "dem",
        "dtm",
        "dsm",
        "slope",
        "hillshade",
        "terrain",
        "lidar",
    )
    return any(k in n for k in keys) or "elevation model" in n


def _repo_data_dir() -> Path:
    from .config import DATA_DIR

    return DATA_DIR


def _manifest_path() -> Path:
    return _repo_data_dir() / MANIFEST_NAME


def read_raster_manifest() -> dict[str, Any]:
    p = _manifest_path()
    if not p.is_file():
        return {}
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return {}


def write_active_ndvi_to_manifest(relative_path: str) -> None:
    """``relative_path`` is POSIX-style relative to DATA_DIR (e.g. uploads/foo.tif)."""
    data_dir = _repo_data_dir()
    data_dir.mkdir(parents=True, exist_ok=True)
    manifest = read_raster_manifest()
    manifest["active_ndvi"] = relative_path.replace("\\", "/")
    _manifest_path().write_text(
        json.dumps(manifest, indent=2),
        encoding="utf-8",
    )


def resolve_ndvi_geotiff_path() -> Path | None:
    explicit = os.environ.get("LANDROID_NDVI_GEOTIFF", "").strip()
    if explicit:
        p = Path(explicit).expanduser()
        if p.is_file():
            return p
    data_dir = _repo_data_dir()
    if not data_dir.is_dir():
        return None
    manifest = read_raster_manifest()
    rel = manifest.get("active_ndvi")
    if isinstance(rel, str) and rel.strip():
        candidate = (data_dir / rel.strip()).resolve()
        if candidate.is_file():
            return candidate
    hard = data_dir / HARDCODED_ACTIVE_RELATIVE.replace("/", os.sep)
    if hard.is_file():
        return hard
    for pattern in (
        "*ndvi*.tif",
        "*ndvi*.tiff",
        "*NDVI*.tif",
        "*NDVI*.tiff",
        "*shi*.tif",
        "*SHI*.tif",
        "*vegetation*.tif",
        "*health*.tif",
    ):
        matches = sorted(data_dir.glob(pattern))
        if matches:
            return matches[0]
    # Any GeoTIFF in data/ that is not obviously a DEM-only product.
    for pattern in ("*.tif", "*.tiff"):
        for candidate in sorted(data_dir.glob(pattern)):
            if candidate.is_file() and not _looks_like_dem_filename(candidate.name):
                return candidate
    uploads = data_dir / "uploads"
    if uploads.is_dir():
        for pattern in ("*.tif", "*.tiff"):
            matches = sorted(uploads.glob(pattern))
            if matches:
                return matches[-1]
    return None


def resolve_dem_geotiff_path() -> Path | None:
    """DEM / elevation GeoTIFF under DATA_DIR or ``LANDROID_DEM_GEOTIFF``."""
    explicit = os.environ.get("LANDROID_DEM_GEOTIFF", "").strip()
    if explicit:
        p = Path(explicit).expanduser()
        if p.is_file():
            return p
    data_dir = _repo_data_dir()
    if not data_dir.is_dir():
        return None
    manifest = read_raster_manifest()
    rel = manifest.get("active_dem")
    if isinstance(rel, str) and rel.strip():
        candidate = (data_dir / rel.strip()).resolve()
        if candidate.is_file():
            return candidate
    for pattern in (
        "*elevation*.tif",
        "*elevation*.tiff",
        "*dem*.tif",
        "*DEM*.tif",
        "*dtm*.tif",
    ):
        matches = sorted(data_dir.glob(pattern))
        if matches:
            return matches[0]
    for pattern in ("*.tif", "*.tiff"):
        for p in sorted(data_dir.glob(pattern)):
            if p.is_file() and _looks_like_dem_filename(p.name):
                return p
    return None


def resolve_ndvi_geotiff_path_for_parcel(parcel: ParcelRecord | None) -> Path | None:
    """Prefer parcel-specific orthomosaic/NDVI upload, then global manifest search."""
    if parcel is not None:
        rel = parcel.meta.get("ndvi_relpath") or parcel.meta.get("active_ndvi")
        if isinstance(rel, str) and rel.strip():
            candidate = (_repo_data_dir() / rel.strip().replace("/", os.sep)).resolve()
            if candidate.is_file():
                return candidate
    return resolve_ndvi_geotiff_path()


def resolve_dem_geotiff_path_for_parcel(parcel: ParcelRecord | None) -> Path | None:
    if parcel is not None:
        rel = parcel.meta.get("dem_relpath") or parcel.meta.get("active_dem")
        if isinstance(rel, str) and rel.strip():
            candidate = (_repo_data_dir() / rel.strip().replace("/", os.sep)).resolve()
            if candidate.is_file():
                return candidate
    return resolve_dem_geotiff_path()


def _normalize_flat_values(
    values: list[float],
    scale: str,
) -> tuple[list[float], str]:
    """Return values in approximately [-1, 1] NDVI space and the scale used."""
    if not values:
        return [], scale
    arr_max = max(values)
    arr_min = min(values)
    if scale == "auto":
        if -1.05 <= arr_min and arr_max <= 1.05:
            scale = "minus1_1"
        elif arr_min >= 0 and arr_max <= 1.0:
            scale = "zero_one"
        elif arr_min >= 0 and arr_max <= 255.0:
            scale = "byte255"
        else:
            scale = "minus1_1"

    out: list[float] = []
    for x in values:
        if not math.isfinite(x):
            continue
        if scale == "minus1_1":
            out.append(max(-1.0, min(1.0, float(x))))
        elif scale == "zero_one":
            v = max(0.0, min(1.0, float(x)))
            out.append(2.0 * v - 1.0)
        elif scale == "byte255":
            v = max(0.0, min(255.0, float(x)))
            out.append((v / 255.0) * 2.0 - 1.0)
        else:
            out.append(float(x))
    return out, scale


def sample_parcel_mean_ndvi(parcel: ParcelRecord) -> dict[str, Any] | None:
    """Mean NDVI under parcel boundary using resolved GeoTIFF path."""
    path = resolve_ndvi_geotiff_path_for_parcel(parcel)
    if path is None:
        return None
    band = max(1, int(os.environ.get("LANDROID_NDVI_BAND", "1")))
    return sample_parcel_mean_ndvi_from_path(parcel, path, band=band)


def sample_parcel_mean_ndvi_from_path(
    parcel: ParcelRecord,
    path: str | Path,
    *,
    band: int = 1,
    scale_mode: str | None = None,
) -> dict[str, Any] | None:
    """
    Zonal mean NDVI under parcel polygon for a specific GeoTIFF path.
    """
    try:
        import numpy as np
        import rasterio
        from rasterio.mask import mask as rio_mask
        from rasterio.warp import transform_geom
    except ImportError:
        return None

    path = Path(path)
    if not path.is_file():
        return None

    sm = scale_mode or os.environ.get("LANDROID_NDVI_VALUE_SCALE", "auto").strip() or "auto"
    geom = parcel.boundary["features"][0]["geometry"]

    try:
        with rasterio.open(path) as src:
            if band > int(src.count):
                return None
            geom_raster = transform_geom(
                "EPSG:4326",
                src.crs,
                geom,
                precision=6,
            )
            out_image, _transform = rio_mask(
                src,
                [geom_raster],
                crop=True,
                filled=True,
                nodata=np.nan,
                indexes=band,
            )
    except Exception:
        return None

    flat = np.asarray(out_image, dtype=np.float64).ravel()
    flat = flat[np.isfinite(flat)]
    if flat.size == 0:
        return None

    raw_list = [float(x) for x in flat.tolist()]
    normed, used_scale = _normalize_flat_values(raw_list, sm)
    if not normed:
        return None

    mean_ndvi = float(sum(normed) / len(normed))
    return {
        "file": path.name,
        "path": str(path.resolve()),
        "mean_ndvi": mean_ndvi,
        "pixel_count": len(normed),
        "value_scale": used_scale,
        "band": band,
    }


def blend_ndvi_current(
    gee_ndvi: float,
    bird: dict[str, Any] | None,
) -> tuple[float, dict[str, Any]]:
    """
    Blend Birdscale zonal mean with GEE Sentinel-2 current (FR-18).
    Weight w applies to Birdscale: current = w * bird + (1-w) * gee.
    """
    meta: dict[str, Any] = {
        "sentinel2_median_ndvi": round(gee_ndvi, 4),
        "birdscale": None,
        "blend_weight_birdscale": 0.0,
    }
    if not bird:
        return gee_ndvi, meta

    w = float(os.environ.get("LANDROID_NDVI_BLEND_WEIGHT", "0.5"))
    w = max(0.0, min(1.0, w))
    b = float(bird["mean_ndvi"])
    blended = w * b + (1.0 - w) * gee_ndvi
    meta["birdscale"] = {k: v for k, v in bird.items() if k != "path"}
    meta["blend_weight_birdscale"] = w
    meta["current_blended"] = round(blended, 4)
    return blended, meta
