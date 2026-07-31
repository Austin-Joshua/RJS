"""Test harness.

`DATABASE_URL` must be set before `app.main` (and its transitive imports) is
first loaded, so it is assigned at import time rather than in a fixture.

Authentication is done by overriding the `get_current_user` dependency. That is
deliberate: the app has no bypass token, because a static credential that grants
access to a shared profile is exactly the cross-account leakage the product
forbids. The override lives here, in the test harness, and ships in nothing.
"""
import os
from pathlib import Path

_TEST_DB = Path(__file__).resolve().parent / "_test.db"
_TEST_DB.unlink(missing_ok=True)
os.environ.setdefault("DATABASE_URL", f"sqlite:///{_TEST_DB}")

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from app.core.security import CurrentUser, get_current_user  # noqa: E402
from app.main import app  # noqa: E402


class _Identity:
    """Mutable stand-in for the signed-in user, swappable mid-test.

    Lets one TestClient act as several Google accounts in sequence, which is
    what the per-account isolation tests need.
    """

    def __init__(self) -> None:
        self.user = CurrentUser(id="user-a", role="farmer", email="a@example.com")

    def as_user(self, user_id: str, role: str = "farmer", email: str | None = None) -> CurrentUser:
        self.user = CurrentUser(id=user_id, role=role, email=email or f"{user_id}@example.com")
        return self.user


@pytest.fixture(scope="session")
def identity() -> _Identity:
    return _Identity()


@pytest.fixture(scope="session")
def client(identity: _Identity):
    async def _override() -> CurrentUser:
        return identity.user

    app.dependency_overrides[get_current_user] = _override
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.pop(get_current_user, None)


@pytest.fixture
def anon_client():
    """A client with no auth override — for asserting routes actually 401."""
    with TestClient(app) as c:
        original = app.dependency_overrides.pop(get_current_user, None)
        try:
            yield c
        finally:
            if original is not None:
                app.dependency_overrides[get_current_user] = original
