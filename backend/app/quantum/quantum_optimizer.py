"""PennyLane QAOA solver (FR-43, TRD §6.4). `default.qubit` simulator only —
no hardware execution, no speedup claimed (PRD §5). CVaR at alpha=0.25 biases
the search toward the best quartile of sampled bitstrings rather than the
mean, which is the well-established improvement for combinatorial QAOA noted
in TRD §6.4.
"""
import time
from dataclasses import dataclass

import numpy as np
import pennylane as qml
from scipy.optimize import minimize

from app.quantum.qubo import QUBOProblem, energy_qubo, feasible_value, is_feasible, to_ising

TRAIN_SHOTS = 256  # shots per COBYLA objective evaluation — kept low so 200
# iterations fit inside QAOA_TIMEOUT_S on default.qubit at demo-scale n.

# ponytail: the standard transverse-field mixer used here (qml.qaoa.x_mixer)
# explores the full 2^n_qubits space and relies purely on the C1 penalty term
# to concentrate probability on valid one-crop-per-plot bitstrings. In
# practice this measures ~5-15% feasible_rate at p=3, well under TRD's 95%
# stretch target, even though it still reliably recovers the exact optimum
# among the feasible samples it does draw (see benchmark.json). Known ceiling:
# penalty-only feasibility is inherently harder to concentrate than a
# constrained search. Upgrade path: a per-plot "one-hot" (ring-XY) mixer
# restricted to each plot's crop subspace (Hadfield et al.'s QAOA+ /
# quantum alternating operator ansatz) would guarantee feasibility by
# construction instead of penalising infeasibility after the fact.


@dataclass
class QAOAResult:
    timed_out: bool
    best_bits: list[int] | None
    best_value: float
    energy: float | None
    feasible_rate: float
    wall_time_s: float
    samples: list[list[int]] | None = None


def _cost_hamiltonian(problem: QUBOProblem) -> tuple[qml.Hamiltonian, float]:
    h, j_coupling, const = to_ising(problem)
    coeffs: list[float] = []
    obs = []
    for i, hi in h.items():
        if abs(hi) > 1e-12:
            coeffs.append(hi)
            obs.append(qml.PauliZ(i))
    for (i, j), jij in j_coupling.items():
        if abs(jij) > 1e-12:
            coeffs.append(jij)
            obs.append(qml.PauliZ(i) @ qml.PauliZ(j))
    if not coeffs:
        coeffs, obs = [0.0], [qml.Identity(0)]
    return qml.Hamiltonian(coeffs, obs), const


def solve_qaoa(
    problem: QUBOProblem,
    *,
    layers: int = 3,
    timeout_s: float = 10.0,
    shots: int = 2048,
    cvar_alpha: float = 0.25,
) -> QAOAResult:
    n = problem.n_qubits
    cost_h, _const = _cost_hamiltonian(problem)
    mixer_h = qml.qaoa.x_mixer(range(n))

    def circuit():
        for w in range(n):
            qml.Hadamard(wires=w)
        for layer_gamma, layer_beta in zip(gammas_ref[0], betas_ref[0]):
            qml.qaoa.cost_layer(layer_gamma, cost_h)
            qml.qaoa.mixer_layer(layer_beta, mixer_h)
        return qml.sample(wires=range(n))

    gammas_ref: list = [None]
    betas_ref: list = [None]

    train_dev = qml.device("default.qubit", wires=n)
    train_qnode = qml.set_shots(qml.QNode(circuit, train_dev), shots=TRAIN_SHOTS)

    start = time.monotonic()
    timed_out = False

    def objective(params: np.ndarray) -> float:
        nonlocal timed_out
        if time.monotonic() - start > timeout_s:
            timed_out = True
            raise TimeoutError("QAOA_TIMEOUT_S breached")
        gammas_ref[0] = params[:layers]
        betas_ref[0] = params[layers:]
        samples = np.atleast_2d(train_qnode())
        energies = [energy_qubo(problem, [int(b) for b in row]) for row in samples]
        energies.sort()
        k = max(1, int(len(energies) * cvar_alpha))
        return float(np.mean(energies[:k]))

    x0 = np.concatenate([np.linspace(0.0, 0.5, layers), np.linspace(0.5, 0.0, layers)])
    best_params = x0
    try:
        result = minimize(objective, x0, method="COBYLA", options={"maxiter": 200})
        best_params = result.x
    except TimeoutError:
        timed_out = True

    wall_time_s = time.monotonic() - start

    if timed_out:
        return QAOAResult(
            timed_out=True, best_bits=None, best_value=0.0, energy=None, feasible_rate=0.0, wall_time_s=wall_time_s
        )

    gammas_ref[0] = best_params[:layers]
    betas_ref[0] = best_params[layers:]
    sample_dev = qml.device("default.qubit", wires=n)
    sample_qnode = qml.set_shots(qml.QNode(circuit, sample_dev), shots=shots)
    raw_samples = np.atleast_2d(sample_qnode())
    all_bits = [[int(b) for b in row] for row in raw_samples]
    feasible_bits = [bits for bits in all_bits if is_feasible(problem, bits)]
    feasible_rate = len(feasible_bits) / len(all_bits)

    if not feasible_bits:
        return QAOAResult(
            timed_out=False,
            best_bits=None,
            best_value=0.0,
            energy=None,
            feasible_rate=0.0,
            wall_time_s=wall_time_s,
            samples=all_bits,
        )

    best_bits = max(feasible_bits, key=lambda bits: feasible_value(problem, bits))
    return QAOAResult(
        timed_out=False,
        best_bits=best_bits,
        best_value=feasible_value(problem, best_bits),
        energy=energy_qubo(problem, best_bits),
        feasible_rate=feasible_rate,
        wall_time_s=wall_time_s,
        samples=all_bits,
    )
