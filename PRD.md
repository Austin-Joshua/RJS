# FarmSync — Product Requirements Document

**Project:** FarmSync (Quantum 2.0 hackathon, problem QT-2.14)
**Doc owner:** Christopher
**Status:** v1.0 — approved scope for hackathon build
**Companion doc:** [`TRD.md`](TRD.md) — technical requirements
**Source of truth:** [`FARMSYNC_BRIEF.md`](FARMSYNC_BRIEF.md) — if this doc and the brief disagree, the brief wins

---

## 1. One-line pitch (fixed — do not reword)

> Zero-hardware data fusion — government soil cards, live weather, and satellite NDVI — feeds a classical yield model, and a quantum optimiser turns those predictions into the best resource plan for each field, right on a smartphone.

---

## 2. Problem

An Indian smallholder farming 1–3 acres makes four decisions every season that determine whether the year is profitable: **what to plant, how much water to allocate, how much fertilizer to buy, and when.** Today those decisions are made on habit and neighbour consensus.

Precision-agriculture products that could inform those decisions have a structural flaw for this user: **they assume sensors.** Soil-moisture probes, weather stations, and IoT gateways cost ₹15,000–₹80,000 per farm plus connectivity and maintenance. At 1–3 acres the payback never arrives. The result is that the farmers with the least margin for error get the least decision support.

There is a second, subtler failure. The advice that *is* available is single-variable — "your nitrogen is low, apply urea" — and ignores that the farmer's real problem is **allocation under scarcity**. They do not have enough water for every plot, enough cash for full-dose fertilizer on every crop, or enough land for every crop they'd like to grow. Optimal advice per-plot, summed, is not an optimal farm plan.

FarmSync attacks both: **remove the hardware**, and **treat the season as a constrained optimisation problem rather than a list of independent tips.**

---

## 3. Solution

Three public, already-existing data sources are fused into a per-field feature vector. A classical regressor predicts yield. A quantum optimiser searches the combinatorial space of crop-and-resource plans against that prediction, under the farmer's actual water, land, and cash constraints. The winning plan becomes plain-language advisory on a phone.

```
  Soil Health Card  ┐
  Weather API       ├─▶ Feature fusion ─▶ CLASSICAL yield model ─▶ net-value matrix ─▶ QAOA optimiser ─▶ Plan ─▶ Advisory
  Sentinel-2 NDVI   ┘                     (LightGBM, owns 35%)     (resources enter)   (owns Innovation 20%)   (dosage,
                                                                                                                pH, crop,
                                                                                                                irrigation)
```

**Zero hardware installed at the farm.** The only device required is the smartphone the farmer already has.

---

## 4. The architectural decision that protects the score

**Quantum does optimisation, not prediction.**

Yield estimation is a regression problem on tabular data with ~15 features. A quantum classifier or quantum kernel method there would be the wrong tool for the job, would underperform a gradient-boosted tree, and would therefore **bleed the 35% Prediction Accuracy criterion** — the single heaviest item on the rubric. So the quantum layer is kept strictly off the prediction path.

Resource allocation is the opposite case: a genuine NP-hard combinatorial problem (multi-dimensional knapsack with assignment constraints) where QAOA is a *legitimate*, textbook-appropriate method. That is where the quantum layer lives, and it earns Innovation on merit rather than on decoration.

| Layer | Method | Owns | Never touches |
|---|---|---|---|
| Yield prediction | LightGBM regressor | Prediction Accuracy (35%) | Anything quantum |
| Plan optimisation | QAOA, PennyLane simulator | Innovation (20%) | Yield numbers |
| Advisory | Deterministic agronomic rules | Practical Impact (20%) | Both — it consumes their outputs |

---

## 5. Claims discipline

The team says these things. They survive a technical judge.

- Regression is the right tool for yield; QAOA is the right tool for allocation. The split is deliberate, not decorative.
- On a simulator at demo scale, QAOA **matches** the brute-force optimum. We claim **quantum-ready**, not **quantum advantage**.
- QAOA biases the output distribution toward low-energy (good) solutions; we sample repeatedly and keep the best feasible bitstring.
- The classical fallback solver exists, is always run, and its result is shown alongside. We are not hiding the comparison.

The team **does not** say these things. They get shredded.

- ❌ "Ry gates keep amplitudes real, making the optimiser faster/more stable." — False.
- ❌ "Entanglement understands why the plant is stressed." — Use classical SHAP for explanation instead.
- ❌ Any phrasing that implies a speedup over the classical solver at this scale. There isn't one, and claiming it invites the one question that ends a demo.

