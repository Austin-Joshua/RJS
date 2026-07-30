"""One-shot: Kallapuram boundary → WGS84 + downsampled Orthomosaic/DEM PNGs for Flutter assets."""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import rasterio
from PIL import Image
from rasterio.enums import Resampling
from rasterio.warp import transform as warp_transform

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "flutter_app" / "assets" / "demo"


def _boundary() -> None:
    raw = json.loads((ROOT / "Boundary.geojson").read_text(encoding="utf-8"))
    coords = raw["features"][0]["geometry"]["coordinates"]
    xy = [(c[0], c[1]) for c in coords]
    xs, ys = zip(*xy)
    lons, lats = warp_transform("EPSG:32643", "EPSG:4326", list(xs), list(ys))
    wgs = list(zip(lons, lats))
    if wgs[0] != wgs[-1]:
        wgs.append(wgs[0])
    lons = [p[0] for p in wgs]
    lats = [p[1] for p in wgs]
    feature = {
        "type": "Feature",
        "properties": {
            "name": "Kallapuram field",
            "district": "Tiruchirappalli",
            "state": "Tamil Nadu",
            "crs_source": "EPSG:32643",
            "citation": "Field boundary surveyed for FarmSync demo (Kallapuram_Actual.geojson)",
        },
        "geometry": {"type": "Polygon", "coordinates": [[[lon, lat] for lon, lat in wgs]]},
        "centroid": {"lat": sum(lats) / len(lats), "lon": sum(lons) / len(lons)},
        "bounds": {
            "south": min(lats),
            "west": min(lons),
            "north": max(lats),
            "east": max(lons),
        },
    }
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "kallapuram_boundary.geojson").write_text(json.dumps(feature, indent=2), encoding="utf-8")
    print("boundary ok", feature["centroid"])


def _wgs_bounds(ds: rasterio.DatasetReader) -> dict[str, float]:
    b = ds.bounds
    if ds.crs and str(ds.crs) not in {"EPSG:4326", "OGC:CRS84"}:
        xs, ys = warp_transform(
            ds.crs,
            "EPSG:4326",
            [b.left, b.right, b.right, b.left],
            [b.bottom, b.bottom, b.top, b.top],
        )
        return {"west": min(xs), "south": min(ys), "east": max(xs), "north": max(ys)}
    return {"west": b.left, "south": b.bottom, "east": b.right, "north": b.top}


def _ortho() -> None:
    path = ROOT / "Orthomosaic.tif"
    with rasterio.open(path) as ds:
        print("ortho", ds.crs, ds.width, ds.height, ds.count)
        scale = max(ds.width, ds.height) / 1024
        out_h = max(1, int(ds.height / scale))
        out_w = max(1, int(ds.width / scale))
        bands = min(3, ds.count)
        data = ds.read(
            list(range(1, bands + 1)),
            out_shape=(bands, out_h, out_w),
            resampling=Resampling.bilinear,
        )
        rgb = np.zeros((out_h, out_w, 3), dtype=np.uint8)
        for i in range(bands):
            band = data[i].astype(np.float64)
            valid = band[np.isfinite(band)]
            if valid.size == 0:
                continue
            lo, hi = np.percentile(valid, [2, 98])
            if hi <= lo:
                hi = lo + 1
            norm = np.clip((band - lo) / (hi - lo), 0, 1)
            rgb[:, :, i] = (norm * 255).astype(np.uint8)
        if bands == 1:
            rgb[:, :, 1] = rgb[:, :, 0]
            rgb[:, :, 2] = rgb[:, :, 0]
        Image.fromarray(rgb).save(OUT / "orthomosaic_preview.png")
        bounds = _wgs_bounds(ds)
        (OUT / "orthomosaic_bounds.json").write_text(json.dumps(bounds, indent=2), encoding="utf-8")
        print("wrote orthomosaic_preview.png", out_w, out_h, bounds)


def _dem() -> None:
    path = ROOT / "Digital Elevation model.tif"
    with rasterio.open(path) as ds:
        print("dem", ds.crs, ds.width, ds.height)
        scale = max(ds.width, ds.height) / 1024
        out_h = max(1, int(ds.height / scale))
        out_w = max(1, int(ds.width / scale))
        data = ds.read(1, out_shape=(out_h, out_w), resampling=Resampling.bilinear).astype(np.float64)
        valid = data[np.isfinite(data)]
        lo, hi = np.percentile(valid, [2, 98])
        norm = np.clip((data - lo) / (hi - lo + 1e-9), 0, 1)
        img = np.zeros((out_h, out_w, 3), dtype=np.uint8)
        img[:, :, 0] = (norm * 180 + 40).astype(np.uint8)
        img[:, :, 1] = (norm * 140 + 60).astype(np.uint8)
        img[:, :, 2] = (40 + (1 - norm) * 40).astype(np.uint8)
        Image.fromarray(img).save(OUT / "dem_hillshade_preview.png")
        print("wrote dem_hillshade_preview.png", out_w, out_h)


def _citations() -> None:
    payload = {
        "field": "Kallapuram demo field",
        "sources": [
            {
                "id": "boundary",
                "label": "Field boundary",
                "citation": "Kallapuram_Actual.geojson (EPSG:32643 → WGS84)",
            },
            {
                "id": "orthomosaic",
                "label": "Drone orthomosaic",
                "citation": "Orthomosaic.tif — local drone survey, downsampled offline map overlay",
            },
            {
                "id": "dem",
                "label": "Digital elevation model",
                "citation": "Digital Elevation model.tif — local DEM preview",
            },
            {
                "id": "soil",
                "label": "Soil N/P/K/pH",
                "citation": "Soil Health Card portal (https://soilhealth.dac.gov.in)",
            },
            {
                "id": "weather",
                "label": "Weather",
                "citation": "Open-Meteo Archive (ERA5)",
            },
            {
                "id": "ndvi_sat",
                "label": "Satellite NDVI",
                "citation": "NASA ORNL DAAC MODIS / Sentinel-2 (GEE)",
            },
            {
                "id": "yield",
                "label": "Yield training",
                "citation": "DES / MoA APY reports (https://data.desagri.gov.in)",
            },
        ],
    }
    (OUT / "citations.json").write_text(json.dumps(payload, indent=2), encoding="utf-8")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    _boundary()
    _ortho()
    _dem()
    _citations()
    print("done ->", OUT)


if __name__ == "__main__":
    main()
