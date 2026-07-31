"""SPARQ — Simplex-Preserving Adaptive Risk-aware QAOA.

The stock QAOA in `quantum_optimizer.py` uses a transverse-field mixer over the
full 2^n Hilbert space and leans on a penalty term to discourage invalid
one-crop-per-plot assignments. Its own benchmark shows what that costs:
`feasible_rate` ~ 0.08 and `uplift_vs_uniform` ~ 1.0. The second number is the
damning one — a distribution statistically indistinguishable from random
guessing. The optimum still got found, but by post-selecting the best of 2048
draws over a 64-element space, which is brute force wearing a costume.

SPARQ changes four things. Each one is a published technique; the combination,
and the coupling to a gradient-boosted yield model, is specific to this problem.

1.  **Simplex preservation.** Each plot's crop qubits start in a Hamming-weight-1
    state and are mixed by an XY ring (Hadfield et al.'s quantum alternating
    *operator* ansatz). `IsingXY` annihilates |00> and |11> and rotates only
    within {|01>, |10>}, so weight-1 per block is a conserved quantity of the
    entire evolution. "Exactly one crop per plot" holds by construction at any
    depth, rather than being paid for with a penalty term.

2.  **Value-gradient warm start.** Block amplitudes are initialised proportional
    to sqrt(softmax(mu_pc / tau)) using the LightGBM net-value matrix. The
    classical regressor seeds the quantum prior. This keeps quantum strictly off
    the prediction path (PRD Section 4) — the model's output is an input here,
    not something quantum is asked to compute.

3.  **Zero slack qubits.** C1 is structural and C2/C3 use unbalanced
    penalisation, so n_qubits == n_dec.

4.  **INTERP layerwise growth** (Zhou et al.). Depth p is trained, then used to
    seed depth p+1. Beyond converging better than cold-starting at p=3, this
    produces a *real* optimisation trace — which is what the analytics screen
    now plots instead of the synthetic curve it was drawing before.

No speedup over classical is claimed at this scale. What is claimed is a
correctly-structured ansatz whose sampled distribution measurably concentrates
on good plans, verified against uniform sampling over the *same feasible
subspace* rather than over all 2^n bitstrings.
"""
import math
import time
from collections.abc import Callable
from dataclasses import dataclass, field

import numpy as np
import pennylane as qml
from scipy.optimize import minimize

# Shared with the legacy solver on purpose: two independent Ising constructions
# would be free to drift apart, and the benchmark compares energies across both.
from app.quantum.quantum_optimizer import _cost_hamiltonian
from app.quantum.qubo import (
    QUBOProblem,
    decode_decision_bits,
    energy_qubo,
    feasible_value,
    is_feasible,
    objective_value,
)

TRAIN_SHOTS = 256  # shots per objective evaluation during training
DEFAULT_WARM_START_TAU = 0.35  # softmax temperature on normalised net value


@dataclass
class SparqResult:
    timed_out: bool
    best_bits: list[int] | None
    best_value: float  # expected Rs (what the farmer sees)
    best_objective: float  # risk-adjusted Rs (what was optimised)
    energy: float | None
    feasible_rate: float  # satisfies C1 *and* C2/C3
    simplex_rate: float  # satisfies C1 — should be exactly 1.0 by symmetry
    wall_time_s: float
    n_qubits: int = 0
    layers: int = 0
    samples: list[list[int]] | None = None
    convergence: list[dict] = field(default_factory=list)
    warm_start: dict[str, dict[str, float]] = field(default_factory=dict)
    # Gate-level circuit description and the measured outcome histogram, so the
    # app can show what the circuit was and where the answer came from rather
    # than asserting a black box produced it (brief §3).
    circuit: dict = field(default_factory=dict)
    measurements: list[dict] = field(default_factory=list)


def _softmax_amplitudes(values: list[float], tau: float) -> list[float]:
    """Amplitudes a_c with sum(a_c^2) = 1 and a_c^2 = softmax(v_c / tau).

    tau -> 0 collapses onto the single best crop (no exploration left for the
    mixer to do); tau -> inf gives the uniform W state, i.e. no warm start at
    all. The default sits between: a real bias toward what the yield model
    likes, with enough amplitude elsewhere that the optimiser can still move.
    """
    if not values:
        return []
    tau = max(tau, 1e-6)
    scaled = [v / tau for v in values]
    peak = max(scaled)
    exps = [math.exp(s - peak) for s in scaled]  # shift for numerical stability
    total = sum(exps) or 1.0
    return [math.sqrt(e / total) for e in exps]


