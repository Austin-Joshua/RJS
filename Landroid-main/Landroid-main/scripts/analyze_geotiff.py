"""
Read GeoTIFF metadata and simple statistics (aligned with typical index.pdf checks:
CRS, shape, bounds, per-band min/max/mean).

Usage (from repo root):
  pip install -r scripts/requirements-raster.txt
  python scripts/analyze_geotiff.py

Optionally set DATA_DIR to a folder containing *.tif files (default: ./data).
"""
from __future__ import annotations

import json
import os
from pathlib import Path

import numpy as np

try:
    import rasterio
    from rasterio.errors import RasterioIOError
except ImportError as e:  # pragma: no cover
    raise SystemExit(
        "rasterio is required. Install with: pip install -r scripts/requirements-raster.txt"
    ) from e


def _stats(arr: np.ndarray) -> dict[str, float]:
    arr = arr.astype("float64", copy=False)
    mask = np.isfinite(arr)
    if not mask.any():
        return {"min": float("nan"), "max": float("nan"), "mean": float("nan")}
    m = arr[mask]
    return {
        "min": float(np.min(m)),
        "max": float(np.max(m)),
        "mean": float(np.mean(m)),
    }


def analyze(path: Path) -> dict:
    with rasterio.open(path) as ds:
        bounds = {
            "left": float(ds.bounds.left),
            "bottom": float(ds.bounds.bottom),
            "right": float(ds.bounds.right),
            "top": float(ds.bounds.top),
        }
        out: dict = {
            "file_name": path.name,
            "crs": ds.crs.to_string() if ds.crs else None,
            "width": int(ds.width),
            "height": int(ds.height),
            "count": int(ds.count),
            "bounds": bounds,
            "dtype": str(ds.dtypes[0]),
            "stats": [],
        }
        for i in range(1, ds.count + 1):
            band = ds.read(i)
            out["stats"].append({"band": i, **_stats(band)})
    return out


def main() -> None:
    data_dir = Path(os.environ.get("DATA_DIR", "data")).resolve()
    if not data_dir.is_dir():
        print(f"DATA_DIR not found: {data_dir}")
        raise SystemExit(1)

    tifs = sorted(data_dir.glob("*.tif")) + sorted(data_dir.glob("*.tiff"))
    if not tifs:
        print(f"No GeoTIFF files found under {data_dir}")
        print("Add your two .tif files (and index.pdf) and re-run.")
        raise SystemExit(0)

    index_pdf = data_dir / "index.pdf"
    if index_pdf.exists():
        print(f"Found index: {index_pdf} (interpret methodology from this PDF manually).")
    else:
        print("Note: index.pdf not found — add it beside the rasters for methodology.")

    results = []
    for p in tifs:
        try:
            results.append(analyze(p))
        except RasterioIOError as e:
            print(f"Failed to open {p}: {e}")

    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
