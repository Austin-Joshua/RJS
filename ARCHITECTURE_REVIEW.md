# FarmSync Quantum 2.0 — Architecture & Build Review

Status snapshot of the backend as built. Companion docs: `FARMSYNC_BRIEF.md` (product framing), `PRD.md`, `TRD.md`.

---

## 1. One-line pitch

Zero-hardware data fusion (govt. soil cards + live weather + satellite/drone NDVI) feeds a classical LightGBM yield model; a QAOA quantum optimizer turns those yield predictions into the best crop/resource plan per field, with a deterministic advisory layer on top.

**Hard rule enforced throughout the codebase:** quantum (QAOA) is only ever used for combinatorial *optimization* (crop/resource allocation). Yield *prediction* is 100% classical regression. Pest/disease detection is rule-based NDVI thresholds — no CNN/CV.

---

## 2. Tech stack

| Layer | Choice | Notes |
|---|---|---|
| API | FastAPI 0.141, Python 3.10+ typing | `backend/app/main.py`, versioned under `/api/v1` |
| Auth | Clerk session tokens + `Bearer demo-farmer` / `demo-officer` bypass | Works venue-offline for a demo |
| DB | SQLAlchemy 2.0 ORM → SQLite (dev/demo) or Supabase Postgres (prod) | Same schema both ways; boundary/geometry kept as JSON, not PostGIS, so it runs on SQLite too |
| Object storage | Supabase Storage (private bucket `field-rasters`) | Uploaded GeoTIFF pixel bytes only; metadata lives in Postgres |
| ML | LightGBM (point + P10/P90 quantile boosters), SHAP | `backend/app/ml/`, `backend/models/v1/*` trained artifacts |
| Quantum | PennyLane `default.qubit` simulator, QAOA + CVaR | `backend/app/quantum/` — simulator only, no hardware claim |
| Geospatial | `rasterio`, `shapely`, `Pillow` | GeoTIFF masking/rendering, boundary geometry, PNG overlays |
| External data | Open-Meteo (+ NASA POWER fallback), Google Earth Engine (Sentinel-2), bundled Soil Health Card CSV, Agmarknet price CSV | All degrade to `None` on failure — never raise |
| Mobile client | Flutter (Riverpod, Drift, MapLibre) | Scaffolded (`flutter_app/`); this review covers the backend, which is where this session's work landed |

---

## 3. High-level system architecture

```mermaid
flowchart TB
    subgraph Client["Flutter App (offline-first, Drift cache)"]
        UI[Map + Dashboard UI]
    end

    subgraph API["FastAPI backend  (/api/v1)"]
        Auth[Clerk / demo-bearer auth]
        Fields[fields.py — Field CRUD]
        Signals[signals.py — fused signals + NDVI layer]
        Rasters[rasters.py — GeoTIFF upload + layers + map-manifest]
        Predict[predict.py — yield only]
        Plan[plan.py — the money endpoint]
        Analytics[analytics.py — dashboard JSON]
    end

    subgraph Services["Service layer"]
        Fusion[fusion.py\nsoil+weather+NDVI fusion]
        YieldSvc[yield_service.py]
        PlanSvc[plan_service.py\nQUBO → QAOA/classical → advisory]
        RasterSvc[raster_ndvi.py\nanalyze / mask / blend / render PNG]
        AdvisorySvc[advisory.py\nfertilizer / pH / irrigation rules]
    end

    subgraph MLQ["ML + Quantum"]
        LGBM[LightGBM yield model\n+ P10/P90 quantile]
        QUBO[qubo.py — QUBO builder]
        QAOA[quantum_optimizer.py\nPennyLane QAOA]
        Classical[classical_fallback.py\nbrute force]
    end

    subgraph Adapters["External adapters (all degrade to None, never raise)"]
        Soil[soil_shc.py\nbundled CSV]
        Weather[weather_openmeteo.py\n+ NASA POWER fallback]
        NDVI[ndvi_gee.py\nSentinel-2 / GEE]
        Prices[prices_agmarknet.py]
        District[district_lookup.py]
        Storage[raster_storage.py\nSupabase Storage httpx client]
    end

    subgraph Data["Persistence"]
        DB[(SQLite / Supabase Postgres)]
        Bucket[(Supabase Storage\nfield-rasters bucket)]
    end

    UI -->|Bearer token| Auth
    Auth --> Fields & Signals & Rasters & Predict & Plan & Analytics

    Signals --> Fusion
    Predict --> Fusion
    Plan --> Fusion
    Fusion --> Soil & Weather & NDVI
    Fusion -.->|blend| RasterSvc

    Predict --> YieldSvc --> LGBM
    Plan --> PlanSvc
    PlanSvc --> YieldSvc
    PlanSvc --> Prices
    PlanSvc --> QUBO --> QAOA & Classical
    PlanSvc --> AdvisorySvc

    Rasters --> RasterSvc
    Rasters --> Storage --> Bucket

    Fields --> District
    Fields & Rasters & PlanSvc & Signals --> DB
```

