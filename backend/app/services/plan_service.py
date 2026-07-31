"""Orchestrates the `/plan` money path (TRD §2 sequence diagram): net-value
matrix -> QUBO -> SPARQ + legacy QAOA + classical (parallel) -> advisory.
Persists the result so a pre-seeded demo field survives a restart (TRD §9).

Three solvers run on every request, not two. FR-44 requires the classical
comparison; we also run the legacy transverse-field QAOA, because the case for
SPARQ is a measured head-to-head, not an assertion. All three are ranked by the
same `objective_value`, so the comparison is honest.
"""
import asyncio
import time
import uuid
from typing import Any

from sqlalchemy.orm import Session

from app.adapters.prices_agmarknet import get_price_rs_per_quintal
from app.core.config import get_settings
from app.db import models
from app.quantum.classical_fallback import brute_force
from app.quantum.qubo import (
    build_qubo,
    build_simplex_qubo,
    certainty_equivalent,
    decode_decision_bits,
    feasible_value,
)
from app.quantum.quantum_optimizer import solve_qaoa
from app.quantum.risk import build_risk_model, evaluate_plan_risk, profit_histogram
from app.quantum.sparq import solve_sparq
from app.services.advisory import build_advisory
from app.services.crop_reference import load_crops
from app.services.yield_service import predict_yields

