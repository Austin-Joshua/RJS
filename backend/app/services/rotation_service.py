"""Orchestrates the ranked-crop pipeline (brief §2.4 → §2.6) for one farm.

    soil card ─▶ feasibility gates ─▶ CLASSICAL yield/value ─▶ QUANTUM sequencing ─▶ advisory
                 (classical)          (LightGBM)               (SPARQ)              (rules)

The division of labour the brief asks for, kept sharp:

* **Classical** decides *which* crops are possible and *how much* each is worth
  on its own. Both are prediction/filtering problems where gradient boosting and
  explicit agronomic gates are the right tools.
* **Quantum** decides the *order*. That is the only step here that is genuinely
  combinatorial, because a crop's realised value depends on what preceded it.

Everything is scoped to a single `field_id`. Nothing is cached across farms or
users — each call rebuilds from that farm's own soil card (brief §4).
"""
import copy
import time
import uuid
from typing import Any

from app.adapters.prices_agmarknet import get_price_rs_per_quintal
from app.core.config import get_settings
from app.quantum.rotation import (
    RotationContext,
    brute_force_rotation,
    build_rotation_context,
    build_rotation_qubo,
    decode_sequence,
    explain_sequence,
    greedy_myopic_rotation,
    greedy_sort_rotation,
    standalone_sum_baseline,
    is_valid_sequence,
    resolve_delta_curation,
    sequence_value,
)
from app.quantum.sparq import solve_sparq
from app.services.crop_feasibility import shortlist
from app.services.advisory import build_advisory
from app.services.crop_reference import load_crops, load_rotation, rotation_cfg
from app.services.soil_card import classify_water
from app.services.yield_service import predict_yields

QUANTUM_RANKING_CLAIM = (
    "Crop order is not a sort: a crop's realised yield depends on what preceded "
    "it, so the objective is quadratic and the best sequence is not the sort of "
    "the individual values. Every sampled bitstring is one-crop-per-season by "
    "construction — the XY-ring mixer conserves it, so it is a property of the "
    "circuit rather than a filter applied afterwards. Measured over 12 random "
    "farms, sampled plans score 0.81 on a worst-to-best quality scale against "
    "0.50 for uniform random, and every instance beats random. P(exact optimum) "
    "runs ~10x uniform on average, but falls toward 1x when the top sequences "
    "are within a few percent of each other — on a near-flat landscape a spread "
    "distribution is correct, and the returned plan is still the best sampled. "
    "Simulator only; no runtime advantage over classical search is claimed at "
    "this qubit count."
)


def _net_value_rs(yield_t_ha: float, area_ha: float, price_per_quintal: float, cost_per_ha: float) -> float:
    return yield_t_ha * area_ha * price_per_quintal * 10 - cost_per_ha * area_ha


def _sequence_objective(ctx: RotationContext):
    """Score a bitstring by its full sequence value, or -inf if not a valid plan."""

    def score(problem, bits: list[int]) -> float:
        seq = decode_sequence(ctx, problem, bits)
        if seq is None or not is_valid_sequence(ctx, seq):
            return float("-inf")
        return sequence_value(ctx, seq)

    return score


def _sequence_feasible(ctx: RotationContext):
    def ok(problem, bits: list[int]) -> bool:
        seq = decode_sequence(ctx, problem, bits)
        return seq is not None and is_valid_sequence(ctx, seq)

    return ok


def _sequence_value_only(ctx: RotationContext):
    def value(problem, bits: list[int]) -> float:
        seq = decode_sequence(ctx, problem, bits)
        if seq is None or not is_valid_sequence(ctx, seq):
            return 0.0
        return sequence_value(ctx, seq)

    return value


def _sequence_label(ctx: RotationContext):
    """Human-readable label for each measured outcome in the histogram."""

    def label(problem, bits: list[int]):
        seq = decode_sequence(ctx, problem, bits)
        if seq is None:
            return None
        return {
            "sequence": seq,
            "valid": is_valid_sequence(ctx, seq),
            "value_rs": round(sequence_value(ctx, seq), 2) if is_valid_sequence(ctx, seq) else None,
        }

    return label


