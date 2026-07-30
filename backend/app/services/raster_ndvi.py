"""Uploaded GeoTIFF raster analysis + NDVI zonal stats/blending.

Lets a ground-truth drone/orthomosaic NDVI raster complement the live
Sentinel-2/GEE signal (see app/services/fusion.py). Ported from the
Landroid-main reference project's birdscale_ndvi.py / raster_layers_render.py,
adapted to:
  - work entirely from in-memory bytes via rasterio.io.MemoryFile — the
    backend never writes the uploaded .tif to local disk (Supabase Storage
    holds it; app/adapters/raster_storage.py fetches bytes on demand);
  - this app's boundary_geojson shape (a raw GeoJSON geometry dict, see
    app/services/geo_utils.py), not Landroid's FeatureCollection.

Requires rasterio + Pillow — unlike the read-only signal adapters, an upload
endpoint with no analysis capability should fail loudly, not silently accept
un-analyzed data.
"""
from __future__ import annotations

import math
from typing import Any

import numpy as np


def _band_stats(arr: np.ndarray) -> dict[str, float]:
    flat = arr.astype(np.float64).ravel()
    valid = flat[np.isfinite(flat)]
    if valid.size == 0:
        return {"min": float("nan"), "max": float("nan"), "mean": float("nan")}
    return {"min": float(valid.min()), "max": float(valid.max()), "mean": float(valid.mean())}


def analyze_geotiff(content: bytes) -> dict[str, Any]:
    """CRS, dimensions, projected bounds, per-band min/max/mean over the full raster."""
    import rasterio

    with rasterio.io.MemoryFile(content) as memfile, memfile.open() as ds:
        bounds = {
            "left": float(ds.bounds.left),
            "bottom": float(ds.bounds.bottom),
            "right": float(ds.bounds.right),
            "top": float(ds.bounds.top),
        }
        out: dict[str, Any] = {
            "crs": ds.crs.to_string() if ds.crs else None,
            "width": int(ds.width),
            "height": int(ds.height),
            "count": int(ds.count),
            "bounds": bounds,
            "dtype": str(ds.dtypes[0]),
            "stats": [],
        }
        for i in range(1, ds.count + 1):
            band = ds.read(i, masked=True)
            arr = np.ma.filled(band.astype(np.float64), np.nan)
            out["stats"].append({"band": i, **_band_stats(arr)})
    return out


def _normalize_flat_values(values: list[float], scale: str) -> tuple[list[float], str]:
    """Map raw pixel values onto NDVI's [-1, 1] range.

    scale: "auto" infers from the data range (prefers -1..1, else 0..1, else
    0..255 byte); or force one of "minus1_1" | "zero_one" | "byte255".
    """
    if not values:
        return [], scale
    arr_max, arr_min = max(values), min(values)
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
        if scale == "zero_one":
            out.append(2.0 * max(0.0, min(1.0, float(x))) - 1.0)
        elif scale == "byte255":
            out.append((max(0.0, min(255.0, float(x))) / 255.0) * 2.0 - 1.0)
        else:  # minus1_1 (also the fallback for an unrecognized scale)
            out.append(max(-1.0, min(1.0, float(x))))
    return out, scale


def zonal_mean_ndvi(
    content: bytes,
    boundary_geojson: dict[str, Any],
    *,
    band: int = 1,
    scale_mode: str = "auto",
) -> dict[str, Any] | None:
    """Mean NDVI under the field polygon (WGS84 -> raster CRS mask), or None
    if the raster/band/polygon don't overlap or intersect."""
    import rasterio
    from rasterio.mask import mask as rio_mask
    from rasterio.warp import transform_geom

    try:
        with rasterio.io.MemoryFile(content) as memfile, memfile.open() as ds:
            if band > int(ds.count):
                return None
            geom_raster = transform_geom("EPSG:4326", ds.crs, boundary_geojson, precision=6)
            out_image, _transform = rio_mask(
                ds, [geom_raster], crop=True, filled=True, nodata=np.nan, indexes=band,
            )
    except Exception:  # noqa: BLE001 — mirrors ndvi_gee: analysis failure degrades, never raises
        return None

    flat = np.asarray(out_image, dtype=np.float64).ravel()
    flat = flat[np.isfinite(flat)]
    if flat.size == 0:
        return None

    normed, used_scale = _normalize_flat_values([float(x) for x in flat.tolist()], scale_mode)
    if not normed:
        return None

    return {
        "mean_ndvi": round(sum(normed) / len(normed), 4),
        "pixel_count": len(normed),
        "value_scale": used_scale,
        "band": band,
    }


