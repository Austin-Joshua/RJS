"""Soil card: farmer-entered readings -> classified parameters (brief §2.2-§2.3).

The farmer types raw numbers off a lab report or Soil Health Card. This module
turns them into the Low / Medium / High classes an agronomist would assign, so
the card the farmer sees back is interpretable rather than a wall of figures.

Every threshold is ICAR / Soil Health Card standard and lives in one table here
rather than being scattered through the code, because these are the numbers a
domain reviewer will want to check first.
"""
from dataclasses import dataclass, field
from typing import Any, Literal

RatingClass = Literal["low", "medium", "high"]

# ICAR / Soil Health Card nutrient rating bands. Same table as TRD §3.1 — the
# feasibility filter and the fertiliser advisory both key off these classes, so
# they must agree.
NUTRIENT_BANDS: dict[str, tuple[float, float, str]] = {
    # key: (low_below, high_above, unit)
    "n_kg_ha": (280.0, 560.0, "kg/ha"),
    "p_kg_ha": (10.0, 25.0, "kg/ha"),
    "k_kg_ha": (120.0, 280.0, "kg/ha"),
    "oc_pct": (0.50, 0.75, "%"),
}

PH_BANDS: list[tuple[float, float, str, str]] = [
    (0.0, 5.5, "strongly_acidic", "Strongly acidic — most crops will struggle without liming."),
    (5.5, 6.5, "slightly_acidic", "Slightly acidic — workable for most crops."),
    (6.5, 7.5, "neutral", "Neutral — the ideal range for nutrient availability."),
    (7.5, 8.5, "alkaline", "Alkaline — iron and zinc uptake may be restricted."),
    (8.5, 14.0, "sodic", "Likely sodic — confirm with a gypsum-requirement test."),
]

# Electrical conductivity: salinity risk (dS/m), SHC standard.
EC_BANDS: list[tuple[float, float, str, str]] = [
    (0.0, 1.0, "normal", "Normal — no salinity constraint."),
    (1.0, 2.0, "critical", "Critical for salt-sensitive crops."),
    (2.0, 100.0, "injurious", "Injurious — salinity will cut yields across most crops."),
]

# Indian field-texture classes a farmer can pick from without a lab.
SOIL_TYPES: dict[str, dict[str, Any]] = {
    "alluvial": {"name_en": "Alluvial", "name_ta": "வண்டல் மண்", "water_holding": "medium", "drainage": "good"},
    "black": {"name_en": "Black (regur)", "name_ta": "கரிசல் மண்", "water_holding": "high", "drainage": "poor"},
    "red": {"name_en": "Red", "name_ta": "செம்மண்", "water_holding": "low", "drainage": "good"},
    "laterite": {"name_en": "Laterite", "name_ta": "பொட்டல் மண்", "water_holding": "low", "drainage": "good"},
    "clay": {"name_en": "Clay", "name_ta": "களி மண்", "water_holding": "high", "drainage": "poor"},
    "clay_loam": {"name_en": "Clay loam", "name_ta": "களி கலந்த வண்டல்", "water_holding": "high", "drainage": "moderate"},
    "loam": {"name_en": "Loam", "name_ta": "கலவை மண்", "water_holding": "medium", "drainage": "good"},
    "sandy_loam": {"name_en": "Sandy loam", "name_ta": "மணல் கலந்த வண்டல்", "water_holding": "low", "drainage": "good"},
    "sandy": {"name_en": "Sandy", "name_ta": "மணல் மண்", "water_holding": "very_low", "drainage": "excessive"},
}

LAB_TEST_CAVEAT = (
    "These classes come from the readings you entered. Confirm with a soil test "
    "before spending money on amendments."
)


@dataclass
class SoilCard:
    field_id: str
    soil_type: str
    readings: dict[str, float | None]
    classes: dict[str, str]
    ph: dict[str, Any]
    ec: dict[str, Any]
    water: dict[str, Any]
    summary: str
    caveat: str = LAB_TEST_CAVEAT
    warnings: list[str] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return {
            "field_id": self.field_id,
            "soil_type": self.soil_type,
            "soil_type_meta": SOIL_TYPES.get(self.soil_type, {}),
            "readings": self.readings,
            "classes": self.classes,
            "ph": self.ph,
            "ec": self.ec,
            "water": self.water,
            "summary": self.summary,
            "caveat": self.caveat,
            "warnings": self.warnings,
        }


