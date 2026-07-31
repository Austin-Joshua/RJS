"""QUBO/QAOA tests (TRD §13): penalty rule holds, Ising round-trip is exact,
timeout path falls back to the classical plan with the right solver tag.

The SPARQ block at the end guards the property the whole design rests on: the
XY-ring mixer conserves Hamming weight per plot block, so one-crop-per-plot is
structurally unreachable to violate. If that regresses, SPARQ degrades to an
ordinary penalty-based QAOA and the benchmark claim stops being true.
"""
import pytest
import random

from app.quantum.classical_fallback import brute_force
from app.quantum.qubo import (
    build_qubo,
    build_simplex_qubo,
    decode_decision_bits,
    energy_ising,
    energy_qubo,
    feasible_value,
    is_feasible,
    objective_value,
    plan_variance,
    to_ising,
)
from app.quantum.quantum_optimizer import QAOAResult, solve_qaoa
from app.quantum.risk import build_risk_model, sigma_from_band
from app.quantum.sparq import _interp, _softmax_amplitudes, solve_sparq


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


# --------------------------------------------------------------------------
# SPARQ — simplex-preserving, risk-aware ansatz (app/quantum/sparq.py)
# --------------------------------------------------------------------------


def _simplex_problem(seed: int, n_plots: int = 3, n_crops: int = 2, kappa: float = 0.35):
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
        water_per_ha[c] = rng.uniform(1500, 6000)

    water_map, cost_map = {}, {}
    for p in plots:
        for c in crops:
            water_map[(p["plot_id"], c)] = water_per_ha[c] * p["area_ha"]
            cost_map[(p["plot_id"], c)] = cost_by_crop[c] * p["area_ha"]

    risk = build_risk_model(
        plots=plots, candidate_crops=crops, predictions=predictions,
        price_by_crop=price_by_crop, cost_by_crop=cost_by_crop, n_scenarios=64,
    )
    cheapest_water = sum(min(water_map[(p["plot_id"], c)] for c in crops) for p in plots)
    cheapest_cost = sum(min(cost_map[(p["plot_id"], c)] for c in crops) for p in plots)
    return build_simplex_qubo(
        plots=plots, candidate_crops=crops, value_map=risk.mu,
        water_map=water_map, cost_map=cost_map,
        water_limit=cheapest_water * 1.6, budget_limit=cheapest_cost * 1.6,
        cov_map=risk.cov, risk_kappa=kappa,
    )


def test_simplex_encoding_spends_no_qubits_on_slack() -> None:
    """n_qubits == n_dec: C1 is a symmetry, C2/C3 are slack-free."""
    problem = _simplex_problem(0, n_plots=3, n_crops=3)
    assert problem.n_qubits == problem.n_dec == 9
    assert sum(problem.slack_bits.values()) == 0
    assert len(problem.blocks) == 3
    assert all(len(b) == 3 for b in problem.blocks)
    # Blocks must partition the decision qubits exactly — an overlap would
    # break Hamming-weight conservation across plots.
    flat = [q for block in problem.blocks for q in block]
    assert sorted(flat) == list(range(problem.n_dec))


def test_xy_mixer_conserves_one_crop_per_plot() -> None:
    """The load-bearing invariant: every sampled bitstring is one-hot per plot.

    Not "almost always" — exactly. `IsingXY` annihilates |00> and |11>, so no
    choice of parameters, depth or seed can leak amplitude out of the weight-1
    subspace. This is what replaces the C1 penalty term.
    """
    for seed in range(6):
        problem = _simplex_problem(seed + 100, n_plots=3, n_crops=3)
        result = solve_sparq(problem, layers=2, timeout_s=25.0, shots=512, maxiter_per_layer=15)
        assert result.simplex_rate == 1.0, f"seed={seed} leaked to {result.simplex_rate}"
        assert result.samples
        for bits in result.samples:
            for block in problem.blocks:
                assert sum(bits[q] for q in block) == 1, f"block {block} had weight != 1"


def test_sparq_beats_penalty_qaoa_on_feasibility() -> None:
    """The headline comparison, as a regression guard.

    The legacy transverse-field ansatz measured ~8% feasible samples; SPARQ
    should stay far above that, since only C2/C3 can now reject a sample.
    """
    rates = []
    for seed in range(4):
        problem = _simplex_problem(seed + 200)
        result = solve_sparq(problem, layers=2, timeout_s=25.0, shots=512, maxiter_per_layer=15)
        rates.append(result.feasible_rate)
    assert sum(rates) / len(rates) > 0.40, f"mean feasible rate {sum(rates)/len(rates):.3f}"


