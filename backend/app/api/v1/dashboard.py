"""Cross-farm analytical dashboard (brief §2.8).

Aggregates only over farms belonging to the caller. The query is filtered by
`farmer_id` at the source rather than fetched-then-filtered, so another
account's farm cannot reach the aggregation step at all (§4).
"""
from typing import Any

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.api.v1.dependencies import CurrentUser, get_current_user, get_db
from app.db import models
from app.services.crop_reference import load_crops


router = APIRouter(prefix="/dashboard", tags=["dashboard"])


@router.get("")
async def get_dashboard(
    db: Session = Depends(get_db), user: CurrentUser = Depends(get_current_user)
) -> dict[str, Any]:
    query = db.query(models.Field)
    if user.role == "farmer":
        query = query.filter(models.Field.farmer_id == user.id)
    farms = query.order_by(models.Field.created_at.desc()).all()

    crops_cfg = load_crops()
    rows: list[dict[str, Any]] = []
    total_area = 0.0
    total_value = 0.0
    crop_frequency: dict[str, int] = {}
    needs_attention: list[dict[str, Any]] = []
    ranked_count = 0

    # Quantum / optimiser roll-up across ranked farms.
    q_farms = 0
    feas_rates: list[float] = []
    simplex_rates: list[float] = []
    wall_times: list[float] = []
    beats_sort = 0
    sort_gap_total = 0.0
    land_npk: list[dict[str, Any]] = []

    for field in farms:
        total_area += field.area_ha or 0.0
        card = field.soil_cards[0] if field.soil_cards else None
        plan = field.rotation_plans[0] if field.rotation_plans else None

        sequence = plan.sequence.get("sequence", []) if plan else []
        for crop in sequence:
            crop_frequency[crop] = crop_frequency.get(crop, 0) + 1
        if plan:
            ranked_count += 1
            total_value += plan.total_value_rs or 0.0

        issues: list[str] = []
        if card:
            classes = card.classes or {}
            low = [k.split("_")[0].upper() for k, v in classes.items() if v == "low" and k != "oc_pct"]
            if low:
                issues.append(f"{', '.join(low)} low — add fertiliser")
            ph_info = (card.card or {}).get("ph", {})
            if ph_info.get("category") in {"strongly_acidic", "sodic"}:
                issues.append(f"soil pH needs fixing ({ph_info.get('category', '').replace('_', ' ')})")
            ec_info = (card.card or {}).get("ec", {})
            if ec_info.get("category") == "injurious":
                issues.append("salt in soil is high — risky for crops")
            readings = card.readings or {}
            land_npk.append(
                {
                    "farm_id": field.id,
                    "name": field.name,
                    "n_kg_ha": readings.get("n_kg_ha"),
                    "p_kg_ha": readings.get("p_kg_ha"),
                    "k_kg_ha": readings.get("k_kg_ha"),
                    "ph": readings.get("ph"),
                    "classes": classes,
                }
            )
        else:
            issues.append("add soil readings first")
        if plan is None:
            issues.append("run crop ranking to see the plan")

        if issues:
            needs_attention.append({"farm_id": field.id, "name": field.name, "issues": issues})

        quantum = (plan.quantum or {}) if plan else {}
        baselines = (plan.baselines or {}) if plan else {}
        if quantum:
            q_farms += 1
            if quantum.get("feasible_rate") is not None:
                feas_rates.append(float(quantum["feasible_rate"]))
            if quantum.get("simplex_rate") is not None:
                simplex_rates.append(float(quantum["simplex_rate"]))
            if quantum.get("wall_time_s") is not None:
                wall_times.append(float(quantum["wall_time_s"]))
            sorted_bl = baselines.get("sorted_by_yield") or {}
            if sorted_bl.get("is_suboptimal"):
                beats_sort += 1
                sort_gap_total += float(sorted_bl.get("gap_rs") or 0.0)

        rows.append(
            {
                "farm_id": field.id,
                "name": field.name,
                "district": field.district,
                "state": field.state,
                "area_ha": field.area_ha,
                "soil_type": card.soil_type if card else None,
                "soil_summary": (card.card or {}).get("summary") if card else None,
                "soil_classes": card.classes if card else None,
                "has_soil_card": card is not None,
                "ranked": plan is not None,
                "sequence": sequence,
                "sequence_names": [crops_cfg.get(c, {}).get("name_en", c) for c in sequence],
                "total_value_rs": plan.total_value_rs if plan else None,
                "solver": plan.solver if plan else None,
                "ranked_at": plan.created_at.isoformat() if plan and plan.created_at else None,
                "issues": issues,
                "quantum": {
                    "feasible_rate": quantum.get("feasible_rate"),
                    "simplex_rate": quantum.get("simplex_rate"),
                    "wall_time_s": quantum.get("wall_time_s"),
                    "n_qubits": quantum.get("n_qubits"),
                    "layers": quantum.get("layers"),
                }
                if quantum
                else None,
            }
        )

    def _avg(xs: list[float]) -> float | None:
        return round(sum(xs) / len(xs), 4) if xs else None

    return {
        "totals": {
            "farms": len(farms),
            "total_area_ha": round(total_area, 3),
            "farms_ranked": ranked_count,
            "farms_awaiting_ranking": len(farms) - ranked_count,
            "combined_projected_value_rs": round(total_value, 2),
        },
        "farms": rows,
        "crop_frequency": crop_frequency,
        "needs_attention": needs_attention,
        "land_variables": land_npk,
        "quantum": {
            "farms_optimised": q_farms,
            "avg_feasible_rate": _avg(feas_rates),
            "avg_simplex_rate": _avg(simplex_rates),
            "avg_wall_time_s": _avg(wall_times),
            "beats_simple_sort_count": beats_sort,
            "extra_value_vs_sort_rs": round(sort_gap_total, 2),
            "plain_summary": (
                f"Quantum optimiser ran on {q_farms} farm(s). "
                + (
                    f"Valid crop-order samples averaged "
                    f"{(_avg(feas_rates) or 0) * 100:.0f}%. "
                    if feas_rates
                    else ""
                )
                + (
                    f"On {beats_sort} farm(s) it beat a simple profit sort "
                    f"(about ₹{sort_gap_total:,.0f} extra over the year)."
                    if beats_sort
                    else "On these farms a simple profit sort matched the quantum order."
                    if q_farms
                    else "Rank a farm to see quantum results here."
                )
            ),
        },
    }
