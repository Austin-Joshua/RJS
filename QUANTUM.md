# FarmSync — Quantum Algorithm & Models

Single reference for what runs under the **Quantum** tab, the rank API, and the survival sliders (water / budget).

**Hard rule:** quantum is used for **combinatorial optimisation only** — never for yield prediction. Classical LightGBM predicts; SPARQ (quantum) orders and allocates under constraints.

---

## End-to-end pipeline

```
Farmer soil card + weather + NDVI
              │
              ▼
┌─────────────────────────────────────┐
│  Classical feasibility gates        │  pH, EC, soil type, water, budget
│  (crop_feasibility.py)              │  → which crops are even allowed
└─────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────┐
│  LightGBM yield model               │  mean + P10/P90 + SHAP
│  (app/ml/)                          │  → ₹ value per crop on this farm
└─────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────┐
│  Rotation QUBO                      │  season × crop, quadratic couplings
│  (quantum/rotation.py)              │  (predecessor changes next yield)
└─────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────┐
│  SPARQ — primary quantum solver     │  PennyLane default.qubit simulator
│  (quantum/sparq.py)                 │  XY-ring QAOA, INTERP depth 1→3
└─────────────────────────────────────┘
              │
              ├── classical baselines (exact / sort / greedy) — always side-by-side
              └── plan + quantum report → Flutter Quantum Lab
```

**API:** `POST /api/v1/farms/{id}/rank`  
Optional scenario body: `water_available_m3`, `budget_rs`, `persist` (false for slider what-ifs).

---

## 1. Classical yield model (not quantum)

| Item | Detail |
|---|---|
| **Algorithm** | LightGBM regressor + two quantile models (P10 / P90) |
| **Role** | Tabular **yield prediction only** |
| **Code** | `backend/app/ml/` |
| **Artifacts** | `backend/models/v1/yield_lgbm.txt`, `yield_q10.txt`, `yield_q90.txt` |
| **Features** | Soil N/P/K/pH/OC, rainfall, GDD, humidity, ET₀, NDVI stats, area, crop, district, season |
| **Training data** | DES district APY + Open-Meteo ERA5 + MODIS NDVI (`metrics.json`) |
| **Holdout (temporal)** | R² ≈ **0.96**, RMSE ≈ 7.1 t/ha (see `models/v1/metrics.json`) |

Net value fed into quantum (per crop):

```text
v = yield_t_ha × area_ha × price_Rs/quintal × 10  −  cost_Rs/ha × area_ha
```

SPARQ **warm-starts** from this value matrix. It does **not** recompute yield.

---

## 2. Why quantum at all? (rotation ≠ sort)

Ranking crops by standalone profit is `sorted()`. That is **not** what SPARQ solves.

A crop’s **realised** value depends on what was planted before it (legume → cereal N credit, pest break, monoculture penalty). Objective:

```text
maximise  Σ_t  base[c_t]
               × yield_multiplier[family(c_{t-1})][family(c_t)]
               × (same_crop_penalty if c_t == c_{t-1})
          +     N_credit_rupees[c_{t-1}]
```

That is a **quadratic assignment / sequencing** problem → native QUBO shape. Config tables live in `backend/models/v1/rotation.yaml`.

**Classical baselines** (same score function, for the comparison board):

| Baseline | Function | Meaning |
|---|---|---|
| Exact | `brute_force_rotation` | Optimum at demo scale |
| Sort by profit | `greedy_sort_rotation` | Naive “best crop first” |
| Greedy look-ahead | `greedy_myopic_rotation` | Stronger classical heuristic |

---

## 3. SPARQ — the quantum algorithm

**Name:** **S**implex-**P**reserving **A**daptive **R**isk-aware **Q**AOA  
**File:** `backend/app/quantum/sparq.py`  
**Device:** PennyLane `default.qubit` (simulator — no cloud QPU required for demo)

Replaces legacy transverse-field QAOA (`quantum_optimizer.py`), which sampled nearly at random on this problem (feasible rate ~3%, uplift vs uniform ~1.8×).

### Four design moves

| # | Technique | What it does |
|---|---|---|
| 1 | **Simplex preservation** | Each **season** (or plot) is a qubit block in Hamming-weight-1. An **XY ring mixer** (`qml.IsingXY`) conserves that weight → **exactly one crop per season by symmetry**, not by penalty. |
| 2 | **Value-gradient warm start** | Block amplitudes ∝ √softmax(μ / τ), τ = 0.35. LightGBM net values seed the quantum prior. |
| 3 | **Zero slack qubits** | One-crop constraint is structural; water/budget use unbalanced penalisation → `n_qubits == n_decision`. |
| 4 | **INTERP layerwise growth** | Train depth p=1 → grow to p=2 → p=3 (Zhou et al.). Real optimisation trace for the UI chart. |

### Circuit parameters

| Parameter | Value |
|---|---|
| Init | Weighted Dicke-1 (generalised W) per block |
| Mixer | Native `IsingXY` ring (must **not** Trotterise as separate XX+YY — that breaks the invariant) |
| Cost layer | Diagonal QUBO Hamiltonian (`qml.qaoa.cost_layer`) |
| Depth | INTERP p = 1 → 2 → 3 |
| Classical outer loop | COBYLA, ~60 iters/stage |
| Train objective | CVaR of QUBO energy at α = 0.25 |
| Shots | 2048 final / 256 during training |
| Timeout | `QAOA_TIMEOUT_S` (default 10 s) → classical fallback |

