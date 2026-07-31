"""Feasible-crop shortlist from the soil card (brief §2.4).

This is the classical half of the division of labour: **filtering** is a set of
agronomic gates that either pass or fail, and **ranking** the survivors is the
combinatorial problem handed to the quantum optimiser. Keeping the boundary
sharp is what makes the architecture explainable — nothing here is quantum, and
nothing in the ranking step re-litigates feasibility.

Every exclusion carries a human-readable reason, because a farmer told "you
can't grow this" deserves to know why, and a reviewer checking the model
deserves to see the gate that fired.
"""
from dataclasses import dataclass
from typing import Any

from app.services.crop_reference import load_crops, rotation_cfg
from app.services.soil_card import SOIL_TYPES

# Crops that genuinely cannot be grown on poorly-drained soil.
#
# Groundnut needs friable soil for pegging, and maize is waterlogging-sensitive
# — both are hard gates. Paddy is the deliberate opposite case: it is grown in
# standing water, so heavy clay is an advantage.
#
# Black gram is *not* here on purpose. It is the standard rice-fallow pulse in
# the Cauvery delta, sown on exactly these clay soils to use residual moisture
# (see its note in crops.yaml). Gating it on drainage contradicted our own
# agronomic reference and left a farmer on delta clay — the most common soil in
# the region — with one feasible crop and no plan at all.
DRAINAGE_SENSITIVE = {"groundnut", "maize"}

# Crops that tolerate heavy soil but not standing water: worth a caution, not
# an exclusion.
DRAINAGE_CAUTION = {"black_gram"}

# Salinity tolerance (EC dS/m) above which a crop is excluded outright.
EC_TOLERANCE: dict[str, float] = {
    "paddy": 3.0,
    "maize": 1.8,
    "groundnut": 2.0,
    "black_gram": 1.5,
    "sugarcane": 1.7,
}


@dataclass
class CropVerdict:
    crop: str
    feasible: bool
    reasons: list[str]
    warnings: list[str]
    water_required_m3: float
    seasons: list[str]
    rotation_eligible: bool

    def to_dict(self) -> dict[str, Any]:
        crops = load_crops()
        cfg = crops.get(self.crop, {})
        return {
            "crop": self.crop,
            "name_en": cfg.get("name_en", self.crop),
            "name_ta": cfg.get("name_ta", self.crop),
            "feasible": self.feasible,
            "reasons": self.reasons,
            "warnings": self.warnings,
            "water_required_m3": round(self.water_required_m3, 1),
            "seasons": self.seasons,
            "rotation_eligible": self.rotation_eligible,
            "cost_rs_per_ha": cfg.get("cost_rs_per_ha"),
            "source": cfg.get("source"),
        }