**Rule for the whole team:** if a claim about the quantum layer cannot be backed by a number in `benchmark.json`, it does not get said on stage.

---

## 6. Users

### Persona A — Murugan, 52, smallholder (primary)

3 acres in Thanjavur district, TN. Paddy in samba season, black gram after. Android phone (₹9,000, 3 GB RAM, Android 12), 4G that drops in the field. Reads Tamil comfortably, English haltingly. Has a Soil Health Card in a drawer and has never acted on it because the numbers mean nothing to him.

**Needs:** what to plant, how much urea to actually buy, whether his water will stretch. In rupees and bags, not in kg/ha and NDVI.
**Fails if:** the app needs signal in the field, is English-only, or shows him a chart instead of an answer.

### Persona B — Kavitha, 34, agri-extension officer (secondary)

Covers ~40 farms for the state agriculture department. Needs to triage which fields are in trouble this week and justify her recommendations with something defensible.

**Needs:** a field list ranked by risk, NDVI trend, and the "why" behind each recommendation.
**Fails if:** she can't see the reasoning, or can't export it.

### Persona C — the judge (real, and the one being optimised for this month)

Technical. Will ask: *what is your R²*, *how do you know it's not leaking*, *what does the quantum part actually do*, *is it faster*, *where does the data come from*.

**Needs:** honest numbers, a visible benchmark, a working demo.
**Fails if:** metrics are hardcoded, the eval protocol is random K-fold on district data, or the quantum layer turns out to be decorative.

---

## 7. User journeys

### J1 — First field, first plan (Murugan, ~4 minutes)

1. Opens app → picks **தமிழ்** → signs in with phone OTP.
2. **Add field** → GPS drops him on his location → he walks the boundary with "Walk boundary" or taps 4 corners on the satellite map.
3. App auto-fills **district** from the centroid → pulls his Soil Health Card district baseline (N, P, K, pH, OC) → shows it as *Low / Medium / High* chips, not raw numbers.
4. He enters what he *has*: water available, land, cash budget. Three sliders.
5. Taps **Get my plan**. ~8 seconds.
6. **Plan screen:** "Plot 1 & 2 → paddy (ADT-45). Plot 3 → black gram. Expected: ₹1,42,000 net." Plus the honest band: "between ₹1.18L and ₹1.63L."
7. **Advisory screen:** "Buy 4 bags urea, 2 bags DAP, 1 bag MOP. Apply 2 bags urea at planting, 2 at tillering." With the *why* one tap away.

### J2 — Mid-season check (Murugan, ~40 seconds)

Opens app → field card shows **NDVI trend falling** → red band: "Greenness dropping in the north-east corner over 12 days. Check for water stress or pest." → tap for the NDVI map overlay.

### J3 — Weekly triage (Kavitha, ~5 minutes)

Field list sorted by risk score → the three red ones → each shows NDVI slope, rainfall deficit, and predicted-yield delta vs. district mean → she exports a PDF for her visit report.

### J4 — Judge walkthrough (demo day, 6 minutes)

Live app on a phone, mirrored → pre-seeded Thanjavur field → plan generated live → **Analytics tab**: model metrics from `metrics.json` (not hardcoded), yield-vs-rainfall chart, SHAP feature importance → **Quantum tab**: QUBO size, qubit count, QAOA vs. brute-force optimum, approximation ratio, and the honest statement that no speedup is claimed.

---

## 8. Functional requirements

Priority: **M** = must (hackathon MVP), **S** = should, **C** = could (roadmap).

### Onboarding & identity

| ID | Requirement | Pri |
|---|---|---|
| FR-01 | Phone-OTP sign-in via Supabase Auth; demo bearer tokens (`demo-farmer`, `demo-officer`) work without Supabase | M |
| FR-02 | Language selection English / தமிழ் at first launch, changeable in Settings; all farmer-facing strings localised | M |
| FR-03 | Two roles — `farmer` (own fields) and `officer` (assigned fields, read-only) — enforced server-side, not just in the UI | M |

### Field management

