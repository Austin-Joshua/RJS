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

    # --- Developer login (off by default, for local work and demos) ---------
    # Both must be set for it to do anything, and the token is compared in
    # constant time. This is not the old `demo-farmer` bypass: that was a
    # hardcoded string every build accepted, so anyone could read one shared
    # profile. This is an operator-chosen secret that resolves to a *specific*
    # account id, so the seeded demo profile is isolated exactly like a real
    # Google account's. Leave both blank in production — `/healthz` reports
    # `dev_login_enabled` so an accidental deploy with it on is visible.
    dev_login_user: str = ""
    dev_login_token: str = ""

    @property
    def dev_login_enabled(self) -> bool:
        return bool(self.dev_login_user and self.dev_login_token)

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
    qaoa_timeout_s: float = 10.0
    qaoa_layers: int = 3
    encoding: str = "slack"  # "slack" | "unbalanced" — legacy QAOA path only
    allow_synthetic: bool = True

    # SPARQ — Simplex-Preserving Adaptive Risk-aware QAOA (app/quantum/sparq.py).
    # Primary solver for /plan. The legacy QAOA above is still built and run on
    # every request as the head-to-head baseline (FR-44 honesty discipline
    # extended: we show the quantum predecessor, not just the classical one).
    solver: str = "sparq"  # "sparq" | "qaoa"
    # Run the legacy transverse-field QAOA alongside SPARQ on every /plan call
    # so the head-to-head is live rather than a stale slide. It is the slowest
    # thing on the critical path (it explores 2^n where SPARQ explores C^P), so
    # set false if a slow venue machine puts NFR-02's 8s p95 at risk — the plan
    # itself never depends on it.
    run_baseline_qaoa: bool = True
    sparq_layers: int = 3  # p=3 — sweep showed p=5 costs 3x wall time for noise
    sparq_warm_start_tau: float = 0.35  # softmax temperature on net value
    sparq_maxiter_per_layer: int = 60  # COBYLA iterations per INTERP stage
    sparq_shots: int = 2048

    # Risk model (app/quantum/risk.py). kappa is the mean-variance trade-off:
    # 0 reproduces the old expected-value-only plan exactly, higher values buy
    # variance reduction with expected rupees. Farmer-overridable per request.
    risk_kappa: float = 0.35
    risk_scenarios: int = 256
    risk_cross_crop_rho: float = 0.45  # shared-monsoon correlation between crops
    risk_cvar_beta: float = 0.2  # reported tail fraction, not optimised

    # Data paths
    data_dir: Path = BACKEND_ROOT / "data"
    models_dir: Path = BACKEND_ROOT / "models"

    @property
    def model_dir(self) -> Path:
        return self.models_dir / self.model_version


@lru_cache
def get_settings() -> Settings:
    return Settings()
