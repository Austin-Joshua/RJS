# FarmSync Quantum 2.0 — Project Brief (QT-2.14)

Single source of truth for the hackathon build. If `PRD.md` or `TRD.md` disagrees with this document, this document wins.

---

## 1. Core concept

A **sensorless, hybrid quantum-classical SaaS** giving small Indian farmers precision-agriculture recommendations with **zero per-farm hardware/IoT cost**.

## 2. Data strategy (the headline strength — lead with this)

Three accessible, multi-modal sources instead of sensors:

- **Soil (baseline):** Government Soil Health Card / district datasets → N, P, K, pH.
- **Weather (dynamic):** Weather API → temperature, humidity, rainfall.
- **Crop health (live):** Sentinel-2 / Copernicus → NDVI greenness.

Delivered to a smartphone. No IoT install → strong Practical Impact (20%) and Scalability (15%).

## 3. Architecture — the decision that protects the score

**Quantum does OPTIMISATION, not prediction.** Yield prediction is regression; a quantum classifier there would be the wrong tool AND would bleed the 35% accuracy score. So:

```
SHC + Weather + NDVI ─▶ CLASSICAL yield model ─▶ net-value matrix ─▶ QAOA optimiser ─▶ plan ─▶ advisory
                        (Accuracy 35%)            (resources enter)   (Innovation 20%)          (outputs)
```

- **Classical yield model** (LightGBM regressor): predicts t/ha. Verified R² ≈ 0.90. Owns Accuracy. Quantum never touches it.
- **QAOA optimiser** (PennyLane, simulated): picks the best crop/resource plan per field under water/land/budget constraints. Verified to recover the exact brute-force optimum at 6–9 qubits. Owns Innovation.
- **Outputs** (fertilizer dosage, pH correction, crop selection) are the *downstream* result of the optimised plan — not quantum claims.

## 4. Claims we can defend (and lines to DELETE)

Defensible:

- Regression for yield (right tool); QAOA for allocation (right tool).
- On a simulator at demo scale QAOA *matches* the classical optimum — we claim quantum-*ready*, not quantum-*advantage*.
- QAOA biases the distribution toward good solutions; we sample and keep the best.

Delete these (they get shredded by a technical judge):

- ❌ "Ry gates keep amplitudes real, making the optimiser faster/more stable." False.
- ❌ "Entanglement understands why the plant is stressed." Use classical SHAP instead.

## 5. Deliverables (build both fully)

1. **Yield prediction model** — RMSE/MAE/R²/CV-R² on real data (FAO / Kaggle India).
2. **Analytics dashboard** — input panel, predicted yield + uncertainty, QAOA plan, ≥2 charts (yield-vs-rainfall, feature importance). Half the deliverable; don't skip.

## 6. Rubric mapping

| Criterion | Weight | Owned by |
|---|---|---|
| Prediction Accuracy | 35% | Classical regressor (quantum kept off it) |
| Innovation | 20% | QAOA optimiser + honest benchmark |
| Practical Impact | 20% | Sensorless data + actionable advisory, TN/India context |
| Scalability | 15% | Microservices + zero-hardware + "quantum-ready at scale" |
| Presentation | 10% | Live demo + recorded fallback |

## 7. Fixed one-line pitch

> "Zero-hardware data fusion — government soil cards, live weather, and satellite NDVI — feeds a classical yield model, and a quantum optimiser turns those predictions into the best resource plan for each field, right on a smartphone."

## 8. Code (already built & tested)

`yield_model.py`, `quantum_optimizer.py`, `pipeline.py` — run `python pipeline.py`.

---

*Data strategy stays the star; quantum is the optimiser, not the liability.*

## Build decisions locked on top of this brief

| Decision | Value |
|---|---|
| Mobile stack | Flutter + FastAPI (reuses the Landroid app shell, GEE auth, and Supabase pattern) |
| Persistence | Postgres + PostGIS via Supabase — **not** Landroid's in-memory store |
| Market scope | Crop prices enter the optimiser's objective (needed for "net value"); the full farm-to-market module is Phase 2 roadmap, not built |
| Quantum runtime | PennyLane `default.qubit` simulator only; hardware execution is roadmap |
| Docs | `PRD.md` (product) and `TRD.md` (technical) live alongside this brief |
