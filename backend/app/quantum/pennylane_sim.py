"""PennyLane ``default.qubit`` simulation for the SPARQ rotation circuit.

Runs the same QNode as production ``solve_sparq`` but can return exact Born
probabilities (``qml.probs``) and a text circuit diagram (``qml.draw``) for
local inspection — not for yield prediction (QAOA optimisation only).
"""
from __future__ import annotations

from typing import Any

import numpy as np
import pennylane as qml

from app.quantum.qubo import QUBOProblem, decode_decision_bits, energy_qubo
from app.quantum.rotation import (
    RotationContext,
    build_rotation_context,
    build_rotation_qubo,
    decode_sequence,
    resolve_delta_curation,
)
from app.quantum.sparq import (
    DEFAULT_WARM_START_TAU,
    circuit_spec,
    make_sparq_qnode,
    warm_start_amplitudes,
)


def _bits_from_index(idx: int, n: int) -> list[int]:
    return [(idx >> (n - 1 - b)) & 1 for b in range(n)]


def _top_probable_outcomes(
    problem: QUBOProblem,
    probs: np.ndarray,
    *,
    top_k: int = 8,
    label_fn=None,
) -> list[dict[str, Any]]:
    n = problem.n_qubits
    ranked = sorted(enumerate(probs), key=lambda kv: kv[1], reverse=True)[:top_k]
    rows: list[dict[str, Any]] = []
    for rank, (idx, p) in enumerate(ranked, start=1):
        bits = _bits_from_index(int(idx), n)
        row: dict[str, Any] = {
            "rank": rank,
            "bitstring": "".join(str(b) for b in bits),
            "probability": round(float(p), 6),
            "energy": round(energy_qubo(problem, bits), 4),
        }
        decoded = decode_decision_bits(problem, bits)
        if all(v is not None for v in decoded.values()):
            row["feasible_simplex"] = True
        if label_fn is not None:
            row["label"] = label_fn(problem, bits)
        rows.append(row)
    return rows


def simulate_sparq_circuit(
    problem: QUBOProblem,
    *,
    layers: int = 1,
    params: np.ndarray | None = None,
    warm_start_tau: float = DEFAULT_WARM_START_TAU,
    top_k: int = 8,
    label_fn=None,
) -> dict[str, Any]:
    """Exact PennyLane simulation: Born probabilities + circuit diagram."""
    depth = max(1, layers)
    if params is None:
        params = np.linspace(0.2, 0.5, depth * 2)
    elif len(params) != depth * 2:
        raise ValueError(f"params must have length {depth * 2} (got {len(params)})")

    amps, warm = warm_start_amplitudes(problem, tau=warm_start_tau)
    qnode = make_sparq_qnode(problem, amps, depth, shots=None, mode="probs")
    probs = np.asarray(qnode(params), dtype=float)
    diagram = qml.draw(qnode, max_length=120)(params)
    spec_obj = qml.specs(qnode)(params)
    spec_dict = spec_obj.to_dict() if hasattr(spec_obj, "to_dict") else {}
    res = getattr(spec_obj, "resources", None)

    return {
        "device": "default.qubit",
        "n_qubits": problem.n_qubits,
        "layers": depth,
        "params": [round(float(x), 5) for x in params],
        "warm_start": warm,
        "circuit_diagram": diagram,
        "resources": {
            "num_gates": getattr(res, "num_gates", None) or spec_dict.get("num_gates"),
            "depth": getattr(res, "depth", None) or spec_dict.get("depth"),
        },
        "top_outcomes": _top_probable_outcomes(problem, probs, top_k=top_k, label_fn=label_fn),
        "circuit_spec": circuit_spec(problem, depth, amps),
    }


def demo_rotation_problem(
    *,
    water_category: str = "abundant",
    area_ha: float = 1.2,
) -> tuple[RotationContext, QUBOProblem]:
    """Thanjavur delta demo — same structure as the Quantum tab."""
    soil = {"soil_type": "alluvial", "water": {"category": water_category}}
    crops = ["paddy", "black_gram", "groundnut"]
    curation = resolve_delta_curation(soil, crops)
    base_value = {"paddy": 38000.0, "black_gram": 23822.4, "groundnut": 85128.0}
    ctx = build_rotation_context(
        seasons=["kharif", "rabi", "summer"],
        crops=crops,
        base_value_per_crop=base_value,
        area_ha=area_ha,
        anchors=curation.get("anchors") or {},
        slot_multipliers=curation.get("slot_multipliers") or [],
    )
    for season, crop in (curation.get("anchors") or {}).items():
        ctx.base_value[(season, crop)] = base_value[crop]
    problem = build_rotation_qubo(ctx)
    for season in ctx.seasons:
        for crop in ctx.crops:
            problem.warm_start_bias[(season, crop)] = base_value[crop]
    return ctx, problem


def simulate_rotation_demo(
    *,
    layers: int = 1,
    warm_start_tau: float = DEFAULT_WARM_START_TAU,
    water_category: str = "abundant",
    area_ha: float = 1.2,
    top_k: int = 8,
) -> dict[str, Any]:
    """One-shot demo: build delta rotation QUBO and simulate on PennyLane."""
    ctx, problem = demo_rotation_problem(water_category=water_category, area_ha=area_ha)

    def label(_problem: QUBOProblem, bits: list[int]) -> dict[str, Any]:
        seq = decode_sequence(ctx, problem, bits)
        return {"sequence": seq} if seq else {}

    out = simulate_sparq_circuit(
        problem,
        layers=layers,
        warm_start_tau=warm_start_tau,
        top_k=top_k,
        label_fn=label,
    )
    out["seasons"] = ctx.seasons
    out["crops"] = ctx.crops
    return out