---

## 4. Database schema (ER diagram)

```mermaid
erDiagram
    FARMER ||--o{ FIELD : owns
    FIELD ||--o{ PLOT : contains
    FIELD ||--o{ RASTER_ASSET : has
    FIELD ||--o{ SIGNAL_SNAPSHOT : has
    FIELD ||--o{ PLAN : has
    OPTIMIZATION_RUN ||--o| PLAN : produced
    PLAN ||--o{ ASSIGNMENT : contains
    PLAN ||--o| ADVISORY : has

    FARMER {
        string id PK
        string phone
        string role "farmer | officer"
        string lang
    }
    FIELD {
        string id PK
        string farmer_id FK
        string name
        json boundary_geojson
        float centroid_lat
        float centroid_lon
        float area_ha
        string district
        string state
        string sowing_date
        json soil_override
    }
    PLOT {
        string id PK
        string field_id FK
        string label
        float area_ha
        json geom_geojson
    }
    RASTER_ASSET {
        string id PK
        string field_id FK
        string kind "ndvi | dem | orthomosaic"
        string file_name
        string storage_bucket
        string storage_path
        int band
        string crs
        int width
        int height
        json bounds
        json stats
        json zonal_ndvi
        bool is_active
        datetime uploaded_at
    }
    SIGNAL_SNAPSHOT {
        string id PK
        string field_id FK
        string data_mode "live | degraded | demo"
        json soil
        json weather
        json ndvi
        json provenance
    }
    OPTIMIZATION_RUN {
        string id PK
        int n_qubits
        string encoding
        int layers
        float qaoa_energy
        float classical_optimum
        float approx_ratio
        bool matched_optimum
        string solver_used
    }
    PLAN {
        string id PK
        string field_id FK
        string run_id FK
        float net_value_rs
        float net_value_p10
        float net_value_p90
        json constraints
    }
    ASSIGNMENT {
        string id PK
        string plan_id FK
        string plot_id
        string crop_code
        float yield_t_ha
        float p10
        float p90
    }
    ADVISORY {
        string id PK
        string plan_id FK
        json fertilizer
        json ph
        json irrigation
        json why
    }
```

---

## 5. Request/response flow — fused signals (`GET /fields/{id}/signals`)

The three-source fusion that feeds every downstream prediction.

```mermaid
sequenceDiagram
    actor U as Farmer/Officer
    participant API as signals.py
    participant Fusion as fusion.py
    participant Soil as soil_shc.py
    participant Weather as weather_openmeteo.py
    participant NDVI as ndvi_gee.py
    participant Raster as raster_ndvi.py
    participant DB as DB

    U->>API: GET /fields/{id}/signals
    API->>DB: load active NDVI RasterAsset (if any)
    API->>Fusion: fuse_field(..., active_raster_ndvi)
    par concurrent fetch
        Fusion->>Soil: get_soil_baseline(district)
        Fusion->>Weather: get_weather_features(lat, lon)
        Fusion->>NDVI: get_ndvi_features(boundary, start, end)
    end
    alt uploaded raster NDVI is active
        Fusion->>Raster: blend_ndvi(gee_mean, raster_zonal, weight)
        Raster-->>Fusion: blended mean + provenance
    end
    Fusion-->>API: {soil, weather, ndvi, data_mode, provenance}
    API-->>U: SignalsResponse (data_mode: live | degraded | demo)
```

