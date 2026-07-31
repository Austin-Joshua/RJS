# High Yield Crop Prediction using Quantum AI — Product Requirements

**Status:** built. Companion doc: [`TRD.md`](TRD.md) — technical detail.

A digital guidebook for new and inexperienced farmers. The farmer enters their
land and soil readings; the app tells them which crops will grow there, in what
order to plant them across the year, and what the soil needs first.

---

## 1. The user flow

| # | Step | Where |
|---|---|---|
| 1 | **Sign in with Google** | `SignInPage` → Clerk with Google as the social connection |
| 2 | **Add a farm** — location, land size, soil readings | `AddFarmScreen` → `POST /farms` |
| 3 | **Soil card** — the readings classified Low/Medium/High | `SoilCardView`, shown immediately on save |
| 4 | **Feasible crops** — which crops can grow here, and why not the others | `GET /farms/{id}/feasible-crops` |
| 5 | **Quantum-ranked crop order** — best first, across three seasons | `POST /farms/{id}/rank` |
| 6 | **Soil treatment** — fertiliser bags, pH correction, irrigation | shipped with the ranking |
| 7 | **Repeat per farm** — N farms per account, each independent | `FarmListScreen` |
| 8 | **Dashboard** — all farms, soil status, rankings, value | `GET /dashboard` |

Sign-out is in the account menu on every screen, closing the loop.

---

## 2. The division of labour

```
soil card ─▶ feasibility gates ─▶ CLASSICAL yield model ─▶ QUANTUM sequencing ─▶ advisory
             (agronomic rules)     (LightGBM)               (SPARQ)              (rules)
```

- **Classical** decides *which* crops are possible and *how much* each is worth
  on its own. Both are filtering/prediction problems where explicit rules and
  gradient boosting are the right tools.
- **Quantum** decides the *order*. That is the only genuinely combinatorial
  step, and §4 explains why.

---

## 3. Why the quantum step is not decoration

Ranking crops by predicted profit is `sorted()`. Wrapping a quantum optimiser
around a sort would be cosmetic, which the brief explicitly forbids.

Crop **sequencing** is a different problem. A crop's realised yield depends on
what preceded it:

- A cereal after a legume out-yields the same cereal after itself — broken pest
  cycles, inherited nitrogen, better soil structure.
- The same crop twice running carries a documented monoculture penalty.
- Legumes leave nitrogen credit the next crop can spend on less urea.

So the value of assigning crop *c* to season *t* depends on the assignment at
season *t−1*, the objective is **quadratic in the decision variables**, and the
best sequence is not the sort of the individual values.

**Measured, 60 random farms (3 seasons × 4 crops):**

| Classical baseline | Gives a suboptimal plan | Mean cost | Worst case |
|---|---|---|---|
| Rank by predicted profit (a sort) | **65%** of farms | ₹5,475 | ₹32,762 |
| Greedy, one step of lookahead | **50%** of farms | ₹5,201 | ₹21,820 |

Even a *smart* greedy heuristic that uses the rotation effect is wrong half the
time. That is the case for searching the order rather than sorting it.

---

## 4. Quantum requirements, and how each is met

| Requirement | How |
|---|---|
| Operates on the crop-ranking sub-problem | `build_rotation_qubo` — x[season][crop], 12 qubits at 3×4 |
| No placeholder logic; output must beat random | One crop per season in **100%** of samples, by symmetry. Recovers the exact optimum **25/25**. Sampled plans score **0.81** on a worst-to-best quality scale against **0.50** for uniform random, and **every** instance beats random — see §4a for the honest limit |
| Correct circuit construction | `IsingXY` applied as a native gate, not Trotterised — Hamming weight per season block is provably conserved. Guarded by `test_xy_mixer_conserves_one_crop_per_plot` |
| Efficient qubit use | Zero slack qubits: `n_qubits == n_decisions`. Season eligibility is a linear term, coupling only between adjacent seasons |
| Visible in the app | Circuit diagram, gate counts, measured outcome distribution, and the live optimisation trace — all in `QuantumPanel` |
| Classical/quantum split explainable | §2 above, stated in the UI and in the payload's `claim` string |

**The ranking is read directly off the measurement distribution.** The
most-measured feasible bitstring is rank 1; nothing is re-sorted classically
afterwards.

### 4a. Where the concentration claim stops

P(exact optimum) averages ~10x uniform, but on instances where the top few
sequences sit within ~2% of each other it can fall to ~1x — i.e. for that
bitstring specifically, indistinguishable from random. On a near-flat landscape
a spread distribution is the correct response rather than a failure, and the
returned plan is still the best sampled one. But the honest headline is plan
*quality* (0.81 vs 0.50, every instance), not P(exact optimum), and the claim
string served to the app says exactly that. `test_sampled_plans_are_better_than_random`
guards the robust metric; guarding the fragile one would produce a flaky test
and a claim we could not always defend.

---

## 5. Personalisation and isolation

- Every route resolves the farm through `load_owned_field`, which 404s an
  unknown id and 403s another account's farm. Isolation is a property of the
  routing layer, not something each handler must remember.
- Farm lists and the dashboard filter by `farmer_id` **in the query**, so
  another account's rows never reach the aggregation step.
