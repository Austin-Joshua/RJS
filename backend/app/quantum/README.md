# FarmSync Quantum Layer — Models & Algorithms

Classical **LightGBM** predicts yield. Quantum (**SPARQ**) allocates crops under constraints and sequences rotations. Quantum never sits on the prediction path.

```
Soil + Weather + NDVI
        │
        ▼
 LightGBM (yield, P10/P90, SHAP)     ← classical ML
        │
        ▼
 Risk model (μ, Cov from bands)      ← couples plots
        │
        ▼
 QUBO (simplex / rotation)           ← combinatorial encoding
        │
        ▼
 SPARQ (PennyLane simulator)         ← primary solver
        │
        ├── classical brute force / SA (always run side-by-side)
        └── plan + benchmark payload → app
```

**Claim (verbatim from `models/v1/benchmark.json`):**

> Simulated QAOA recovers the exact optimum at demo scale. No runtime advantage over classical is claimed or observed at n ≤ 25 qubits.

---

## 1. Classical yield model (input to quantum)

| Item | Detail |
|---|---|
| Algorithm | LightGBM regressor + two quantile boosters (P10 / P90) |
| Role | Tabular yield prediction only — **not** quantum |
| Features | Soil N/P/K, weather, NDVI, crop/district encodings (`app/ml/`) |
| Artifacts | `models/v1/yield_lgbm.txt`, `yield_q10.txt`, `yield_q90.txt`, `metrics.json` |
| Eval (temporal holdout) | R² ≈ 0.96 — see `metrics.json` for all protocols |

Net value per (plot, crop):

```
v = yield_t_ha × area_ha × price_Rs/quintal × 10  −  cost_Rs/ha × area_ha
```

SPARQ warm-starts from this matrix; it does not recompute yield.

---

## 2. SPARQ — primary quantum solver

**SPARQ** = **S**implex-**P**reserving **A**daptive **R**isk-aware **Q**AOA  
Code: [`sparq.py`](sparq.py) · Device: PennyLane `default.qubit`

Replaces legacy transverse-field QAOA, which sampled ~randomly (`uplift_vs_uniform ≈ 1.8×`, feasible rate ~3%).

### Four design moves

| # | Technique | What it does |
|---|---|---|
| 1 | **Simplex preservation** | Each plot (or season) is a qubit block in a Hamming-weight-1 state. An **XY ring mixer** (`qml.IsingXY`) conserves that weight — exactly one crop per block by symmetry, not by penalty. |
| 2 | **Value-gradient warm start** | Block amplitudes ∝ √softmax(μ_pc / τ), τ = 0.35. LightGBM net values seed the quantum prior. |
| 3 | **Zero slack qubits** | C1 is structural; water/budget use unbalanced penalisation → `n_qubits == n_dec`. |
| 4 | **INTERP layerwise growth** | Train p=1 → grow to p=2 → p=3 (Zhou et al.). Real optimisation trace for the analytics chart. |

### Circuit parameters

| Parameter | Value |
|---|---|
| Init | Weighted Dicke-1 (generalised W) per block — excitation cascade (X → CRY → CNOT) |
| Mixer | XY ring via native `IsingXY` (not Trotterised XX+YY — that breaks the invariant) |
| Cost | `qml.qaoa.cost_layer(γ, H_C)` — diagonal, exact |
| Depth | INTERP p = 1→2→3 |
| Classical opt | COBYLA, 60 iters/stage; best schedule retained on timeout |
| Train objective | CVaR of QUBO energy at α = 0.25 (best quartile of shots) |
| Sample shots | 2048 (256 during training) |
| Timeout | `QAOA_TIMEOUT_S` (default 10 s) → classical fallback |

Must use the native `IsingXY` gate: decomposing as separate XX/YY Paulis maps `|00⟩→|11⟩` and destroys the one-crop invariant (`test_xy_mixer_conserves_one_crop_per_plot`).

### Benchmark (50 instances, 3×3 plots×crops, p=3)

| Metric | SPARQ | Legacy QAOA |
|---|---|---|
| Qubits | **9** | 11 |
| Simplex rate (one crop/plot) | **100%** | not enforced |
| Feasible rate (all constraints) | **61.4%** | 2.9% |
| Uplift vs 2ⁿ uniform | **98.5×** | 1.8× |
| Uplift vs Cᴾ feasible uniform | **5.19×** | 0.10× |
| Optimum match | **94%** | 92% |
| Approximation ratio | **1.0000** | 0.9997 |
| Wall clock | **~2.2 s** | ~3.3 s |

