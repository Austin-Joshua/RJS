"""Analytics dashboard data sources (FR-60..66). These serve trained-artifact
JSON verbatim — FR-33 forbids a hardcoded metric anywhere in this path."""
import json

from fastapi import APIRouter, HTTPException, status

from app.core.config import get_settings

router = APIRouter(prefix="/analytics", tags=["analytics"])


def _read_json_artifact(filename: str) -> dict:
    settings = get_settings()
    path = settings.model_dir / filename
    if not path.exists():
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"{filename} not generated yet. Run the corresponding scripts/*.py.",
        )
    with open(path, encoding="utf-8") as f:
        return json.load(f)


@router.get("/model-metrics")
async def model_metrics() -> dict:
    return _read_json_artifact("metrics.json")


@router.get("/feature-importance")
async def feature_importance() -> dict:
    return _read_json_artifact("shap_global.json")


@router.get("/yield-vs-rainfall")
async def yield_vs_rainfall() -> dict:
    return _read_json_artifact("yield_vs_rainfall.json")


@router.get("/quantum-benchmark")
async def quantum_benchmark() -> dict:
    return _read_json_artifact("benchmark.json")
