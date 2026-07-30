"""Deterministic, auditable advisory rules engine (FR-50..55, TRD §7). No ML,
no quantum — every output carries the inputs that produced it (FR-54)."""
import math
from typing import Any

from app.adapters.soil_shc import rate_nutrient
from app.services.crop_reference import load_crops, load_fertilizers

SOIL_CLASS_FACTOR = {"Low": 1.25, "Medium": 1.00, "High": 0.75}


def _fertilizer_requirement_kg(crop: str, soil: dict[str, Any], area_ha: float) -> dict[str, float]:
    crops = load_crops()
    req = crops[crop]["npk_req_kg_ha"]
    n_factor = SOIL_CLASS_FACTOR[rate_nutrient("n_kg_ha", soil.get("n_kg_ha", 0))]
    p_factor = SOIL_CLASS_FACTOR[rate_nutrient("p_kg_ha", soil.get("p_kg_ha", 0))]
    k_factor = SOIL_CLASS_FACTOR[rate_nutrient("k_kg_ha", soil.get("k_kg_ha", 0))]
    return {
        "n_kg": req["n"] * n_factor * area_ha,
        "p2o5_kg": req["p2o5"] * p_factor * area_ha,
        "k2o_kg": req["k2o"] * k_factor * area_ha,
    }


def fertilizer_advisory(assignment: dict[str, str], soil: dict[str, Any], area_by_plot: dict[str, float]) -> dict:
    """TRD §7.1 straight-fertilizer conversion, summed across every plot in
    the winning plan so the farmer gets one shopping list, in bags."""
    fert = load_fertilizers()
    total_n = total_p2o5 = total_k2o = 0.0
    split_schedule: list[dict[str, Any]] = []
    seen_crops: set[str] = set()

    for plot_id, crop in assignment.items():
        req = _fertilizer_requirement_kg(crop, soil, area_by_plot[plot_id])
        total_n += req["n_kg"]
        total_p2o5 += req["p2o5_kg"]
        total_k2o += req["k2o_kg"]
        if crop not in seen_crops:
            seen_crops.add(crop)
            for step in load_crops()[crop]["split_schedule"]:
                split_schedule.append({"crop": crop, **step})

    dap_kg = total_p2o5 / (fert["dap"]["p2o5_pct"] / 100)
    n_from_dap = dap_kg * (fert["dap"]["n_pct"] / 100)
    urea_kg = max(0.0, total_n - n_from_dap) / (fert["urea"]["n_pct"] / 100)
    mop_kg = total_k2o / (fert["mop"]["k2o_pct"] / 100)

    dominant_crop = max(assignment.values(), key=list(assignment.values()).count)
    soil_class = f"N:{rate_nutrient('n_kg_ha', soil.get('n_kg_ha', 0))}"

    return {
        "urea_bags": math.ceil(urea_kg / fert["urea"]["bag_kg"]),
        "dap_bags": math.ceil(dap_kg / fert["dap"]["bag_kg"]),
        "mop_bags": math.ceil(mop_kg / fert["mop"]["bag_kg"]),
        "split_schedule": split_schedule,
        "soil_class": soil_class,
        "_dominant_crop": dominant_crop,
    }


def ph_advisory(soil_ph: float) -> dict:
    """TRD §7.2 pH correction table. The caveat string is non-removable."""
    if soil_ph < 5.5:
        category, amendment, dose = "Strongly acidic", "Lime", 2.5
    elif soil_ph < 6.5:
        category, amendment, dose = "Slightly acidic", "Lime", 1.5
    elif soil_ph <= 7.5:
        category, amendment, dose = "Optimal", "None", 0.0
    elif soil_ph <= 8.5:
        category, amendment, dose = "Alkaline", "Organic matter (gypsum only if sodicity confirmed)", 0.0
    else:
        category, amendment, dose = "Likely sodic", "Gypsum", 3.5

    return {
        "soil_ph": soil_ph,
        "category": category,
        "amendment": amendment,
        "dose_t_ha": dose,
        "caveat": "District-level indicative values; confirm with a soil test before applying amendments at cost.",
    }


def irrigation_advisory(crop: str, weather: dict[str, Any]) -> dict:
    """TRD §7.3. ponytail: TRD's effective-rainfall formula is defined for a
    monthly P; applied here to the 7-day forecast rainfall as a weekly-scale
    approximation (the granularity the app actually shows the farmer:
    "irrigate ~Z mm this week"). Upgrade path: track a real daily ET0/rainfall
    series per plot instead of the season-cumulative aggregate from the
    weather adapter.
    """
    crops = load_crops()
    kc_mid = crops[crop]["kc_stages"]["mid"]
    et0_cum = weather.get("et0_cum_mm")
    forecast_rain = weather.get("forecast_7d_rainfall_mm") or 0.0

    if et0_cum is None:
        etc_weekly = 0.0
    else:
        # Approximate a "typical week" ET0 from the season-cumulative value.
        et0_daily = et0_cum / 90  # season-to-date window used by the weather adapter
        etc_weekly = kc_mid * et0_daily * 7

    p = forecast_rain
    pe = p * (125 - 0.2 * p) / 125 if p < 250 else 125 + 0.1 * p
    nir = max(0.0, etc_weekly - pe)

    return {
        "etc_mm": round(etc_weekly, 1),
        "effective_rainfall_mm": round(pe, 1),
        "net_irrigation_mm": round(nir, 1),
        "guidance": f"Crop needs ~{round(etc_weekly)} mm this week; rain should supply ~{round(pe)} mm; irrigate ~{round(nir)} mm.",
    }


def build_advisory(
    *, assignment: dict[str, str], soil: dict[str, Any], weather: dict[str, Any], area_by_plot: dict[str, float]
) -> dict:
    fert = fertilizer_advisory(assignment, soil, area_by_plot)
    dominant_crop = fert.pop("_dominant_crop")
    return {
        "fertilizer": fert,
        "ph": ph_advisory(soil.get("ph", 6.5)),
        "irrigation": irrigation_advisory(dominant_crop, weather),
        "why": {
            "assignment": assignment,
            "soil_inputs": {k: soil.get(k) for k in ("n_kg_ha", "p_kg_ha", "k_kg_ha", "ph", "oc_pct")},
            "dominant_crop": dominant_crop,
        },
    }
