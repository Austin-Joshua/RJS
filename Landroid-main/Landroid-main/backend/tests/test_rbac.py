from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)

_DEMO_LANDOWNER_UID = "00000000-0000-4000-8000-0000000000b1"


def test_landowner_cannot_create_parcel() -> None:
    response = client.post(
        "/api/v1/parcels",
        headers={"Authorization": "Bearer demo-owner"},
        json={
            "name": "Denied Parcel",
            "owner_user_id": _DEMO_LANDOWNER_UID,
        },
    )
    assert response.status_code == 403


def test_consultant_can_create_parcel() -> None:
    response = client.post(
        "/api/v1/parcels",
        headers={"Authorization": "Bearer demo-consultant"},
        json={
            "name": "Allowed Parcel",
            "owner_user_id": _DEMO_LANDOWNER_UID,
        },
    )
    assert response.status_code == 200
    assert "parcel" in response.json()
    assert response.json()["parcel"]["id"].startswith("parcel-")
