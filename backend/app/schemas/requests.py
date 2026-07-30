"""Input payload schemas — the Flutter → FastAPI contract (TRD §8)."""
from typing import Any

from pydantic import BaseModel, Field


class PlotIn(BaseModel):
    label: str
    area_ha: float = Field(..., gt=0)
    geom_geojson: dict[str, Any] | None = None


class FieldCreateRequest(BaseModel):
    name: str
    boundary_geojson: dict[str, Any] = Field(..., description="GeoJSON Polygon for the field boundary")
    plots: list[PlotIn] = Field(default_factory=list)
    sowing_date: str | None = Field(None, description="ISO date; falls back to season default")


class FieldBoundaryUpdateRequest(BaseModel):
    boundary_geojson: dict[str, Any]


class SoilOverrideRequest(BaseModel):
    n_kg_ha: float = Field(..., ge=0)
    p_kg_ha: float = Field(..., ge=0)
    k_kg_ha: float = Field(..., ge=0)
    ph: float = Field(..., ge=0, le=14)
    oc_pct: float = Field(..., ge=0)
    ec_ds_m: float | None = None


class PredictYieldRequest(BaseModel):
    field_id: str
    crops: list[str] = Field(..., min_length=1)


class ConstraintsIn(BaseModel):
    water_m3: float = Field(..., ge=0, description="Total available irrigation water")
    budget_rs: float = Field(..., ge=0, description="Total cash budget in INR")


class PlotAllocationIn(BaseModel):
    plot_id: str
    area_ha: float = Field(..., gt=0)


class PlanRequest(BaseModel):
    field_id: str
    plots: list[PlotAllocationIn] = Field(..., min_length=1)
    candidate_crops: list[str] = Field(..., min_length=1)
    constraints: ConstraintsIn
    price_overrides: dict[str, float] | None = None