def _prepare_block(amplitudes: list[float], wires: list[int]) -> None:
    """Weighted Dicke-1 (generalised W) state on `wires`.

    Standard excitation-cascade construction: place a single excitation on the
    first wire, then at each step split off the amplitude this position should
    keep and carry the remainder forward. Exactly one qubit in the block is
    excited in every branch of the superposition, which is the invariant the
    XY mixer then preserves.
    """
    n = len(wires)
    if n == 0:
        return
    qml.PauliX(wires=wires[0])
    if n == 1:
        return

    remaining_sq = 1.0  # amplitude^2 still to be distributed
    for k in range(n - 1):
        a_sq = amplitudes[k] ** 2 if k < len(amplitudes) else 0.0
        if remaining_sq <= 1e-12:
            ratio = 0.0
        else:
            ratio = min(1.0, max(0.0, math.sqrt(min(1.0, a_sq / remaining_sq))))
        theta = 2.0 * math.acos(ratio)
        # Split the excitation currently on wire k across k and k+1 ...
        qml.CRY(theta, wires=[wires[k], wires[k + 1]])
        # ... then clear wire k on the branch that moved on, so weight stays 1.
        qml.CNOT(wires=[wires[k + 1], wires[k]])
        remaining_sq = max(0.0, remaining_sq - a_sq)


def _xy_ring_mixer(beta: float, blocks: list[list[int]]) -> None:
    """Hamming-weight-preserving mixer, applied independently per plot block.

    `IsingXY(phi)` implements exp(-i phi/4 (XX + YY)) as a native two-qubit
    gate. Trotterising XX and YY as separate Pauli words — which is what
    `qml.qaoa.mixer_layer` would do — breaks the symmetry, because XX alone
    maps |00> to |11>. Using the exact gate is what makes the invariant hold.
    """
    for wires in blocks:
        n = len(wires)
        if n < 2:
            continue
        # A 2-qubit block has a single edge; a ring would apply it twice.
        edges = (
            [(wires[0], wires[1])]
            if n == 2
            else [(wires[k], wires[(k + 1) % n]) for k in range(n)]
        )
        for a, b in edges:
            qml.IsingXY(2.0 * beta, wires=[a, b])


def _interp(params: np.ndarray) -> np.ndarray:
    """INTERP heuristic (Zhou et al.): grow a depth-p schedule to depth p+1.

    gamma^(p+1)_i = (i-1)/p * gamma^(p)_{i-1} + (p-i+1)/p * gamma^(p)_i,
    with out-of-range entries treated as zero. Optimal QAOA schedules are
    smooth in the layer index, so linearly resampling the previous solution
    lands close to the next depth's optimum instead of restarting cold.
    """
    p = len(params) // 2
    gammas, betas = list(params[:p]), list(params[p:])

    def grow(seq: list[float]) -> list[float]:
        out = []
        for i in range(1, p + 2):
            lo = seq[i - 2] if i >= 2 else 0.0
            hi = seq[i - 1] if i <= p else 0.0
            out.append((i - 1) / p * lo + (p - i + 1) / p * hi)
        return out

    return np.array(grow(gammas) + grow(betas))


def circuit_spec(problem: QUBOProblem, layers: int, amplitudes_per_block: list[list[float]]) -> dict:
    """Gate-level description of the circuit actually executed.

    Rendered as a diagram in the app. Reconstructed from the same `blocks` and
    amplitudes the circuit is built from, so it cannot drift out of sync with
    what ran — there is no second source of truth to go stale.
    """
    ops: list[dict] = []

    for b, (wires, amps) in enumerate(zip(problem.blocks, amplitudes_per_block)):
        ops.append({"stage": "init", "block": b, "gate": "X", "wires": [wires[0]]})
        # Replays `_prepare_block`'s recurrence rather than approximating it, so
        # the angle drawn on the diagram is the angle the circuit applied. Using
        # acos(a_k) directly is wrong: each rotation is conditioned on the
        # amplitude still undistributed at that step, not on a_k alone.
        remaining_sq = 1.0
        for k in range(len(wires) - 1):
            a_sq = amps[k] ** 2 if k < len(amps) else 0.0
            ratio = 0.0 if remaining_sq <= 1e-12 else min(1.0, max(0.0, math.sqrt(min(1.0, a_sq / remaining_sq))))
            ops.append(
                {
                    "stage": "init",
                    "block": b,
                    "gate": "CRY",
                    "wires": [wires[k], wires[k + 1]],
                    "label": f"θ={2 * math.acos(ratio):.2f}",
                }
            )
            ops.append({"stage": "init", "block": b, "gate": "CNOT", "wires": [wires[k + 1], wires[k]]})
            remaining_sq = max(0.0, remaining_sq - a_sq)

    for layer in range(layers):
        ops.append(
            {
                "stage": "cost",
                "layer": layer + 1,
                "gate": "exp(-iγH_C)",
                "wires": list(range(problem.n_qubits)),
                "label": f"γ{layer + 1}",
            }
        )
        for b, wires in enumerate(problem.blocks):
            n = len(wires)
            if n < 2:
                continue
            edges = [(wires[0], wires[1])] if n == 2 else [(wires[k], wires[(k + 1) % n]) for k in range(n)]
            for a, c in edges:
                ops.append(
                    {
                        "stage": "mixer",
                        "layer": layer + 1,
                        "block": b,
                        "gate": "IsingXY",
                        "wires": [a, c],
                        "label": f"2β{layer + 1}",
                    }
                )

    two_qubit = sum(1 for o in ops if len(o["wires"]) == 2)
    return {
        "n_qubits": problem.n_qubits,
        "layers": layers,
        "blocks": [list(b) for b in problem.blocks],
        "operations": ops,
        "gate_counts": {
            "total": len(ops),
            "two_qubit": two_qubit,
            "entangling_mixer": sum(1 for o in ops if o["gate"] == "IsingXY"),
        },
        "invariant": (
            "IsingXY annihilates |00> and |11>, so Hamming weight inside each "
            "block is conserved. Exactly one crop per block holds at any depth."
        ),
    }


