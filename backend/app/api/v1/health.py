from fastapi import APIRouter

from app.adapters.ndvi_gee import is_earth_engine_ready
from app.core.config import get_settings
from app.ml.yield_model import get_yield_model
from app.schemas.responses import HealthResponse

router = APIRouter(tags=["health"])


@router.get("/healthz", response_model=HealthResponse)
async def healthz() -> HealthResponse:
    settings = get_settings()
    return HealthResponse(
        earth_engine_initialized=is_earth_engine_ready(),
        model_loaded=get_yield_model() is not None,
        model_version=settings.model_version,
        # Whether a Clerk verification key is present. Without one every data
        # route 401s, so this is the first thing to check on a bad deploy.
        auth_configured=bool(settings.clerk_jwt_key or settings.clerk_secret_key),
        # Loud on purpose: if this is ever true on a deployed instance, someone
        # shipped a development credential.
        dev_login_enabled=settings.dev_login_enabled,
    )