SPARQ_CLAIM = (
    "SPARQ confines the search to the one-crop-per-plot subspace via an XY-ring "
    "mixer, so every sample is structurally valid rather than penalised after "
    "the fact. Distribution uplift is reported against uniform sampling over "
    "that same feasible subspace — the harder baseline — alongside the 2^n "
    "figure. Simulator only. No runtime advantage over classical brute force is "
    "claimed or observed at this scale."
)


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
    risk_aversion: float | None = None,
) -> dict[str, Any]:
    settings = get_settings()
    price_overrides = price_overrides or {}
    crops_cfg = load_crops()
    timings: dict[str, float] = {}
    kappa = settings.risk_kappa if risk_aversion is None else max(0.0, risk_aversion)

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

    price_by_crop = {c: price_for(c) for c in candidate_crops}
    cost_by_crop = {c: crops_cfg[c]["cost_rs_per_ha"] for c in candidate_crops}

    water_map, cost_map = {}, {}
    for plot in plots_in:
        for crop in candidate_crops:
            key = (plot["plot_id"], crop)
            water_map[key] = crops_cfg[crop]["water_m3_per_ha"] * plot["area_ha"]
            cost_map[key] = cost_by_crop[crop] * plot["area_ha"]

    # The P10/P90 band the quantile boosters already produce becomes the
    # optimiser's covariance model instead of a post-hoc annotation (see
    # quantum/risk.py). `risk.mu` is the same expected net value the old
    # `value_map` held — identical formula, now carrying second moments too.
    t0 = time.monotonic()
    risk = build_risk_model(
        plots=plots_in,
        candidate_crops=candidate_crops,
        predictions=yield_by_crop,
        price_by_crop=price_by_crop,
        cost_by_crop=cost_by_crop,
        rho_cross_crop=settings.risk_cross_crop_rho,
        n_scenarios=settings.risk_scenarios,
    )
    value_map = risk.mu
    timings["risk_ms"] = round((time.monotonic() - t0) * 1000, 1)

    problem = build_simplex_qubo(
        plots=plots_in,
        candidate_crops=candidate_crops,
        value_map=value_map,
        water_map=water_map,
        cost_map=cost_map,
        water_limit=water_m3,
        budget_limit=budget_rs,
        cov_map=risk.cov,
        risk_kappa=kappa,
    )

    # Legacy transverse-field QAOA on the old slack encoding — kept as the
    # measured baseline SPARQ is claimed to beat, not as a fallback.
    legacy_problem = build_qubo(
        plots=plots_in,
        candidate_crops=candidate_crops,
        value_map=value_map,
        water_map=water_map,
        cost_map=cost_map,
        water_limit=water_m3,
        budget_limit=budget_rs,
        encoding=settings.encoding,
    )

    async def run_legacy():
        if not settings.run_baseline_qaoa:
            return None
        return await asyncio.to_thread(
            solve_qaoa, legacy_problem, layers=settings.qaoa_layers, timeout_s=settings.qaoa_timeout_s
        )

    sparq_result, legacy_result, classical_result = await asyncio.gather(
        asyncio.to_thread(
            solve_sparq,
            problem,
            layers=settings.sparq_layers,
            timeout_s=settings.qaoa_timeout_s,
            shots=settings.sparq_shots,
            warm_start_tau=settings.sparq_warm_start_tau,
            maxiter_per_layer=settings.sparq_maxiter_per_layer,
        ),
        run_legacy(),
        asyncio.to_thread(brute_force, problem),
    )
    timings["sparq_ms"] = round(sparq_result.wall_time_s * 1000, 1)
    if legacy_result is not None:
        timings["qaoa_ms"] = round(legacy_result.wall_time_s * 1000, 1)
    timings["classical_ms"] = round(classical_result["wall_time_s"] * 1000, 1)

    use_sparq = sparq_result.best_bits is not None
    solver = "sparq" if use_sparq else "classical_fallback"
    winning_bits = sparq_result.best_bits if use_sparq else classical_result["best_bits"]
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
    optimum_objective = classical_result["best_objective"]

    def concentration(samples: list[list[int]] | None, prob) -> tuple[float | None, float | None, float | None]:
        """P(optimum) in a sampled distribution, against two baselines.

        `uplift_vs_uniform` divides by 1/2^n — the figure the original
        benchmark reported. `uplift_vs_feasible_uniform` divides by 1/C^P,
        i.e. uniform over only the structurally-valid assignments. The second
        is much harder and is the one to lead with: an ansatz that cannot emit
        an invalid bitstring should not be credited for avoiding them.
        """
        if not samples or classical_result["assignment"] is None:
            return None, None, None
        hits = sum(1 for bits in samples if decode_decision_bits(prob, bits) == classical_result["assignment"])
        p_opt = hits / len(samples)
        uniform_p = classical_result["num_optima"] / (2**prob.n_dec)
        n_feasible_space = len(candidate_crops) ** len(plots_in)
        feasible_uniform_p = classical_result["num_optima"] / n_feasible_space
        return (
            p_opt,
            (p_opt / uniform_p) if uniform_p > 0 else None,
            (p_opt / feasible_uniform_p) if feasible_uniform_p > 0 else None,
        )

    p_optimum, uplift, uplift_feasible = concentration(sparq_result.samples, problem)
    legacy_p, legacy_uplift, legacy_uplift_feasible = (
        concentration(legacy_result.samples, legacy_problem) if legacy_result else (None, None, None)
    )

    approximation_ratio = (
        sparq_result.best_objective / optimum_objective
        if optimum_objective not in (0.0, float("-inf")) and use_sparq
        else None
    )
    matched_optimum = use_sparq and abs(sparq_result.best_objective - optimum_objective) <= 1e-6

    # What the farmer would have been told with risk ignored (kappa = 0). The
    # gap between this and the plan above *is* the risk-awareness feature, so
    # it is shown rather than described.
    risk_neutral_problem = build_simplex_qubo(
        plots=plots_in,
        candidate_crops=candidate_crops,
        value_map=value_map,
        water_map=water_map,
        cost_map=cost_map,
        water_limit=water_m3,
        budget_limit=budget_rs,
        cov_map=risk.cov,
        risk_kappa=0.0,
    )
    risk_neutral = brute_force(risk_neutral_problem)
    risk_neutral_assignment = risk_neutral["assignment"] or assignment

    plan_risk = evaluate_plan_risk(
        assignment=assignment,
        plots=plots_in,
        risk=risk,
        price_by_crop=price_by_crop,
        cost_by_crop=cost_by_crop,
        cvar_beta=settings.risk_cvar_beta,
    )
    risk_neutral_risk = evaluate_plan_risk(
        assignment=risk_neutral_assignment,
        plots=plots_in,
        risk=risk,
        price_by_crop=price_by_crop,
        cost_by_crop=cost_by_crop,
        cvar_beta=settings.risk_cvar_beta,
    )

    distinct_crops = len(set(assignment.values()))
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
            # `certainty_equivalent_rs` is the figure to put on screen: expected
            # rupees minus kappa standard deviations, i.e. what this plan is
            # worth to a farmer with this risk appetite. `risk_adjusted_value_rs`
            # is the raw mean-variance score the solver ranked by — kept for the
            # quantum panel, but it is an internal score, not money.
            "certainty_equivalent_rs": round(certainty_equivalent(problem, assignment), 2),
            "risk_adjusted_value_rs": round(sparq_result.best_objective if use_sparq else optimum_objective, 2),
            "risk": plan_risk,
            "diversification": {
                "distinct_crops": distinct_crops,
                "n_plots": len(plots_in),
                "crop_mix": {c: sum(1 for v in assignment.values() if v == c) for c in set(assignment.values())},
            },
        },
        "alternatives": {
            "classical": {
                "assignments": to_plan_assignments(classical_assignment),
                "net_value_rs": round(classical_result["best_value"], 2),
            },
            "legacy_qaoa": {
                "assignments": to_plan_assignments(
                    decode_decision_bits(legacy_problem, legacy_result.best_bits)
                    if legacy_result is not None and legacy_result.best_bits is not None
                    else assignment
                ),
                "net_value_rs": round(legacy_result.best_value, 2) if legacy_result else 0.0,
            },
            "risk_neutral": {
                "assignments": to_plan_assignments(risk_neutral_assignment),
                "net_value_rs": round(risk_neutral["best_value"], 2),
            },
        },
        "benchmark": {
            "solver": solver,
            "n_qubits": problem.n_qubits,
            "encoding": problem.encoding,
            "qaoa_layers": sparq_result.layers or settings.sparq_layers,
            "qubo_terms": len(problem.Q),
            "qaoa_energy": sparq_result.energy,
            "classical_optimum": classical_result["best_value"],
            "classical_optimum_objective": optimum_objective,
            "approximation_ratio": approximation_ratio,
            "matched_optimum": matched_optimum,
            "p_optimum": p_optimum,
            "uplift_vs_uniform": uplift,
            "uplift_vs_feasible_uniform": uplift_feasible,
            "feasible_rate": sparq_result.feasible_rate,
            "simplex_rate": sparq_result.simplex_rate,
            "t_qaoa_s": round(sparq_result.wall_time_s, 3),
            "t_classical_s": round(classical_result["wall_time_s"], 3),
            "timed_out": sparq_result.timed_out,
            "convergence": sparq_result.convergence,
            "warm_start": sparq_result.warm_start,
            "risk_kappa": kappa,
            "risk_scenarios": settings.risk_scenarios,
            "risk_cross_crop_rho": settings.risk_cross_crop_rho,
            "plan_std_rs": plan_risk["std_rs"],
            "risk_neutral_std_rs": risk_neutral_risk["std_rs"],
            "risk_neutral_cvar_rs": risk_neutral_risk["cvar_rs"],
            "profit_histogram": profit_histogram(
                assignment=assignment,
                plots=plots_in,
                risk=risk,
                price_by_crop=price_by_crop,
                cost_by_crop=cost_by_crop,
            ),
            # Same instance, previous-generation ansatz — the measured contrast.
            # None when `run_baseline_qaoa` is off; the UI then just omits the
            # comparison column rather than showing a fabricated one.
            "baseline_qaoa": None
            if legacy_result is None
            else {
                "n_qubits": legacy_problem.n_qubits,
                "encoding": legacy_problem.encoding,
                "slack_qubits": sum(legacy_problem.slack_bits.values()),
                "qubo_terms": len(legacy_problem.Q),
                "feasible_rate": legacy_result.feasible_rate,
                "p_optimum": legacy_p,
                "uplift_vs_uniform": legacy_uplift,
                "uplift_vs_feasible_uniform": legacy_uplift_feasible,
                "net_value_rs": round(legacy_result.best_value, 2),
                "t_s": round(legacy_result.wall_time_s, 3),
                "timed_out": legacy_result.timed_out,
            },
            "claim": SPARQ_CLAIM,
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
        # `qubo_meta` is a JSON column, so the SPARQ-specific metrics land here
        # without a migration. TRD §15 wants the quantum panel rebuildable from
        # the database if a live run misbehaves on stage — that needs the
        # convergence trace and the head-to-head baseline, not just term counts.
        qubo_meta={
            "qubo_terms": bench["qubo_terms"],
            "simplex_rate": bench.get("simplex_rate"),
            "feasible_rate": bench.get("feasible_rate"),
            "p_optimum": bench.get("p_optimum"),
            "uplift_vs_uniform": bench.get("uplift_vs_uniform"),
            "uplift_vs_feasible_uniform": bench.get("uplift_vs_feasible_uniform"),
            "risk_kappa": bench.get("risk_kappa"),
            "risk_scenarios": bench.get("risk_scenarios"),
            "plan_std_rs": bench.get("plan_std_rs"),
            "risk_neutral_std_rs": bench.get("risk_neutral_std_rs"),
            "warm_start": bench.get("warm_start"),
            "convergence": bench.get("convergence"),
            "baseline_qaoa": bench.get("baseline_qaoa"),
            "timed_out": bench.get("timed_out", False),
        },
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