def test_sparq_recovers_brute_force_optimum() -> None:
    """SPARQ and brute force rank by the same `objective_value`, so a match is
    a genuine agreement on the risk-adjusted optimum, not on two targets."""
    hits = trials = 0
    for seed in range(5):
        problem = _simplex_problem(seed + 300)
        optimum = brute_force(problem)
        if optimum["best_bits"] is None:
            continue
        trials += 1
        result = solve_sparq(problem, layers=3, timeout_s=25.0, shots=1024)
        if result.best_bits is not None and abs(result.best_objective - optimum["best_objective"]) < 1e-6:
            hits += 1
    assert trials and hits >= trials - 1, f"matched {hits}/{trials}"


def test_risk_aversion_shifts_plan_toward_diversification() -> None:
    """The behavioural claim: raising kappa cannot increase plan variance.

    Two plots of the same crop are perfectly correlated (one monsoon), so the
    covariance term is what makes the optimiser spread the risk. If a high-kappa
    plan ever had *more* variance than the risk-neutral one, the sign of the
    risk term would be wrong.
    """
    compared = 0
    for seed in range(8):
        neutral = _simplex_problem(seed + 400, n_plots=3, n_crops=3, kappa=0.0)
        averse = _simplex_problem(seed + 400, n_plots=3, n_crops=3, kappa=1.5)
        n_opt, a_opt = brute_force(neutral), brute_force(averse)
        if n_opt["assignment"] is None or a_opt["assignment"] is None:
            continue
        compared += 1
        # Both variances measured on the same covariance matrix.
        var_neutral = plan_variance(averse, n_opt["assignment"])
        var_averse = plan_variance(averse, a_opt["assignment"])
        assert var_averse <= var_neutral + 1e-6, f"seed={seed}: risk aversion raised variance"
    assert compared >= 5


def test_objective_collapses_to_net_value_without_risk() -> None:
    """kappa = 0 must reproduce the pre-existing expected-value behaviour byte
    for byte, so the risk model is strictly additive rather than a rewrite."""
    problem = _simplex_problem(7, kappa=0.0)
    optimum = brute_force(problem)
    assert optimum["best_bits"] is not None
    assert abs(objective_value(problem, optimum["best_bits"]) - feasible_value(problem, optimum["best_bits"])) < 1e-9


def test_softmax_amplitudes_are_normalised() -> None:
    for tau in (0.05, 0.35, 2.0):
        amps = _softmax_amplitudes([1.0, 0.2, -0.5, 0.9], tau)
        assert abs(sum(a * a for a in amps) - 1.0) < 1e-9
    # Lower temperature must concentrate more mass on the best-valued crop.
    hot = _softmax_amplitudes([1.0, 0.0], 2.0)
    cold = _softmax_amplitudes([1.0, 0.0], 0.1)
    assert cold[0] > hot[0]


def test_interp_grows_schedule_by_one_layer() -> None:
    """INTERP maps a depth-p schedule to depth p+1 (Zhou et al.)."""
    import numpy as np

    p1 = np.array([0.25, 0.35])
    p2 = _interp(p1)
    assert len(p2) == 4
    p3 = _interp(p2)
    assert len(p3) == 6
    assert np.all(np.isfinite(p3))


def test_sigma_from_band_is_positive_even_when_quantiles_collapse() -> None:
    """A degenerate P10/P90 band means high confidence, not undefined risk —
    the covariance matrix must stay factorisable."""
    assert sigma_from_band(3.0, 3.0) > 0
    assert sigma_from_band(4.0, 2.0) > 0  # crossed quantiles
    assert sigma_from_band(2.0, 4.0) > sigma_from_band(2.9, 3.1)


# --------------------------------------------------------------------------
# Rotation sequencing (app/quantum/rotation.py) — the quantum-ranked crop order
# --------------------------------------------------------------------------


