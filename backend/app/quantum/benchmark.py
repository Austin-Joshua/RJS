"""QAOA vs. brute-force benchmark protocol (TRD §6.6). Used both by
`scripts/benchmark_qaoa.py` (offline 50-instance sweep -> benchmark.json) and
by `plan_service.py` (single live instance per `/plan` call)."""
import random

from app.quantum.classical_fallback import brute_force
from app.quantum.qubo import QUBOProblem, decode_decision_bits
from app.quantum.quantum_optimizer import QAOAResult, solve_qaoa

CLAIM = (
    "Simulated QAOA recovers the exact optimum at demo scale. No runtime "
    "advantage over classical is claimed or observed at n <= 25 qubits."
)


def random_instance(*, n_plots: int = 3, n_crops: int = 2, seed: int | None = None) -> dict:
    """Generates a random allocation instance for the benchmark sweep — not
    tied to real crop/field data, purely for stressing the QUBO/QAOA path
    across many random coefficient draws (TRD §6.6)."""
    rng = random.Random(seed)
    plots = [{"plot_id": f"p{i}", "area_ha": round(rng.uniform(0.3, 1.2), 2)} for i in range(n_plots)]
    crops = [f"crop{i}" for i in range(n_crops)]
    value_map, water_map, cost_map = {}, {}, {}
    for p in plots:
        for c in crops:
            key = (p["plot_id"], c)
            value_map[key] = round(rng.uniform(5000, 60000) * p["area_ha"], 2)
            water_map[key] = round(rng.uniform(1000, 6000) * p["area_ha"], 2)
            cost_map[key] = round(rng.uniform(8000, 30000) * p["area_ha"], 2)

    # Calibrate limits against the cheapest per-plot choice so at least one
    # assignment is always feasible — an all-infeasible random instance would
    # report a meaningless "optimum" of 0 and isn't a useful benchmark point.
    cheapest_water = sum(min(water_map[(p["plot_id"], c)] for c in crops) for p in plots)
    cheapest_cost = sum(min(cost_map[(p["plot_id"], c)] for c in crops) for p in plots)
    return {
        "plots": plots,
        "candidate_crops": crops,
        "value_map": value_map,
        "water_map": water_map,
        "cost_map": cost_map,
        "water_limit": round(cheapest_water * rng.uniform(1.2, 2.0), 2),
        "budget_limit": round(cheapest_cost * rng.uniform(1.2, 2.0), 2),
    }


def score_instance(problem: QUBOProblem, qaoa: QAOAResult, optimum: dict) -> dict:
    optimum_value = optimum["best_value"]
    optimum_assignment = optimum["assignment"]

    matched_optimum = (not qaoa.timed_out) and optimum_value > 0 and abs(qaoa.best_value - optimum_value) <= 1e-6
    approximation_ratio = (qaoa.best_value / optimum_value) if optimum_value > 0 and not qaoa.timed_out else None

    p_optimum = None
    uplift_vs_uniform = None
    if qaoa.samples and optimum_assignment is not None:
        hits = sum(
            1 for bits in qaoa.samples if decode_decision_bits(problem, bits) == optimum_assignment
        )
        p_optimum = hits / len(qaoa.samples)
        uniform_p = optimum["num_optima"] / (2**problem.n_dec)
        uplift_vs_uniform = (p_optimum / uniform_p) if uniform_p > 0 else None

    return {
        "n_qubits": problem.n_qubits,
        "encoding": problem.encoding,
        "qubo_terms": len(problem.Q),
        "qaoa_energy": qaoa.energy,
        "classical_optimum_value": optimum_value,
        "qaoa_best_value": qaoa.best_value,
        "matched_optimum": matched_optimum,
        "approximation_ratio": approximation_ratio,
        "p_optimum": p_optimum,
        "uplift_vs_uniform": uplift_vs_uniform,
        "feasible_rate": qaoa.feasible_rate,
        "t_qaoa_s": qaoa.wall_time_s,
        "t_classical_s": optimum["wall_time_s"],
        "solver_used": "classical_fallback" if qaoa.timed_out else "qaoa",
    }


def run_suite(n_instances: int = 50, *, layers: int = 3, timeout_s: float = 10.0, seed: int = 42) -> dict:
    from app.quantum.qubo import build_qubo

    rng = random.Random(seed)
    rows = []
    for i in range(n_instances):
        inst = random_instance(seed=rng.randint(0, 10_000_000))
        problem = build_qubo(
            plots=inst["plots"],
            candidate_crops=inst["candidate_crops"],
            value_map=inst["value_map"],
            water_map=inst["water_map"],
            cost_map=inst["cost_map"],
            water_limit=inst["water_limit"],
            budget_limit=inst["budget_limit"],
            encoding="slack",
        )
        optimum = brute_force(problem)
        qaoa = solve_qaoa(problem, layers=layers, timeout_s=timeout_s)
        rows.append(score_instance(problem, qaoa, optimum))

    matched = [r for r in rows if r["matched_optimum"]]
    ratios = [r["approximation_ratio"] for r in rows if r["approximation_ratio"] is not None]
    uplifts = [r["uplift_vs_uniform"] for r in rows if r["uplift_vs_uniform"] is not None]
    feasible_rates = [r["feasible_rate"] for r in rows]

    return {
        "n_instances": n_instances,
        "qaoa_layers": layers,
        "optimum_match_rate": len(matched) / n_instances,
        "mean_approximation_ratio": sum(ratios) / len(ratios) if ratios else None,
        "mean_uplift_vs_uniform": sum(uplifts) / len(uplifts) if uplifts else None,
        "mean_feasible_rate": sum(feasible_rates) / len(feasible_rates),
        "instances": rows,
        "claim": CLAIM,
    }
