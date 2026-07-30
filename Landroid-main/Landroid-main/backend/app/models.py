from typing import Literal

from pydantic import BaseModel, Field


Role = Literal["consultant", "landowner"]


class UserContext(BaseModel):
    uid: str
    email: str | None = None
    role: Role


class ParcelCreateRequest(BaseModel):
    name: str = Field(min_length=3, max_length=120)
    owner_user_id: str
    boundary_geojson_path: str = "../data/Boundary.geojson"
    ndvi_current: float = Field(ge=-1.0, le=1.0, default=0.42)
    ndvi_monthly_history: list[float] = Field(default_factory=lambda: [0.35, 0.37, 0.39, 0.4, 0.41, 0.42])
    ndvi_previous_survey: float = Field(ge=-1.0, le=1.0, default=0.46)
    area_acres: float = Field(gt=0, default=2.5)


class HealthSignal(BaseModel):
    label: str
    current: float | str
    trend: str
    confidence: float = Field(ge=0, le=100)


class LandHealthResponse(BaseModel):
    score: float = Field(ge=0, le=100)
    status: Literal["Healthy", "Moderate", "At Risk"]
    signals: list[HealthSignal]
    confidence: float = Field(ge=0, le=100)


class ZoneBand(BaseModel):
    zone: Literal["Bare/Stressed", "Sparse", "Healthy", "Dense"]
    percentage: float = Field(ge=0, le=100)


class PlantZoneResponse(BaseModel):
    zones: list[ZoneBand]
    lower_health_zone_increase: bool
    confidence: float = Field(ge=0, le=100)


class ValuationResponse(BaseModel):
    low_per_acre_inr: int
    mid_per_acre_inr: int
    high_per_acre_inr: int
    confidence: float = Field(ge=0, le=100)
    top_drivers: list[str]
    disclaimer: str