def blend_ndvi(
    gee_mean: float | None,
    raster_zonal: dict[str, Any] | None,
    weight: float,
) -> tuple[float | None, dict[str, Any]]:
    """Weighted blend of the uploaded raster's zonal NDVI with satellite (GEE)
    NDVI: blended = weight * raster + (1 - weight) * gee. Falls back to
    whichever source is available if the other is missing."""
    w = max(0.0, min(1.0, weight))
    meta: dict[str, Any] = {"blend_weight_raster": w, "raster": None}
    if raster_zonal is None:
        return gee_mean, meta

    meta["raster"] = dict(raster_zonal)
    raster_mean = float(raster_zonal["mean_ndvi"])
    if gee_mean is None:
        return raster_mean, meta

    blended = w * raster_mean + (1.0 - w) * float(gee_mean)
    return round(blended, 4), meta


def _ndvi_array_to_minus1_1(arr: np.ndarray, scale_mode: str) -> np.ndarray:
    flat = arr.astype(np.float64).ravel()
    valid = np.isfinite(flat)
    if not valid.any():
        return np.full_like(arr, np.nan, dtype=np.float64)
    normed, _used = _normalize_flat_values([float(x) for x in flat[valid].tolist()], scale_mode)
    if not normed:
        return np.full_like(arr, np.nan, dtype=np.float64)
    out = np.full(flat.shape, np.nan, dtype=np.float64)
    out[valid] = np.array(normed, dtype=np.float64)
    return out.reshape(arr.shape)


def _rgba_ndvi(ndvi: np.ndarray) -> np.ndarray:
    """ndvi in [-1, 1], NaN outside the mask -> HxWx4 uint8 (red-green ramp,
    matching the existing GEE overlay in app/adapters/ndvi_gee.py getThumbURL vis_params)."""
    v = np.clip((ndvi + 1.0) / 2.0, 0.0, 1.0)
    r = np.where(np.isfinite(ndvi), (255 * (1.0 - v)).astype(np.uint8), 0)
    g = np.where(np.isfinite(ndvi), (255 * v).astype(np.uint8), 0)
    b = np.full_like(r, 40, dtype=np.uint8)
    a = np.where(np.isfinite(ndvi), 245, 0).astype(np.uint8)
    return np.stack([r, g, b, a], axis=-1)


def _mask_to_boundary(
    content: bytes,
    boundary_geojson: dict[str, Any],
    indexes: int | list[int],
) -> tuple[Any, tuple[float, float, float, float]] | None:
    """Shared crop step for every PNG layer renderer: mask + crop the raster
    to the field polygon and return (raw masked array, WGS84 bounds), or None
    if the band(s)/polygon don't line up with the raster."""
    import rasterio
    import rasterio.transform
    from rasterio.mask import mask as rio_mask
    from rasterio.warp import transform_bounds, transform_geom

    max_index = max(indexes) if isinstance(indexes, list) else indexes
    try:
        with rasterio.io.MemoryFile(content) as memfile, memfile.open() as ds:
            if max_index > int(ds.count):
                return None
            geom_raster = transform_geom("EPSG:4326", ds.crs, boundary_geojson, precision=6)
            out_image, out_transform = rio_mask(ds, [geom_raster], crop=True, filled=False, indexes=indexes)
            h, w = out_image.shape[-2], out_image.shape[-1]
            left, bottom, right, top = rasterio.transform.array_bounds(h, w, out_transform)
            bounds = transform_bounds(ds.crs, "EPSG:4326", left, bottom, right, top)
    except Exception:  # noqa: BLE001 — mirrors ndvi_gee: analysis failure degrades, never raises
        return None
    return out_image, tuple(bounds)


def _resize_max(rgba: np.ndarray, max_side: int) -> np.ndarray:
    from PIL import Image

    h, w = rgba.shape[:2]
    if max(h, w) <= max_side:
        return rgba
    scale = max_side / max(h, w)
    nh, nw = max(1, int(h * scale)), max(1, int(w * scale))
    # LANCZOS preserves edges better than bilinear (clearer overlays on the map).
    return np.array(Image.fromarray(rgba, mode="RGBA").resize((nw, nh), Image.Resampling.LANCZOS))


