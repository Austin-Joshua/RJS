import os
from pathlib import Path


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


# Project ``data/`` at the Landroid repo root (GeoTIFFs live next to Boundary.geojson), not under ``backend/``.
DATA_DIR = Path(os.environ.get("LANDROID_DATA_DIR", _repo_root() / "data"))
BOUNDARY_FILENAME = os.environ.get("LANDROID_BOUNDARY_FILE", "Boundary.geojson")

# Map orthomosaic / DEM XYZ or TMS templates (see map-manifest layers.orthomosaic / .dem):
#   LANDROID_ORTHOMOSAIC_TILE_URL_TEMPLATE, LANDROID_ORTHOMOSAIC_TILE_SCHEME (xyz|tms)
#   LANDROID_DEM_TILE_URL_TEMPLATE, LANDROID_DEM_TILE_SCHEME

# When False, ``GET .../land-health`` returns 503 if Earth Engine cannot produce signals
# (instead of synthetic_demo). Default False so production/hackathon uses real Sentinel-2 NDVI
# via EE. For offline UI dev without credentials, set LANDROID_ALLOW_SYNTHETIC_LAND_HEALTH=true.
LANDROID_ALLOW_SYNTHETIC_LAND_HEALTH = os.environ.get(
    "LANDROID_ALLOW_SYNTHETIC_LAND_HEALTH", "false"
).lower() in ("1", "true", "yes")

# Set at runtime to refuse unsigned demo tokens in production.
ALLOW_DEMO_TOKENS = os.environ.get("ALLOW_DEMO_TOKENS", "true").lower() in (
    "1",
    "true",
    "yes",
)

JWT_SECRET = os.environ.get("JWT_SECRET", "").strip()
JWT_ALGORITHM = "HS256"

# Supabase API auth: ``SUPABASE_JWT_SECRET``, ``SUPABASE_URL``, ``SUPABASE_SERVICE_ROLE_KEY``
# (see ``backend/.env.example``). Read from ``os.environ`` in ``auth_user.py``.

# Insecure dev-only: accept ``email-{uuid}`` bearer without verifying a JWT (all mapped to consultant).
ALLOW_LEGACY_EMAIL_TOKENS = os.environ.get(
    "ALLOW_LEGACY_EMAIL_TOKENS", "false"
).lower() in ("1", "true", "yes")
