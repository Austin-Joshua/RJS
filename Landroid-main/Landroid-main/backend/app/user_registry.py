"""Resolve registered landowner identifiers to stable user ids (demo prototype)."""

from __future__ import annotations

import re


def _normalize_phone(raw: str) -> str:
    s = re.sub(r"\s+", "", raw.strip())
    digits = re.sub(r"\D", "", s)
    if len(digits) >= 10:
        return digits[-10:]
    return digits


# Demo accounts (must match Flutter DemoCredentials UIDs when using demo emails).
_REGISTRY_EMAIL: dict[str, str] = {
    "landowner.demo@landroid.local": "00000000-0000-4000-8000-0000000000b1",
}

# Optional phone keys: last 10 digits only.
_REGISTRY_PHONE: dict[str, str] = {
    "9876543210": "00000000-0000-4000-8000-0000000000b1",
}


def resolve_owner_user_id(
    *,
    owner_user_id: str | None,
    owner_email: str | None,
    owner_phone: str | None,
) -> str:
    """
    Return the landowner ``sub`` to attach to the parcel.

    - If ``owner_user_id`` is set (non-empty), it is used as-is (consultant-supplied UUID).
    - Otherwise ``owner_email`` or ``owner_phone`` must match a registered landowner.
    """
    if owner_user_id and owner_user_id.strip():
        return owner_user_id.strip()

    email = (owner_email or "").strip().lower()
    if email:
        uid = _REGISTRY_EMAIL.get(email)
        if uid:
            return uid
        raise ValueError(
            "Unknown landowner email. The landowner must register first, "
            "or pass owner_user_id from their profile."
        )

    phone = _normalize_phone(owner_phone or "")
    if phone:
        uid = _REGISTRY_PHONE.get(phone)
        if uid:
            return uid
        raise ValueError(
            "Unknown landowner phone number. Use a registered number or owner_user_id."
        )

    raise ValueError("Provide owner_user_id, owner_email, or owner_phone.")
