# FarmSync Quantum 2.0 — Backend

FastAPI backend: LightGBM yield prediction + PennyLane QAOA resource
optimization + a deterministic advisory rules engine, fusing soil (SHC),
weather (Open-Meteo), and NDVI (Sentinel-2/GEE) signals for Tamil Nadu
smallholder farms. See `../TRD.md` / `../PRD.md` for the full spec.

## Setup

```bash
python -m venv .venv
.venv\Scripts\activate            # Windows
# source .venv/bin/activate       # macOS/Linux
pip install -r requirements.txt   # add requirements-dev.txt for pytest
copy .env.example .env            # fill in Supabase/GEE creds, or leave blank for demo mode
```

## Train the model (required before `/predict/yield` or `/plan` will work)

```bash
python -m scripts.build_training_set   # writes data/training/yield_training_set.csv
python -m scripts.train_model          # writes models/v1/*.txt, feature_list.json, metrics.json, shap_global.json
python -m scripts.benchmark_qaoa       # writes models/v1/benchmark.json (~50 QAOA-vs-brute-force instances, ~3-4 min)
python -m scripts.seed_demo            # seeds one warm demo field + plan into the local DB
```

`scripts/build_training_set.py` generates a structured **synthetic** panel
standing in for the real ICRISAT District Level Database (see the module
docstring for why, and the upgrade path). `metrics.json` always records
`training_data_source` so this is never presented as real data.

## Run

```bash
uvicorn app.main:app --reload
python pipeline.py          # fast end-to-end smoke check (forces DEMO_MODE)
```

Auth: send `Authorization: Bearer demo-farmer` or `Bearer demo-officer` to
bypass Clerk entirely (see `app/core/security.py`), or a real Clerk session
token once `CLERK_JWT_KEY` (or `CLERK_SECRET_KEY`) is configured. Supabase is
used for Postgres/PostGIS persistence only (`DATABASE_URL`) — sign-in itself
happens in Clerk's frontend SDK, not this backend.

## Test

```bash
pip install -r requirements-dev.txt
pytest
```

Tests use an isolated sqlite file (`tests/_test.db`, gitignored) and
`DEMO_MODE=true`, so they never touch the dev database that `seed_demo.py`
populates and never need live network/Supabase/GEE access.

## Layout

```
app/
  core/       settings, security (JWT + demo bearer), caching, exceptions
  db/         SQLAlchemy models + session (SQLite dev / Postgres+PostGIS prod)
  adapters/   soil (SHC), weather (Open-Meteo), NDVI (GEE), prices, district lookup
  services/   fusion, yield_service, plan_service (QUBO/QAOA orchestration), advisory
  ml/         feature engineering, LightGBM model wrapper, SHAP explanations
  quantum/    QUBO formulation, PennyLane QAOA + CVaR, classical fallback, benchmark
  schemas/    Pydantic request/response contracts
  api/v1/     FastAPI routers
scripts/      offline batch jobs: build_training_set, train_model, benchmark_qaoa, seed_demo
models/v1/    trained artifacts (committed) — booster files, metrics.json, benchmark.json
data/         bundled offline reference data (SHC baselines, district boundaries, prices) + demo fixtures
```
