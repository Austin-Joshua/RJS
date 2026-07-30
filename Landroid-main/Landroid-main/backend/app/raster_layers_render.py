"""PNG overlays for GIS map (NDVI ramp, plant health zones) — FR-12 / FR-25."""

from __future__ import annotations

import io
import os
from pathlib import Path
from typing import Any

import numpy as np

from .birdscale_ndvi import _normalize_flat_values
from .parcel_store import ParcelRecord


def _bounds_wgs84(
    height: int,
    width: int,
    transform: Any,
    src_crs: Any,
) -> tuple[float, float, float, float]:
    import rasterio.transform
    from rasterio.warp import transform_bounds

    left, bottom, right, top = rasterio.transform.array_bounds(height, width, transform)
    return transform_bounds(src_crs, "EPSG:4326", left, bottom, right, top)


def _ndvi_array_to_minus1_1(arr: np.ndarray, scale_mode: str) -> np.ndarray:
    flat = arr.astype(np.float64).ravel()
    valid = np.isfinite(flat)
    if not valid.any():
        return np.full_like(arr, np.nan, dtype=np.float64)
    raw_list = [float(x) for x in flat[valid].tolist()]
    normed, _used = _normalize_flat_values(raw_list, scale_mode)
    if not normed:
        return np.full_like(arr, np.nan, dtype=np.float64)
    out = np.full(flat.shape, np.nan, dtype=np.float64)
    out[valid] = np.array(normed, dtype=np.float64)
    return out.reshape(arr.shape)


def _rgba_ndvi(ndvi: np.ndarray) -> np.ndarray:
    """ndvi in [-1,1] nan outside → HxWx4 uint8."""
    v = np.clip((ndvi + 1.0) / 2.0, 0.0, 1.0)
    v = np.where(np.isfinite(ndvi), v, np.nan)
    r = np.where(np.isfinite(v), (255 * (1.0 - v)).astype(np.uint8), 0)
    g = np.where(np.isfinite(v), (255 * v).astype(np.uint8), 0)
    b = np.full_like(r, 40, dtype=np.uint8)
    a = np.where(np.isfinite(ndvi), 245, 0).astype(np.uint8)
    return np.stack([r, g, b, a], axis=-1)


def _rgba_zones(ndvi: np.ndarray) -> np.ndarray:
    """FR-25 zone colors on normalized NDVI."""
    z = np.zeros(ndvi.shape, dtype=np.uint8)
    z[np.isfinite(ndvi) & (ndvi < 0.2)] = 1
    z[np.isfinite(ndvi) & (ndvi >= 0.2) & (ndvi < 0.4)] = 2
    z[np.isfinite(ndvi) & (ndvi >= 0.4) & (ndvi < 0.6)] = 3
    z[np.isfinite(ndvi) & (ndvi >= 0.6)] = 4
    colors = {
        0: (0, 0, 0, 0),
        1: (139, 0, 0, 210),
        2: (218, 165, 32, 210),
        3: (50, 205, 50, 210),
        4: (0, 100, 0, 210),
    }
    h, w = ndvi.shape
    rgba = np.zeros((h, w, 4), dtype=np.uint8)
    for k, c in colors.items():
        rgba[z == k] = c
    return rgba


def render_placeholder_ndvi_png(
    parcel: ParcelRecord,
    *,
    width: int = 256,
    height: int = 256,
) -> tuple[bytes, tuple[float, float, float, float]]:
    """When no GeoTIFF is configured, serve a visible red–green ramp over the parcel bbox."""
    from PIL import Image

    bbox = parcel.bbox
    west = float(bbox["min_lng"])
    south = float(bbox["min_lat"])
    east = float(bbox["max_lng"])
    north = float(bbox["max_lat"])
    img = Image.new("RGBA", (width, height))
    px = img.load()
    for y in range(height):
        for x in range(width):
            t = x / max(width - 1, 1)
            r = int(255 * (1.0 - t))
            g = int(255 * t)
            px[x, y] = (r, g, 40, 200)
    buf = io.BytesIO()
    img.save(buf, format="PNG", optimize=True)
    return buf.getvalue(), (west, south, east, north)