def _to_png(rgba: np.ndarray) -> bytes:
    import io

    from PIL import Image

    buf = io.BytesIO()
    Image.fromarray(rgba, mode="RGBA").save(buf, format="PNG", optimize=True)
    return buf.getvalue()


def render_ndvi_png(
    content: bytes,
    boundary_geojson: dict[str, Any],
    *,
    band: int = 1,
    scale_mode: str = "auto",
    max_side: int = 1024,
) -> tuple[bytes, tuple[float, float, float, float]] | None:
    """The toggleable NDVI overlay: PNG bytes + WGS84 (west, south, east,
    north) bounds, clipped to the field boundary, transparent outside the
    polygon and outside valid pixels — or None if it can't be rendered."""
    masked = _mask_to_boundary(content, boundary_geojson, band)
    if masked is None:
        return None
    out_image, bounds = masked

    arr = np.squeeze(np.ma.filled(np.ma.asarray(out_image, dtype=np.float64), np.nan))
    ndvi = _ndvi_array_to_minus1_1(arr, scale_mode)
    rgba = _resize_max(_rgba_ndvi(ndvi), max_side)
    return _to_png(rgba), bounds


def render_true_color_png(
    content: bytes,
    boundary_geojson: dict[str, Any],
    *,
    bands: tuple[int, int, int] = (1, 2, 3),
    max_side: int = 2048,
) -> tuple[bytes, tuple[float, float, float, float]] | None:
    """The base map layer under the NDVI overlay: a true-color crop of an
    uploaded orthomosaic, masked to the field boundary (transparent outside
    the polygon). Assumes an 8-bit RGB source (drone orthomosaics)."""
    masked = _mask_to_boundary(content, boundary_geojson, list(bands))
    if masked is None:
        return None
    out_image, bounds = masked

    arr = np.ma.asarray(out_image)
    outside = np.ma.getmaskarray(arr).any(axis=0)
    rgb = np.moveaxis(np.ma.filled(arr, 0), 0, -1).astype(np.uint8)
    alpha = np.where(outside, 0, 255).astype(np.uint8)
    rgba = _resize_max(np.dstack([rgb, alpha]), max_side)
    return _to_png(rgba), bounds


def _hillshade_rgba(elev: np.ndarray, *, azimuth_deg: float = 315.0, altitude_deg: float = 45.0) -> np.ndarray:
    """Classic hillshade -> RGBA (terrain gray, transparent where invalid)."""
    z_raw = np.asarray(elev, dtype=np.float64)
    valid = np.isfinite(z_raw)
    if not valid.any():
        raise ValueError("no valid elevation pixels")
    z = np.where(valid, z_raw, float(np.nanmedian(z_raw[valid])))
    dy, dx = np.gradient(z)
    slope = np.arctan(np.sqrt(dx * dx + dy * dy))
    aspect = np.arctan2(-dx, dy)
    az, al = np.radians(azimuth_deg), np.radians(altitude_deg)
    hs = np.clip(np.sin(al) * np.cos(slope) + np.cos(al) * np.sin(slope) * np.cos(az - aspect), -1.0, 1.0)
    gray = ((hs + 1.0) * 0.5 * 255).astype(np.uint8)
    a = np.where(valid, 220, 0).astype(np.uint8)
    return np.stack([gray, gray, gray, a], axis=-1)


def render_hillshade_png(
    content: bytes,
    boundary_geojson: dict[str, Any],
    *,
    band: int = 1,
    max_side: int = 2048,
) -> tuple[bytes, tuple[float, float, float, float]] | None:
    """Optional DEM overlay: grayscale hillshade crop, masked to the field boundary."""
    masked = _mask_to_boundary(content, boundary_geojson, band)
    if masked is None:
        return None
    out_image, bounds = masked

    arr = np.squeeze(np.ma.filled(np.ma.asarray(out_image, dtype=np.float64), np.nan))
    try:
        rgba = _resize_max(_hillshade_rgba(arr), max_side)
    except ValueError:
        return None
    return _to_png(rgba), bounds
