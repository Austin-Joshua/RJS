"""Clerk session-token verification, backed by Google Sign-In.

Google is configured as the social connection in the Clerk dashboard, so the
user sees "Continue with Google" and the backend still verifies one kind of
credential: a Clerk session token, RS256-verified against the instance JWT key
with no network call on the hot path.

There is no hardcoded bypass. The old `demo-farmer` bearer was a fixed string
every build accepted, so anyone who knew it could read and write one shared
profile — the cross-account leakage the product forbids.

What exists instead is an **operator-configured** developer login (`_dev_login`
below): inert unless both `DEV_LOGIN_USER` and `DEV_LOGIN_TOKEN` are set, gated
on a secret the operator chooses, and resolving to a specific account whose data
is scoped by the same `farmer_id` filter as any Google user's. `/healthz`
reports whether it is on. Tests use neither — they override the
`get_current_user` dependency in `tests/conftest.py`, which ships in no build.

`CurrentUser.id` is the Clerk subject claim (or the configured dev user) and is
the sole partition key for every farm, soil card and recommendation.
"""
import secrets
from dataclasses import dataclass

from clerk_backend_api import AuthenticateRequestOptions, authenticate_request
from fastapi import Header, HTTPException, Request, status

from app.core.config import get_settings


@dataclass
class CurrentUser:
    id: str
    role: str  # "farmer" | "officer"
    email: str | None = None


def _verify_clerk_token(request: Request) -> dict:
    settings = get_settings()
    if not settings.clerk_jwt_key and not settings.clerk_secret_key:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Auth not configured")

    state = authenticate_request(
        request,
        AuthenticateRequestOptions(
            secret_key=settings.clerk_secret_key or None,
            jwt_key=settings.clerk_jwt_key or None,
            authorized_parties=settings.clerk_authorized_parties or None,
            accepts_token=["session_token"],
        ),
    )
    if not state.is_signed_in:
        reason = state.reason.name if state.reason else "unauthorized"
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=f"Invalid session token ({reason})")
    return state.payload or {}


def _dev_login(token: str) -> CurrentUser | None:
    """Resolve an operator-configured development token, or None.

    Returns None unless both `DEV_LOGIN_USER` and `DEV_LOGIN_TOKEN` are set, so
    it is completely inert in a default deployment. The comparison is constant
    time because the token is a shared secret.

    The account it resolves to is a normal account: its farms are scoped by the
    same `farmer_id` filter as everyone else's, so enabling this does not let
    anyone read another user's data — it only provides a way in without Google.
    """
    settings = get_settings()
    if not settings.dev_login_enabled:
        return None
    if not secrets.compare_digest(token, settings.dev_login_token):
        return None
    return CurrentUser(id=settings.dev_login_user, role="farmer", email=f"{settings.dev_login_user}@local")


async def get_current_user(request: Request, authorization: str | None = Header(default=None)) -> CurrentUser:
    """Resolve the caller from their Clerk session token, or 401.

    Every data route depends on this, and the returned `id` is what scopes the
    query. One Google account maps to one Clerk subject maps to one profile.
    """
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing bearer token")

    dev_user = _dev_login(authorization.split(" ", 1)[1].strip())
    if dev_user is not None:
        return dev_user

    claims = _verify_clerk_token(request)
    sub = claims.get("sub")
    if not sub:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Session token carries no subject")

    # "role" is not a default Clerk session claim — add a custom claim in the
    # Clerk Dashboard (Sessions -> Customize session token):
    #   {"role": "{{user.public_metadata.role}}", "email": "{{user.primary_email_address}}"}
    # and set each user's public_metadata.role to "farmer" or "officer".
    # Defaulting to "farmer" means a freshly signed-up Google user can use the
    # app immediately; elevating to "officer" is an explicit dashboard action.
    return CurrentUser(id=sub, role=claims.get("role") or "farmer", email=claims.get("email"))
