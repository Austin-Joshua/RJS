"""Mounts every /api/v1 sub-router (TRD §8)."""
from fastapi import APIRouter

from app.api.v1 import analytics, fields, health, plan, predict, rasters, signals

router = APIRouter()
router.include_router(health.router)
router.include_router(fields.router)
router.include_router(signals.router)
router.include_router(rasters.router)
router.include_router(predict.router)
router.include_router(plan.router)
router.include_router(analytics.router)
