"""Output payload schemas — every response carries data_mode + timings (TRD §8)."""
from typing import Any, Literal

from pydantic import BaseModel, Field

DataMode = Literal["live", "degraded"]  # no "demo": there is no fixture path


class HealthResponse(BaseModel):
    status: str = "ok"
    earth_engine_initialized: bool
    model_loaded: bool
    model_version: str
    auth_configured: bool
    dev_login_enabled: bool = False


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


class PlanRisk(BaseModel):
    """Profit distribution of the chosen plan across correlated yield scenarios.

    Reported from the scenario draws, not optimised: CVaR is not quadratic in
    the decision variables, so the QUBO encodes the mean-variance surrogate
    instead. Keeping the two separate in the payload is deliberate.
    """

    expected_rs: float
    std_rs: float
    cvar_rs: float
    cvar_beta: float
    worst_case_rs: float | None = None
    best_case_rs: float | None = None
    n_scenarios: int | None = None


class PlanDiversification(BaseModel):
    distinct_crops: int
    n_plots: int
    crop_mix: dict[str, int]


class PlanCore(BaseModel):
    solver: Literal["sparq", "qaoa", "classical_fallback"]
    assignments: list[PlanAssignment]
    net_value_rs: float
    net_value_p10_rs: float
    net_value_p90_rs: float
    water_used_m3: float
    budget_used_rs: float
    # Expected rupees minus kappa standard deviations — the interpretable
    # "what this plan is worth at this risk appetite" figure for the UI.
    certainty_equivalent_rs: float | None = None
    # Mean minus kappa-weighted *variance* — the raw score the optimiser ranked
    # by. Quadratic (so it fits a QUBO) but not in meaningful rupee units, so it
    # belongs in the quantum panel, not on the plan screen. `net_value_rs` stays
    # the plain expected-rupees figure, because that is what a farmer can check.
    risk_adjusted_value_rs: float | None = None
    risk: PlanRisk | None = None
    diversification: PlanDiversification | None = None


class ClassicalAlternative(BaseModel):
    assignments: list[PlanAssignment]
    net_value_rs: float


class BaselineQaoaPayload(BaseModel):
    """Legacy transverse-field QAOA on the same instance — the measured contrast."""

    n_qubits: int
    encoding: str
    slack_qubits: int
    qubo_terms: int
    feasible_rate: float | None = None
    p_optimum: float | None = None
    uplift_vs_uniform: float | None = None
    uplift_vs_feasible_uniform: float | None = None
    net_value_rs: float
    t_s: float
    timed_out: bool = False


class BenchmarkPayload(BaseModel):
    solver: str = "sparq"
    n_qubits: int
    encoding: str
    qaoa_layers: int
    qubo_terms: int
    qaoa_energy: float | None
    classical_optimum: float
    classical_optimum_objective: float | None = None
    approximation_ratio: float | None
    matched_optimum: bool
    p_optimum: float | None = None
    uplift_vs_uniform: float | None = None
    # The harder baseline: uniform over the C^P structurally-valid assignments
    # rather than over all 2^n bitstrings. Lead with this one.
    uplift_vs_feasible_uniform: float | None = None
    feasible_rate: float | None = None
    # Fraction of samples satisfying one-crop-per-plot. Exactly 1.0 under the
    # XY-ring mixer, because Hamming weight per block is a conserved quantity.
    simplex_rate: float | None = None
    t_qaoa_s: float
    t_classical_s: float
    timed_out: bool = False
    # Real COBYLA trace across INTERP depth stages — this is what the
    # analytics chart plots, replacing the synthetic curve it drew before.
    convergence: list[dict[str, Any]] = Field(default_factory=list)
    warm_start: dict[str, dict[str, float]] = Field(default_factory=dict)
    risk_kappa: float | None = None
    risk_scenarios: int | None = None
    risk_cross_crop_rho: float | None = None
    plan_std_rs: float | None = None
    risk_neutral_std_rs: float | None = None
    risk_neutral_cvar_rs: float | None = None
    profit_histogram: list[dict[str, Any]] = Field(default_factory=list)
    baseline_qaoa: BaselineQaoaPayload | None = None
    claim: str = ""


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