`data_mode` is **derived, never hand-set**: `"demo"` under `DEMO_MODE`, `"live"` only if soil + weather + NDVI all returned real values, `"degraded"` otherwise. An uploaded raster is a *refinement* on top of NDVI, not a fourth required source — its absence never degrades `data_mode`.

---

## 6. The money path — `POST /plan`

```mermaid
sequenceDiagram
    actor U as Farmer
    participant API as plan.py
    participant Fusion as fusion.py
    participant PlanSvc as plan_service.py
    participant Yield as LightGBM yield model
    participant QUBO as qubo.py
    participant QAOA as PennyLane QAOA
    participant Classical as brute_force
    participant Advisory as advisory.py
    participant DB as DB

    U->>API: POST /plan {plots, crops, water_m3, budget_rs}
    API->>Fusion: fuse_field(field)
    Fusion-->>API: fused signals
    API->>PlanSvc: build_plan(field, plots, crops, fused)
    PlanSvc->>Yield: predict_yields() per candidate crop
    Yield-->>PlanSvc: yield_t_ha, p10, p90, SHAP
    PlanSvc->>PlanSvc: net_value_rs = f(yield, price, cost) per (plot, crop)
    PlanSvc->>QUBO: build_qubo(value/water/cost maps, limits)
    QUBO-->>PlanSvc: QUBOProblem (n_qubits, Q matrix)
    par run in parallel
        PlanSvc->>QAOA: solve_qaoa(problem) [timeout-bounded]
        PlanSvc->>Classical: brute_force(problem) [ground truth]
    end
    QAOA-->>PlanSvc: best_bits, energy, feasible_rate
    Classical-->>PlanSvc: best_bits, best_value (exact optimum)
    PlanSvc->>PlanSvc: use QAOA if it didn't time out, else classical_fallback
    PlanSvc->>Advisory: build_advisory(winning assignment, soil, weather)
    Advisory-->>PlanSvc: fertilizer / pH / irrigation / why
    PlanSvc-->>API: plan + alternatives + benchmark + advisory
    API->>DB: persist_plan (OptimizationRun, Plan, Assignment, Advisory)
    API-->>U: PlanResponse
```

### QAOA / QUBO design

- **Decision variables**: one binary `x_(plot, crop)` per (plot, candidate crop) pair.
- **Constraints**: C1 exactly-one-crop-per-plot (equality penalty), C2 water ≤ budget, C3 cash ≤ budget (slack-encoded inequalities, 6–9 qubits at demo scale).
- **Objective**: maximize net value = `yield × area × price × 10 − cost × area`.
- **Solver**: PennyLane `default.qubit` simulator, CVaR-biased COBYLA training (best-quartile of sampled bitstrings), classical brute-force always runs in parallel as ground truth.
- **Verified property**: QAOA recovers the exact brute-force optimum at 6–9 qubit demo scale — the pitch is "quantum-ready", not "quantum-advantage" (no hardware, no speedup claim).

```mermaid
flowchart LR
    A[Net-value matrix\nplot x crop] --> B[QUBO builder\nC1 one-hot + C2 water + C3 budget]
    B --> C{"n_qubits ~ 6 to 9"}
    C --> D[Ising Hamiltonian]
    D --> E["QAOA circuit: Hadamard init, then p layers of cost_layer + mixer_layer"]
    E --> F[COBYLA optimizes gamma/beta\nvia CVaR-0.25 objective]
    F --> G[Sample best params\n2048 shots]
    G --> H{Any feasible\nbitstring?}
    H -- yes --> I[Pick max feasible_value]
    H -- no / timeout --> J[Fall back to\nclassical brute force]
    I --> K[Winning assignment]
    J --> K
```

---

## 7. Raster / NDVI pipeline — this session's build

Landroid-style GeoTIFF upload pipeline: pixel bytes in Supabase Storage, metadata + cached zonal stats in Postgres, PNG rendering on-demand via `rasterio.io.MemoryFile` (never touches local disk).

