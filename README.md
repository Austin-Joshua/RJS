# High Yield Crop Prediction using Quantum AI

A digital guidebook for new farmers. Enter your land and soil readings; get the
crops that will grow there, the order to plant them across the year, and what
the soil needs first.

**Sign in with Google → add a farm → soil card → feasible crops →
quantum-ranked crop order → soil treatment → dashboard.**

- [`PRD.md`](PRD.md) — the product, the flow, and why the quantum step is not decoration
- [`TRD.md`](TRD.md) — architecture, the ansatz, the ML pipeline

## Why quantum

Ranking crops by predicted profit is a sort. Crop **sequencing** is not: a
cereal after a legume out-yields the same cereal after itself, and the same crop
twice running carries a monoculture penalty. So a crop's value depends on what
preceded it, the objective is quadratic, and the best order is not the sorted
order.

Across 60 random farms, sorting gives a suboptimal plan **65%** of the time
(mean ₹5,475 lost, worst ₹32,762). Even greedy-with-lookahead is wrong **50%**
of the time.

The optimiser confines its search to the one-crop-per-season subspace using an
XY-ring mixer, so **100%** of sampled bitstrings are structurally valid — by
symmetry, not by filtering. It recovers the exact optimum on 25/25 instances,
and the crop order shown in the app is read directly off the measurement
distribution.

## Run it

```bash
cd backend
python -m scripts.build_training_set && python -m scripts.train_model
uvicorn app.main:app --reload

cd ../flutter_app
flutter run --dart-define=CLERK_PUBLISHABLE_KEY=pk_... --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

`python backend/pipeline.py` runs the whole flow in one process.

## Demo account

To see the app populated without setting up Google sign-in:

```bash
cd backend
python -m scripts.seed_demo            # 3 real Thanjavur farms
# then in backend/.env:
#   DEV_LOGIN_USER=demo-farmer
#   DEV_LOGIN_TOKEN=<any secret you choose>

cd ../flutter_app
flutter run --dart-define=DEV_LOGIN_TOKEN=<the same secret>             --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

The app shows a **DEV LOGIN** banner so this is never mistaken for a real
session, and `/healthz` reports `dev_login_enabled`. Leave both env vars blank
and the path does not exist.

The seeded data is **not** fixtures. The script supplies only what a farmer
would type — location, land size, soil readings — then runs the real pipeline:
live weather and Sentinel-2, the trained model, the agronomic gates and the
quantum sequencer. The three farms deliberately take different paths:

| Farm | Soil | Feasible | Plan |
|---|---|---|---|
| Home field | Alluvial, pH 6.7, ample water | 4/5 | groundnut ×3 — ₹2,67,028 |
| Canal plot | Heavy clay, pH 7.3 | 2/5 (drainage gate) | paddy → black gram → black gram — ₹59,616 |
| Upland strip | Red, pH 7.8, low water | 3/5 (paddy fails on water) | groundnut ×3 — ₹1,64,724 |

`python -m scripts.seed_demo --clean` removes it.

## Tests

```bash
cd backend && pytest          # 55
cd flutter_app && flutter test # 12
```
