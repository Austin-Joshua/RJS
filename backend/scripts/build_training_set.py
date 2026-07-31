"""Generates the yield training set (TRD SS5.1) from real, freely-licensed
sources — no synthetic data.

- Yield + area: real district-crop-year Area/Production/Yield statistics
  from the Directorate of Economics & Statistics (DES), Ministry of
  Agriculture & Farmers Welfare — manually exported from
  https://data.desagri.gov.in and parsed by `parse_apy_reports.py` into
  `data/training/apy_real_tn.csv` (648 rows, 1997-98 to 2022-23, the 5
  districts / 5 crops this app supports). The source reports one figure
  per crop per district per *Indian crop year* (India's official
  agricultural year, 1 July - 30 June) rather than per sub-season, so
  every generated row is stamped `season="whole_year"` (see the SEASONS
  note below).
- Weather: Open-Meteo Archive API (ERA5 reanalysis), same source family as
  `app/adapters/weather_openmeteo.py`, aggregated over each row's real
  1 Jul - 30 Jun crop-year window.
- NDVI: NASA ORNL DAAC MODIS MOD13Q1 (250 m, 16-day composite, free, no
  API key, back to Feb 2000: https://modis.ornl.gov/rst/api/v1/). Rows
  before mid-2000 get no NDVI (None — LightGBM consumes NaN natively per
  features.py); rows are also dropped from NDVI stats if fewer than 2
  reliable (pixel_reliability in {0, 1}) composites fall in the window.
- Soil: `data/soil/shc_districts.csv` (real Soil Health Card baseline),
  applied uniformly across years per district — the only district-level
  nutrient reading available without portal registration, so there is no
  real historical N/P/K time series to join here instead (documented
  limitation, not fabricated).
- area_ha (the farm-plot-size feature, distinct from the district total
  area in the source data): no public per-holding data exists at this
  grain, so it is sampled from TN's real average operational holding size
  band (~0.6-1.4 ha, Agriculture Census) with a seeded RNG for
  reproducibility — the only non-government-sourced number in this file.
- SEASONS includes the sub-annual labels `yield_service.py`/`fusion.py`
  compute from a real sowing date (kharif/rabi/kuruvai/samba) even though
  training only ever sees "whole_year" — this keeps the categorical dtype
  serving-compatible, but means the model cannot yet learn a real
  intra-year seasonal effect. Documented limitation, upgrade path is a
  season-disaggregated DES export per crop.

`metrics.json` records `training_data_source: "real_govt_district_apy"`.
Network access is only required to run this script; the shipped model and
API never call these endpoints at runtime.
"""
import csv
import json
import random
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import date, timedelta
from pathlib import Path

import httpx
import pandas as pd
from shapely.geometry import shape

from app.ml.features import build_feature_row
from app.services.crop_reference import load_crops

ROOT = Path(__file__).resolve().parents[1]
OUT_PATH = ROOT / "data" / "training" / "yield_training_set.csv"
APY_PATH = ROOT / "data" / "training" / "apy_real_tn.csv"
GEOJSON_PATH = ROOT / "data" / "geo" / "district_boundaries.geojson"
SOIL_PATH = ROOT / "data" / "soil" / "shc_districts.csv"
CACHE_PATH = ROOT / "data" / "training" / ".weather_ndvi_cache.json"

DISTRICTS = ["Thanjavur", "Tiruvarur", "Nagapattinam", "Tiruchirappalli", "Madurai"]
CROPS = ["paddy", "black_gram", "groundnut", "sugarcane", "maize"]
# "whole_year" is what every training row is stamped with (see module
# docstring); the sub-annual labels are kept so the trained categorical
# dtype matches what fusion.determine_season emits at serve time.
SEASONS = ["whole_year", "kharif", "rabi", "kuruvai", "samba"]

OPEN_METEO_ARCHIVE_URL = "https://archive-api.open-meteo.com/v1/archive"
OPEN_METEO_DAILY_VARS = [
    "temperature_2m_max",
    "temperature_2m_mean",
    "relative_humidity_2m_mean",
    "precipitation_sum",
    "et0_fao_evapotranspiration",
]
MODIS_URL = "https://modis.ornl.gov/rst/api/v1/MOD13Q1/subset"
MODIS_START_DATE = date(2000, 2, 18)  # first MOD13Q1 composite


def _crop_year_window(crop_year: int) -> tuple[date, date]:
    """India's official agricultural/crop year: 1 July - 30 June (matches
    the "YYYY-YYYY+1" fiscal-year labels in the DES source reports)."""
    return date(crop_year, 7, 1), date(crop_year + 1, 6, 30)


def _district_centroids() -> dict[str, tuple[float, float]]:
    features = json.loads(GEOJSON_PATH.read_text(encoding="utf-8"))["features"]
    out = {}
    for f in features:
        centroid = shape(f["geometry"]).centroid
        out[f["properties"]["district"]] = (centroid.y, centroid.x)
    return out