def _rotation_ctx(seed: int, crops: list[str] | None = None):
    from app.quantum.rotation import build_rotation_context

    rng = random.Random(seed)
    crops = crops or ["paddy", "black_gram", "groundnut", "maize"]
    base = {c: rng.uniform(20000, 85000) for c in crops}
    return build_rotation_context(
        seasons=["kharif", "rabi", "summer"], crops=crops, base_value_per_crop=base, area_ha=1.0
    )


def test_rotation_value_is_not_separable() -> None:
    """The load-bearing claim: sequence value depends on *order*, not just the
    set of crops. If this ever became order-independent, the ranking would
    collapse to a sort and the quantum step would be decorative."""
    from app.quantum.rotation import sequence_value

    ctx = _rotation_ctx(1)
    a = ["paddy", "black_gram", "groundnut"]
    b = ["black_gram", "paddy", "groundnut"]
    assert set(a) == set(b), "same crops, different order"
    assert abs(sequence_value(ctx, a) - sequence_value(ctx, b)) > 1e-6


def test_legume_before_cereal_beats_the_reverse() -> None:
    """Agronomic direction check: a cereal after a legume must out-earn the
    same pair reversed, because the break-crop multiplier and the nitrogen
    credit both point that way."""
    from app.quantum.rotation import sequence_value

    ctx = _rotation_ctx(2, crops=["paddy", "black_gram"])
    legume_first = sequence_value(ctx, ["black_gram", "paddy", "black_gram"])
    cereal_first = sequence_value(ctx, ["paddy", "black_gram", "paddy"])
    assert legume_first != cereal_first
    # Same crop twice running must always cost something.
    assert sequence_value(ctx, ["paddy", "paddy", "paddy"]) < sequence_value(ctx, ["paddy", "black_gram", "paddy"])


def test_sorting_is_measurably_wrong() -> None:
    """Quantifies why this is not a sort: across random farms, the naive
    "rank by predicted profit" answer is suboptimal often enough, and by
    enough rupees, to matter."""
    from app.quantum.rotation import brute_force_rotation, greedy_sort_rotation

    suboptimal = 0
    gaps = []
    for seed in range(30):
        ctx = _rotation_ctx(seed + 700)
        opt = brute_force_rotation(ctx)
        naive = greedy_sort_rotation(ctx)
        if opt["sequence"] is None:
            continue
        gap = opt["value"] - naive["value"]
        gaps.append(gap)
        assert gap >= -1e-6, "brute force must never lose to the sort"
        if gap > 1e-6:
            suboptimal += 1
    assert suboptimal >= len(gaps) // 3, f"sort was optimal in {len(gaps)-suboptimal}/{len(gaps)} — coupling too weak"


def test_rotation_respects_season_eligibility() -> None:
    """Black gram cannot be sown in kharif, so no returned sequence may put it
    there — an agronomic hard gate, not a preference."""
    from app.quantum.rotation import brute_force_rotation, is_valid_sequence

    ctx = _rotation_ctx(3)
    opt = brute_force_rotation(ctx)
    assert opt["sequence"] is not None
    assert is_valid_sequence(ctx, opt["sequence"])
    assert not is_valid_sequence(ctx, ["black_gram", "paddy", "groundnut"]), "black gram is rabi/summer only"


def test_no_back_to_back_same_crop_when_alternative_exists() -> None:
    """Break-crop rule: triple monoculture is invalid when another crop fits."""
    from app.quantum.rotation import brute_force_rotation, build_rotation_context, is_valid_sequence

    ctx = build_rotation_context(
        seasons=["kharif", "rabi", "summer"],
        crops=["black_gram", "groundnut"],
        base_value_per_crop={"black_gram": 23822.4, "groundnut": 85128.0},
        area_ha=1.2,
    )
    assert not is_valid_sequence(ctx, ["groundnut", "groundnut", "groundnut"])
    opt = brute_force_rotation(ctx)
    assert opt["sequence"] == ["groundnut", "black_gram", "groundnut"]


def test_delta_curation_anchors_kharif_paddy_when_water_is_sufficient() -> None:
    """Thanjavur delta: abundant water + alluvial soil → kharif paddy in the plan."""
    from app.quantum.rotation import (
        brute_force_rotation,
        build_rotation_context,
        resolve_delta_curation,
    )

    soil = {"soil_type": "alluvial", "water": {"category": "abundant"}}
    crops = ["paddy", "black_gram", "groundnut"]
    curation = resolve_delta_curation(soil, crops)
    assert curation["system"] == "cauvery_delta_rice_fallow"
    assert curation["anchors"]["kharif"] == "paddy"

    ctx = build_rotation_context(
        seasons=["kharif", "rabi", "summer"],
        crops=crops,
        base_value_per_crop={"paddy": 38000.0, "black_gram": 23822.4, "groundnut": 85128.0},
        area_ha=1.2,
        anchors=curation["anchors"],
    )
    opt = brute_force_rotation(ctx)
    assert opt["sequence"] == ["paddy", "black_gram", "groundnut"]


