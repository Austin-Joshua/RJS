"""Clerk session-token verification with demo-bearer bypass (FR-01, FR-03).

`Bearer demo-farmer` / `Bearer demo-officer` work without a Clerk instance so
the app is demoable on a venue network with no auth backend reachable.
"""
from dataclasses import dataclass

from clerk_backend_api import AuthenticateRequestOptions, authenticate_request
from fastapi import Header, HTTPException, Request, status

from app.core.config import get_settings

DEMO_TOKENS = {
    "demo-farmer": {"sub": "demo-farmer", "role": "farmer"},
    "demo-officer": {"sub": "demo-officer", "role": "officer"},
}


@dataclass
class CurrentUser:
    id: str
    role: str  # "farmer" | "officer"


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


async def get_current_user(request: Request, authorization: str | None = Header(default=None)) -> CurrentUser:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing bearer token")

    token = authorization.split(" ", 1)[1].strip()

    if token in DEMO_TOKENS:
        claims = DEMO_TOKENS[token]
        return CurrentUser(id=claims["sub"], role=claims["role"])

    claims = _verify_clerk_token(request)
    # "role" is not a default Clerk session claim — add a custom claim in the
    # Clerk Dashboard (Sessions -> Customize session token):
    #   {"role": "{{user.public_metadata.role}}"}
    # and set each user's public_metadata.role to "farmer" or "officer".
    role = claims.get("role") or "farmer"
    return CurrentUser(id=claims["sub"], role=role)
