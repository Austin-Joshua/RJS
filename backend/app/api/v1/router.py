"""Mounts every /api/v1 sub-router.

`farms` and `dashboard` are the product surface the app talks to: the brief's
flow, end to end. The remaining routers expose supporting capability on the
same entity (satellite signals, raster uploads, allocation planning) and are
not part of the farmer's path through the app.
"""
from fastapi import APIRouter

from app.api.v1 import analytics, dashboard, farms, fields, health, plan, predict, rasters, signals

router = APIRouter()
router.include_router(health.router)
router.include_router(farms.router)
router.include_router(dashboard.router)
router.include_router(fields.router)
router.include_router(signals.router)
router.include_router(rasters.router)
router.include_router(predict.router)
router.include_router(plan.router)
router.include_router(analytics.router)
