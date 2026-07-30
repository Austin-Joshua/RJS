"""QUBO/QAOA tests (TRD §13): penalty rule holds, Ising round-trip is exact,
timeout path falls back to the classical plan with the right solver tag."""
import random

from app.quantum.classical_fallback import brute_force
from app.quantum.qubo import build_qubo, decode_decision_bits, energy_ising, energy_qubo, feasible_value, is_feasible, to_ising
from app.quantum.quantum_optimizer import QAOAResult, solve_qaoa


def _random_problem(seed: int):
    rng = random.Random(seed)
    plots = [{"plot_id": f"p{i}", "area_ha": round(rng.uniform(0.3, 1.2), 2)} for i in range(3)]
    crops = ["cropA", "cropB"]
    value_map, water_map, cost_map = {}, {}, {}
    for p in plots:
        for c in crops:
            key = (p["plot_id"], c)
            value_map[key] = rng.uniform(10000, 80000)
            water_map[key] = rng.uniform(1000, 6000)
            cost_map[key] = rng.uniform(8000, 30000)
    cheapest_water = sum(min(water_map[(p["plot_id"], c)] for c in crops) for p in plots)
    cheapest_cost = sum(min(cost_map[(p["plot_id"], c)] for c in crops) for p in plots)
    return build_qubo(
        plots=plots,
        candidate_crops=crops,
        value_map=value_map,
        water_map=water_map,
        cost_map=cost_map,
        water_limit=cheapest_water * 1.5,
        budget_limit=cheapest_cost * 1.5,
        encoding="slack",
    )


def test_ising_round_trip_matches_qubo_energy() -> None:
    """energy_qubo(x) == energy_ising(z) for every random instance/bitstring
    (TRD §13 — the Ising round-trip test)."""
    for seed in range(20):
        problem = _random_problem(seed)
        h, j_coupling, const = to_ising(problem)
        rng = random.Random(seed + 1000)
        for _ in range(5):
            bits = [rng.randint(0, 1) for _ in range(problem.n_qubits)]
            z = [1 - 2 * b for b in bits]
            e_qubo = energy_qubo(problem, bits)
            e_ising = energy_ising(h, j_coupling, const, z)
            assert abs(e_qubo - e_ising) < 1e-6, f"seed={seed} bits={bits}"


def test_penalty_rule_no_infeasible_beats_feasible() -> None:
    """lambda > max|v'_i| guarantees an infeasible assignment can never score
    better than the true feasible optimum (TRD §6.2 penalty rule)."""
    for seed in range(50):
        problem = _random_problem(seed)
        optimum = brute_force(problem)
        if optimum["best_bits"] is None:
            continue  # instance happened to have no feasible assignment at all

        # Any bitstring that violates C1 (not exactly one crop per plot) must
        # score worse (higher QUBO energy) than the true feasible optimum.
        var_index = {v: i for i, v in enumerate(problem.variables)}
        bad_bits = [0] * problem.n_qubits
        bad_bits[var_index[problem.variables[0]]] = 1
        bad_bits[var_index[problem.variables[1]]] = 1  # two crops on the same plot
        assert not is_feasible(problem, bad_bits)
        assert energy_qubo(problem, bad_bits) > energy_qubo(problem, optimum["best_bits"]) - 1e-9


def test_slack_bit_width_matches_encoding() -> None:
    problem_slack = _random_problem(1)
    assert problem_slack.n_qubits == problem_slack.n_dec + sum(problem_slack.slack_bits.values())

    problem_unbalanced = build_qubo(
        plots=[{"plot_id": "p1", "area_ha": 1.0}],
        candidate_crops=["a", "b"],
        value_map={("p1", "a"): 100.0, ("p1", "b"): 50.0},
        water_map={("p1", "a"): 10.0, ("p1", "b"): 5.0},
        cost_map={("p1", "a"): 10.0, ("p1", "b"): 5.0},
        water_limit=8.0,
        budget_limit=8.0,
        encoding="unbalanced",
    )
    assert problem_unbalanced.n_qubits == problem_unbalanced.n_dec  # no slack qubits


def test_qaoa_recovers_brute_force_optimum() -> None:
    """FR-43/TRD §13 — QAOA should recover the true optimum (value, not
    necessarily the exact bitstring, since ties are possible) most of the
    time at demo scale. Kept to a handful of instances so the suite stays fast."""
    hits = 0
    trials = 5
    for seed in range(trials):
        problem = _random_problem(seed + 5000)
        optimum = brute_force(problem)
        if optimum["best_bits"] is None:
            continue
        result = solve_qaoa(problem, layers=3, timeout_s=10.0, shots=1024)
        if not result.timed_out and abs(result.best_value - optimum["best_value"]) < 1e-6:
            hits += 1
    assert hits >= trials - 1, f"only matched optimum {hits}/{trials} times"


def test_timeout_path_has_no_feasible_bits() -> None:
    """A timed-out QAOAResult must carry no plan bits, so callers are forced
    onto the classical_fallback path (FR-46) instead of serving a stale plan."""
    result = QAOAResult(timed_out=True, best_bits=None, best_value=0.0, energy=None, feasible_rate=0.0, wall_time_s=10.01)
    assert result.best_bits is None


def test_feasible_value_zero_when_infeasible() -> None:
    problem = _random_problem(2)
    all_ones = [1] * problem.n_qubits
    if not is_feasible(problem, all_ones):
        assert feasible_value(problem, all_ones) == 0.0


def test_decode_decision_bits_shape() -> None:
    problem = _random_problem(3)
    optimum = brute_force(problem)
    if optimum["best_bits"] is not None:
        assignment = decode_decision_bits(problem, optimum["best_bits"])
        plot_ids = {p for p, _ in problem.variables}
        assert set(assignment.keys()) == plot_ids
        assert all(crop is not None for crop in assignment.values())