def measurement_histogram(
    problem: QUBOProblem,
    samples: list[list[int]],
    *,
    top_k: int = 12,
    label_fn=None,
) -> list[dict]:
    """Measured bitstring frequencies — where the ranking literally comes from.

    The returned order *is* the quantum ranking: the most-measured feasible
    outcome is rank 1. Nothing is re-sorted classically afterwards, which is
    what makes "ranked results derived directly from measurement outcomes"
    true rather than a description of something adjacent.
    """
    counts: dict[tuple[int, ...], int] = {}
    for bits in samples:
        key = tuple(bits)
        counts[key] = counts.get(key, 0) + 1

    total = len(samples) or 1
    ranked = sorted(counts.items(), key=lambda kv: kv[1], reverse=True)[:top_k]

    rows: list[dict] = []
    for rank, (bits, count) in enumerate(ranked, start=1):
        row = {
            "rank": rank,
            "bitstring": "".join(str(b) for b in bits),
            "count": count,
            "probability": round(count / total, 5),
        }
        if label_fn is not None:
            row["label"] = label_fn(problem, list(bits))
        rows.append(row)
    return rows


def solve_sparq(
    problem: QUBOProblem,
    *,
    layers: int = 3,
    timeout_s: float = 10.0,
    shots: int = 2048,
    cvar_alpha: float = 0.25,
    warm_start_tau: float = DEFAULT_WARM_START_TAU,
    maxiter_per_layer: int = 60,
    objective_fn: Callable[[QUBOProblem, list[int]], float] | None = None,
    feasibility_fn: Callable[[QUBOProblem, list[int]], bool] | None = None,
    value_fn: Callable[[QUBOProblem, list[int]], float] | None = None,
    label_fn: Callable[[QUBOProblem, list[int]], object] | None = None,
) -> SparqResult:
    """Run SPARQ and return the best feasible plan it sampled.

    Requires `problem.blocks` — a QUBO built by `build_simplex_qubo` (crop per
    plot) or `build_rotation_qubo` (crop per season). Both are the same simplex
    structure, which is why one ansatz serves both; the legacy slack encoding
    has no block structure to preserve, so it stays on `solve_qaoa`.

    The three `*_fn` hooks let a caller supply a problem-specific objective.
    Rotation sequencing scores a bitstring by its full sequence value —
    including the adjacent-season coupling — which the allocation-shaped
    defaults in `qubo.py` know nothing about. Defaults preserve the allocation
    behaviour exactly.
    """
    score = objective_fn or objective_value
    is_ok = feasibility_fn or is_feasible
    value_of = value_fn or feasible_value
    if not problem.blocks:
        raise ValueError("SPARQ requires a simplex-encoded QUBO (build_simplex_qubo)")

    n = problem.n_qubits
    cost_h, _const = _cost_hamiltonian(problem)

    # --- Warm start: bias each plot's block toward the crops the yield model
    # rates highest, then let the mixer redistribute under the constraints.
    plot_ids = list(dict.fromkeys(p for p, _ in problem.variables))
    amplitudes_per_block: list[list[float]] = []
    warm_start_report: dict[str, dict[str, float]] = {}
    for plot_id, wires in zip(plot_ids, problem.blocks):
        crops = [c for (p, c) in problem.variables if p == plot_id]
        values = [problem.warm_start_bias.get((plot_id, c), 0.0) for c in crops]
        amps = _softmax_amplitudes(values, warm_start_tau)
        amplitudes_per_block.append(amps)
        warm_start_report[plot_id] = {c: round(a * a, 4) for c, a in zip(crops, amps)}
        del wires  # block wiring is read from problem.blocks inside the circuit

    def build_qnode(depth: int, n_shots: int):
        dev = qml.device("default.qubit", wires=n)

        def circuit(params):
            for amps, wires in zip(amplitudes_per_block, problem.blocks):
                _prepare_block(amps, wires)
            for layer in range(depth):
                qml.qaoa.cost_layer(params[layer], cost_h)
                _xy_ring_mixer(params[depth + layer], problem.blocks)
            return qml.sample(wires=range(n))

        return qml.set_shots(qml.QNode(circuit, dev), shots=n_shots)

    start = time.monotonic()
    timed_out = False
    convergence: list[dict] = []
    # Seed depth 1 with a short linear ramp — the standard adiabatic-inspired
    # initialisation, and the starting point INTERP then grows from.
    params = np.array([0.25, 0.35])
    best_params = params.copy()

    for depth in range(1, layers + 1):
        if depth > 1:
            params = _interp(best_params)
        train_qnode = build_qnode(depth, TRAIN_SHOTS)
        stage_best = {"value": float("inf"), "params": params.copy()}
        iteration = [0]

        def objective(p_vec: np.ndarray, _depth: int = depth, _stage: dict = stage_best, _it: list = iteration) -> float:
            nonlocal timed_out
            if time.monotonic() - start > timeout_s:
                timed_out = True
                raise TimeoutError("QAOA_TIMEOUT_S breached")
            raw = np.atleast_2d(train_qnode(p_vec))
            energies = sorted(energy_qubo(problem, [int(b) for b in row]) for row in raw)
            # CVaR at alpha: optimise the best quartile of samples, not the
            # mean. We only need one good bitstring, so the tail is what counts
            # (Barkoutsos et al.).
            k = max(1, int(len(energies) * cvar_alpha))
            value = float(np.mean(energies[:k]))
            _it[0] += 1
            convergence.append({"layer": _depth, "iteration": _it[0], "cvar_energy": round(value, 6)})
            if value < _stage["value"]:
                # Track the best schedule seen so far, so a timeout mid-search
                # still leaves us with a usable circuit instead of nothing.
                _stage["value"] = value
                _stage["params"] = p_vec.copy()
            return value

        try:
            result = minimize(objective, params, method="COBYLA", options={"maxiter": maxiter_per_layer})
            best_params = result.x if result.x is not None else stage_best["params"]
        except TimeoutError:
            best_params = stage_best["params"]
            break

        if stage_best["value"] < float("inf"):
            best_params = stage_best["params"]
        if time.monotonic() - start > timeout_s:
            timed_out = True
            break

    trained_depth = max(1, len(best_params) // 2)
    wall_time_s = time.monotonic() - start

    # Even on timeout we sample: the schedule found so far is still a valid
    # circuit, and every sample is C1-feasible by construction, so the worst
    # case is a merely-mediocre plan rather than no plan.
    sample_qnode = build_qnode(trained_depth, shots)
    raw_samples = np.atleast_2d(sample_qnode(best_params))
    all_bits = [[int(b) for b in row] for row in raw_samples]

    simplex_ok = [
        bits for bits in all_bits if all(v is not None for v in decode_decision_bits(problem, bits).values())
    ]
    feasible_bits = [bits for bits in all_bits if is_ok(problem, bits)]
    simplex_rate = len(simplex_ok) / len(all_bits) if all_bits else 0.0
    feasible_rate = len(feasible_bits) / len(all_bits) if all_bits else 0.0

    spec = circuit_spec(problem, trained_depth, amplitudes_per_block)
    # Histogram over *feasible* outcomes only: an infeasible bitstring is not a
    # candidate answer, so ranking it would misrepresent where the result came
    # from. The full distribution is still available via `samples`.
    histogram = measurement_histogram(problem, feasible_bits or all_bits, label_fn=label_fn)

    if not feasible_bits:
        return SparqResult(
            timed_out=timed_out,
            best_bits=None,
            best_value=0.0,
            best_objective=0.0,
            energy=None,
            feasible_rate=0.0,
            simplex_rate=simplex_rate,
            wall_time_s=wall_time_s,
            n_qubits=n,
            layers=trained_depth,
            samples=all_bits,
            convergence=convergence,
            warm_start=warm_start_report,
            circuit=spec,
            measurements=histogram,
        )

    best_bits = max(feasible_bits, key=lambda bits: score(problem, bits))
    return SparqResult(
        timed_out=timed_out,
        best_bits=best_bits,
        best_value=value_of(problem, best_bits),
        best_objective=score(problem, best_bits),
        energy=energy_qubo(problem, best_bits),
        feasible_rate=feasible_rate,
        simplex_rate=simplex_rate,
        wall_time_s=wall_time_s,
        n_qubits=n,
        layers=trained_depth,
        samples=all_bits,
        convergence=convergence,
        warm_start=warm_start_report,
        circuit=spec,
        measurements=histogram,
    )
