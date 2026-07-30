from __future__ import annotations

import math

import httpx

from app.config import settings


class ExternalAPIService:
    async def fetch_soilgrids(self, lat: float, lon: float) -> dict:
        url = f"{settings.soilgrids_base_url}/properties/query"
        params = {
            "lat": lat,
            "lon": lon,
            "property": ["phh2o", "soc", "clay"],
            "depth": ["0-5cm"],
            "value": ["mean"],
        }
        async with httpx.AsyncClient(timeout=20) as client:
            response = await client.get(url, params=params)
            response.raise_for_status()
            return response.json()

    async def fetch_location_signals(self, lat: float, lon: float, bbox: list[float]) -> dict:
        # Hackathon-safe proxy metrics when full OSM pipeline is not yet wired.
        span = math.hypot(bbox[2] - bbox[0], bbox[3] - bbox[1])
        return {
            "nearest_highway_km": round(max(0.3, span / 1000), 2),
            "nearest_water_km": 1.2,
            "nearest_town_km": 7.5,
            "night_lights_index": 0.42,
            "location_confidence": 74.0,
            "place_context": "Tamil Nadu parcel context",
        }
