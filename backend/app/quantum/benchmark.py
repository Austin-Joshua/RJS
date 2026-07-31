"""SPARQ vs. legacy QAOA vs. brute-force benchmark protocol (TRD §6.6).

Used by `scripts/benchmark_qaoa.py` (offline sweep -> benchmark.json). The
sweep runs both ansaetze on the *same* instances and ranks both with the same
`objective_value`, so the head-to-head is a measurement rather than a claim.

Two uplift baselines are recorded per instance. `uplift_vs_uniform` divides
P(optimum) by 1/2^n, which is what the original benchmark reported.
`uplift_vs_feasible_uniform` divides by 1/C^P — uniform over only the
structurally-valid assignments. The second is much harder, and it is the one
to quote: an ansatz that *cannot* emit an invalid bitstring should not collect
credit for declining to.
"""
import random

from app.quantum.classical_fallback import brute_force
from app.quantum.qubo import QUBOProblem, build_simplex_qubo, decode_decision_bits
from app.quantum.quantum_optimizer import QAOAResult, solve_qaoa
from app.quantum.risk import build_risk_model
from app.quantum.sparq import SparqResult, solve_sparq

CLAIM = (
    "SPARQ confines the search to the one-crop-per-plot subspace via an XY-ring "
    "mixer, so every sample is structurally valid rather than penalised after "
    "the fact. Distribution uplift is reported against uniform sampling over "
    "that same feasible subspace — the harder baseline — alongside the 2^n "
    "figure. Simulator only. No runtime advantage over classical brute force is "
    "claimed or observed at this scale."
)


def random_instance(*, n_plots: int = 3, n_crops: int = 2, seed: int | None = None) -> dict:
    """Generates a random allocation instance for the benchmark sweep.

    Draws a yield *band* (P10/P90) per crop rather than a bare net value, so
    the instance carries the second moments the risk model needs. Not tied to
    real field data — the point is to stress the QUBO/ansatz path across many
    coefficient draws (TRD §6.6).
    """
    rng = random.Random(seed)
    plots = [{"plot_id": f"p{i}", "area_ha": round(rng.uniform(0.3, 1.2), 2)} for i in range(n_plots)]
    crops = [f"crop{i}" for i in range(n_crops)]

    predictions, price_by_crop, cost_by_crop, water_per_ha = {}, {}, {}, {}
    for c in crops:
        y = rng.uniform(2.0, 6.0)
        band = y * rng.uniform(0.15, 0.5)
        predictions[c] = {"yield_t_ha": y, "p10": max(0.0, y - band), "p90": y + band}
        price_by_crop[c] = rng.uniform(1500, 3000)
        cost_by_crop[c] = rng.uniform(15000, 40000)
        water_per_ha[c] = rng.uniform(1000, 6000)

    water_map, cost_map = {}, {}
    for p in plots:
        for c in crops:
            water_map[(p["plot_id"], c)] = round(water_per_ha[c] * p["area_ha"], 2)
            cost_map[(p["plot_id"], c)] = round(cost_by_crop[c] * p["area_ha"], 2)

    risk = build_risk_model(
        plots=plots, candidate_crops=crops, predictions=predictions,
        price_by_crop=price_by_crop, cost_by_crop=cost_by_crop,
        n_scenarios=64, seed=rng.randint(0, 10_000_000),
    )

    # Calibrate limits against the cheapest per-plot choice so at least one
    # assignment is always feasible — an all-infeasible random instance would
    # report a meaningless "optimum" of 0 and isn't a useful benchmark point.
    cheapest_water = sum(min(water_map[(p["plot_id"], c)] for c in crops) for p in plots)
    cheapest_cost = sum(min(cost_map[(p["plot_id"], c)] for c in crops) for p in plots)
    return {
        "plots": plots,
        "candidate_crops": crops,
        "value_map": risk.mu,
        "cov_map": risk.cov,
        "water_map": water_map,
        "cost_map": cost_map,
        "water_limit": round(cheapest_water * rng.uniform(1.2, 2.0), 2),
        "budget_limit": round(cheapest_cost * rng.uniform(1.2, 2.0), 2),
    }


def _feasible_space_size(problem: QUBOProblem) -> int:
    """C^P — the number of structurally-valid one-crop-per-plot assignments."""
    plot_ids = {p for p, _ in problem.variables}
    crops = {c for _, c in problem.variables}
    return len(crops) ** len(plot_ids) if plot_ids else 1


def _concentration(problem: QUBOProblem, samples: list[list[int]] | None, optimum: dict) -> dict:
    """P(optimum) in a sampled distribution, against both uniform baselines."""
    if not samples or optimum["assignment"] is None:
        return {"p_optimum": None, "uplift_vs_uniform": None, "uplift_vs_feasible_uniform": None}
    hits = sum(1 for bits in samples if decode_decision_bits(problem, bits) == optimum["assignment"])
    p_optimum = hits / len(samples)
    uniform_p = optimum["num_optima"] / (2**problem.n_dec)
    feasible_uniform_p = optimum["num_optima"] / _feasible_space_size(problem)
    return {
        "p_optimum": p_optimum,
        "uplift_vs_uniform": (p_optimum / uniform_p) if uniform_p > 0 else None,
        "uplift_vs_feasible_uniform": (p_optimum / feasible_uniform_p) if feasible_uniform_p > 0 else None,
    }


