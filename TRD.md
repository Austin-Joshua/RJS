# Technical Requirements — Quantum-AI Crop Advisor

Companion to [`PRD.md`](PRD.md). Flutter + FastAPI + SQLAlchemy, PennyLane for
the quantum layer, LightGBM for yield.

---

## 1. Architecture

```
Flutter (Riverpod)
  SignInPage ─ Clerk/Google
  FarmListScreen ─▶ AddFarmScreen ─▶ FarmDetailScreen ─▶ QuantumPanel
  DashboardScreen
        │  Clerk session JWT on every request
        ▼
FastAPI  /api/v1
  farms.py      add farm, soil card, feasible crops, rank, advisory
  dashboard.py  cross-farm aggregation
        ▼
  services/   soil_card · crop_feasibility · rotation_service · advisory · fusion
  ml/         features · yield_model            (classical: filter + predict)
  quantum/    rotation · sparq · qubo           (quantum: order)
        ▼
SQLAlchemy — Farmer, Field, SoilCard, RotationPlan  (SQLite dev / Postgres prod)
```

---

## 2. The quantum layer

### 2.1 Why a QUBO

Assign one crop to each season of the cycle. With `x[(season, crop)] ∈ {0,1}`:

```
maximise  Σ_t  base_value[c_t]
               × yield_multiplier[family(c_{t-1})][family(c_t)]
               × (same_crop_penalty if c_t == c_{t-1})
          +    n_credit_rupees[c_{t-1}]
```

The multiplier term couples **adjacent seasons**, making the objective
quadratic. Drop it and the problem separates into independent per-season picks
that need no optimiser at all — which is exactly why the coupling is the
justification for the quantum step, not decoration on top of it.

Coefficients live in `models/v1/rotation.yaml` and are echoed back in every API
response under `rotation_model`, so the numbers used are inspectable.

### 2.2 SPARQ — the ansatz

`app/quantum/sparq.py`. Originally built for crop-per-plot allocation; crop-per-
season is the same simplex structure, so it transfers unchanged.

| Element | Choice | Why |
|---|---|---|
| Initial state | Weighted Dicke-1 (generalised W) per season block | Exactly one crop per season before any layer runs |
| Warm start | amplitudes ∝ √softmax(base_value / τ), τ = 0.35 | The LightGBM values seed the quantum prior — classical output as *input*, keeping quantum off the prediction path |
| Mixer | XY ring per block via `qml.IsingXY` | Conserves Hamming weight per block |
| Cost layer | `qml.qaoa.cost_layer` | Diagonal, so exact — no Trotter error |
| Depth | INTERP growth p=1→2→3 (Zhou et al.) | Converges better than a cold start, and yields a real trace |
| Optimiser | COBYLA, 60 iters per stage, CVaR α=0.25 | Best-quartile objective; best schedule retained so a timeout still leaves a usable circuit |
| Sampling | 2048 shots, filter to feasible, take max objective | |

> **The mixer must be a native gate.** `qml.qaoa.mixer_layer` Trotterises XX and
> YY as separate Pauli words, and XX *alone* maps |00⟩→|11⟩ — that silently
> destroys the symmetry the whole design rests on. `qml.IsingXY` annihilates
> |00⟩ and |11⟩ and rotates only within {|01⟩,|10⟩}. Guarded by
> `test_xy_mixer_conserves_one_crop_per_plot`, which asserts every sampled
> bitstring has weight exactly 1 in every block.

### 2.3 Measured

Rotation sequencing, 3 seasons × 4 crops, 12 qubits, p=3:

| Metric | Value |
|---|---|
| One crop per season | **100%** (structural) |
| Recovers exact optimum | **25/25** instances |
| Top measured outcome | 54–70% of the distribution (uniform would be 1/64) |
| Wall clock | ~2.2 s |

Allocation mode (`build_simplex_qubo`, 50 instances at 3 plots × 3 crops) also
retains its head-to-head against the previous transverse-field QAOA: 98.5×
distribution uplift vs 1.8×, 61.4% feasible vs 2.9%, 9 qubits vs 11.

### 2.4 Baselines

Every `/rank` response ships three comparisons, computed on the same instance
and scored by the same `sequence_value`:

- `exact` — exhaustive search over C^T sequences, the ground truth.
- `sorted_by_yield` — rank by standalone profit. The naive reading of "rank the
  crops", and the thing the quantum step has to beat.
- `greedy_with_lookback` — pick each season using the previous choice. The
  steel-man classical heuristic.

---

## 3. Classical layer

### 3.1 Soil card (`services/soil_card.py`)

Farmer readings → ICAR Low/Medium/High. Thresholds in one table:
N <280/560, P <10/25, K <120/280, OC <0.5/0.75. Plus pH bands, EC salinity
bands, and water availability anchored on real crop demand (black gram
1,800 m³/ha, paddy 6,500).