```mermaid
sequenceDiagram
    actor U as Farmer/Officer
    participant API as rasters.py
    participant Analyze as raster_ndvi.analyze_geotiff
    participant Storage as raster_storage.py (Supabase Storage)
    participant DB as raster_assets table

    U->>API: POST /fields/{id}/rasters (multipart .tif, kind=ndvi|dem|orthomosaic)
    API->>API: validate suffix, size under RASTER_MAX_UPLOAD_MB
    API->>Analyze: analyze_geotiff(bytes) — CRS, dims, per-band stats
    alt kind == "ndvi"
        API->>Analyze: zonal_mean_ndvi(bytes, field.boundary_geojson)
    end
    API->>Storage: upload(bucket, path, bytes)
    API->>DB: deactivate previous active asset of same kind
    API->>DB: insert RasterAsset(is_active=true, stats, zonal_ndvi)
    API-->>U: RasterUploadResponse {asset, analysis}
```

### Toggleable map layers

The orthomosaic is the **base layer**; NDVI (satellite or uploaded) and the DEM hillshade are **transparent overlay PNGs at the same field-boundary crop**, so the frontend can show/hide any of them independently — no backend round-trip needed to "toggle".

```mermaid
flowchart TB
    subgraph Manifest["GET /fields/{id}/map-manifest"]
        M[base_layer + overlays list\nwith available / default_on flags]
    end

    subgraph Base["Base layer"]
        Ortho["GET /layers/orthomosaic.png\ntrue-color crop of uploaded drone orthomosaic"]
    end

    subgraph Overlays["Toggleable overlays (transparent outside boundary + outside valid pixels)"]
        NdviSat["GET /layers/ndvi.png\nlive Sentinel-2/GEE NDVI, red-green ramp"]
        NdviRaster["GET /layers/raster-ndvi.png\nuploaded NDVI raster, if any"]
        Dem["GET /layers/dem-hillshade.png\ngrayscale hillshade from uploaded DEM"]
    end

    M -.->|lists| Ortho
    M -.->|lists| NdviSat
    M -.->|lists| NdviRaster
    M -.->|lists| Dem
    Ortho --> Composite["Map view: Orthomosaic + any enabled overlays, stacked by z-order"]
    NdviSat -.->|toggle on/off| Composite
    NdviRaster -.->|toggle on/off| Composite
    Dem -.->|toggle on/off| Composite
```

All three PNG renderers (`render_true_color_png`, `render_ndvi_png`, `render_hillshade_png`) share one masking primitive (`_mask_to_boundary`): reproject the field's WGS84 boundary into the raster's native CRS, `rasterio.mask.mask(..., crop=True)`, then reproject the cropped extent's bounds back to WGS84 so the frontend can place the PNG on the map with `X-Geo-Bounds`.

### NDVI value fusion (uploaded raster + satellite)

```mermaid
flowchart LR
    A[Uploaded NDVI raster\nzonal_mean_ndvi, cached at upload time] --> C{blend_ndvi}
    B[Live Sentinel-2 mean NDVI\nfrom ndvi_gee.py] --> C
    C -->|weight = RASTER_NDVI_BLEND_WEIGHT, default 0.5| D["Blended ndvi_mean, fed into fusion.py, then the yield model"]
    C -->|either source missing| E[Fall back to whichever\nsource is available]
```

---

## 8. Data degradation model

Every external adapter (`soil_shc`, `weather_openmeteo`, `ndvi_gee`, `prices_agmarknet`) is designed to **return `None`, never raise** — the app must stay demoable even with zero network/GEE credentials.

```mermaid
stateDiagram-v2
    [*] --> demo: DEMO_MODE=true
    [*] --> checking: DEMO_MODE=false
    checking --> live: soil AND weather AND ndvi all resolved
    checking --> degraded: any of the three is None
    demo --> [*]
    live --> [*]
    degraded --> [*]
    note right of degraded
      Model still predicts (NaN-safe
      LightGBM features) with
      confidence="reduced" if NDVI missing
    end note
```

---

