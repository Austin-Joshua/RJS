"""Orchestrates the `/plan` money path (TRD §2 sequence diagram): net-value
matrix -> QUBO -> QAOA + classical (parallel) -> advisory. Persists the
result so a pre-seeded demo field survives a restart (TRD §9)."""
import asyncio
import time
import uuid
from typing import Any

from sqlalchemy.orm import Session

from app.adapters.prices_agmarknet import get_price_rs_per_quintal
from app.core.config import get_settings
from app.db import models
from app.quantum.classical_fallback import brute_force
from app.quantum.qubo import build_qubo, decode_decision_bits, feasible_value
from app.quantum.quantum_optimizer import solve_qaoa
from app.services.advisory import build_advisory
from app.services.crop_reference import load_crops
from app.services.yield_service import predict_yields


def _net_value_rs(yield_t_ha: float, area_ha: float, price_per_quintal: float, cost_per_ha: float) -> float:
    return yield_t_ha * area_ha * price_per_quintal * 10 - cost_per_ha * area_ha


async def build_plan(
    *,
    field: models.Field,
    plots_in: list[dict[str, Any]],
    candidate_crops: list[str],
    water_m3: float,
    budget_rs: float,
    price_overrides: dict[str, float] | None,
    fused_signals: dict[str, Any],
) -> dict[str, Any]:
    settings = get_settings()
    price_overrides = price_overrides or {}
    crops_cfg = load_crops()
    timings: dict[str, float] = {}

    t0 = time.monotonic()
    predictions, model = predict_yields(
        fused_signals=fused_signals, area_ha=field.area_ha, district=field.district, crops=candidate_crops
    )
    timings["predict_ms"] = round((time.monotonic() - t0) * 1000, 1)
    if model is None:
        raise RuntimeError("Yield model not trained yet. Run scripts/train_model.py first.")

    yield_by_crop = {p["crop"]: p for p in predictions}

    def price_for(crop: str) -> float:
        return price_overrides.get(crop) or get_price_rs_per_quintal(crop, field.district) or 0.0

    value_map, water_map, cost_map = {}, {}, {}
    for plot in plots_in:
        for crop in candidate_crops:
            pred = yield_by_crop[crop]
            cfg = crops_cfg[crop]
            key = (plot["plot_id"], crop)
            value_map[key] = _net_value_rs(pred["yield_t_ha"], plot["area_ha"], price_for(crop), cfg["cost_rs_per_ha"])
            water_map[key] = cfg["water_m3_per_ha"] * plot["area_ha"]
            cost_map[key] = cfg["cost_rs_per_ha"] * plot["area_ha"]

    problem = build_qubo(
        plots=plots_in,
        candidate_crops=candidate_crops,
        value_map=value_map,
        water_map=water_map,
        cost_map=cost_map,
        water_limit=water_m3,
        budget_limit=budget_rs,
        encoding=settings.encoding,
    )

    qaoa_result, classical_result = await asyncio.gather(
        asyncio.to_thread(solve_qaoa, problem, layers=settings.qaoa_layers, timeout_s=settings.qaoa_timeout_s),
        asyncio.to_thread(brute_force, problem),
    )
    timings["qaoa_ms"] = round(qaoa_result.wall_time_s * 1000, 1)
    timings["classical_ms"] = round(classical_result["wall_time_s"] * 1000, 1)

    use_qaoa = (not qaoa_result.timed_out) and qaoa_result.best_bits is not None
    solver = "qaoa" if use_qaoa else "classical_fallback"
    winning_bits = qaoa_result.best_bits if use_qaoa else classical_result["best_bits"]
    if winning_bits is None:
        raise ValueError("No feasible crop assignment satisfies the given water/budget constraints")

    assignment = decode_decision_bits(problem, winning_bits)

    def to_plan_assignments(assign: dict[str, str]) -> list[dict[str, Any]]:
        return [
            {
                "plot_id": plot["plot_id"],
                "crop": assign[plot["plot_id"]],
                "yield_t_ha": yield_by_crop[assign[plot["plot_id"]]]["yield_t_ha"],
                "p10": yield_by_crop[assign[plot["plot_id"]]]["p10"],
                "p90": yield_by_crop[assign[plot["plot_id"]]]["p90"],
            }
            for plot in plots_in
        ]

    net_p10 = sum(
        _net_value_rs(
            yield_by_crop[assignment[p["plot_id"]]]["p10"], p["area_ha"],
            price_for(assignment[p["plot_id"]]), crops_cfg[assignment[p["plot_id"]]]["cost_rs_per_ha"],
        )
        for p in plots_in
    )
    net_p90 = sum(
        _net_value_rs(
            yield_by_crop[assignment[p["plot_id"]]]["p90"], p["area_ha"],
            price_for(assignment[p["plot_id"]]), crops_cfg[assignment[p["plot_id"]]]["cost_rs_per_ha"],
        )
        for p in plots_in
    )
    water_used = sum(problem.water_raw[(p["plot_id"], assignment[p["plot_id"]])] for p in plots_in)
    budget_used = sum(problem.cost_raw[(p["plot_id"], assignment[p["plot_id"]])] for p in plots_in)

    classical_assignment = classical_result["assignment"] or assignment

    approximation_ratio = (
        qaoa_result.best_value / classical_result["best_value"]
        if classical_result["best_value"] > 0 and not qaoa_result.timed_out
        else None
    )
    matched_optimum = approximation_ratio is not None and abs(qaoa_result.best_value - classical_result["best_value"]) <= 1e-6

    p_optimum = uplift = None
    if qaoa_result.samples and classical_result["assignment"] is not None:
        hits = sum(
            1 for bits in qaoa_result.samples if decode_decision_bits(problem, bits) == classical_result["assignment"]
        )
        p_optimum = hits / len(qaoa_result.samples)
        uniform_p = classical_result["num_optima"] / (2**problem.n_dec)
        uplift = (p_optimum / uniform_p) if uniform_p > 0 else None

    t0 = time.monotonic()
    advisory = build_advisory(
        assignment=assignment,
        soil=fused_signals.get("soil", {}),
        weather=fused_signals.get("weather", {}),
        area_by_plot={p["plot_id"]: p["area_ha"] for p in plots_in},
    )
    timings["advisory_ms"] = round((time.monotonic() - t0) * 1000, 1)

    return {
        "request_id": str(uuid.uuid4()),
        "plan": {
            "solver": solver,
            "assignments": to_plan_assignments(assignment),
            "net_value_rs": round(feasible_value(problem, winning_bits), 2),
            "net_value_p10_rs": round(net_p10, 2),
            "net_value_p90_rs": round(net_p90, 2),
            "water_used_m3": round(water_used, 1),
            "budget_used_rs": round(budget_used, 2),
        },
        "alternatives": {
            "classical": {
                "assignments": to_plan_assignments(classical_assignment),
                "net_value_rs": round(classical_result["best_value"], 2),
            }
        },
        "benchmark": {
            "n_qubits": problem.n_qubits,
            "encoding": problem.encoding,
            "qaoa_layers": settings.qaoa_layers,
            "qubo_terms": len(problem.Q),
            "qaoa_energy": qaoa_result.energy,
            "classical_optimum": classical_result["best_value"],
            "approximation_ratio": approximation_ratio,
            "matched_optimum": matched_optimum,
            "p_optimum": p_optimum,
            "uplift_vs_uniform": uplift,
            "feasible_rate": qaoa_result.feasible_rate,
            "t_qaoa_s": round(qaoa_result.wall_time_s, 3),
            "t_classical_s": round(classical_result["wall_time_s"], 3),
        },
        "advisory": advisory,
        "data_mode": fused_signals.get("data_mode", "degraded"),
        "timings": timings,
    }