def _load_soil() -> dict[str, dict]:
    with open(SOIL_PATH, encoding="utf-8") as f:
        return {row["district"]: row for row in csv.DictReader(f)}


def _clean(values: list | None, lo: float, hi: float) -> list[float]:
    """Physically plausible readings only — mirrors weather_openmeteo._clean."""
    if not values:
        return []
    return [float(v) for v in values if v is not None and lo <= float(v) <= hi]


def _dry_spell(precip: list[float]) -> int:
    longest = current = 0
    for p in precip:
        current = current + 1 if p < 2.5 else 0
        longest = max(longest, current)
    return longest


def _get_with_retries(client: httpx.Client, url: str, params: dict, attempts: int = 3) -> httpx.Response | None:
    for i in range(attempts):
        try:
            resp = client.get(url, params=params, timeout=20.0)
            if resp.status_code == 200:
                return resp
            if resp.status_code < 500:  # bad request / not found — retrying won't help
                return None
        except httpx.HTTPError:
            pass
        time.sleep(1.0 * (i + 1))
    return None


def _fetch_weather(client: httpx.Client, lat: float, lon: float, start: date, end: date) -> dict | None:
    params = {
        "latitude": lat,
        "longitude": lon,
        "start_date": start.isoformat(),
        "end_date": end.isoformat(),
        "daily": ",".join(OPEN_METEO_DAILY_VARS),
        "timezone": "auto",
    }
    resp = _get_with_retries(client, OPEN_METEO_ARCHIVE_URL, params)
    if resp is None:
        return None
    try:
        daily = resp.json()["daily"]
    except (ValueError, KeyError):
        return None

    # Same physical-plausibility filter the runtime adapter applies. Providers
    # signal missing data with out-of-range sentinels as well as nulls, and a
    # sentinel here would silently poison a training row.
    precip = _clean(daily["precipitation_sum"], 0.0, 2000.0)
    temp_mean = _clean(daily["temperature_2m_mean"], -60.0, 60.0)
    temp_max = _clean(daily["temperature_2m_max"], -60.0, 65.0)
    humidity = _clean(daily["relative_humidity_2m_mean"], 0.0, 100.0)
    et0 = _clean(daily["et0_fao_evapotranspiration"], 0.0, 30.0)
    if len(temp_mean) < 10 or len(precip) < 10:
        return None

    return {
        "observation_days": len(precip),
        "rainfall_cum_mm": round(sum(precip), 1),
        "rainfall_last30_mm": round(sum(precip[-30:]), 1),
        "dry_spell_max_days": _dry_spell(precip),
        "temp_mean_c": round(sum(temp_mean) / len(temp_mean), 2),
        "temp_max_c": round(max(temp_max), 2) if temp_max else None,
        "humidity_mean_pct": round(sum(humidity) / len(humidity), 2) if humidity else None,
        "et0_cum_mm": round(sum(et0), 1) if et0 else None,
        "daily_temp_mean_c": temp_mean,
    }


MODIS_CHUNK_DAYS = 140  # <=10 16-day composites per request (API hard limit)


def _fetch_ndvi(client: httpx.Client, lat: float, lon: float, start: date, end: date) -> dict | None:
    if end < MODIS_START_DATE:
        return None
    query_start = max(start, MODIS_START_DATE)

    by_date: dict[str, dict] = {}
    chunk_start = query_start
    while chunk_start <= end:
        chunk_end = min(chunk_start + timedelta(days=MODIS_CHUNK_DAYS), end)
        params = {
            "latitude": lat,
            "longitude": lon,
            "startDate": f"A{chunk_start.year}{chunk_start.timetuple().tm_yday:03d}",
            "endDate": f"A{chunk_end.year}{chunk_end.timetuple().tm_yday:03d}",
            "kmAboveBelow": 0,
            "kmLeftRight": 0,
        }
        resp = _get_with_retries(client, MODIS_URL, params)
        if resp is not None:
            try:
                for item in resp.json()["subset"]:
                    by_date.setdefault(item["calendar_date"], {})[item["band"]] = item["data"][0]
            except (ValueError, KeyError):
                pass
        chunk_start = chunk_end + timedelta(days=1)

    points = []
    for d, bands in sorted(by_date.items()):
        ndvi_raw = bands.get("250m_16_days_NDVI")
        reliability = bands.get("250m_16_days_pixel_reliability")
        if ndvi_raw is None or reliability not in (0, 1):
            continue
        points.append((d, ndvi_raw * 0.0001))
    if len(points) < 2:
        return None

    values = [v for _, v in points]
    sorted_vals = sorted(values)
    p90_idx = max(0, int(0.9 * (len(sorted_vals) - 1)))
    recent = points[-2:]  # ~last 30 days at MODIS' 16-day composite cadence
    days = [(date.fromisoformat(d) - date.fromisoformat(points[0][0])).days for d, _ in points]
    dt = days[-1] - days[-2] if len(recent) == 2 else 1
    slope_30d = (recent[-1][1] - recent[0][1]) / dt if dt else 0.0
    auc = sum(
        (days[i + 1] - days[i]) * (values[i] + values[i + 1]) / 2 for i in range(len(values) - 1)
    )

    return {
        "ndvi_mean": round(sum(values) / len(values), 3),
        "ndvi_max": round(max(values), 3),
        "ndvi_p90": round(sorted_vals[p90_idx], 3),
        "ndvi_slope_30d": round(slope_30d, 5),
        "ndvi_auc": round(auc, 2),
    }


