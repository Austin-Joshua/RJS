"""Supabase JWT + profiles role resolution for ``parse_bearer``."""

from __future__ import annotations

import jwt
import pytest


def test_parse_bearer_supabase_jwt_landowner_from_profile(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("SUPABASE_JWT_SECRET", "unit-test-jwt-secret")
    monkeypatch.setenv("SUPABASE_URL", "https://unit-test.supabase.co")
    monkeypatch.setenv("SUPABASE_SERVICE_ROLE_KEY", "unit-test-sr-key")

    def fake_get(url: str, params: object = None, headers: object = None, timeout: object = None):
        class R:
            status_code = 200

            def raise_for_status(self) -> None:
                return None

            def json(self) -> list[dict[str, str]]:
                return [{"app_role": "landowner"}]

        return R()

    monkeypatch.setattr("app.auth_user.httpx.get", fake_get)

    from app.auth_user import parse_bearer

    sub = "00000000-0000-4000-8000-0000000000b1"
    token = jwt.encode(
        {"sub": sub, "aud": "authenticated"},
        "unit-test-jwt-secret",
        algorithm="HS256",
    )
    user = parse_bearer(f"Bearer {token}")
    assert user is not None
    assert user.sub == sub
    assert user.role == "landowner"


def test_parse_bearer_demo_still_works() -> None:
    from app.auth_user import parse_bearer

    user = parse_bearer("Bearer demo-owner")
    assert user is not None
    assert user.role == "landowner"
