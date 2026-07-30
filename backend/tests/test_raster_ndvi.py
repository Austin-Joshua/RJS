"""Raster NDVI pipeline sanity check (TRD raster pipeline): a synthetic
in-memory GeoTIFF with known pixel values, asserting analyze/zonal/blend
produce the expected numbers. No network or Supabase calls."""
import numpy as np
import pytest
import rasterio
from rasterio.transform import from_bounds

from app.services import raster_ndvi

# 2x2 grid of known NDVI values [-1, 1] over a 1deg x 1deg box in EPSG:4326.
_ARR = np.array([[0.1, 0.3], [0.5, 0.9]], dtype="float32")
_BOUNDS = (0.0, 0.0, 1.0, 1.0)  # west, south, east, north
_BOUNDARY_GEOJSON = {
    "type": "Polygon",
    "coordinates": [[[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0], [0.0, 0.0]]],
}


def _make_geotiff_bytes() -> bytes:
    height, width = _ARR.shape
    transform = from_bounds(*_BOUNDS, width, height)
    with rasterio.io.MemoryFile() as memfile:
        with memfile.open(
            driver="GTiff", height=height, width=width, count=1,
            dtype=_ARR.dtype, crs="EPSG:4326", transform=transform,
        ) as ds:
            ds.write(_ARR, 1)
        return memfile.read()


def test_analyze_geotiff_reports_shape_crs_and_band_stats() -> None:
    content = _make_geotiff_bytes()
    analysis = raster_ndvi.analyze_geotiff(content)
    assert analysis["width"] == 2
    assert analysis["height"] == 2
    assert analysis["crs"] == "EPSG:4326"
    assert analysis["stats"][0]["min"] == pytest.approx(0.1, abs=1e-4)
    assert analysis["stats"][0]["max"] == pytest.approx(0.9, abs=1e-4)
    assert analysis["stats"][0]["mean"] == pytest.approx(float(_ARR.mean()), abs=1e-4)


def test_zonal_mean_ndvi_covers_full_raster_when_boundary_matches_extent() -> None:
    content = _make_geotiff_bytes()
    zonal = raster_ndvi.zonal_mean_ndvi(content, _BOUNDARY_GEOJSON, band=1)
    assert zonal is not None
    assert zonal["pixel_count"] == 4
    assert zonal["value_scale"] == "minus1_1"  # values already in [-1, 1]
    assert zonal["mean_ndvi"] == pytest.approx(float(_ARR.mean()), abs=1e-3)


def test_zonal_mean_ndvi_returns_none_outside_raster_extent() -> None:
    content = _make_geotiff_bytes()
    far_away = {
        "type": "Polygon",
        "coordinates": [[[50.0, 50.0], [51.0, 50.0], [51.0, 51.0], [50.0, 51.0], [50.0, 50.0]]],
    }
    assert raster_ndvi.zonal_mean_ndvi(content, far_away, band=1) is None


def test_blend_ndvi_matches_weighted_average() -> None:
    raster_zonal = {"mean_ndvi": 0.8, "pixel_count": 4, "value_scale": "minus1_1", "band": 1}
    blended, meta = raster_ndvi.blend_ndvi(gee_mean=0.4, raster_zonal=raster_zonal, weight=0.5)
    assert blended == pytest.approx(0.6)  # 0.5*0.8 + 0.5*0.4
    assert meta["blend_weight_raster"] == 0.5
    assert meta["raster"]["mean_ndvi"] == 0.8


def test_blend_ndvi_falls_back_to_whichever_source_is_available() -> None:
    raster_zonal = {"mean_ndvi": 0.8, "pixel_count": 4, "value_scale": "minus1_1", "band": 1}
    assert raster_ndvi.blend_ndvi(None, raster_zonal, weight=0.5)[0] == pytest.approx(0.8)
    assert raster_ndvi.blend_ndvi(0.4, None, weight=0.5)[0] == pytest.approx(0.4)


def _make_rgb_geotiff_bytes() -> bytes:
    """3-band 2x2 RGB orthomosaic over the same 1deg x 1deg box."""
    height, width = _ARR.shape
    transform = from_bounds(*_BOUNDS, width, height)
    r = np.array([[10, 20], [30, 40]], dtype="uint8")
    g = np.array([[50, 60], [70, 80]], dtype="uint8")
    b = np.array([[90, 100], [110, 120]], dtype="uint8")
    with rasterio.io.MemoryFile() as memfile:
        with memfile.open(
            driver="GTiff", height=height, width=width, count=3,
            dtype="uint8", crs="EPSG:4326", transform=transform,
        ) as ds:
            ds.write(r, 1)
            ds.write(g, 2)
            ds.write(b, 3)
        return memfile.read()


def test_render_true_color_png_masks_to_boundary_and_reports_wgs84_bounds() -> None:
    content = _make_rgb_geotiff_bytes()
    rendered = raster_ndvi.render_true_color_png(content, _BOUNDARY_GEOJSON, bands=(1, 2, 3))
    assert rendered is not None
    png_bytes, bounds = rendered
    assert png_bytes[:8] == b"\x89PNG\r\n\x1a\n"  # PNG magic bytes
    assert bounds == pytest.approx(_BOUNDS, abs=1e-6)


def test_render_true_color_png_returns_none_outside_raster_extent() -> None:
    content = _make_rgb_geotiff_bytes()
    far_away = {
        "type": "Polygon",
        "coordinates": [[[50.0, 50.0], [51.0, 50.0], [51.0, 51.0], [50.0, 51.0], [50.0, 50.0]]],
    }
    assert raster_ndvi.render_true_color_png(content, far_away, bands=(1, 2, 3)) is None


def test_render_hillshade_png_masks_dem_to_boundary() -> None:
    # Sloped elevation so the gradient/hillshade math has a well-defined direction.
    elev = np.array([[100.0, 105.0], [110.0, 115.0]], dtype="float32")
    height, width = elev.shape
    transform = from_bounds(*_BOUNDS, width, height)
    with rasterio.io.MemoryFile() as memfile:
        with memfile.open(
            driver="GTiff", height=height, width=width, count=1,
            dtype=elev.dtype, crs="EPSG:4326", transform=transform,
        ) as ds:
            ds.write(elev, 1)
        content = memfile.read()

    rendered = raster_ndvi.render_hillshade_png(content, _BOUNDARY_GEOJSON, band=1)
    assert rendered is not None
    png_bytes, bounds = rendered
    assert png_bytes[:8] == b"\x89PNG\r\n\x1a\n"
    assert bounds == pytest.approx(_BOUNDS, abs=1e-6)