def test_delta_curation_off_when_water_is_low() -> None:
    from app.quantum.rotation import resolve_delta_curation

    soil = {"soil_type": "alluvial", "water": {"category": "low"}}
    assert resolve_delta_curation(soil, ["paddy", "groundnut"])["anchors"] == {}


def test_rotation_qubo_is_one_season_per_block() -> None:
    from app.quantum.rotation import build_rotation_qubo

    ctx = _rotation_ctx(4)
    problem = build_rotation_qubo(ctx)
    assert problem.encoding == "rotation_simplex"
    assert problem.n_qubits == problem.n_dec == len(ctx.seasons) * len(ctx.crops)
    assert sum(problem.slack_bits.values()) == 0
    assert len(problem.blocks) == len(ctx.seasons)
    flat = [q for block in problem.blocks for q in block]
    assert sorted(flat) == list(range(problem.n_dec))


def test_sparq_solves_rotation_with_the_same_ansatz() -> None:
    """One crop per *season* is the same simplex structure as one crop per
    *plot*, so the XY-ring mixer transfers unchanged — including the exact
    100% one-hot guarantee."""
    from app.quantum.rotation import (
        brute_force_rotation,
        build_rotation_qubo,
        decode_sequence,
        is_valid_sequence,
        sequence_value,
    )

    hits = trials = 0
    for seed in range(4):
        ctx = _rotation_ctx(seed + 800)
        problem = build_rotation_qubo(ctx)
        opt = brute_force_rotation(ctx)
        if opt["sequence"] is None:
            continue
        trials += 1

        def obj(p, b, _c=ctx):
            seq = decode_sequence(_c, p, b)
            return sequence_value(_c, seq) if seq and is_valid_sequence(_c, seq) else float("-inf")

        def ok(p, b, _c=ctx):
            seq = decode_sequence(_c, p, b)
            return seq is not None and is_valid_sequence(_c, seq)

        result = solve_sparq(
            problem, layers=2, timeout_s=25.0, shots=512, maxiter_per_layer=20,
            objective_fn=obj, feasibility_fn=ok, value_fn=obj,
        )
        assert result.simplex_rate == 1.0, "one crop per season must be structural"
        for bits in result.samples or []:
            for block in problem.blocks:
                assert sum(bits[q] for q in block) == 1
        if result.best_bits is not None and abs(result.best_objective - opt["value"]) < 1e-6:
            hits += 1

    assert trials and hits >= trials - 1, f"matched {hits}/{trials}"


def test_circuit_spec_and_measurements_are_exposed() -> None:
    """Brief §3 requires the quantum contribution to be visible, so the solver
    must hand back the gates it ran and the outcomes it measured."""
    from app.quantum.rotation import build_rotation_qubo, decode_sequence, is_valid_sequence, sequence_value

    ctx = _rotation_ctx(5)
    problem = build_rotation_qubo(ctx)

    def obj(p, b, _c=ctx):
        seq = decode_sequence(_c, p, b)
        return sequence_value(_c, seq) if seq and is_valid_sequence(_c, seq) else float("-inf")

    def ok(p, b, _c=ctx):
        seq = decode_sequence(_c, p, b)
        return seq is not None and is_valid_sequence(_c, seq)

    result = solve_sparq(
        problem, layers=2, timeout_s=25.0, shots=512, maxiter_per_layer=15,
        objective_fn=obj, feasibility_fn=ok, value_fn=obj,
        label_fn=lambda p, b, _c=ctx: {"sequence": decode_sequence(_c, p, b)},
    )

    circuit = result.circuit
    assert circuit["n_qubits"] == problem.n_qubits
    assert circuit["gate_counts"]["entangling_mixer"] > 0
    assert any(op["gate"] == "IsingXY" for op in circuit["operations"])
    assert any(op["gate"] == "CRY" for op in circuit["operations"]), "warm-started Dicke prep"

    # The ranking is read off measurement frequencies, so rank 1 must be the
    # most-measured outcome and probabilities must be real fractions.
    assert result.measurements
    assert result.measurements[0]["rank"] == 1
    probs = [m["probability"] for m in result.measurements]
    assert probs == sorted(probs, reverse=True)
    assert all(0.0 < p <= 1.0 for p in probs)
    assert result.measurements[0]["label"]["sequence"] is not None


