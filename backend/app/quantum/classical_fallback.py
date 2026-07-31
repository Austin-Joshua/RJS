"""Classical comparison and fallback solvers (FR-44/46, TRD §6.5). Always run
alongside QAOA so the response can show both, honestly, side by side."""
import itertools
import math
import random
import time

from app.quantum.qubo import QUBOProblem, energy_qubo, feasible_value, is_feasible, objective_value


def brute_force(problem: QUBOProblem) -> dict:
    """Exhaustive search over crop-per-plot assignments — exact for n_dec <= 20
    (TRD §6.5). This is the ground truth `classical_optimum` in the benchmark.

    Ranks by `objective_value` (mean minus kappa-weighted variance) so that it
    optimises exactly what SPARQ optimises — otherwise the head-to-head would
    be comparing two solvers against two different targets. With no risk model
    attached, `objective_value` collapses to `feasible_value` and this is the
    same exhaustive search it always was.
    """
    start = time.monotonic()
    plot_ids = list(dict.fromkeys(p for p, _ in problem.variables))
    crops_by_plot = {p: [c for pp, c in problem.variables if pp == p] for p in plot_ids}
    var_index = {v: i for i, v in enumerate(problem.variables)}

    # -inf, not -1: a risk-adjusted objective is routinely negative, and so is
    # net value for a crop whose input cost exceeds its revenue. Seeding at -1
    # would silently report "no feasible plan" for those instances.
    best_objective = float("-inf")
    best_bits: list[int] | None = None
    best_value = 0.0
    tied_assignments: list[tuple] = []

    for combo in itertools.product(*(crops_by_plot[p] for p in plot_ids)):
        bits = [0] * problem.n_qubits
        for p, c in zip(plot_ids, combo):
            bits[var_index[(p, c)]] = 1
        if not is_feasible(problem, bits):
            continue
        score = objective_value(problem, bits)
        if score > best_objective + 1e-9:
            best_objective, best_bits, tied_assignments = score, bits, [combo]
            best_value = feasible_value(problem, bits)
        elif abs(score - best_objective) <= 1e-9:
            tied_assignments.append(combo)

    elapsed = time.monotonic() - start
    return {
        "best_bits": best_bits,
        "best_value": best_value if best_bits else 0.0,
        "best_objective": best_objective if best_bits else 0.0,
        "num_optima": len(tied_assignments),
        "assignment": dict(zip(plot_ids, tied_assignments[0])) if tied_assignments else None,
        "wall_time_s": elapsed,
    }


def simulated_annealing(problem: QUBOProblem, iters: int = 2000, seed: int = 42) -> dict:
    """For n_dec beyond brute-force range (TRD Tier D, 25 qubits / 33M
    combinations) — not exercised by the default demo endpoint, kept so the
    scaling story has a working classical comparison at larger n."""
    rng = random.Random(seed)
    start = time.monotonic()
    n = problem.n_qubits
    current = [rng.randint(0, 1) for _ in range(n)]
    current_energy = energy_qubo(problem, current)
    best, best_energy = current[:], current_energy

    for step in range(iters):
        temp = max(0.01, 1.0 - step / iters)
        candidate = current[:]
        candidate[rng.randrange(n)] ^= 1
        cand_energy = energy_qubo(problem, candidate)
        delta = cand_energy - current_energy
        if delta < 0 or rng.random() < math.exp(-delta / temp):
            current, current_energy = candidate, cand_energy
            if current_energy < best_energy:
                best, best_energy = current[:], current_energy

    elapsed = time.monotonic() - start
    value = feasible_value(problem, best)
    return {"best_bits": best, "best_value": value, "wall_time_s": elapsed}
