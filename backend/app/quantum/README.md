# Quantum layer (code-local)

Full algorithm + model write-up (SPARQ, LightGBM, rotation QUBO, sliders, benchmarks):

**→ [QUANTUM.md](../../../QUANTUM.md)** (repo root)

This folder implements that doc:

| File | Role |
|---|---|
| `sparq.py` | SPARQ — primary solver |
| `rotation.py` | Season×crop sequencing QUBO |
| `qubo.py` | Simplex / slack encodings |
| `risk.py` | Mean–variance from LightGBM bands |
| `quantum_optimizer.py` | Legacy transverse-field QAOA |
| `pennylane_sim.py` | PennyLane `default.qubit` exact probs + `qml.draw` |
| `classical_fallback.py` | Brute force / SA |
| `benchmark.py` | SPARQ vs legacy metrics |