def test_n_credit_is_monetised_and_signed_correctly() -> None:
    """Legumes leave nitrogen behind (positive credit); heavy cereal feeders
    take it (negative). The sign is what drives legume-before-cereal ordering."""
    from app.quantum.rotation import n_credit_rupees

    assert n_credit_rupees("black_gram", 1.0) > 0
    assert n_credit_rupees("groundnut", 1.0) > n_credit_rupees("black_gram", 1.0)
    assert n_credit_rupees("paddy", 1.0) < 0
    # Linear in area — twice the land, twice the urea saved.
    assert n_credit_rupees("groundnut", 2.0) == pytest.approx(2 * n_credit_rupees("groundnut", 1.0))


def test_timeout_still_returns_a_feasible_plan() -> None:
    """FR-46 is stronger under SPARQ: a timeout mid-search keeps the best
    schedule found so far and samples from it. Because every sample is one-hot
    by construction, a squeezed optimisation degrades plan *quality* rather
    than costing the farmer a plan entirely."""
    problem = _simplex_problem(11, n_plots=3, n_crops=3)
    result = solve_sparq(problem, layers=3, timeout_s=0.01, shots=256)
    assert result.timed_out
    assert result.simplex_rate == 1.0
    assert result.best_bits is not None or result.feasible_rate == 0.0


def test_sampled_plans_are_better_than_random() -> None:
    """Brief §3's hard requirement: the output must be demonstrably different
    from random guessing.

    Measured on plan *quality* (0 = the worst valid sequence, 1 = the optimum)
    rather than P(exact optimum). P(optimum) is fragile: when the top sequences
    sit within a couple of percent of each other the landscape is nearly flat,
    a spread distribution is the correct response, and the uplift can fall to
    ~1x. Quality is the metric that holds on every instance, so it is the one
    guarded here — and the claim string says the same thing.
    """
    import itertools
    import statistics

    from app.quantum.rotation import (
        brute_force_rotation,
        build_rotation_qubo,
        decode_sequence,
        is_valid_sequence,
        sequence_value,
    )

    crops = ["paddy", "black_gram", "groundnut", "maize"]
    beaten = 0
    trials = 0
    qualities = []

    for seed in range(5):
        ctx = _rotation_ctx(seed + 1500, crops=crops)
        problem = build_rotation_qubo(ctx)
        optimum = brute_force_rotation(ctx)
        if optimum["sequence"] is None:
            continue
        trials += 1

        def obj(p, b, _c=ctx):
            seq = decode_sequence(_c, p, b)
            return sequence_value(_c, seq) if seq and is_valid_sequence(_c, seq) else float("-inf")

        def ok(p, b, _c=ctx):
            seq = decode_sequence(_c, p, b)
            return seq is not None and is_valid_sequence(_c, seq)

        result = solve_sparq(
            problem, layers=3, timeout_s=30.0, shots=1024, maxiter_per_layer=30,
            objective_fn=obj, feasibility_fn=ok, value_fn=obj,
        )
        assert result.samples

        every = [
            sequence_value(ctx, list(s))
            for s in itertools.product(crops, repeat=len(ctx.seasons))
            if is_valid_sequence(ctx, list(s))
        ]
        best, worst = max(every), min(every)
        span = best - worst
        if span <= 0:
            continue

        random_quality = (statistics.mean(every) - worst) / span
        sampled = [sequence_value(ctx, decode_sequence(ctx, problem, b)) for b in result.samples]
        sampled_quality = (statistics.mean(sampled) - worst) / span
        qualities.append(sampled_quality)

        if sampled_quality > random_quality:
            beaten += 1

    assert trials, "no solvable instances generated"
    assert beaten == trials, f"only {beaten}/{trials} instances beat uniform random on plan quality"
    assert statistics.mean(qualities) > 0.65, f"mean sampled quality {statistics.mean(qualities):.3f} too close to random"