Lead with **`uplift_vs_feasible_uniform`** (5.19×): SPARQ cannot emit invalid C1 bitstrings, so uplift vs all 2ⁿ overstates concentration. Feasible-rate shortfall vs the 95% target is entirely water/budget (C2/C3); C1 is always satisfied.

---

## 3. Risk-aware QUBO objective

Code: [`risk.py`](risk.py) · Encoding: [`qubo.py`](qubo.py) → `build_simplex_qubo`

Yield bands used to *choose* the plan, not only decorate it:

```
maximise   Σᵢ μᵢ xᵢ  −  κ · Σᵢⱼ Cov(vᵢ, vⱼ) xᵢ xⱼ
```

Variance is **quadratic in x**, so mean–variance is a native QUBO. Without the risk term the objective separates (greedy per-plot wins); covariance is what makes allocation combinatorial.

| Piece | Detail |
|---|---|
| σ_c | `(P90 − P10) / (2 · z₀.₉₀)`, z₀.₉₀ ≈ 1.282 |
| Cov(y_c, y_c′) | σ_c σ_c′ ρ — ρ = 1 same crop, `risk_cross_crop_rho` = 0.45 across crops |
| κ | Farmer slider `risk_aversion` ∈ [0, 3] |
| Normalisation | Variance / farm max value so κ is scale-free |

**Optimised:** mean–variance.  
**Reported only:** CVaR, scenario histogram, `certainty_equivalent_rs = mean − κσ`. CVaR is not quadratic in x and is not what the QUBO encodes.

Demo frontier (Thanjavur, κ 0 → 3): monoculture → diversified groundnut/paddy as risk aversion rises.

---

## 4. Crop rotation sequencing

Code: [`rotation.py`](rotation.py) · Tables: `models/v1/rotation.yaml`

Not a sort of expected profit. Realised yield depends on the predecessor:

```
maximise  Σₜ  base[cₜ] × yield_multiplier[family(cₜ₋₁)][family(cₜ)]
               × (same_crop_penalty if cₜ == cₜ₋₁)
          +     N_credit_value[cₜ₋₁]
```

Same simplex structure as allocation (one crop per **season**), so SPARQ’s XY-ring ansatz transfers unchanged. Only the objective changes (adjacent-season quadratic couplings + eligibility penalties).

Baselines in the same module (same scoring function):

- `brute_force_rotation` — exact at demo scale  
- `greedy_sort_rotation` — naive “rank by standalone value”  
- `greedy_myopic_rotation` — one-step lookahead (steel-man classical)

---

## 5. Encodings & fallbacks

| Encoding | Builder | Slack | Used by |
|---|---|---|---|
| `simplex` | `build_simplex_qubo` | none | SPARQ (primary) |
| `rotation_simplex` | `build_rotation_qubo` | none | SPARQ (rotation) |
| `slack` | `build_qubo` | water + budget bits | Legacy QAOA (`quantum_optimizer.py`) |

Water/budget on simplex: unbalanced penalisation (Montanez-Barrera & Michielsen). Every sample is re-checked with true constraints before selection.

Classical path ([`classical_fallback.py`](classical_fallback.py)): brute force (n ≤ 20) + simulated annealing. Both quantum and classical run every request; timeout returns `solver: "classical_fallback"`.

---

## 6. Module map

| File | Responsibility |
|---|---|
| `sparq.py` | SPARQ ansatz, INTERP training, sampling, circuit/measurement export |
| `risk.py` | μ / Cov from LightGBM bands, scenarios, CVaR report |
| `qubo.py` | Slack + simplex QUBO, feasibility, risk-adjusted objective |
| `rotation.py` | Season×crop QUBO, sequence value, classical baselines |
| `quantum_optimizer.py` | Legacy transverse-field QAOA (kept for head-to-head) |
| `classical_fallback.py` | Brute force / SA |
| `benchmark.py` | Instance generation + metric aggregation |

Offline: `python -m scripts.benchmark_qaoa` → `models/v1/benchmark.json`  
API: `GET /api/v1/analytics/quantum-benchmark`

---

## 7. What we do / do not claim

| Do | Do not |
|---|---|
| Quantum-ready combinatorial formulation | Quantum advantage / speedup at demo n |
| SPARQ concentrates on good feasible plans | Quantum ML for yield prediction |
| Mean–variance inside the QUBO | “The QUBO optimises CVaR” |
| Side-by-side classical + legacy QAOA | Hide the old ansatz’s ~random sampling |

Rule: if it isn’t backed by a number in `benchmark.json`, it doesn’t get said on stage.