| ID | Requirement | Pri |
|---|---|---|
| FR-10 | Create a field by tapping vertices on a satellite basemap | M |
| FR-11 | Create a field by GPS "walk the boundary" trace, with point simplification | S |
| FR-12 | Auto-derive centroid, bbox, and area (acres + hectares) from the boundary polygon | M |
| FR-13 | Auto-resolve district and state from the centroid (offline shapefile lookup, no network) | M |
| FR-14 | List, rename, and delete fields; a farmer sees only their own | M |
| FR-15 | Manual override of the district-level soil baseline when the farmer has a personal SHC or lab report | S |

### Data fusion (the headline)

| ID | Requirement | Pri |
|---|---|---|
| FR-20 | Fetch soil baseline (N, P, K, pH, OC, EC) for the field's district from bundled Soil Health Card data — must work fully offline | M |
| FR-21 | Fetch weather (temp, humidity, rainfall, ET₀) for the centroid, historical season-to-date plus 7-day forecast | M |
| FR-22 | Compute NDVI statistics from cloud-masked Sentinel-2 for the boundary polygon over the season window | M |
| FR-23 | Every response carries a `data_mode` field: `live`, `degraded` (a source unavailable or too cloudy), or `demo` — surfaced in the UI as a badge, never hidden | M |
| FR-24 | Cache all three sources with per-source TTL; a cached plan remains viewable with no network | M |
| FR-25 | Render NDVI as a map overlay on the field boundary | S |

### Yield prediction

| ID | Requirement | Pri |
|---|---|---|
| FR-30 | Predict yield (t/ha) per candidate crop for a field from the fused feature vector | M |
| FR-31 | Return a prediction interval (P10–P90) alongside the point estimate; the UI always shows the band | M |
| FR-32 | Return per-prediction SHAP contributions so "why this number?" is answerable | M |
| FR-33 | Serve live model metrics (RMSE, MAE, R², grouped-CV R², temporal-holdout R²) from the trained artifact — **no hardcoded numbers anywhere in the app** | M |
| FR-34 | Degrade gracefully when NDVI is missing — LightGBM handles the NaN natively; response flags reduced confidence | M |

### Quantum optimisation

| ID | Requirement | Pri |
|---|---|---|
| FR-40 | Accept farmer constraints: total water (m³), total land (ha, per plot), cash budget (₹) | M |
| FR-41 | Build the net-value matrix from predicted yield × plot area × crop price − input cost | M |
| FR-42 | Encode the allocation problem as a QUBO with slack-variable inequality handling, 6–9 qubits at demo scale | M |
| FR-43 | Solve with QAOA on the PennyLane simulator; sample the distribution and keep the best **feasible** bitstring | M |
| FR-44 | Always run the classical solver too, and return both results in the same response for honest comparison | M |
| FR-45 | Return a benchmark payload: qubit count, QUBO terms, QAOA objective, classical optimum, approximation ratio, wall-clock for each | M |
| FR-46 | Hard timeout on the quantum path; on breach, return the classical plan with `solver: "classical_fallback"` — the farmer always gets a plan | M |

### Advisory (the farmer-visible output)

| ID | Requirement | Pri |
|---|---|---|
| FR-50 | Fertilizer recommendation converted to **retail units** — bags of urea / DAP / MOP — with a split-application schedule by crop stage | M |
| FR-51 | pH correction advice (lime or gypsum, t/ha) with an explicit "confirm with a lab test" caveat | M |
| FR-52 | Irrigation guidance from ET₀ × crop coefficient minus effective rainfall | S |
| FR-53 | Crop selection and per-plot assignment, rendered from the optimiser's plan | M |
| FR-54 | Every recommendation has a **"Why this?"** expansion showing the driving inputs | M |
| FR-55 | All advisory text available in Tamil | M |

### Analytics dashboard (half the deliverable — do not skip)

| ID | Requirement | Pri |
|---|---|---|
| FR-60 | Input panel: soil, weather, and NDVI values actually used for this field, with source and timestamp per value | M |
| FR-61 | Predicted yield with the uncertainty band, plotted | M |
| FR-62 | The QAOA plan rendered as a plot-by-plot allocation table | M |
| FR-63 | Chart — yield vs. rainfall across the training set, with this field's position marked | M |
| FR-64 | Chart — SHAP feature importance, global and for this prediction | M |
| FR-65 | Chart — NDVI time series for the season | S |
| FR-66 | Quantum panel: qubits, circuit depth, QAOA vs. classical optimum, approximation ratio, timings | M |
| FR-67 | Export the dashboard as PDF | C |

### Market layer