def _crop_gdd(daily_temp_mean_c: list[float], t_base_c: float) -> float:
    return round(sum(max(0.0, t - t_base_c) for t in daily_temp_mean_c), 1)


def _fetch_all_windows(windows: list[tuple[str, int, float, float]]) -> dict:
    """windows: list of (district, year, lat, lon). Returns
    {(district, year): {"weather": ..., "ndvi": ...}}, cached to disk so
    re-running this script after the first real fetch is offline."""
    cache: dict = {}
    if CACHE_PATH.exists():
        cache = json.loads(CACHE_PATH.read_text(encoding="utf-8"))

    to_fetch = [w for w in windows if f"{w[0]}|{w[1]}" not in cache]
    if to_fetch:
        with httpx.Client() as client:
            def fetch_one(w):
                district, year, lat, lon = w
                start, end = _crop_year_window(year)
                return (
                    f"{district}|{year}",
                    {"weather": _fetch_weather(client, lat, lon, start, end), "ndvi": _fetch_ndvi(client, lat, lon, start, end)},
                )

            with ThreadPoolExecutor(max_workers=8) as pool:
                for i, (key, result) in enumerate(pool.map(fetch_one, to_fetch)):
                    cache[key] = result
                    if (i + 1) % 10 == 0 or (i + 1) == len(to_fetch):
                        print(f"  fetched {i + 1}/{len(to_fetch)} windows...", flush=True)
                        CACHE_PATH.write_text(json.dumps(cache), encoding="utf-8")

        CACHE_PATH.write_text(json.dumps(cache), encoding="utf-8")

    return cache


def build_real_panel(area_seed: int = 42) -> list[dict]:
    apy = pd.read_csv(APY_PATH)
    centroids = _district_centroids()
    soil = _load_soil()
    crops_cfg = load_crops()
    rng = random.Random(area_seed)

    windows = sorted({(r.district, int(r.year), *centroids[r.district]) for r in apy.itertuples()})
    print(f"Fetching real weather + NDVI for {len(windows)} unique district-year crop-year windows...", flush=True)
    cache = _fetch_all_windows(windows)

    rows: list[dict] = []
    skipped_no_weather = 0
    for r in apy.itertuples():
        district, crop, year = r.district, r.crop, int(r.year)
        yield_t_ha = r.yield_t_ha
        if yield_t_ha <= 0 or yield_t_ha != yield_t_ha:  # NaN guard
            continue

        cached = cache.get(f"{district}|{year}", {})
        weather = cached.get("weather")
        if weather is None:
            skipped_no_weather += 1
            continue
        ndvi = cached.get("ndvi")

        soil_row = soil[district]
        # Real per-holding area isn't published at district-crop grain; sampled
        # from TN's real average operational holding size band (Agriculture
        # Census ~0.6-1.4 ha) — the one non-government-sourced number here.
        area_ha = round(rng.uniform(0.6, 1.4), 3)

        # Built by the same function the API calls at inference. This used to
        # be an inline dict, which is how the two paths drifted apart: training
        # rows carried whole-season totals while inference sent season-to-date
        # ones, and the model silently extrapolated. One implementation is the
        # only way that claim in features.py is actually true.
        feature_row = build_feature_row(
            soil={k: float(soil_row[k]) for k in ("n_kg_ha", "p_kg_ha", "k_kg_ha", "ph", "oc_pct")},
            weather=weather,
            ndvi=ndvi,
            area_ha=area_ha,
            crop=crop,
            district=district,
            season="whole_year",
        )
        rows.append({"year": year, **feature_row, "yield_t_ha": round(yield_t_ha, 3)})

    if skipped_no_weather:
        print(f"  skipped {skipped_no_weather} rows with no fetchable weather (archive outage)")
    return rows


def main() -> None:
    rows = build_real_panel()
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT_PATH, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)
    print(f"Wrote {len(rows)} real rows to {OUT_PATH}")


if __name__ == "__main__":
    main()