### 3.2 Feasibility (`services/crop_feasibility.py`)

Hard gates: pH tolerance, salinity tolerance, season water sufficiency,
drainage vs texture. Low nutrients are a **warning, not a gate** — that is a
reason to fertilise, not to rule a crop out.

Failures and passes are collected separately so an excluded crop's first listed
reason is why it failed, never an unrelated check it happened to pass.

### 3.3 Yield model (`ml/`)

LightGBM on `log1p(yield)`, 623 real district-crop-year rows. Two quantile heads
for the P10–P90 band.

**Features are window-invariant by construction.** Training aggregates a whole
crop year; inference runs mid-season. Every cumulative quantity is stored as a
rate — `gdd_per_day`, `rainfall_mm_per_day`, `et0_mm_per_day`,
`ndvi_auc_per_day`, `dry_spell_frac` — so a 45-day window and a 365-day window
describe the same field the same way. `test_features_are_window_invariant`
and `test_no_cumulative_features_remain` guard this.

`build_feature_row` is the **only** implementation. `build_training_set.py` and
`yield_service.py` both call it; `train_model.py` reads the columns straight
from the CSV without re-deriving them. There were previously three
implementations, and only two agreed.

### 3.4 Adapters

Weather (Open-Meteo, NASA POWER fallback) and NDVI (Sentinel-2 via Earth
Engine). Both weather paths filter to physical bounds — providers signal missing
data with `-999` as well as null, and a sentinel that reaches an aggregate
poisons every feature derived from it. Under `MIN_VALID_DAYS` valid readings the
fetch is treated as degraded, not usable.

---

## 4. API

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/healthz` | liveness, `model_loaded`, `auth_configured` |
| `POST` | `/farms` | create farm + first soil card, returns both |
| `GET` | `/farms` | this account's farms |
| `GET`/`DELETE` | `/farms/{id}` | detail / delete (cascades) |
| `POST`/`GET` | `/farms/{id}/soil-card` | new reading / latest + history |
| `GET` | `/farms/{id}/feasible-crops` | shortlist with reasons |
| `POST` | `/farms/{id}/rank` | the money endpoint — feasibility → yield → quantum order → advisory |
| `GET` | `/farms/{id}/rotation-plan` | last saved ranking |
| `GET` | `/dashboard` | cross-farm aggregation |

Auth on everything except `/healthz`. No bypass token exists.

---

## 5. Persistence

```
Farmer ──< Field ──< SoilCard      (append-only, version counter)
                 ──< RotationPlan  (sequence, quantum evidence, baselines, advisory)
                 ──< Plot / Plan / RasterAsset
```

`Field` cascades to all children. Ordering uses an explicit `version` counter
rather than `created_at`: Windows clock granularity is ~15 ms, so two cards
saved in succession share a timestamp and "latest" becomes arbitrary.

---

## 6. Configuration

```
CLERK_JWT_KEY=            CLERK_PUBLISHABLE_KEY=     CLERK_AUTHORIZED_PARTIES=
DATABASE_URL=             MODEL_VERSION=v1
GEE_PROJECT_ID=           GOOGLE_APPLICATION_CREDENTIALS=
SPARQ_LAYERS=3            SPARQ_WARM_START_TAU=0.35  SPARQ_SHOTS=2048
QAOA_TIMEOUT_S=10         RISK_KAPPA=0.35            RISK_CROSS_CROP_RHO=0.45
```

Google Sign-In is configured on the Clerk instance (Dashboard → SSO
connections → Google), so no code change is needed to enable it. Add a custom
session claim for role:
`{"role": "{{user.public_metadata.role}}", "email": "{{user.primary_email_address}}"}`.

---

## 7. Testing

| Layer | Coverage |
|---|---|
| Quantum | Hamming-weight conservation per block; rotation value is order-dependent; sorting measurably suboptimal; SPARQ recovers the exact optimum; circuit + measurements exposed; N-credit sign |
| ML | Window invariance; no cumulative features; band brackets the estimate; predictions inside the trained range; weather sentinel filtering |
| API | Every farm route 401s unauthenticated; full flow; N farms independent; two accounts isolated; dashboard scoped |
| Flutter | Payload parsing for every model; currency formatting; no bypass path on the sign-in screen |

Run: `pytest` (55), `flutter test` (12), `python pipeline.py` (end-to-end).

---

## 8. Running it

```bash
# backend
cd backend && python -m scripts.build_training_set && python -m scripts.train_model
uvicorn app.main:app --reload

# app
cd flutter_app
flutter run --dart-define=CLERK_PUBLISHABLE_KEY=pk_... --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

`python pipeline.py` runs the whole flow in one process and prints the soil
card, the feasibility verdicts, the ranked rotation, the sort-gap comparison,
and the circuit summary.