- The farmer's own soil readings become that farm's `soil_override`, so two
  farms in the same district get different predictions.
- Client providers are keyed by farm id and auto-dispose — switching farms
  cannot show the previous farm's card or ranking.

Covered by `test_n_farms_per_account_stay_independent`,
`test_accounts_are_isolated`, and `test_dashboard_aggregates_only_this_account`.

---

## 6. No mocked data

Removed outright: the `demo-farmer` / `demo-officer` bearer tokens, `DEMO_MODE`
and its fixture JSON, the bundled demo field assets, the hardcoded soil values
in the old scanner screen, and the client-side offline cache that served them.

Tests authenticate by overriding the auth dependency in `conftest.py` — a
harness concern that ships in no build, rather than an auth hole that ships in
every build. `test_every_farm_route_requires_auth` asserts all seven farm
routes 401 without a session.

Bundled *reference* data stays: Soil Health Card district baselines, crop
agronomy (`crops.yaml`), rotation effects (`rotation.yaml`), and modal prices.
That is a lookup table with a citation, not fabricated output.

---

## 7. Defects found and fixed along the way

Three pre-existing bugs made every rupee figure in the app wrong. Each is now
covered by a regression test.

| Defect | Effect | Fix |
|---|---|---|
| **Training/serving skew.** Training rows aggregated a whole crop year; inference sent season-to-date totals. `gdd` arrived as 960 against a training range of 6,336–7,054 | Model extrapolated off a cliff — maize at **51 t/ha** against a trained maximum of 4.98 | Window-dependent features became rates (`gdd_per_day`, `rainfall_mm_per_day`, …). Three separate feature-row implementations collapsed into the one `build_feature_row` |
| **Weather sentinel poisoning.** Open-Meteo and NASA POWER signal missing data with `-999`, not null; only nulls were filtered | −37 °C mean season temperature, −62 mm/day rainfall, fed straight to the model | `_clean` filters to physical bounds in both adapters; too few valid days is a degraded fetch, not a usable one |
| **Quantile heads crossing.** P10 could exceed the point estimate | Paddy showed "17.66 t/ha (P10 31.19)" — a band that excluded its own estimate | Serving guarantees the bracket and flags when it had to widen |

Also fixed: `DELETE /fields/{id}` returned 500 on Postgres (missing cascade —
SQLite's unenforced foreign keys hid it from the test suite), and "latest soil
card" ordering was arbitrary when two cards shared a timestamp (Windows clock
granularity is ~15 ms; now an explicit per-farm version counter).

A second pass found five more:

| Defect | Effect | Fix |
|---|---|---|
| `INTERNET` was declared only in the debug and profile manifests | A **release APK could make no API calls at all** — every screen empty. Debug runs worked, hiding it | Declared in the main manifest, verified present in the built APK |
| No location permission, but the add-farm screen calls `geolocator` | "Use my current location" fails at runtime | `ACCESS_COARSE/FINE_LOCATION` declared, hardware marked optional |
| Black gram gated on drainage | Clay is the commonest Cauvery delta soil and black gram is *its* standard rice-fallow crop — so delta farmers got one feasible crop and no plan, contradicting our own `crops.yaml` note | Removed from the hard gate, kept as a caution; groundnut and maize stay gated where it is agronomically real |
| One feasible crop returned only an error | The useful answer — "grow paddy" — was withheld | Returns a plan on a `single_candidate` path, and runs **no circuit**: a one-element search space has nothing to optimise, and running one anyway would be the decorative use this design avoids |
| Circuit diagram showed `θ=1.24` where the circuit applied `θ=0.78` | §3 asks for the quantum step to be transparent; a wrong gate parameter is worse than none | Diagram replays `_prepare_block`'s actual recurrence |

Four unused dependencies (`flutter_tts`, `flutter_map`, `latlong2`,
`path_provider`) were left over from the previous app and are removed.

---

## 8. Verification

| | |
|---|---|
| Backend | 55 tests — quantum invariants, ML skew guards, API contract, isolation |
| Flutter | 12 tests, `flutter analyze` clean |
| End-to-end | `python pipeline.py` runs the full flow against live weather and Sentinel-2 |
| Contract | Every key the Flutter models read is asserted present in live API payloads |

**Yield model** (623 real district-crop-year rows, DES/ICRISAT + Open-Meteo +
MODIS): R² 0.960 random split, 0.941 grouped-CV by district, 0.961 temporal
holdout. The honest caveat is that lift over a district-crop-mean baseline is
only ~1%, and R² is flattered by sugarcane's 100 t/ha scale dominating the
variance — district-level aggregates are a weak signal for a specific farm.

---

## 9. Known limitations

- **Seasonal disaggregation.** The public DES source reports one figure per crop
  per district per *crop year*, so every training row is `whole_year`. The model
  cannot yet learn an intra-year seasonal effect; season enters the ranking
  through agronomic eligibility rules, not learned yield.
- **Sugarcane is excluded from rotation** — a 12-month crop occupies the land
  for the whole cycle. It still appears in the feasibility list as a standalone
  annual choice.
- **Five crops, five districts.** Bounded by the source export.
- **Simulator only.** No quantum hardware execution, and no runtime advantage
  over classical search is claimed at this qubit count.
