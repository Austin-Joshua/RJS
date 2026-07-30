"""Shared FastAPI dependencies: auth, DB session, and role-scoped field access
enforced server-side (FR-03 — not just hidden in the UI)."""
from fastapi import Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.core.security import CurrentUser, get_current_user
from app.db import models
from app.db.session import get_db

__all__ = [
    "get_current_user",
    "get_db",
    "CurrentUser",
    "get_owned_field",
    "get_writable_field",
    "require_farmer",
    "load_owned_field",
]


def load_owned_field(field_id: str, db: Session, user: CurrentUser) -> models.Field:
    """Shared ownership check for endpoints where `field_id` comes from the
    request body (predict/plan) rather than the URL path (see get_owned_field)."""
    field = db.get(models.Field, field_id)
    if field is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Field not found")
    if user.role == "farmer" and field.farmer_id != user.id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not your field")
    return field


def get_owned_field(field_id: str, db: Session = Depends(get_db), user: CurrentUser = Depends(get_current_user)) -> models.Field:
    return load_owned_field(field_id, db, user)


def require_farmer(user: CurrentUser = Depends(get_current_user)) -> CurrentUser:
    """Officers are read-only (FR-03) — write endpoints require the farmer role."""
    if user.role != "farmer":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Officers have read-only access")
    return user


def get_writable_field(field: models.Field = Depends(get_owned_field), _: CurrentUser = Depends(require_farmer)) -> models.Field:
    return field
