"""Open-Meteo weather adapter — no API key (TRD §3.2). Falls back to NASA
POWER on failure. Never raises: returns None and lets fusion downgrade
data_mode.
"""
from datetime import date, datetime, timedelta, timezone

import httpx

from app.core.cache import weather_archive_cache, weather_cache

ARCHIVE_URL = "https://archive-api.open-meteo.com/v1/archive"
FORECAST_URL = "https://api.open-meteo.com/v1/forecast"
POWER_URL = "https://power.larc.nasa.gov/api/temporal/daily/point"

DAILY_VARS = [
    "temperature_2m_max",
    "temperature_2m_min",
    "temperature_2m_mean",
    "relative_humidity_2m_mean",
    "precipitation_sum",
    "et0_fao_evapotranspiration",
]


def _dry_spell(precip: list[float]) -> int:
    longest = current = 0
    for p in precip:
        current = current + 1 if p < 2.5 else 0
        longest = max(longest, current)
    return longest


async def _fetch_open_meteo(lat: float, lon: float, start: str, end: str) -> dict | None:
    cache_key = (round(lat, 3), round(lon, 3), start, end)
    if cache_key in weather_archive_cache:
        return weather_archive_cache[cache_key]

    params = {
        "latitude": lat,
        "longitude": lon,
        "start_date": start,
        "end_date": end,
        "daily": ",".join(DAILY_VARS),
        "timezone": "auto",
    }
    try:
        async with httpx.AsyncClient(timeout=8.0) as client:
            resp = await client.get(ARCHIVE_URL, params=params)
            resp.raise_for_status()
            data = resp.json()
    except (httpx.HTTPError, ValueError):
        return None

    weather_archive_cache[cache_key] = data
    return data


async def _fetch_forecast(lat: float, lon: float) -> dict | None:
    cache_key = (round(lat, 3), round(lon, 3))
    if cache_key in weather_cache:
        return weather_cache[cache_key]

    params = {"latitude": lat, "longitude": lon, "daily": ",".join(DAILY_VARS), "forecast_days": 7, "timezone": "auto"}
    try:
        async with httpx.AsyncClient(timeout=8.0) as client:
            resp = await client.get(FORECAST_URL, params=params)
            resp.raise_for_status()
            data = resp.json()
    except (httpx.HTTPError, ValueError):
        return None

    weather_cache[cache_key] = data
    return data


async def _fetch_nasa_power_fallback(lat: float, lon: float, start: str, end: str) -> dict | None:
    params = {
        "parameters": "T2M,T2M_MAX,RH2M,PRECTOTCORR",
        "community": "AG",
        "longitude": lon,
        "latitude": lat,
        "start": start.replace("-", ""),
        "end": end.replace("-", ""),
        "format": "JSON",
    }
    try:
        async with httpx.AsyncClient(timeout=8.0) as client:
            resp = await client.get(POWER_URL, params=params)
            resp.raise_for_status()
            payload = resp.json()["properties"]["parameter"]
    except (httpx.HTTPError, ValueError, KeyError):
        return None

    dates = sorted(payload["T2M"].keys())
    precip = [payload["PRECTOTCORR"][d] for d in dates]
    return {
        "source": "nasa_power",
        "rainfall_cum_mm": sum(precip),
        "rainfall_last30_mm": sum(precip[-30:]),
        "dry_spell_max_days": _dry_spell(precip),
        "temp_mean_c": sum(payload["T2M"].values()) / len(payload["T2M"]),
        "temp_max_c": max(payload["T2M_MAX"].values()),
        "humidity_mean_pct": sum(payload["RH2M"].values()) / len(payload["RH2M"]),
        "et0_cum_mm": None,
        "daily_temp_mean_c": None,  # NASA fallback path can't support per-crop GDD recompute
        "forecast_7d_rainfall_mm": None,
    }


async def get_weather_features(lat: float, lon: float, sowing_date: str | None) -> dict | None:
    """Season-to-date aggregates + 7-day forecast. Returns None on total failure."""
    today = date.today()
    start = date.fromisoformat(sowing_date) if sowing_date else today - timedelta(days=90)
    start = min(start, today - timedelta(days=1))

    archive = await _fetch_open_meteo(lat, lon, start.isoformat(), today.isoformat())
    forecast = await _fetch_forecast(lat, lon)

    if archive is None:
        fallback = await _fetch_nasa_power_fallback(lat, lon, start.isoformat(), today.isoformat())
        if fallback is None:
            return None
        fallback["forecast_7d_rainfall_mm"] = (
            sum(forecast["daily"]["precipitation_sum"]) if forecast else None
        )
        fallback["fetched_at"] = datetime.now(timezone.utc).isoformat()
        return fallback

    daily = archive["daily"]
    precip = [p for p in daily["precipitation_sum"] if p is not None]
    temp_mean = [t for t in daily["temperature_2m_mean"] if t is not None]
    temp_max = [t for t in daily["temperature_2m_max"] if t is not None]
    humidity = [h for h in daily["relative_humidity_2m_mean"] if h is not None]
    et0 = [e for e in daily["et0_fao_evapotranspiration"] if e is not None]

    return {
        "source": "open_meteo",
        "rainfall_cum_mm": round(sum(precip), 1),
        "rainfall_last30_mm": round(sum(precip[-30:]), 1),
        "dry_spell_max_days": _dry_spell(precip),
        "temp_mean_c": round(sum(temp_mean) / len(temp_mean), 2) if temp_mean else None,
        "temp_max_c": round(max(temp_max), 2) if temp_max else None,
        "humidity_mean_pct": round(sum(humidity) / len(humidity), 2) if humidity else None,
        "et0_cum_mm": round(sum(et0), 1) if et0 else None,
        # Raw series kept so features.py can compute GDD with the candidate
        # crop's own T_base (crops.yaml) rather than one fixed baseline here.
        "daily_temp_mean_c": temp_mean,
        "forecast_7d_rainfall_mm": (
            round(sum(forecast["daily"]["precipitation_sum"]), 1) if forecast else None
        ),
        "fetched_at": datetime.now(timezone.utc).isoformat(),
    }