def score_instance(problem: QUBOProblem, qaoa: QAOAResult, optimum: dict) -> dict:
    """Score the legacy transverse-field QAOA on one instance."""
    optimum_value = optimum["best_value"]
    matched_optimum = (not qaoa.timed_out) and optimum_value > 0 and abs(qaoa.best_value - optimum_value) <= 1e-6
    approximation_ratio = (qaoa.best_value / optimum_value) if optimum_value > 0 and not qaoa.timed_out else None

    return {
        "ansatz": "qaoa_transverse_field",
        "n_qubits": problem.n_qubits,
        "n_dec": problem.n_dec,
        "slack_qubits": sum(problem.slack_bits.values()),
        "encoding": problem.encoding,
        "qubo_terms": len(problem.Q),
        "qaoa_energy": qaoa.energy,
        "classical_optimum_value": optimum_value,
        "qaoa_best_value": qaoa.best_value,
        "matched_optimum": matched_optimum,
        "approximation_ratio": approximation_ratio,
        "feasible_rate": qaoa.feasible_rate,
        "simplex_rate": None,  # no block structure to preserve
        "t_qaoa_s": qaoa.wall_time_s,
        "t_classical_s": optimum["wall_time_s"],
        "solver_used": "classical_fallback" if qaoa.timed_out else "qaoa",
        **_concentration(problem, qaoa.samples, optimum),
    }


def score_sparq(problem: QUBOProblem, result: SparqResult, optimum: dict) -> dict:
    """Score SPARQ on one instance, ranked by the same risk-adjusted objective
    brute force used, so `matched_optimum` means agreement on one target."""
    optimum_objective = optimum["best_objective"]
    matched = (
        result.best_bits is not None
        and optimum_objective != float("-inf")
        and abs(result.best_objective - optimum_objective) <= 1e-6
    )
    ratio = (
        result.best_objective / optimum_objective
        if optimum_objective not in (0.0, float("-inf")) and result.best_bits is not None
        else None
    )
    return {
        "ansatz": "sparq_xy_ring",
        "n_qubits": problem.n_qubits,
        "n_dec": problem.n_dec,
        "slack_qubits": 0,
        "encoding": problem.encoding,
        "qubo_terms": len(problem.Q),
        "qaoa_energy": result.energy,
        "classical_optimum_value": optimum["best_value"],
        "classical_optimum_objective": optimum_objective,
        "qaoa_best_value": result.best_value,
        "sparq_best_objective": result.best_objective,
        "matched_optimum": matched,
        "approximation_ratio": ratio,
        "feasible_rate": result.feasible_rate,
        "simplex_rate": result.simplex_rate,
        "layers_trained": result.layers,
        "t_qaoa_s": result.wall_time_s,
        "t_classical_s": optimum["wall_time_s"],
        "timed_out": result.timed_out,
        "solver_used": "sparq",
        **_concentration(problem, result.samples, optimum),
    }


def _summarise(rows: list[dict]) -> dict:
    def mean(key: str) -> float | None:
        vals = [r[key] for r in rows if r.get(key) is not None]
        return sum(vals) / len(vals) if vals else None

    return {
        "optimum_match_rate": (sum(1 for r in rows if r["matched_optimum"]) / len(rows)) if rows else None,
        "mean_approximation_ratio": mean("approximation_ratio"),
        "mean_uplift_vs_uniform": mean("uplift_vs_uniform"),
        "mean_uplift_vs_feasible_uniform": mean("uplift_vs_feasible_uniform"),
        "mean_feasible_rate": mean("feasible_rate"),
        "mean_simplex_rate": mean("simplex_rate"),
        "mean_t_s": mean("t_qaoa_s"),
        "mean_n_qubits": mean("n_qubits"),
    }


def run_suite(
    n_instances: int = 50,
    *,
    layers: int = 3,
    timeout_s: float = 10.0,
    seed: int = 42,
    n_plots: int = 3,
    n_crops: int = 3,
    risk_kappa: float = 0.35,
) -> dict:
    """Run SPARQ and the legacy QAOA over the same instances, head to head."""
    from app.quantum.qubo import build_qubo

    rng = random.Random(seed)
    sparq_rows, legacy_rows = [], []

    for _ in range(n_instances):
        inst = random_instance(n_plots=n_plots, n_crops=n_crops, seed=rng.randint(0, 10_000_000))
        shared = {
            "plots": inst["plots"],
            "candidate_crops": inst["candidate_crops"],
            "value_map": inst["value_map"],
            "water_map": inst["water_map"],
            "cost_map": inst["cost_map"],
            "water_limit": inst["water_limit"],
            "budget_limit": inst["budget_limit"],
        }

        simplex = build_simplex_qubo(**shared, cov_map=inst["cov_map"], risk_kappa=risk_kappa)
        simplex_optimum = brute_force(simplex)
        sparq_rows.append(
            score_sparq(simplex, solve_sparq(simplex, layers=layers, timeout_s=timeout_s), simplex_optimum)
        )

        legacy = build_qubo(**shared, encoding="slack")
        legacy_optimum = brute_force(legacy)
        legacy_rows.append(
            score_instance(legacy, solve_qaoa(legacy, layers=layers, timeout_s=timeout_s), legacy_optimum)
        )

    sparq_summary = _summarise(sparq_rows)
    legacy_summary = _summarise(legacy_rows)

    return {
        "n_instances": n_instances,
        "qaoa_layers": layers,
        "instance_shape": {"n_plots": n_plots, "n_crops": n_crops},
        "risk_kappa": risk_kappa,
        # Top-level keys mirror the previous schema so existing readers of
        # benchmark.json keep working; they now describe SPARQ, the solver
        # actually serving /plan.
        **sparq_summary,
        "sparq": {**sparq_summary, "instances": sparq_rows},
        "baseline_qaoa": {**legacy_summary, "instances": legacy_rows},
        "instances": sparq_rows,
        "claim": CLAIM,
    }
