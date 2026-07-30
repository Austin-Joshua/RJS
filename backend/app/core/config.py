"""App-wide settings, loaded from environment / .env (FR: NFR-07 — no secrets committed)."""
from functools import lru_cache
from pathlib import Path

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict

BACKEND_ROOT = Path(__file__).resolve().parents[2]


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore", populate_by_name=True)

    # Supabase (Postgres+PostGIS persistence only — auth is Clerk, see below)
    supabase_url: str = ""
    supabase_anon_key: str = ""
    # Service role key — required for backend-side Storage writes (bucket is
    # private; the anon key can't bypass RLS/storage policies). Never send
    # this to the Flutter app.
    supabase_service_role_key: str = ""

    # Raster uploads (drone/orthomosaic NDVI GeoTIFFs, see app/services/raster_ndvi.py)
    raster_bucket: str = "field-rasters"
    raster_ndvi_blend_weight: float = 0.5  # weight on uploaded raster vs. GEE in blend_ndvi
    raster_max_upload_mb: int = 150

    # Clerk (session-token auth, FR-01/03). Prefer clerk_jwt_key (PEM public
    # key from Dashboard -> API keys -> "Show JWT public key") for networkless
    # RS256 verification; clerk_secret_key is only a fallback that fetches
    # JWKS from Clerk's Backend API per request.
    clerk_secret_key: str = ""
    clerk_jwt_key: str = ""
    clerk_authorized_parties_raw: str = Field("", alias="CLERK_AUTHORIZED_PARTIES")

    @property
    def clerk_authorized_parties(self) -> list[str]:
        return [p.strip() for p in self.clerk_authorized_parties_raw.split(",") if p.strip()]

    # Persistence — defaults to a local SQLite file so the stack runs fully
    # offline without a provisioned Supabase Postgres instance (dev/demo).
    # ponytail: swap for the Supabase Postgres+PostGIS DSN in production;
    # geometry columns fall back to JSON text on SQLite (see db/models.py).
    database_url: str = f"sqlite:///{BACKEND_ROOT / 'data' / 'farmsync.db'}"

    # Earth Engine
    gee_project_id: str = ""
    google_application_credentials: str = ""

    # Model / quantum runtime
    model_version: str = "v1"
    demo_mode: bool = False
    qaoa_timeout_s: float = 10.0
    qaoa_layers: int = 3
    encoding: str = "slack"  # "slack" | "unbalanced"
    allow_synthetic: bool = True

    # Data paths
    data_dir: Path = BACKEND_ROOT / "data"
    models_dir: Path = BACKEND_ROOT / "models"

    @property
    def model_dir(self) -> Path:
        return self.models_dir / self.model_version


@lru_cache
def get_settings() -> Settings:
    return Settings()