| ID | Requirement | Pri |
|---|---|---|
| FR-70 | Crop prices feed the net-value matrix — bundled modal prices per crop per district, refreshed from Agmarknet when online | M |
| FR-71 | Show the price assumption on the plan screen and let the farmer override it | S |
| FR-72 | Full farm-to-market module — harvest listings, buyer matching, mandi selection, logistics routing | C (Phase 2) |

> **Note on scope:** an earlier scoping pass selected "farm intelligence **+ market sync". The brief (QT-2.14) does not include a market module, and adding one would dilute the four rubric criteria that actually carry weight. The compromise implemented here: **market prices enter as the price vector in the optimiser's objective** (FR-70/71 — genuinely necessary, since "best plan" is meaningless without prices), and the full market-sync platform is documented as Phase 2 (FR-72). This is called out in the deck as roadmap, not as built.

### Non-functional

| ID | Requirement | Target |
|---|---|---|
| NFR-01 | Yield prediction latency | < 150 ms server-side |
| NFR-02 | Full plan latency (fusion cached → QAOA → advisory) | < 8 s p95 |
| NFR-03 | Cold data fusion (all three sources live) | < 12 s p95 |
| NFR-04 | App cold start on a 3 GB Android device | < 2.5 s |
| NFR-05 | Offline: last plan, advisory, and cached signals fully viewable with no network | Hard requirement |
| NFR-06 | APK size | < 40 MB |
| NFR-07 | Secrets — no API key, service-account JSON, or Supabase key in the repo or the APK | Hard requirement |
| NFR-08 | Per-farm hardware cost | ₹0 |
| NFR-09 | Marginal cost per additional farm | < ₹2/season (public APIs + cached district data) |
| NFR-10 | Demo resilience — `DEMO_MODE=true` serves fixtures if the venue network fails | Hard requirement |

---

## 9. Screens

| # | Screen | Content | FRs |
|---|---|---|---|
| S1 | Language & sign-in | EN/TA toggle, phone OTP, demo-token shortcut | FR-01, 02 |
| S2 | Field list | Field cards with health chip, NDVI sparkline, risk sort for officers | FR-14, 25 |
| S3 | Add field | Satellite map, tap-vertices or walk-boundary, area readout | FR-10, 11, 12, 13 |
| S4 | Field detail | NDVI overlay, soil chips, weather strip, `data_mode` badge | FR-20–25 |
| S5 | Constraints | Three sliders — water, land, budget — plus candidate-crop picker | FR-40 |
| S6 | Plan | Plot→crop table, net value with band, solver badge, price assumption | FR-31, 43, 44, 53, 71 |
| S7 | Advisory | Fertilizer bags + schedule, pH card, irrigation card, each with "Why this?" | FR-50–55 |
| S8 | Analytics | Input panel, yield+uncertainty, 3 charts, quantum panel | FR-60–66 |
| S9 | Settings | Language, cache clear, data sources & attribution, model version | FR-02, 24 |

---

## 10. Success metrics

### Model quality (the ones judges will ask for)

| Metric | Target | Why this target |
|---|---|---|
| Test R² (random split) | ≥ 0.90 | Matches the brief's verified figure — but we lead with the two below |
| **Grouped-CV R² (GroupKFold by district)** | ≥ 0.75 | The honest number. Random splits on district-panel data leak; we report both and say so |
| **Temporal-holdout R² (train ≤ 2020, test ≥ 2021)** | ≥ 0.70 | The number that reflects real deployment |
| RMSE | Reported in t/ha, per crop | Absolute error is what a farmer feels |
| Lift over district-crop mean baseline | ≥ 30% RMSE reduction | Proves the model beats "just use the district average" |

> Reporting a lower grouped-CV number next to a high random-split number is a **feature of the submission, not a weakness.** It is the fastest way to signal to a technical judge that the eval is real.

### Optimiser quality

| Metric | Target |
|---|---|
| QAOA recovers brute-force optimum | ≥ 90% of 50 random instances at 6–9 qubits |
| Approximation ratio (best sampled / optimum) | ≥ 0.98 mean |
| P(optimum) in QAOA distribution vs. uniform 1/2ⁿ | ≥ 20× uplift — this is the defensible "biases the distribution" claim, quantified |
| Feasible-solution rate after penalty tuning | ≥ 95% |

### Product

| Metric | Target |
|---|---|
| Time from app open → first plan (new user) | < 5 min |
| Plan generated with zero field hardware | 100% |
| Advisory rendered in Tamil | 100% of farmer-facing strings |

