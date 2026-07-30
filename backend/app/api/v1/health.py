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
        demo_mode=settings.demo_mode,
    )