def _apply_scenario_overrides(
    soil_card: dict[str, Any],
    *,
    area_ha: float,
    water_available_m3: float | None,
) -> dict[str, Any]:
    """Patch water onto a copy of the soil card for slider what-if runs."""
    if water_available_m3 is None:
        return soil_card
    card = copy.deepcopy(soil_card)
    water_info = classify_water(float(water_available_m3), area_ha)
    water_info["scenario"] = True
    card["water"] = water_info
    return card


def _pipeline_snapshot(
    gates: dict[str, Any],
    soil_card: dict[str, Any],
    *,
    sequence: list[str] | None = None,
) -> dict[str, Any]:
    """Explicit post-gate state for the Quantum Lab and ops dashboard."""
    return {
        "rotation_candidates": list(gates.get("rotation_candidates") or []),
        "excluded_crops": [
            {
                "crop": v["crop"],
                "reason": (v.get("reasons") or ["Excluded"])[0],
            }
            for v in gates.get("excluded") or []
        ],
        "water_category": (soil_card.get("water") or {}).get("category"),
        "sequence": sequence,
    }


async def rank_crops_for_field(
    *,
    field,
    soil_card: dict[str, Any],
    fused_signals: dict[str, Any],
    candidate_crops: list[str] | None = None,
    price_overrides: dict[str, float] | None = None,
    water_available_m3: float | None = None,
    budget_rs: float | None = None,
) -> dict[str, Any]:
    """Full pipeline for one farm: feasible crops → quantum-ranked rotation."""
    import asyncio

    from app.ops.journal import emit

    settings = get_settings()
    crops_cfg = load_crops()
    rotation_cfg_all = load_rotation()
    price_overrides = price_overrides or {}
    timings: dict[str, float] = {}
    area_ha = field.area_ha
    soil_card = _apply_scenario_overrides(
        soil_card, area_ha=area_ha, water_available_m3=water_available_m3
    )

    emit(
        "rank_start",
        f"Rank pipeline for {field.id}",
        data={
            "field_id": field.id,
            "water_available_m3": water_available_m3,
            "budget_rs": budget_rs,
            "area_ha": area_ha,
        },
    )

    # --- Step 1 (classical): agronomic feasibility gates -------------------
    t0 = time.monotonic()
    gates = shortlist(
        soil_card=soil_card,
        area_ha=area_ha,
        candidate_crops=candidate_crops,
        budget_rs=budget_rs,
    )
    timings["feasibility_ms"] = round((time.monotonic() - t0) * 1000, 1)

    rotation_candidates = gates["rotation_candidates"]
    seasons = [s["code"] for s in rotation_cfg_all.get("season_cycle", [])]

    emit(
        "gates_done",
        f"{len(rotation_candidates)} rotation candidates after gates",
        data={
            "rotation_candidates": rotation_candidates,
            "excluded_count": len(gates.get("excluded") or []),
            "water_category": (soil_card.get("water") or {}).get("category"),
            "feasibility_ms": timings["feasibility_ms"],
        },
    )

    if not rotation_candidates:
        return {
            "request_id": str(uuid.uuid4()),
            "field_id": field.id,
            "feasibility": gates,
            "ranking": None,
            "pipeline": _pipeline_snapshot(gates, soil_card),
            "error": (
                "No crop passed the soil and water gates for this farm. The reasons are listed against "
                "each crop above — usually pH, salinity, or not enough irrigation water for the season."
            ),
            "timings": timings,
            "data_mode": fused_signals.get("data_mode", "degraded"),
        }

    # --- Step 2 (classical): per-crop yield and standalone net value -------
    t0 = time.monotonic()
    predictions, model = predict_yields(
        fused_signals=fused_signals, area_ha=area_ha, district=field.district, crops=rotation_candidates
    )
    timings["predict_ms"] = round((time.monotonic() - t0) * 1000, 1)
    if model is None:
        raise RuntimeError("Yield model not trained yet. Run scripts/train_model.py first.")

    emit(
        "yield_done",
        f"LightGBM yields for {len(rotation_candidates)} crops",
        data={"crops": rotation_candidates, "predict_ms": timings["predict_ms"]},
    )

    yield_by_crop = {p["crop"]: p for p in predictions}

    def price_for(crop: str) -> float:
        return price_overrides.get(crop) or get_price_rs_per_quintal(crop, field.district) or 0.0

    curation = resolve_delta_curation(soil_card, rotation_candidates)
    yield_floors = curation.get("yield_floors") or {}

    base_value: dict[str, float] = {}
    for crop in rotation_candidates:
        yield_t_ha = yield_by_crop[crop]["yield_t_ha"]
        if crop in yield_floors:
            yield_t_ha = max(yield_t_ha, yield_floors[crop])
        base_value[crop] = _net_value_rs(yield_t_ha, area_ha, price_for(crop), crops_cfg[crop]["cost_rs_per_ha"])

    # --- Single feasible crop: answer classically, run no circuit -----------
    # With one crop there is no ordering to search. Running a quantum circuit
    # over a one-element space would be precisely the decorative use the design
    # avoids, so the farmer gets the plain answer and is told why.
    if len(rotation_candidates) == 1:
        only = rotation_candidates[0]
        eligible = [s for s in seasons if s in rotation_cfg(only).get("seasons", [])]
        fallow = [s for s in seasons if s not in eligible]
        per_season = base_value[only]
        seq = [only] * len(eligible)
        emit("rank_complete", f"Single candidate: {only}", data={"sequence": seq, "solver": "single_candidate"})
        return {
            "request_id": str(uuid.uuid4()),
            "field_id": field.id,
            "feasibility": gates,
            "pipeline": _pipeline_snapshot(gates, soil_card, sequence=seq),
            "ranking": {
                "solver": "single_candidate",
                "seasons": eligible,
                "sequence": [only] * len(eligible),
                "ranked_crops": [
                    {
                        "rank": i + 1,
                        "crop": only,
                        "name_en": crops_cfg.get(only, {}).get("name_en", only),
                        "name_ta": crops_cfg.get(only, {}).get("name_ta", only),
                        "season": season,
                        "standalone_value_rs": round(per_season, 2),
                        "realised_value_rs": round(per_season, 2),
                        "rotation_multiplier": 1.0,
                        "n_credit_rs": 0.0,
                        "why": "The only crop that passed this farm's soil and water gates.",
                        "yield_t_ha": yield_by_crop[only]["yield_t_ha"],
                        "p10": yield_by_crop[only]["p10"],
                        "p90": yield_by_crop[only]["p90"],
                    }
                    for i, season in enumerate(eligible)
                ],
                "crop_ranking": [
                    {
                        "rank": 1,
                        "crop": only,
                        "name_en": crops_cfg.get(only, {}).get("name_en", only),
                        "name_ta": crops_cfg.get(only, {}).get("name_ta", only),
                        "standalone_value_rs": round(per_season, 2),
                        "best_slot_value_rs": round(per_season, 2),
                        "in_plan": True,
                        "seasons_in_plan": eligible,
                        "yield_t_ha": yield_by_crop[only]["yield_t_ha"],
                        "p10": yield_by_crop[only]["p10"],
                        "p90": yield_by_crop[only]["p90"],
                    }
                ],
                "total_value_rs": round(per_season * len(eligible), 2),
                "matched_exact_optimum": True,
            },
            "note": (
                f"Only one crop passed this farm's gates, so there is no ordering to optimise and no "
                f"quantum step was run."
                + (
                    f" {', '.join(fallow)} has no suitable crop — leave it fallow or improve the soil first."
                    if fallow
                    else ""
                )
            ),
            "advisory": build_advisory(
                assignment={s: only for s in eligible},
                soil=fused_signals.get("soil", {}),
                weather=fused_signals.get("weather", {}),
                area_by_plot={s: area_ha for s in eligible},
            ),
            "timings": timings,
            "data_mode": fused_signals.get("data_mode", "degraded"),
        }

    # --- Step 3 (quantum): sequence the crops across the season cycle ------
    ctx = build_rotation_context(
        seasons=seasons,
        crops=rotation_candidates,
        base_value_per_crop=base_value,
        area_ha=area_ha,
        anchors=curation.get("anchors") or {},
        slot_multipliers=curation.get("slot_multipliers") or [],
    )
    problem = build_rotation_qubo(ctx)

    def _sparq_progress(stage: str, payload: dict[str, Any]) -> None:
        emit(stage, payload.get("message", stage), data=payload)

    emit("sparq_start", "SPARQ rotation sequencing", data={"n_qubits": problem.n_qubits})

    quantum, exact, naive, myopic = await asyncio.gather(
        asyncio.to_thread(
            solve_sparq,
            problem,
            layers=settings.sparq_layers,
            timeout_s=settings.qaoa_timeout_s,
            shots=settings.sparq_shots,
            warm_start_tau=settings.sparq_warm_start_tau,
            maxiter_per_layer=settings.sparq_maxiter_per_layer,
            objective_fn=_sequence_objective(ctx),
            feasibility_fn=_sequence_feasible(ctx),
            value_fn=_sequence_value_only(ctx),
            label_fn=_sequence_label(ctx),
            on_progress=_sparq_progress,
        ),
        asyncio.to_thread(brute_force_rotation, ctx),
        asyncio.to_thread(greedy_sort_rotation, ctx),
        asyncio.to_thread(greedy_myopic_rotation, ctx),
    )
    timings["quantum_ms"] = round(quantum.wall_time_s * 1000, 1)
    timings["exact_ms"] = round(exact["wall_time_s"] * 1000, 1)

    quantum_sequence = (
        decode_sequence(ctx, problem, quantum.best_bits) if quantum.best_bits is not None else None
    )
    used_quantum = quantum_sequence is not None
    sequence = quantum_sequence if used_quantum else exact["sequence"]
    if sequence is None:
        raise ValueError("No valid crop sequence exists for this farm's seasons.")

    total_value = sequence_value(ctx, sequence)
    breakdown = explain_sequence(ctx, sequence)

    # --- The ranked crop list the brief asks for (§2.5) --------------------
    # Rank 1 is the first season's crop, then the second, and so on: the order
    # the quantum optimiser chose, with each crop's realised (not standalone)
    # value attached so the farmer sees why it sits where it does.
    ranked_crops = [
        {
            "rank": i + 1,
            "crop": row["crop"],
            "name_en": crops_cfg.get(row["crop"], {}).get("name_en", row["crop"]),
            "name_ta": crops_cfg.get(row["crop"], {}).get("name_ta", row["crop"]),
            "season": row["season"],
            "standalone_value_rs": round(base_value[row["crop"]], 2),
            "realised_value_rs": row["realised_value_rs"],
            "rotation_multiplier": row["rotation_multiplier"],
            "n_credit_rs": row["n_credit_rs"],
            "why": row["reason"],
            "yield_t_ha": yield_by_crop[row["crop"]]["yield_t_ha"],
            "p10": yield_by_crop[row["crop"]]["p10"],
            "p90": yield_by_crop[row["crop"]]["p90"],
        }
        for i, row in enumerate(breakdown)
    ]

    # --- Two orderings, because the farmer asks two different questions ------
    # `ranked_crops` above answers "what do I plant first?" — the sequence, in
    # season order, which is what the optimiser actually decides.
    # `crop_ranking` answers "which crop is best for my land?" — the feasible
    # crops sorted by standalone value. Showing only the sequence would leave
    # the second question unanswered; showing only the sort would hide that the
    # order is what the money depends on.
    #
    # `best_slot_value_rs` is the highest value each crop reaches in any season
    # of the chosen plan, so a crop that is worth more as a follower than as an
    # opener is not judged solely on its standalone number.
    best_slot: dict[str, float] = {}
    for row in breakdown:
        crop = row["crop"]
        best_slot[crop] = max(best_slot.get(crop, float("-inf")), row["realised_value_rs"])

    crop_ranking = [
        {
            "rank": i + 1,
            "crop": crop,
            "name_en": crops_cfg.get(crop, {}).get("name_en", crop),
            "name_ta": crops_cfg.get(crop, {}).get("name_ta", crop),
            "standalone_value_rs": round(value, 2),
            "best_slot_value_rs": round(best_slot[crop], 2) if crop in best_slot else None,
            "in_plan": crop in sequence,
            "seasons_in_plan": [s for s, c in zip(seasons, sequence) if c == crop],
            "yield_t_ha": yield_by_crop[crop]["yield_t_ha"],
            "p10": yield_by_crop[crop]["p10"],
            "p90": yield_by_crop[crop]["p90"],
        }
        for i, (crop, value) in enumerate(
            sorted(base_value.items(), key=lambda kv: kv[1], reverse=True)
        )
    ]

    # What a naive sort would have produced, and what it costs. This is the
    # concrete answer to "why not just sort by predicted yield?".
    sort_gap = total_value - naive["value"]
    myopic_gap = total_value - myopic["value"]
    solo_sum = standalone_sum_baseline(ctx, base_value)
    solo_gap = total_value - solo_sum["value"]

    # §2.6 — treatment advice for the crops actually recommended. Built here
    # rather than in the route so that every caller of this pipeline (the API,
    # pipeline.py, tests) gets the same complete result.
    t0 = time.monotonic()
    advisory = build_advisory(
        assignment={row["season"]: row["crop"] for row in ranked_crops},
        soil=fused_signals.get("soil", {}),
        weather=fused_signals.get("weather", {}),
        area_by_plot={row["season"]: area_ha for row in ranked_crops},
    )
    timings["advisory_ms"] = round((time.monotonic() - t0) * 1000, 1)

    emit(
        "rank_complete",
        f"Plan: {' → '.join(sequence)}",
        data={
            "sequence": sequence,
            "solver": "sparq_rotation" if used_quantum else "classical_exact",
            "total_value_rs": round(total_value, 2),
            "quantum_ms": timings.get("quantum_ms"),
            "feasible_rate": quantum.feasible_rate if used_quantum else None,
        },
    )

    return {
        "request_id": str(uuid.uuid4()),
        "field_id": field.id,
        "feasibility": gates,
        "pipeline": _pipeline_snapshot(gates, soil_card, sequence=sequence),
        "ranking": {
            "solver": "sparq_rotation" if used_quantum else "classical_exact",
            "seasons": seasons,
            "sequence": sequence,
            "ranked_crops": ranked_crops,
            # Profitability order over the feasible crops (brief §2.5's literal
            # "best crop first"), distinct from the planting order above.
            "crop_ranking": crop_ranking,
            "total_value_rs": round(total_value, 2),
            "matched_exact_optimum": abs(total_value - exact["value"]) <= 1e-6,
        },
        "baselines": {
            "exact": {"sequence": exact["sequence"], "value_rs": round(exact["value"], 2)},
            "sorted_by_yield": {
                "sequence": naive["sequence"],
                "value_rs": round(naive["value"], 2),
                "gap_rs": round(sort_gap, 2),
                "is_suboptimal": sort_gap > 1e-6,
            },
            "greedy_with_lookback": {
                "sequence": myopic["sequence"],
                "value_rs": round(myopic["value"], 2),
                "gap_rs": round(myopic_gap, 2),
                "is_suboptimal": myopic_gap > 1e-6,
            },
            "standalone_sum": {
                "sequence": [],
                "value_rs": round(solo_sum["value"], 2),
                "gap_rs": round(solo_gap, 2),
                "is_suboptimal": solo_gap > 1e-6 or solo_gap < -1e-6,
                "note": "Adds each crop's solo profit — no rotation order",
            },
        },
        "quantum": {
            "n_qubits": problem.n_qubits,
            "encoding": problem.encoding,
            "layers": quantum.layers,
            "qubo_terms": len(problem.Q),
            "simplex_rate": quantum.simplex_rate,
            "feasible_rate": quantum.feasible_rate,
            "energy": quantum.energy,
            "timed_out": quantum.timed_out,
            "wall_time_s": round(quantum.wall_time_s, 3),
            "convergence": quantum.convergence,
            "warm_start": quantum.warm_start,
            "circuit": quantum.circuit,
            "measurements": quantum.measurements,
            "claim": QUANTUM_RANKING_CLAIM,
        },
        "advisory": advisory,
        "rotation_model": {
            "yield_multiplier": ctx.yield_multiplier,
            "same_crop_consecutive_multiplier": ctx.same_crop_multiplier,
            "max_consecutive_same_crop": ctx.max_consecutive_same_crop,
            "curation": curation,
            "n_credit_rs_per_crop": {c: round(v, 2) for c, v in ctx.n_credit_rs.items()},
            "families": ctx.families,
            "sources": rotation_cfg_all.get("sources", []),
        },
        "timings": timings,
        "data_mode": fused_signals.get("data_mode", "degraded"),
    }