---

## 11. Rubric traceability

| Criterion | Weight | Owned by | Evidence at demo |
|---|---|---|---|
| Prediction Accuracy | 35% | Classical LightGBM regressor; quantum kept entirely off this path | Analytics tab reads live `metrics.json`; three eval protocols shown; baseline lift |
| Innovation | 20% | QAOA optimiser on a real QUBO, with an honest benchmark | Quantum panel: qubits, QAOA vs. brute force, approximation ratio, no-speedup statement |
| Practical Impact | 20% | Sensorless data fusion, ₹0 hardware, Tamil advisory in retail units, offline-capable | Live plan on a phone; bags-of-urea output; airplane-mode demo |
| Scalability | 15% | Stateless microservices, public data sources, per-farm marginal cost < ₹2, quantum-ready at larger n | Architecture slide + cost table + the scaling argument for QAOA |
| Presentation | 10% | Live demo with a recorded fallback and `DEMO_MODE` fixtures | Both prepared before demo day |

---

## 12. Scope

### In (hackathon MVP)

Everything marked **M** in §8. Concretely: two roles, field drawing, three-source fusion with offline SHC, LightGBM yield with intervals and SHAP, QUBO+QAOA optimiser with classical comparison and fallback, fertilizer/pH/crop advisory in EN+TA, and the full analytics dashboard.

### Out (explicitly, and say so)

- Quantum hardware execution. Simulator only. Stated openly.
- Any claim of quantum speedup.
- Per-farm soil sensors or drone imagery.
- Full market-sync platform (FR-72) — prices in, marketplace out.
- Real-money transactions, credit, or insurance.
- Pest/disease image classification.

### Phase 2 roadmap (the "where this goes" slide)

1. Farm-to-market: harvest listings, buyer matching, mandi choice, logistics routing — and note that routing is *another* QAOA-shaped problem, which makes the quantum layer more valuable, not less.
2. Field-level SHC ingestion via OCR of the physical card.
3. Hardware execution on IBM Quantum / Braket for a benchmark run at larger n.
4. Cooperative-scale optimisation: allocate a shared canal or FPO fertilizer budget across many farms — where n grows past brute-force range and the quantum-ready argument stops being hypothetical.

---

## 13. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Judge asks "is quantum actually faster?" | High | Answer prepared and rehearsed: *no, and we don't claim it — at 9 qubits brute force is trivially fast. What we claim is correct formulation and a solver that scales into a regime brute force can't.* Then show the benchmark. |
| Random-split R² looks too good, judge suspects leakage | High | Pre-empt it. Lead with grouped-CV and temporal holdout. Volunteering the weaker number is the strongest move available. |
| Venue network dies during demo | High | `DEMO_MODE=true` fixtures + full offline cache + recorded video fallback |
| Sentinel-2 cloudy over the demo field | Medium | Pre-cached NDVI for the demo field; `data_mode: degraded` path is a *demonstrated feature*, not a failure |
| SHC portal unavailable / scrape-hostile | Medium | District data bundled in-repo as CSV; the app never depends on that portal at runtime |
| QAOA penalty weights mis-tuned → infeasible plans | Medium | Penalty rule λ > max objective gain, unit-tested; feasibility filter on samples; classical fallback |
| Team over-claims on stage under pressure | High | §5 is a rehearsed script, not a guideline. One person owns the quantum answer. |
| Flutter build breaks (see `build_log.txt` — pub cache path with spaces) | Medium | `.pub-cache` pinned to a space-free path via `run_android.ps1`; APK built and sideloaded ≥ 24h before demo |

---

## 14. Open questions

1. Which crops make the candidate set? Proposal: **paddy, black gram, groundnut, sugarcane, maize** — TN-relevant, well-represented in ICRISAT district data, and enough combinatorial width for a meaningful QUBO.
2. Which district is the demo field in? Proposal: **Thanjavur** — strong paddy record, clean SHC data.
3. Officer role in MVP, or farmer-only? Officer adds credibility but costs a screen. Proposal: build it read-only behind a demo token.
4. Season windows for feature computation — fixed samba/kuruvai/rabi dates, or derived from the sowing date the farmer enters? Proposal: farmer-entered sowing date, fixed fallback.

---

*Written for the Quantum 2.0 hackathon (QT-2.14). Technical detail lives in [`TRD.md`](TRD.md).*
