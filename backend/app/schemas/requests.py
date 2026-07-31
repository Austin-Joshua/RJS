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


class SoilReadingsIn(BaseModel):
    """Raw values the farmer types off a lab report or Soil Health Card (§2.2).

    Only pH and NPK are required. Everything else sharpens the recommendation
    when present, and the soil card says explicitly which checks it could not
    run when it is absent — a farmer without an EC reading still gets a card.
    """

    soil_type: str = Field(..., description="alluvial | black | red | laterite | clay | clay_loam | loam | sandy_loam | sandy")
    n_kg_ha: float = Field(..., ge=0, le=2000)
    p_kg_ha: float = Field(..., ge=0, le=500)
    k_kg_ha: float = Field(..., ge=0, le=2000)
    ph: float = Field(..., ge=0, le=14)
    oc_pct: float | None = Field(None, ge=0, le=10)
    ec_ds_m: float | None = Field(None, ge=0, le=50)
    moisture_pct: float | None = Field(None, ge=0, le=100)
    water_available_m3: float | None = Field(None, ge=0, description="Irrigation water for the season")


class FarmCreateRequest(BaseModel):
    """Create a farm plus its first soil card in one call (§2.2 -> §2.3).

    Location can be given either as a drawn boundary polygon or as a point plus
    an area, because a smallholder entering their land on a phone should not be
    forced to trace a polygon before they can get a recommendation.
    """

    name: str = Field(..., min_length=1, max_length=120)
    boundary_geojson: dict[str, Any] | None = None
    lat: float | None = Field(None, ge=-90, le=90)
    lon: float | None = Field(None, ge=-180, le=180)
    area_ha: float | None = Field(None, gt=0, le=10000)
    sowing_date: str | None = None
    soil: SoilReadingsIn


class RankCropsRequest(BaseModel):
    """Run the feasibility filter and the quantum sequencer for one farm (§2.4-2.5)."""

    candidate_crops: list[str] | None = Field(
        None, description="Defaults to the full crop catalogue; the feasibility gates filter it."
    )
    price_overrides: dict[str, float] | None = None


class PlanRequest(BaseModel):
    field_id: str
    plots: list[PlotAllocationIn] = Field(..., min_length=1)
    candidate_crops: list[str] = Field(..., min_length=1)
    constraints: ConstraintsIn
    price_overrides: dict[str, float] | None = None
    # Mean-variance trade-off for the SPARQ objective. 0 reproduces the old
    # expected-value-only plan; higher values trade expected rupees for a
    # tighter profit distribution. Omitted -> server default (`risk_kappa`).
    risk_aversion: float | None = Field(None, ge=0, le=3, description="0 = ignore risk")