### Benchmark (50 instances, 3×3, p=3) — `models/v1/benchmark.json`

| Metric | SPARQ | Legacy QAOA |
|---|---|---|
| Qubits | **9** | 11 (with slack) |
| Simplex rate (one crop / block) | **100%** | not enforced |
| Feasible rate (all constraints) | **~61%** | ~3% |
| Uplift vs 2ⁿ uniform | **~98×** | ~1.8× |
| Uplift vs feasible uniform | **~5.2×** | ~0.1× |
| Optimum match | **94%** | ~92% |
| Wall clock | **~2.2 s** | ~3.3 s |

**Honest claim:** simulated SPARQ/QAOA recovers the exact optimum at demo scale. **No runtime quantum advantage** is claimed at n ≤ 25 qubits.

---

## 4. Risk-aware objective (allocation path)

**File:** `backend/app/quantum/risk.py` · QUBO builder: `qubo.py` → `build_simplex_qubo`

Used when allocating **plots × crops** under water/budget (plan API). Rotation ranking uses the sequencing objective in §2; risk bands still come from LightGBM P10/P90.

```text
maximise   Σᵢ μᵢ xᵢ  −  κ · Σᵢⱼ Cov(vᵢ, vⱼ) xᵢ xⱼ
```

| Piece | Detail |
|---|---|
| σ from bands | `(P90 − P10) / (2 · z₀.₉₀)`, z₀.₉₀ ≈ 1.282 |
| Cross-crop ρ | ~0.45 (`risk_cross_crop_rho`) |
| κ | Risk aversion (0 = ignore variance) |

Variance is **quadratic in x**, so mean–variance is a native QUBO term (not a post-hoc chart decoration).

---

## 5. Encodings & fallbacks

| Encoding | Builder | Slack qubits | Used by |
|---|---|---|---|
| `simplex` | `build_simplex_qubo` | none | SPARQ (plot allocation) |
| `rotation_simplex` | `build_rotation_qubo` | none | SPARQ (crop order / Quantum Lab) |
| `slack` | `build_qubo` | water + budget bits | Legacy QAOA only |

**Classical fallback** (`classical_fallback.py`): brute force (n ≤ 20) + simulated annealing. Quantum and classical run every request; timeout → `solver: "classical_fallback"`.

---

## 6. Survival sliders (Quantum Lab)

Farmer framing: *mazhai varalana?* / *uram vela eriducha?*  
Jury framing: live combinatorial re-optimisation.

| Slider | Backend field | Effect |
|---|---|---|
| **Available water** | `water_available_m3` | Hard gate: crop needs `water_m3_per_ha × area` ≤ available. Cut water → **paddy** (~6500 m³/ha) drops; **black gram / groundnut** stay. |
| **My budget** | `budget_rs` | Hard gate: `cost_rs_per_ha × area` ≤ budget. Cuts sugarcane/paddy first. |

What-if runs use `persist: false` so slider drags do not write a new `rotation_plan` row every time.

Then SPARQ re-sequences whatever crops still pass the gates.

---

## 7. Module map

| Path | Responsibility |
|---|---|
| `app/ml/` | LightGBM features, predict, SHAP |
| `app/services/crop_feasibility.py` | Soil / water / budget gates |
| `app/services/rotation_service.py` | Full farm pipeline orchestrator |
| `app/quantum/sparq.py` | **SPARQ** ansatz + INTERP + sampling |
| `app/quantum/rotation.py` | Season×crop QUBO + classical baselines |
| `app/quantum/qubo.py` | Slack + simplex QUBO, feasibility |
| `app/quantum/risk.py` | μ / Cov / CVaR report |
| `app/quantum/quantum_optimizer.py` | Legacy transverse-field QAOA |
| `app/quantum/classical_fallback.py` | Brute force / SA |
| `app/quantum/benchmark.py` | Head-to-head metrics |
| `models/v1/crops.yaml` | Water, cost, rotation families |
| `models/v1/rotation.yaml` | Yield multipliers, N credit |
| `models/v1/benchmark.json` | Frozen SPARQ benchmark numbers |
| `models/v1/metrics.json` | LightGBM eval protocols |

Offline bench: `python -m scripts.benchmark_qaoa`  
Flutter UI: **Quantum** tab (`flutter_app/lib/features/quantum/`)

---

## 8. What we claim / do not claim

| We claim | We do **not** claim |
|---|---|
| Quantum-ready combinatorial formulation (QUBO) | Quantum speedup at demo n |
| SPARQ concentrates on good feasible plans (~5× vs feasible-uniform) | Quantum ML for yield |
| Mean–variance / rotation couplings inside the QUBO | “The QUBO optimises CVaR as the farmer-facing score” |
| Side-by-side classical + legacy QAOA for honesty | That sorting by profit is the same as sequencing |

**Stage rule:** if it isn’t backed by a number in `benchmark.json` or `metrics.json`, don’t say it.

---

## 9. One-line summary

> **LightGBM** predicts how much each crop yields on this farm; **SPARQ** (simplex-preserving XY-ring QAOA on PennyLane) searches the **order** of crops across seasons under water and budget — a quadratic problem where sorting alone is wrong — and the Quantum Lab sliders re-run that search live.
