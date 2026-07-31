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


MIN_VALID_DAYS = 10  # below this the window is too sparse to aggregate honestly


def _clean(values: list | None, lo: float, hi: float) -> list[float]:
    """Keep only physically plausible readings.

    Providers signal "no data" with out-of-range sentinels (-999) as well as
    nulls, and a sentinel that reaches an aggregate poisons every feature
    derived from it. Bounds are physical limits, not statistical outlier
    trimming — a real 55 C day survives.
    """
    if not values:
        return []
    return [float(v) for v in values if v is not None and lo <= float(v) <= hi]


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

    # NASA POWER fills gaps with -999, so the same physical-plausibility filter
    # the Open-Meteo path uses is required here. Without it the "fallback" is
    # worse than no data: it returns a -37 C mean and looks successful.
    dates = sorted(payload["T2M"].keys())
    precip = _clean([payload["PRECTOTCORR"][d] for d in dates], 0.0, 2000.0)
    temp_mean = _clean([payload["T2M"][d] for d in dates], -60.0, 60.0)
    temp_max = _clean([payload["T2M_MAX"][d] for d in dates], -60.0, 65.0)
    humidity = _clean([payload["RH2M"][d] for d in dates], 0.0, 100.0)

    if len(temp_mean) < MIN_VALID_DAYS or len(precip) < MIN_VALID_DAYS:
        return None

    return {
        "source": "nasa_power",
        "observation_days": len(precip),
        "rainfall_cum_mm": round(sum(precip), 1),
        "rainfall_last30_mm": round(sum(precip[-30:]), 1),
        "dry_spell_max_days": _dry_spell(precip),
        "temp_mean_c": round(sum(temp_mean) / len(temp_mean), 2),
        "temp_max_c": round(max(temp_max), 2) if temp_max else None,
        "humidity_mean_pct": round(sum(humidity) / len(humidity), 2) if humidity else None,
        "et0_cum_mm": None,
        # Per-day series kept so features.py can compute GDD with the candidate
        # crop's own T_base rather than one fixed baseline here.
        "daily_temp_mean_c": temp_mean,
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
    precip = _clean(daily["precipitation_sum"], 0.0, 2000.0)
    temp_mean = _clean(daily["temperature_2m_mean"], -60.0, 60.0)
    temp_max = _clean(daily["temperature_2m_max"], -60.0, 65.0)
    humidity = _clean(daily["relative_humidity_2m_mean"], 0.0, 100.0)
    et0 = _clean(daily["et0_fao_evapotranspiration"], 0.0, 30.0)

    # ERA5 reanalysis lags real time by several days, and the archive fills the
    # gap with out-of-range sentinels rather than nulls. Filtering only `None`
    # let those through, which produced -37 C mean temperature and -62 mm/day
    # rainfall — and a yield model handed physically impossible inputs returns
    # physically impossible yields. Too few surviving days is a degraded fetch,
    # not a usable one.
    if len(temp_mean) < MIN_VALID_DAYS or len(precip) < MIN_VALID_DAYS:
        fallback = await _fetch_nasa_power_fallback(lat, lon, start.isoformat(), today.isoformat())
        if fallback is not None:
            fallback["forecast_7d_rainfall_mm"] = (
                sum(forecast["daily"]["precipitation_sum"]) if forecast else None
            )
            fallback["fetched_at"] = datetime.now(timezone.utc).isoformat()
            return fallback
        return None

    return {
        "source": "open_meteo",
        # Window length, so features.py can normalise cumulative quantities
        # into rates. Without it a mid-season row is not comparable to a
        # full-season training row.
        "observation_days": len(precip),
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
