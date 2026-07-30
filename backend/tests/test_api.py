"""API contract tests (TRD §13): auth enforcement, every response carries
data_mode/timings, officer read-only, farmer-scoped access."""
import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.ml.yield_model import get_yield_model

BOUNDARY = {
    "type": "Polygon",
    "coordinates": [[[79.05, 10.75], [79.06, 10.75], [79.06, 10.76], [79.05, 10.76], [79.05, 10.75]]],
}


@pytest.fixture(scope="module")
def client():
    with TestClient(app) as c:
        yield c


def test_healthz_no_auth_required(client: TestClient) -> None:
    resp = client.get("/api/v1/healthz")
    assert resp.status_code == 200
    body = resp.json()
    assert {"model_loaded", "demo_mode", "earth_engine_initialized", "model_version"} <= body.keys()


def test_protected_endpoint_requires_bearer(client: TestClient) -> None:
    resp = client.get("/api/v1/fields")
    assert resp.status_code == 401


def test_field_lifecycle_and_plan(client: TestClient) -> None:
    if get_yield_model() is None:
        pytest.skip("Model not trained — run scripts/train_model.py first")

    farmer_headers = {"Authorization": "Bearer demo-farmer"}
    officer_headers = {"Authorization": "Bearer demo-officer"}

    create_resp = client.post(
        "/api/v1/fields",
        headers=farmer_headers,
        json={
            "name": "Contract test field",
            "boundary_geojson": BOUNDARY,
            "plots": [{"label": "Plot 1", "area_ha": 0.5}, {"label": "Plot 2", "area_ha": 0.5}],
            "sowing_date": "2026-06-01",
        },
    )
    assert create_resp.status_code == 201, create_resp.text
    field = create_resp.json()
    field_id = field["id"]
    assert field["district"] and field["state"]

    signals_resp = client.get(f"/api/v1/fields/{field_id}/signals", headers=farmer_headers)
    assert signals_resp.status_code == 200
    assert signals_resp.json()["data_mode"] == "demo"  # FR-23, forced by conftest's DEMO_MODE

    # Officers are read-only server-side (FR-03), not just hidden in the UI.
    forbidden_resp = client.delete(f"/api/v1/fields/{field_id}", headers=officer_headers)
    assert forbidden_resp.status_code == 403

    plot_ids = [p["id"] for p in field["plots"]]
    plan_resp = client.post(
        "/api/v1/plan",
        headers=farmer_headers,
        json={
            "field_id": field_id,
            "plots": [{"plot_id": pid, "area_ha": 0.5} for pid in plot_ids],
            "candidate_crops": ["paddy", "black_gram"],
            "constraints": {"water_m3": 5000, "budget_rs": 60000},
        },
    )
    assert plan_resp.status_code == 200, plan_resp.text
    plan = plan_resp.json()
    assert plan["data_mode"] and "timings" in plan and "request_id" in plan
    assert plan["plan"]["solver"] in ("qaoa", "classical_fallback")
    assert plan["plan"]["assignments"]
    assert "classical" in plan["alternatives"]

    advisory_resp = client.get(f"/api/v1/fields/{field_id}/advisory", headers=farmer_headers)
    assert advisory_resp.status_code == 200
    assert "fertilizer" in advisory_resp.json()

    cleanup_resp = client.delete(f"/api/v1/fields/{field_id}", headers=farmer_headers)
    assert cleanup_resp.status_code == 204


def test_analytics_model_metrics_served_verbatim(client: TestClient) -> None:
    resp = client.get("/api/v1/analytics/model-metrics")
    if resp.status_code == 503:
        pytest.skip("metrics.json not generated — run scripts/train_model.py first")
    body = resp.json()
    assert "protocols" in body and "training_data_source" in body