def persist_plan(db: Session, *, field_id: str, result: dict[str, Any], constraints: dict[str, float]) -> None:
    """Writes PLAN + OPTIMIZATION_RUN + ASSIGNMENT + ADVISORY (TRD §9) so the
    quantum panel and last plan survive a restart — required for the demo
    (a pre-seeded field must still show its plan after a service bounce)."""
    bench = result["benchmark"]
    run = models.OptimizationRun(
        n_qubits=bench["n_qubits"],
        encoding=bench["encoding"],
        layers=bench["qaoa_layers"],
        qubo_meta={"qubo_terms": bench["qubo_terms"]},
        qaoa_energy=bench["qaoa_energy"],
        classical_optimum=bench["classical_optimum"],
        approx_ratio=bench["approximation_ratio"],
        matched_optimum=bench["matched_optimum"],
        t_qaoa_s=bench["t_qaoa_s"],
        t_classical_s=bench["t_classical_s"],
        solver_used=result["plan"]["solver"],
    )
    db.add(run)
    db.flush()

    plan_row = models.Plan(
        field_id=field_id,
        run_id=run.id,
        net_value_rs=result["plan"]["net_value_rs"],
        net_value_p10=result["plan"]["net_value_p10_rs"],
        net_value_p90=result["plan"]["net_value_p90_rs"],
        constraints=constraints,
    )
    db.add(plan_row)
    db.flush()

    for a in result["plan"]["assignments"]:
        db.add(
            models.Assignment(
                plan_id=plan_row.id,
                plot_id=a["plot_id"],
                crop_code=a["crop"],
                yield_t_ha=a["yield_t_ha"],
                p10=a["p10"],
                p90=a["p90"],
            )
        )

    adv = result["advisory"]
    db.add(
        models.Advisory(
            plan_id=plan_row.id,
            fertilizer=adv["fertilizer"],
            ph=adv["ph"],
            irrigation=adv["irrigation"],
            why=adv["why"],
        )
    )
    db.commit()
