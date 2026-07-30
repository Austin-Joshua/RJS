"""Output payload schemas — every response carries data_mode + timings (TRD §8)."""
from typing import Any, Literal

from pydantic import BaseModel, Field

DataMode = Literal["live", "degraded", "demo"]


class HealthResponse(BaseModel):
    status: str = "ok"
    earth_engine_initialized: bool
    model_loaded: bool
    model_version: str
    demo_mode: bool


class PlotOut(BaseModel):
    id: str
    label: str
    area_ha: float


class FieldResponse(BaseModel):
    id: str
    name: str
    centroid: dict[str, float]
    area_ha: float
    district: str
    state: str
    sowing_date: str | None
    plots: list[PlotOut]


class SignalsResponse(BaseModel):
    field_id: str
    data_mode: DataMode
    fetched_at: str
    soil: dict[str, Any]
    weather: dict[str, Any]
    ndvi: dict[str, Any]
    provenance: dict[str, Any]


class RasterAssetResponse(BaseModel):
    id: str
    field_id: str
    kind: str
    file_name: str
    band: int
    crs: str | None
    width: int | None
    height: int | None
    bounds: dict[str, Any] | None
    stats: list[dict[str, Any]] | None
    zonal_ndvi: dict[str, Any] | None
    is_active: bool
    uploaded_at: str


class RasterUploadResponse(BaseModel):
    asset: RasterAssetResponse
    analysis: dict[str, Any]


class NdviSeriesPoint(BaseModel):
    date: str
    ndvi_mean: float | None


class NdviSeriesResponse(BaseModel):
    field_id: str
    data_mode: DataMode
    series: list[NdviSeriesPoint]


class YieldPrediction(BaseModel):
    crop: str
    yield_t_ha: float
    p10: float
    p90: float
    shap: dict[str, float]
    confidence: Literal["full", "reduced"]


class PredictYieldResponse(BaseModel):
    field_id: str
    data_mode: DataMode
    predictions: list[YieldPrediction]


class PlanAssignment(BaseModel):
    plot_id: str
    crop: str
    yield_t_ha: float
    p10: float
    p90: float


class PlanCore(BaseModel):
    solver: Literal["qaoa", "classical_fallback"]
    assignments: list[PlanAssignment]
    net_value_rs: float
    net_value_p10_rs: float
    net_value_p90_rs: float
    water_used_m3: float
    budget_used_rs: float


class ClassicalAlternative(BaseModel):
    assignments: list[PlanAssignment]
    net_value_rs: float


class BenchmarkPayload(BaseModel):
    n_qubits: int
    encoding: str
    qaoa_layers: int
    qubo_terms: int
    qaoa_energy: float | None
    classical_optimum: float
    approximation_ratio: float | None
    matched_optimum: bool
    p_optimum: float | None = None
    uplift_vs_uniform: float | None = None
    feasible_rate: float | None = None
    t_qaoa_s: float
    t_classical_s: float
    claim: str = (
        "Simulated QAOA recovers the exact optimum at demo scale. No runtime "
        "advantage over classical is claimed or observed at n <= 25 qubits."
    )


class FertilizerAdvisory(BaseModel):
    urea_bags: int
    dap_bags: int
    mop_bags: int
    split_schedule: list[dict[str, Any]]
    soil_class: str


class PhAdvisory(BaseModel):
    soil_ph: float
    category: str
    amendment: str
    dose_t_ha: float
    caveat: str = "District-level indicative values; confirm with a soil test before applying amendments at cost."


class IrrigationAdvisory(BaseModel):
    etc_mm: float
    effective_rainfall_mm: float
    net_irrigation_mm: float
    guidance: str


class AdvisoryPayload(BaseModel):
    fertilizer: FertilizerAdvisory
    ph: PhAdvisory
    irrigation: IrrigationAdvisory
    why: dict[str, Any]


class PlanResponse(BaseModel):
    request_id: str
    plan: PlanCore
    alternatives: dict[str, ClassicalAlternative]
    benchmark: BenchmarkPayload
    advisory: AdvisoryPayload
    data_mode: DataMode
    timings: dict[str, float]


class ModelMetricsResponse(BaseModel):
    model_config = {"extra": "allow"}


class QuantumBenchmarkResponse(BaseModel):
    model_config = {"extra": "allow"}
