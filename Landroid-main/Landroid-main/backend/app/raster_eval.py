"""GeoTIFF analysis and parcel zonal stats (NDVI) for uploaded rasters."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from .parcel_store import ParcelRecord


def _band_stats(arr: Any) -> dict[str, float]:
    import numpy as np

    a = np.asarray(arr, dtype=np.float64).ravel()
    a = a[np.isfinite(a)]
    if a.size == 0:
        return {"min": float("nan"), "max": float("nan"), "mean": float("nan")}
    return {
        "min": float(np.min(a)),
        "max": float(np.max(a)),
        "mean": float(np.mean(a)),
    }


def analyze_geotiff(path: Path) -> dict[str, Any]:
    """CRS, shape, per-band min/max/mean over full raster (quick overview)."""
    try:
        import rasterio
    except ImportError as e:
        raise RuntimeError("rasterio is required for TIFF evaluation") from e

    path = Path(path)
    if not path.is_file():
        raise FileNotFoundError(str(path))

    with rasterio.open(path) as ds:
        bounds = {
            "left": float(ds.bounds.left),
            "bottom": float(ds.bounds.bottom),
            "right": float(ds.bounds.right),
            "top": float(ds.bounds.top),
        }
        out: dict[str, Any] = {
            "file_name": path.name,
            "absolute_path": str(path.resolve()),
            "crs": ds.crs.to_string() if ds.crs else None,
            "width": int(ds.width),
            "height": int(ds.height),
            "count": int(ds.count),
            "bounds_projected": bounds,
            "dtype": [str(ds.dtypes[i]) for i in range(ds.count)],
            "nodata": ds.nodata,
            "bands": [],
        }
        for i in range(1, ds.count + 1):
            band = ds.read(i)
            out["bands"].append({"band": i, **_band_stats(band)})
    return out


def evaluate_raster_for_parcel(
    path: Path,
    parcel: ParcelRecord | None,
    band: int | None = None,
) -> dict[str, Any]:
    """
    Full raster stats plus optional zonal NDVI under parcel polygon
    (uses same normalization as ``birdscale_ndvi``).
    """
    from .birdscale_ndvi import sample_parcel_mean_ndvi_from_path

    path = Path(path)
    analysis = analyze_geotiff(path)
    out: dict[str, Any] = {
        "analysis": analysis,
        "parcel_zonal_ndvi": None,
    }
    if parcel is not None:
        b = band if band is not None else int(__import__("os").environ.get("LANDROID_NDVI_BAND", "1"))
        zonal = sample_parcel_mean_ndvi_from_path(parcel, path, band=b)
        out["parcel_zonal_ndvi"] = zonal
    return out
