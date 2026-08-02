"""Run SPARQ on PennyLane's ``default.qubit`` simulator and print the circuit.

    python -m scripts.simulate_pennylane
    python -m scripts.simulate_pennylane --layers 2
"""
from __future__ import annotations

import argparse
import json
import sys

from app.quantum.pennylane_sim import simulate_rotation_demo


def main() -> None:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    parser = argparse.ArgumentParser(description="Simulate SPARQ rotation circuit in PennyLane")
    parser.add_argument("--layers", type=int, default=1, help="QAOA depth (default 1)")
    parser.add_argument("--json", action="store_true", help="Print full JSON instead of summary")
    args = parser.parse_args()

    try:
        result = simulate_rotation_demo(layers=args.layers)
    except Exception as exc:
        print(f"Simulation failed: {exc}", file=sys.stderr)
        sys.exit(1)

    if args.json:
        print(json.dumps(result, indent=2))
        return

    print(f"\nPennyLane default.qubit - {result['n_qubits']} qubits, {result['layers']} layer(s)\n")
    print("--- Circuit diagram ---")
    print(result["circuit_diagram"])
    print("\n--- Top measured outcomes (Born probabilities) ---")
    for row in result["top_outcomes"]:
        label = row.get("label") or {}
        seq = label.get("sequence")
        seq_txt = " → ".join(seq) if seq else row["bitstring"]
        feas = "ok" if row.get("feasible_simplex") else "·"
        print(
            f"  {row['rank']:>2}. {row['probability']*100:5.2f}%  {feas}  {seq_txt}  "
            f"(E={row['energy']:.3f})"
        )
    print(f"\nGates: {result['resources'].get('num_gates')}  Depth: {result['resources'].get('depth')}\n")


if __name__ == "__main__":
    main()
