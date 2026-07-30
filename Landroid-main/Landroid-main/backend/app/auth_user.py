from __future__ import annotations

import logging
import os
from dataclasses import dataclass
from typing import Any, Literal

import httpx
import jwt

from .config import (
    ALLOW_DEMO_TOKENS,
    ALLOW_LEGACY_EMAIL_TOKENS,
    JWT_ALGORITHM,
    JWT_SECRET,
)

_log = logging.getLogger(__name__)

Role = Literal["consultant", "landowner"]


@dataclass(frozen=True)
class AuthUser:
    sub: str
    role: Role


def _role_from_demo_token(raw: str) -> AuthUser | None:
    if not ALLOW_DEMO_TOKENS:
        return None
    if raw == "demo-consultant":
        return AuthUser(sub="00000000-0000-4000-8000-0000000000c1", role="consultant")
    if raw == "demo-owner":
        return AuthUser(sub="00000000-0000-4000-8000-0000000000b1", role="landowner")
    if raw == "demo-owner-2":
        return AuthUser(sub="00000000-0000-4000-8000-0000000000b2", role="landowner")
    return None


def _legacy_email_token(raw: str) -> AuthUser | None:
    if not ALLOW_LEGACY_EMAIL_TOKENS:
        return None
    if raw.startswith("email-"):
        _log.warning(
            "Authorization used legacy email-* bearer; set SUPABASE_JWT_SECRET and send access tokens instead."
        )
        return AuthUser(sub=raw.removeprefix("email-"), role="consultant")
    return None


def _looks_like_jwt(raw: str) -> bool:
    parts = raw.split(".")
    return len(parts) == 3 and all(len(p) > 0 for p in parts)


def _normalize_role(value: Any) -> Role | None:
    if value == "landowner":
        return "landowner"
    if value == "consultant":
        return "consultant"
    return None


def _role_from_jwt_user_metadata(payload: dict[str, Any]) -> Role | None:
    um = payload.get("user_metadata")
    if not isinstance(um, dict):
        return None
    return _normalize_role(um.get("app_role"))


def _fetch_profile_app_role(sub: str) -> Role | None:
    base = os.environ.get("SUPABASE_URL", "").strip().rstrip("/")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip()
    if not base or not key:
        return None
    try:
        r = httpx.get(
            f"{base}/rest/v1/profiles",
            params={"id": f"eq.{sub}", "select": "app_role"},
            headers={
                "apikey": key,
                "Authorization": f"Bearer {key}",
            },
            timeout=10.0,
        )
        r.raise_for_status()
        rows = r.json()
        if not isinstance(rows, list) or not rows:
            return None
        return _normalize_role(rows[0].get("app_role"))
    except Exception as e:
        _log.warning("profiles lookup failed for sub=%s: %s", sub[:8], e)
        return None


def _auth_user_from_supabase_access_token(raw: str) -> AuthUser | None:
    secret = os.environ.get("SUPABASE_JWT_SECRET", "").strip()
    if not secret or not _looks_like_jwt(raw):
        return None
    try:
        payload = jwt.decode(
            raw,
            secret,
            algorithms=["HS256"],
            audience="authenticated",
        )
    except jwt.PyJWTError:
        try:
            payload = jwt.decode(
                raw,
                secret,
                algorithms=["HS256"],
                options={"verify_aud": False},
            )
        except jwt.PyJWTError:
            return None

    sub = str(payload.get("sub", "")).strip()
    if not sub:
        return None

    role = _fetch_profile_app_role(sub)
    if role is None:
        role = _role_from_jwt_user_metadata(payload)
    if role is None:
        role = "consultant"

    return AuthUser(sub=sub, role=role)


def _auth_user_from_custom_jwt(raw: str) -> AuthUser | None:
    if not JWT_SECRET:
        return None
    try:
        payload = jwt.decode(raw, JWT_SECRET, algorithms=[JWT_ALGORITHM])
        sub = str(payload.get("sub", ""))
        role = payload.get("role", "landowner")
        if role not in ("consultant", "landowner"):
            role = "landowner"
        if sub:
            return AuthUser(sub=sub, role=role)  # type: ignore[arg-type]
    except jwt.PyJWTError:
        return None
    return None


def parse_bearer(authorization: str | None) -> AuthUser | None:
    if not authorization or not authorization.lower().startswith("bearer "):
        return None
    raw = authorization.split(None, 1)[1].strip()
    if not raw:
        return None

    demo = _role_from_demo_token(raw)
    if demo:
        return demo

    su = _auth_user_from_supabase_access_token(raw)
    if su:
        return su

    custom = _auth_user_from_custom_jwt(raw)
    if custom:
        return custom

    legacy = _legacy_email_token(raw)
    if legacy:
        return legacy

    return None
