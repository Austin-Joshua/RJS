"""ISRIC SoilGrids REST (no API key)."""

from __future__ import annotations

from typing import Any

import httpx

SOIL_URL = "https://rest.isric.org/soilgrids/v2.0/properties/query"


async def fetch_soil_at_point(lng: float, lat: float) -> dict[str, Any] | None:
    params: list[tuple[str, str]] = [
        ("lon", str(lng)),
        ("lat", str(lat)),
        ("depth", "0-5cm"),
        ("value", "mean"),
    ]
    for prop in ("phh2o", "soc", "clay", "sand", "silt"):
        params.append(("property", prop))
    async with httpx.AsyncClient(timeout=12.0) as client:
        try:
            r = await client.get(SOIL_URL, params=params)
            r.raise_for_status()
            return r.json()
        except (httpx.HTTPError, ValueError):
            return None


def _mean_layer(data: dict[str, Any], prop: str) -> float | None:
    try:
        layers = data["properties"]["layers"]
        for layer in layers:
            if layer.get("name") != prop:
                continue
            depths = layer.get("depths") or []
            for d in depths:
                vals = d.get("values") or {}
                mean = vals.get("mean")
                if mean is not None:
                    return float(mean)
    except (KeyError, TypeError, ValueError):
        return None
    return None


def summarize_soil_json(data: dict[str, Any] | None) -> dict[str, Any]:
    if not data:
        return {
            "ph": None,
            "organic_carbon_g_kg": None,
            "texture": "unknown",
            "confidence": 40,
            "source": "fallback",
        }
    # phh2o: ISRIC SoilGrids 2.0 reports means in celsius pH × 10 for this property
    # (see https://www.isric.org/explore/soilgrids/soilgrids-access/ ).
    ph_raw = _mean_layer(data, "phh2o")
    soc = _mean_layer(data, "soc")
    clay = _mean_layer(data, "clay")
    sand = _mean_layer(data, "sand")
    silt = _mean_layer(data, "silt")

    ph = ph_raw / 10.0 if ph_raw is not None else None

    texture = "loam"
    if clay is not None and sand is not None and silt is not None:
        m = max(clay, sand, silt)
        texture = (
            "clay"
            if clay == m
            else "sand"
            if sand == m
            else "silt"
            if silt == m
            else "loam"
        )

    confidence = 78 if ph is not None and soc is not None else 52

    return {
        "ph": round(ph, 2) if ph is not None else None,
        "organic_carbon_g_kg": round(soc, 2) if soc is not None else None,
        "clay_pct": clay,
        "sand_pct": sand,
        "silt_pct": silt,
        "texture": texture,
        "confidence": confidence,
        "source": "isric_soilgrids",
    }
