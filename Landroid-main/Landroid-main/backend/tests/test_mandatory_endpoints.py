"""Contract tests aligned with current parcel + AI API shapes."""

from pathlib import Path

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)

_REPO_ROOT = Path(__file__).resolve().parents[2]
_BOUNDARY_FILE = _REPO_ROOT / "data" / "Boundary.geojson"

# Matches demo landowner JWT / demo-owner token (see app.auth_user).
_DEMO_LANDOWNER_UID = "00000000-0000-4000-8000-0000000000b1"

# Distinct WGS84 polygon (Brazil) so GEE / soil signals differ from Tamil Nadu parcel.
_BOUNDARY_B_ALT = """{"type":"FeatureCollection","features":[{"type":"Feature","geometry":{"type":"Polygon","coordinates":[[[-47.52,-15.78],[-47.48,-15.78],[-47.48,-15.74],[-47.52,-15.74],[-47.52,-15.78]]]},"properties":{}}]}"""


def _boundary_text() -> str:
    return _BOUNDARY_FILE.read_text(encoding="utf-8")


def _create_parcel(*, name: str = "M-criteria Parcel", boundary_geojson: str | None = None) -> str:
    payload: dict = {
        "name": name,
        "owner_user_id": _DEMO_LANDOWNER_UID,
    }
    if boundary_geojson is not None:
        payload["boundary_geojson"] = boundary_geojson
    response = client.post(
        "/api/v1/parcels",
        headers={"Authorization": "Bearer demo-consultant"},
        json=payload,
    )
    assert response.status_code == 200, response.text
    return response.json()["parcel"]["id"]


def test_ai_modules_return_confidence() -> None:
    parcel_id = _create_parcel()
    health = client.get(
        f"/api/v1/ai/{parcel_id}/land-health",
        headers={"Authorization": "Bearer demo-owner"},
    )
    zones = client.get(
        f"/api/v1/ai/{parcel_id}/plant-zones",
        headers={"Authorization": "Bearer demo-owner"},
    )
    assert health.status_code == 200
    assert zones.status_code == 200
    assert "confidence" in health.json()["land_health"]
    assert "confidence" in zones.json()["plant_zones"]


def test_landowner_cannot_access_other_owner_parcel() -> None:
    parcel_id = _create_parcel()
    forbidden = client.get(
        f"/api/v1/parcels/{parcel_id}",
        headers={"Authorization": "Bearer demo-owner-2"},
    )
    assert forbidden.status_code == 403


def test_ai_output_changes_with_parcel_input() -> None:
    parcel_a = _create_parcel(name="Parcel A", boundary_geojson=_boundary_text())
    parcel_b = _create_parcel(name="Parcel B", boundary_geojson=_BOUNDARY_B_ALT)

    score_a = client.get(
        f"/api/v1/ai/{parcel_a}/land-health",
        headers={"Authorization": "Bearer demo-owner"},
    ).json()["land_health"]["score"]
    score_b = client.get(
        f"/api/v1/ai/{parcel_b}/land-health",
        headers={"Authorization": "Bearer demo-owner"},
    ).json()["land_health"]["score"]
    assert score_a != score_b