## 9. API surface (implemented)

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/v1/healthz` | Liveness + model/GEE readiness |
| GET/POST | `/api/v1/fields` | List / create fields |
| GET/PUT/DELETE | `/api/v1/fields/{id}` | Field detail, boundary update, delete |
| POST | `/api/v1/fields/{id}/soil-override` | Farmer-provided soil test override |
| GET | `/api/v1/fields/{id}/signals` | Fused soil+weather+NDVI (+ raster blend) |
| GET | `/api/v1/fields/{id}/layers/ndvi.png` | Live satellite NDVI overlay PNG |
| GET | `/api/v1/fields/{id}/ndvi-series` | Time series for the NDVI trend chart |
| GET | `/api/v1/prices?crop&district` | Modal market price lookup |
| POST | `/api/v1/fields/{id}/rasters` | Upload GeoTIFF (ndvi \| dem \| orthomosaic) |
| GET | `/api/v1/fields/{id}/rasters` | List uploaded raster assets |
| DELETE | `/api/v1/fields/{id}/rasters/{asset_id}` | Delete a raster asset |
| GET | `/api/v1/fields/{id}/layers/raster-ndvi.png` | Uploaded-raster NDVI overlay PNG |
| GET | `/api/v1/fields/{id}/layers/orthomosaic.png` | **New** — true-color base layer PNG |
| GET | `/api/v1/fields/{id}/layers/dem-hillshade.png` | **New** — DEM hillshade overlay PNG |
| GET | `/api/v1/fields/{id}/map-manifest` | **New** — base + overlay layer catalogue for the map UI |
| POST | `/api/v1/predict/yield` | Classical yield prediction only |
| POST | `/api/v1/plan` | The money endpoint — QAOA/classical plan + advisory |
| GET | `/api/v1/fields/{id}/advisory` | Latest persisted advisory |
| GET | `/api/v1/analytics/model-metrics` | Trained model RMSE/MAE/R² |
| GET | `/api/v1/analytics/feature-importance` | Global SHAP values |
| GET | `/api/v1/analytics/yield-vs-rainfall` | Dashboard chart data |
| GET | `/api/v1/analytics/quantum-benchmark` | QAOA vs classical benchmark JSON |

Auth: every field-scoped route runs through `get_owned_field` / `get_writable_field` — an officer role gets read-only access, a farmer only ever sees their own fields, enforced server-side (not just hidden in the UI).

---

## 10. What was verified end-to-end this session

- Connected Google Earth Engine via a service account (`GOOGLE_APPLICATION_CREDENTIALS` + `GEE_PROJECT_ID`); confirmed `earth_engine_initialized: true` on `/healthz`.
- Built the full raster pipeline: `RasterAsset` model + migration, Supabase Storage adapter, `raster_ndvi.py` analysis/masking/blending/rendering service, upload/list/delete/layer endpoints, request/response schemas, fusion blending wired into `/signals`.
- Uploaded and validated your real field survey files against the live backend:
  - `Orthomosaic.tif` (EPSG:32643, 4-band RGB+alpha, downsampled from 2.8GB)
  - `Digital Elevation model.tif` (EPSG:32643, 1-band float32, downsampled from 377MB)
  - `Boundary.geojson` (reprojected from a UTM LineString to a WGS84 Polygon)
- Confirmed masking is pixel-accurate: both the orthomosaic true-color crop and the DEM hillshade crop match the field's exact boundary polygon (screenshots verified visually, not just unit-tested).
- Added the base-layer / toggleable-overlay model (`orthomosaic.png` + `map-manifest`) so NDVI, uploaded-raster-NDVI, and DEM hillshade can each be shown/hidden independently on top of the orthomosaic.
- 8/8 backend unit tests passing (`backend/tests/test_raster_ndvi.py`) on synthetic in-memory GeoTIFFs — no network, no Supabase calls required to run them.

## 11. Known gaps / next review items

- Frontend (`flutter_app/`) is only scaffolded (auth placeholder, theme, env) — none of the map/layer UI described above has a Flutter consumer yet.
- QAOA's transverse-field mixer explores the full 2^n space and relies on penalty terms alone for feasibility (~5–15% feasible_rate at p=3, TRD target is 95%) — flagged in code as a known ceiling; upgrade path is a per-plot "one-hot" mixer (documented in `quantum_optimizer.py`).
- `RasterAsset`/`Field.boundary_geojson` are JSON columns, not native PostGIS geometry — fine for SQLite-or-Postgres portability now, but centroid/area math happens in Python (`shapely`) instead of `ST_Centroid`/`ST_Area`.
- Persistence defaults to local SQLite; Supabase Postgres is wired but not yet the default `DATABASE_URL` for this environment.