def render_placeholder_zones_png(
    parcel: ParcelRecord,
    *,
    width: int = 256,
    height: int = 256,
) -> tuple[bytes, tuple[float, float, float, float]]:
    """Four horizontal bands (FR-25 style) when no raster is available."""
    from PIL import Image

    bbox = parcel.bbox
    west = float(bbox["min_lng"])
    south = float(bbox["min_lat"])
    east = float(bbox["max_lng"])
    north = float(bbox["max_lat"])
    bands = [
        (139, 0, 0, 210),
        (218, 165, 32, 210),
        (50, 205, 50, 210),
        (0, 100, 0, 210),
    ]
    img = Image.new("RGBA", (width, height))
    px = img.load()
    bh = max(height // len(bands), 1)
    for i, rgba in enumerate(bands):
        y0 = i * bh
        y1 = height if i == len(bands) - 1 else min((i + 1) * bh, height)
        for y in range(y0, y1):
            for x in range(width):
                px[x, y] = rgba
    buf = io.BytesIO()
    img.save(buf, format="PNG", optimize=True)
    return buf.getvalue(), (west, south, east, north)


def _to_png(rgba: np.ndarray) -> bytes:
    from PIL import Image

    img = Image.fromarray(rgba, mode="RGBA")
    buf = io.BytesIO()
    img.save(buf, format="PNG", optimize=True)
    return buf.getvalue()


def _rio_mask_to_float_nan(out_image: Any) -> np.ndarray:
    """Convert rasterio mask output to a plain float array (masked → NaN)."""
    data = np.ma.asarray(out_image, dtype=np.float64)
    return np.squeeze(np.ma.filled(data, np.nan))


def _resize_max(rgba: np.ndarray, max_side: int) -> np.ndarray:
    from PIL import Image

    h, w = rgba.shape[:2]
    if max(h, w) <= max_side:
        return rgba
    scale = max_side / max(h, w)
    nh, nw = max(1, int(h * scale)), max(1, int(w * scale))
    img = Image.fromarray(rgba, mode="RGBA")
    # LANCZOS preserves edges better than bilinear (clearer NDVI / zones on map).
    img = img.resize((nw, nh), Image.Resampling.LANCZOS)
    return np.array(img)


def _png_max_side() -> int:
    raw = os.environ.get("LANDROID_MAP_PNG_MAX_SIDE", "2048").strip()
    try:
        n = int(raw)
    except ValueError:
        n = 2048
    return max(512, min(n, 8192))


def render_parcel_ndvi_png(
    parcel: ParcelRecord,
    tif_path: Path,
    *,
    band: int | None = None,
    max_side: int | None = None,
) -> tuple[bytes, tuple[float, float, float, float]]:
    """PNG bytes and WGS84 bounds (west, south, east, north)."""
    import rasterio
    from rasterio.mask import mask as rio_mask
    from rasterio.warp import transform_geom

    try:
        from PIL import Image  # noqa: F401
    except ImportError as e:
        raise RuntimeError("Pillow is required for PNG map layers") from e

    tif_path = Path(tif_path)
    if not tif_path.is_file():
        raise FileNotFoundError(str(tif_path))

    ms = max_side if max_side is not None else _png_max_side()
    b = band if band is not None else int(os.environ.get("LANDROID_NDVI_BAND", "1"))
    scale_mode = os.environ.get("LANDROID_NDVI_VALUE_SCALE", "auto").strip() or "auto"
    geom = parcel.boundary["features"][0]["geometry"]

    with rasterio.open(tif_path) as src:
        if b > int(src.count):
            raise ValueError("band out of range")
        geom_raster = transform_geom("EPSG:4326", src.crs, geom, precision=6)
        out_image, out_transform = rio_mask(
            src,
            [geom_raster],
            crop=True,
            filled=False,
            indexes=b,
        )
        h, w = out_image.shape[-2], out_image.shape[-1]
        west, south, east, north = _bounds_wgs84(h, w, out_transform, src.crs)

    arr = _rio_mask_to_float_nan(out_image)
    ndvi = _ndvi_array_to_minus1_1(arr, scale_mode)
    rgba = _rgba_ndvi(ndvi)
    rgba = _resize_max(rgba, ms)
    return _to_png(rgba), (west, south, east, north)


def render_parcel_zones_png(
    parcel: ParcelRecord,
    tif_path: Path,
    *,
    band: int | None = None,
    max_side: int | None = None,
) -> tuple[bytes, tuple[float, float, float, float]]:
    """Plant health zone overlay (FR-25)."""
    import rasterio
    from rasterio.mask import mask as rio_mask
    from rasterio.warp import transform_geom

    tif_path = Path(tif_path)
    if not tif_path.is_file():
        raise FileNotFoundError(str(tif_path))

    ms = max_side if max_side is not None else _png_max_side()
    b = band if band is not None else int(os.environ.get("LANDROID_NDVI_BAND", "1"))
    scale_mode = os.environ.get("LANDROID_NDVI_VALUE_SCALE", "auto").strip() or "auto"
    geom = parcel.boundary["features"][0]["geometry"]

    with rasterio.open(tif_path) as src:
        if b > int(src.count):
            raise ValueError("band out of range")
        geom_raster = transform_geom("EPSG:4326", src.crs, geom, precision=6)
        out_image, out_transform = rio_mask(
            src,
            [geom_raster],
            crop=True,
            filled=False,
            indexes=b,
        )
        h, w = out_image.shape[-2], out_image.shape[-1]
        west, south, east, north = _bounds_wgs84(h, w, out_transform, src.crs)

    arr = _rio_mask_to_float_nan(out_image)
    ndvi = _ndvi_array_to_minus1_1(arr, scale_mode)
    rgba = _rgba_zones(ndvi)
    rgba = _resize_max(rgba, ms)
    return _to_png(rgba), (west, south, east, north)


def _elevation_hillshade_rgba(elev: np.ndarray) -> np.ndarray:
    """Classic hillshade → RGBA (terrain gray, transparent where invalid)."""
    z_raw = np.asarray(elev, dtype=np.float64)
    valid = np.isfinite(z_raw)
    if not valid.any():
        raise ValueError("no valid elevation pixels")
    fill = float(np.nanmedian(z_raw[valid]))
    z = np.where(valid, z_raw, fill)
    dy, dx = np.gradient(z)
    slope = np.arctan(np.sqrt(dx * dx + dy * dy))
    aspect = np.arctan2(-dx, dy)
    az = np.radians(float(os.environ.get("LANDROID_DEM_HILLSHADE_AZIMUTH", "315")))
    al = np.radians(float(os.environ.get("LANDROID_DEM_HILLSHADE_ALTITUDE", "45")))
    hs = np.sin(al) * np.cos(slope) + np.cos(al) * np.sin(slope) * np.cos(az - aspect)
    hs = np.clip(hs, -1.0, 1.0)
    gray = ((hs + 1.0) * 0.5 * 255).astype(np.uint8)
    a = np.where(valid, 215, 0).astype(np.uint8)
    return np.stack([gray, gray, gray, a], axis=-1)


def render_parcel_dem_hillshade_png(
    parcel: ParcelRecord,
    dem_path: Path,
    *,
    band: int | None = None,
    max_side: int | None = None,
) -> tuple[bytes, tuple[float, float, float, float]]:
    """Grayscale hillshade PNG from a DEM GeoTIFF, clipped to the parcel."""
    import rasterio
    from rasterio.mask import mask as rio_mask
    from rasterio.warp import transform_geom

    try:
        from PIL import Image  # noqa: F401
    except ImportError as e:
        raise RuntimeError("Pillow is required for PNG map layers") from e

    dem_path = Path(dem_path)
    if not dem_path.is_file():
        raise FileNotFoundError(str(dem_path))

    ms = max_side if max_side is not None else _png_max_side()
    b = band if band is not None else int(os.environ.get("LANDROID_DEM_BAND", "1"))
    geom = parcel.boundary["features"][0]["geometry"]

    with rasterio.open(dem_path) as src:
        if b > int(src.count):
            raise ValueError("DEM band out of range")
        geom_raster = transform_geom("EPSG:4326", src.crs, geom, precision=6)
        out_image, out_transform = rio_mask(
            src,
            [geom_raster],
            crop=True,
            filled=False,
            indexes=b,
        )
        h, w = out_image.shape[-2], out_image.shape[-1]
        west, south, east, north = _bounds_wgs84(h, w, out_transform, src.crs)

    arr = _rio_mask_to_float_nan(out_image)
    rgba = _elevation_hillshade_rgba(arr)
    rgba = _resize_max(rgba, ms)
    return _to_png(rgba), (west, south, east, north)