def classify_nutrient(key: str, value: float | None) -> str:
    """Low / medium / high against the ICAR band for this nutrient."""
    if value is None:
        return "unknown"
    low_below, high_above, _unit = NUTRIENT_BANDS[key]
    if value < low_below:
        return "low"
    if value > high_above:
        return "high"
    return "medium"


def classify_ph(ph: float | None) -> dict[str, Any]:
    if ph is None:
        return {"value": None, "category": "unknown", "note": "No pH reading entered."}
    for lo, hi, name, note in PH_BANDS:
        if lo <= ph < hi:
            return {"value": ph, "category": name, "note": note}
    return {"value": ph, "category": "sodic", "note": PH_BANDS[-1][3]}


def classify_ec(ec: float | None) -> dict[str, Any]:
    if ec is None:
        return {"value": None, "category": "unknown", "note": "No EC reading entered."}
    for lo, hi, name, note in EC_BANDS:
        if lo <= ec < hi:
            return {"value": ec, "category": name, "note": note}
    return {"value": ec, "category": "injurious", "note": EC_BANDS[-1][3]}


def classify_water(available_m3: float | None, area_ha: float) -> dict[str, Any]:
    """Season water availability per hectare, banded against crop demand.

    Bands are anchored on the crop water requirements in crops.yaml: black gram
    needs ~1,800 m3/ha and paddy ~6,500, so those figures set what "low" and
    "high" mean rather than an arbitrary scale.
    """
    if available_m3 is None or area_ha <= 0:
        return {"available_m3": available_m3, "per_ha_m3": None, "category": "unknown"}

    per_ha = available_m3 / area_ha
    if per_ha < 2000:
        category, note = "low", "Enough for short-duration pulses only."
    elif per_ha < 4500:
        category, note = "medium", "Enough for oilseeds and irrigated dry crops; not for paddy."
    elif per_ha < 7000:
        category, note = "high", "Enough for one paddy crop."
    else:
        category, note = "abundant", "Enough for paddy or a water-intensive crop."

    return {
        "available_m3": available_m3,
        "per_ha_m3": round(per_ha, 1),
        "category": category,
        "note": note,
    }


def build_soil_card(
    *,
    field_id: str,
    area_ha: float,
    soil_type: str,
    n_kg_ha: float | None,
    p_kg_ha: float | None,
    k_kg_ha: float | None,
    ph: float | None,
    oc_pct: float | None = None,
    ec_ds_m: float | None = None,
    moisture_pct: float | None = None,
    water_available_m3: float | None = None,
) -> SoilCard:
    """Classify one farm's entered readings. Pure function — no DB, no network."""
    readings = {
        "n_kg_ha": n_kg_ha,
        "p_kg_ha": p_kg_ha,
        "k_kg_ha": k_kg_ha,
        "ph": ph,
        "oc_pct": oc_pct,
        "ec_ds_m": ec_ds_m,
        "moisture_pct": moisture_pct,
        "water_available_m3": water_available_m3,
    }
    classes = {key: classify_nutrient(key, readings.get(key)) for key in NUTRIENT_BANDS}
    ph_info = classify_ph(ph)
    ec_info = classify_ec(ec_ds_m)
    water_info = classify_water(water_available_m3, area_ha)

    warnings: list[str] = []
    if soil_type not in SOIL_TYPES:
        warnings.append(f"Unrecognised soil type '{soil_type}' — treated as loam for recommendations.")
    for key, value in (("ph", ph), ("n_kg_ha", n_kg_ha), ("p_kg_ha", p_kg_ha), ("k_kg_ha", k_kg_ha)):
        if value is None:
            warnings.append(f"No {key} reading — crop feasibility for this farm is less certain.")
    if ec_info["category"] == "injurious":
        warnings.append("Salinity is in the injurious band; yields will be depressed across all crops.")

    deficient = [k.split("_")[0].upper() for k, v in classes.items() if v == "low" and k != "oc_pct"]
    if deficient:
        nutrient_text = f"{', '.join(deficient)} {'is' if len(deficient) == 1 else 'are'} low"
    else:
        nutrient_text = "N, P and K are adequate"

    type_label = SOIL_TYPES.get(soil_type, {}).get("name_en", soil_type)
    summary = (
        f"{type_label} soil, {ph_info['category'].replace('_', ' ')} "
        f"(pH {ph if ph is not None else '—'}). {nutrient_text}. "
        f"Water availability: {water_info['category']}."
    )

    return SoilCard(
        field_id=field_id,
        soil_type=soil_type,
        readings=readings,
        classes=classes,
        ph=ph_info,
        ec=ec_info,
        water=water_info,
        summary=summary,
        warnings=warnings,
    )