def assess_crop(crop: str, *, soil_card: dict[str, Any], area_ha: float) -> CropVerdict:
    """Run every agronomic gate for one crop against one farm's soil card."""
    crops = load_crops()
    cfg = crops.get(crop, {})
    rot = rotation_cfg(crop)

    # Failures and passes are collected separately so an excluded crop's first
    # listed reason is always why it failed. Mixing them meant sugarcane —
    # excluded on water — led with "pH sits inside the crop's range", which
    # reads as nonsense to the farmer being told they cannot grow it.
    failures: list[str] = []
    passes: list[str] = []
    warnings: list[str] = []

    # Tolerance is the gate; the optimum is only a warning. Gating on the
    # optimum excluded four of five crops at pH 7.8 — ordinary calcareous
    # alluvium — which would make the app useless across much of India.
    ph = (soil_card.get("ph") or {}).get("value")
    ph_min, ph_max = rot.get("ph_min", 5.0), rot.get("ph_max", 8.5)
    ph_opt_min, ph_opt_max = rot.get("ph_opt_min", ph_min), rot.get("ph_opt_max", ph_max)
    if ph is not None:
        if ph < ph_min:
            failures.append(f"Soil pH {ph} is below this crop's tolerance ({ph_min}–{ph_max}).")
        elif ph > ph_max:
            failures.append(f"Soil pH {ph} is above this crop's tolerance ({ph_min}–{ph_max}).")
        else:
            passes.append(f"pH {ph} sits inside the crop's {ph_min}–{ph_max} tolerance.")
            if ph > ph_opt_max:
                warnings.append(
                    f"pH {ph} is above the {ph_opt_min}–{ph_opt_max} optimum — workable, but expect a "
                    "yield penalty and check micronutrient (iron, zinc) availability."
                )
            elif ph < ph_opt_min:
                warnings.append(
                    f"pH {ph} is below the {ph_opt_min}–{ph_opt_max} optimum — workable, but liming would lift yield."
                )
    else:
        warnings.append("No pH reading — pH suitability could not be checked.")

    # --- Salinity
    ec = (soil_card.get("ec") or {}).get("value")
    if ec is not None:
        limit = EC_TOLERANCE.get(crop, 2.0)
        if ec > limit:
            failures.append(f"Salinity {ec} dS/m exceeds this crop's tolerance of {limit} dS/m.")
        else:
            passes.append(f"Salinity {ec} dS/m is within tolerance.")

    # --- Water: the crop must fit inside the season water the farmer actually has
    water_required = float(cfg.get("water_m3_per_ha", 0.0)) * area_ha
    available = (soil_card.get("water") or {}).get("available_m3")
    if available is not None:
        if water_required > available:
            failures.append(
                f"Needs ~{water_required:,.0f} m³ of water but only {available:,.0f} m³ is available this season."
            )
        else:
            passes.append(f"Water need ~{water_required:,.0f} m³ fits the {available:,.0f} m³ available.")
            if water_required > available * 0.8:
                warnings.append("Water requirement uses over 80% of the season's supply — little margin.")

    # --- Drainage / texture
    soil_type = soil_card.get("soil_type", "loam")
    type_name = SOIL_TYPES.get(soil_type, {}).get("name_en", soil_type)
    drainage = SOIL_TYPES.get(soil_type, {}).get("drainage", "moderate")
    if crop in DRAINAGE_SENSITIVE and drainage == "poor":
        failures.append(f"{type_name} drains poorly; this crop needs well-drained soil.")
    if crop in DRAINAGE_CAUTION and drainage == "poor":
        warnings.append(
            f"{type_name} drains poorly — sow on residual moisture after the main crop and avoid standing water."
        )
    if crop == "paddy" and drainage == "excessive":
        failures.append("Sandy soil drains too fast to hold standing water for paddy.")

    feasible = not failures

    # --- Nutrient status: a warning, never a gate. Low N is a reason to
    # fertilise, not a reason to rule a crop out — the advisory step handles it.
    classes = soil_card.get("classes") or {}
    npk_req = cfg.get("npk_req_kg_ha", {})
    if classes.get("n_kg_ha") == "low" and npk_req.get("n", 0) > 100:
        warnings.append("Soil nitrogen is low and this is a heavy nitrogen feeder — expect a higher urea bill.")
    if classes.get("k_kg_ha") == "low" and npk_req.get("k2o", 0) > 70:
        warnings.append("Soil potassium is low and this crop has a high K demand.")

    if feasible and not passes:
        passes.append("Meets every soil and water gate for this farm.")

    return CropVerdict(
        crop=crop,
        feasible=feasible,
        # Excluded crops lead with what blocked them; feasible ones list what
        # they cleared.
        reasons=failures + passes if failures else passes,
        warnings=warnings,
        water_required_m3=water_required,
        seasons=list(rot.get("seasons", [])),
        rotation_eligible=bool(rot.get("rotation_eligible", True)),
    )


def shortlist(*, soil_card: dict[str, Any], area_ha: float, candidate_crops: list[str] | None = None) -> dict[str, Any]:
    """Split the crop catalogue into feasible and excluded, with reasons for both.

    Returns both halves rather than only the survivors: "why can't I grow X?" is
    one of the questions this app exists to answer, and silently dropping X
    would leave the farmer guessing.
    """
    crops = candidate_crops or list(load_crops().keys())
    verdicts = [assess_crop(c, soil_card=soil_card, area_ha=area_ha) for c in crops]

    feasible = [v for v in verdicts if v.feasible]
    excluded = [v for v in verdicts if not v.feasible]
    rotation_ready = [v for v in feasible if v.rotation_eligible]

    return {
        "feasible": [v.to_dict() for v in feasible],
        "excluded": [v.to_dict() for v in excluded],
        # Crops that pass the gates *and* fit a multi-season cycle. This is the
        # set handed to the quantum sequencer; sugarcane passes feasibility but
        # occupies the land for 12 months, so it cannot take a rotation slot.
        "rotation_candidates": [v.crop for v in rotation_ready],
        "counts": {
            "assessed": len(verdicts),
            "feasible": len(feasible),
            "excluded": len(excluded),
            "rotation_candidates": len(rotation_ready),
        },
    }
