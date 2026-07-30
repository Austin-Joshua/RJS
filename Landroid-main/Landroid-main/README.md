<div align="center">

# Landroid

**Land intelligence for consultants and landowners** — satellite NDVI, climate signals, GIS maps, and valuation in one Flutter app backed by FastAPI, Google Earth Engine, and Supabase-ready auth.

[![Stack](https://img.shields.io/badge/Flutter-02569B?logo=flutter&logoColor=white)](https://flutter.dev/)
[![Stack](https://img.shields.io/badge/FastAPI-009688?logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com/)
[![Stack](https://img.shields.io/badge/Supabase-3FCF8E?logo=supabase&logoColor=white)](https://supabase.com/)
[![Stack](https://img.shields.io/badge/Google%20Earth%20Engine-4285F4?logo=google&logoColor=white)](https://earthengine.google.com/)

[Quick start](#-quick-start) · [Architecture](#-system-architecture) · [API](#-api-architecture) · [Screenshots](#-product-tour-screenshots)

</div>

---

## Table of contents

1. [Overview](#-overview)
2. [Product tour (screenshots)](#-product-tour-screenshots)
3. [User flows](#-user-flows)
4. [Tech stack](#-tech-stack)
5. [System architecture](#-system-architecture)
6. [API architecture](#-api-architecture)
7. [Data & schema](#-data--schema)
8. [Hackathon alignment](#-hackathon--srs-alignment)
9. [Earth Engine (live NDVI)](#-real-time--earth-engine)
10. [Quick start](#-quick-start)
11. [Docs](#-additional-documentation)

---

## Overview

**Landroid** is a full-stack prototype for **SRS FR**-style land workflows:

- **Land Consultant** creates parcels, assigns landowners, uploads Birdscale outputs (GeoTIFF / boundary GeoJSON), and reviews AI signals.
- **Landowner** sees a **read-only** map, dashboard (land health, zones, valuation), and document vault for assigned parcels only.
- **Dashboard** combines **Sentinel-2** NDVI (via Earth Engine), **CHIRPS** rainfall, **ERA5-Land** temperature, and **SoilGrids** soil — with transparent **“Why this score?”** weights (FR-22 composite).
- **Map** uses **MapLibre** with satellite/street basemap, boundary, NDVI/zones overlays, optional orthomosaic/DEM tiles, and **tap-to-measure** path length & area.

---

## Product tour (screenshots)

Place additional exports in [`snapshots/`](snapshots/); paths below match the current repo.

### Authentication & roles

| | |
|:--|:--|
| **Sign in** — Supabase or demo tokens (`demo-consultant`, `demo-owner`). | ![Sign in](snapshots/Sign%20in.jpeg) |
| **Consultant home** — parcels list, create parcel, role banner. | ![Consultant UI](snapshots/Consultant%20UI.jpeg) |
| **Landowner home** — assigned parcel focus, read-only hints. | ![Land owner UI](snapshots/Land%20owner%20UI.jpeg) |

### Dashboard & intelligence

| | |
|:--|:--|
| **Land Consultant Dashboard** — health score, signal cards, trends. | ![Land Consultant Dashboard](snapshots/Land%20Consultant%20Dashboard.jpeg) |
| **Valuation & advisory** — valuation band and consultant advisory strip. | ![Land valuation and consultant advisory](snapshots/Land%20valuation%20and%20consultant%20advisory.jpeg) |

### GIS & parcels

| | |
|:--|:--|
| **GIS layers & filters** — basemap, boundary, NDVI, zones, measure, boundary metrics. | ![GIS filter](snapshots/GIS%20filter.jpeg) |
| **Parcel assign** — create parcel and assign landowner. | ![Parcel Assign](snapshots/Parcel%20Assign.jpeg) |

### Documents & settings

| | |
|:--|:--|
| **Document vault** — parcel documents and downloads. | ![Document vault](snapshots/document%20vault.jpeg) |
| **Clear cache** — on-device map/dashboard cache controls. | ![Clear cache](snapshots/clear%20cache.jpeg) |

### Backend (ops)

| | |
|:--|:--|
| **API / dev** — FastAPI, health, logs (example). | ![Backend](snapshots/backend.jpeg) |

---

## User flows

```mermaid
flowchart LR
  subgraph Auth["Authentication"]
    A[Sign in] --> B{Role}
    B -->|Consultant| C[Parcels + Create]
    B -->|Landowner| D[Assigned parcels only]
  end

  subgraph Consultant["Consultant path"]
    C --> E[Create parcel / Assign owner]
    E --> F[Upload NDVI DEM boundary]
    F --> G[Map + Dashboard]
  end

  subgraph Landowner["Landowner path"]
    D --> H[Map + Dashboard read-only]
    H --> I[Documents]
  end

  G --> J[(FastAPI + EE + SoilGrids)]
  H --> J
```

```mermaid
sequenceDiagram
  participant App as Flutter App
  participant API as FastAPI
  participant EE as Earth Engine
  participant SG as SoilGrids
  participant SB as Supabase Auth

  App->>SB: JWT / demo bearer
  App->>API: GET /api/v1/ai/{id}/land-health
  API->>SG: Soil at centroid
  API->>EE: Sentinel-2 NDVI + climate stacks
  API-->>App: land_health + score_breakdown + data_mode
```

---

## Tech stack

| Layer | Technology | Notes |
|--------|------------|--------|
| **Mobile / Web UI** | Flutter 3.x, Material 3 | MapLibre GL, `fl_chart`, liquid-glass style cards |
| **API** | FastAPI, Uvicorn, Pydantic | CORS enabled; `/api/v1` prefix |
| **Geo / RS** | Google Earth Engine Python API | Sentinel-2 SR harmonized, masks, composites |
| **Raster** | Rasterio / Pillow (server) | NDVI/zones/DEM PNG overlays |
| **Soil** | ISRIC SoilGrids (HTTP) | Point summaries at parcel centroid |
| **Auth** | Supabase JWT (optional) + demo bearers | `Authorization: Bearer` |
| **Data (prototype)** | In-memory parcel store + `data/` GeoJSON & GeoTIFF | Swap for Postgres/PostGIS for production |

---

## System architecture

High-level context: client talks to **one API**; the API pulls **external intelligence** and local files.

```mermaid
flowchart TB
  subgraph Clients["Clients"]
    FL[Flutter App]
  end

  subgraph API["Landroid API FastAPI"]
    R[REST /api/v1]
    A[Auth parse_bearer]
    P[Parcel store]
    AI[AI signals land health zones valuation]
    GEE[gee_auth + gee_signals]
    RAS[Raster PNG render]
  end

  subgraph External["External services"]
    EE[Google Earth Engine]
    SG[SoilGrids API]
    SB[Supabase JWT verify]
  end

  subgraph Local["Local / repo data"]
    DATA[(data/ Boundary GeoJSON GeoTIFF uploads)]
  end

  FL -->|HTTPS JSON PNG| R
  R --> A
  R --> P
  R --> AI
  AI --> GEE
  AI --> SG
  A --> SB
  P --> DATA
  RAS --> DATA
  GEE --> EE
```

---

## API architecture

Logical grouping of routes (all under host root; JSON unless noted).

```mermaid
flowchart LR
  subgraph Health["Health"]
    H1["GET /healthz"]
  end

  subgraph Parcels["Parcels"]
    P1["POST /api/v1/parcels"]
    P2["GET /api/v1/parcels"]
    P3["GET /api/v1/parcels/{id}"]
    P4["POST .../assets/*"]
    P5["GET .../map-manifest"]
    P6["GET .../layers/*.png"]
  end

  subgraph AI["AI"]
    A1["GET .../land-health"]
    A2["GET .../plant-zones"]
    A3["GET .../valuation"]
  end

  subgraph Docs["Documents"]
    D1["GET .../documents"]
    D2["GET .../gis-snapshot-report"]
  end

  Health --- Parcels
  Parcels --- AI
  AI --- Docs
```

**Selected endpoints**

| Method | Path | Purpose |
|--------|------|---------|
| `GET` | `/healthz` | Liveness + Earth Engine / data dir flags |
| `GET` | `/api/v1/parcels` | List parcels for current role |
| `POST` | `/api/v1/parcels` | Create parcel + assign owner |
| `GET` | `/api/v1/parcels/{id}/map-manifest` | GIS layer URLs, bbox, `parcel_metrics`, health snapshot |
| `GET` | `/api/v1/parcels/{id}/layers/ndvi.png` | NDVI raster overlay PNG + `X-Geo-Bounds` |
| `GET` | `/api/v1/ai/{id}/land-health` | Composite score, `score_breakdown`, `data_mode` |
| `GET` | `/api/v1/ai/{id}/valuation` | Valuation band using land health |
| `POST` | `/api/v1/parcels/{id}/assets/boundary` | Replace boundary GeoJSON |

---

## Data & schema

### Prototype backend model (in-memory)

The hackathon server keeps parcels in process memory (`ParcelStore`). Conceptual entity:

```mermaid
erDiagram
  PARCEL {
    string id PK
    string name
    string owner_user_id FK
    json boundary_geojson
    json centroid
    json bbox
    float area_acres_approx
    json meta
  }

  LANDOWNER_REGISTRY {
    string email_or_phone
    string stable_user_id
  }

  PARCEL ||--o{ LANDOWNER_REGISTRY : "owner_user_id matches auth sub"
```

> **Production note:** Replace `ParcelStore` with a durable database (e.g. PostgreSQL + PostGIS for boundaries). Supabase already fits **auth**; add a `parcels` table with RLS by `owner_user_id`.

### Supabase (auth)

| Concept | Usage |
|---------|--------|
| `auth.users` | Managed by Supabase |
| JWT claims | `sub`, `email`, app metadata for role (`landowner` / `consultant`) |
| Flutter | `supabase_flutter` + `--dart-define` for URL/anon key |

### External datasets (read-only APIs)

| Source | Data |
|--------|------|
| **Earth Engine** | Sentinel-2 NDVI composites, CHIRPS, ERA5-Land |
| **SoilGrids** | pH, SOC, texture at centroid |

---

## Hackathon / SRS alignment

| Area | What to demo |
|------|----------------|
| **AI (NDVI + confidence)** | Land health from **Earth Engine** when configured; **confidence %** and **“Why this score?”** (FR-22 weights + subscores). |
| **GIS / map** | MapLibre: boundary, NDVI/zones PNGs, basemap, tap measure, boundary metrics from manifest. |
| **UI/UX** | Liquid-glass style cards, **English / Tamil**, consultant vs landowner UX. |
| **Security** | Supabase keys via **`--dart-define`**; secrets not committed — see `backend/.env.example`. |

---

## Real-time / Earth Engine

1. **Backend:** Set `GEE_PROJECT_ID` (or `GOOGLE_CLOUD_PROJECT`), service account JSON (`GOOGLE_APPLICATION_CREDENTIALS` or `GEE_SERVICE_ACCOUNT_KEY_PATH`), and register the SA on [Earth Engine](https://code.earthengine.google.com/register).
2. **Default:** `LANDROID_ALLOW_SYNTHETIC_LAND_HEALTH` defaults to **`false`** — live EE when initialization succeeds. For **offline UI only**, set `LANDROID_ALLOW_SYNTHETIC_LAND_HEALTH=true` in `backend/.env`.
3. **Verify:** `GET http://localhost:8000/healthz` → `earth_engine_initialized: true`.
4. **App:** Pull-to-refresh on Dashboard; cached synthetic rows are skipped once EE data exists.

Map NDVI **PNG** is rendered from your **GeoTIFF** (or API placeholder); dashboard **numbers** come from the EE time-series pipeline.

---

## Quick start

### Backend

```bash
cd backend
python -m venv .venv
.venv\Scripts\activate   # Windows
pip install -r requirements.txt
copy .env.example .env   # fill GEE + optional flags
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

### Flutter

```bash
cd flutter_app
flutter pub get
flutter run --dart-define=SUPABASE_URL=https://YOUR_REF.supabase.co ^
  --dart-define=SUPABASE_ANON_KEY=your_anon_key
```

**Demo API tokens** (no Supabase): `demo-consultant`, `demo-owner` as `Authorization: Bearer …`.

---

## Additional documentation

- `docs/validation-matrix.md` — requirement traceability (if present)
- `docs/evaluation-runbook.md` — evaluation steps (if present)
- `backend/.env.example` — environment variable reference

---

<div align="center">

**Landroid** — *from boundary to intelligence, in one flow.*

</div>
