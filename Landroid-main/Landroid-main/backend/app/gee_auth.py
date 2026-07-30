"""
Google Earth Engine authentication (service account or CLI).

Official pattern:
https://developers.google.com/earth-engine/guides/auth

Set either:
  - ``GEE_SERVICE_ACCOUNT_EMAIL`` + ``GEE_SERVICE_ACCOUNT_KEY_PATH`` (JSON key file), or
  - ``GOOGLE_APPLICATION_CREDENTIALS`` pointing at the same JSON (``client_email`` read from file).

**Project (required for current Earth Engine Python client):**
  - ``GEE_PROJECT_ID`` or ``GOOGLE_CLOUD_PROJECT`` — your Google Cloud project that has the
    Earth Engine API enabled and (for service accounts) EE access granted; or
  - ``project_id`` inside the service account JSON (used automatically when present).

CLI auth (``earthengine authenticate``) still needs ``GEE_PROJECT_ID`` unless your credential
file supplies a default project.

Never commit key files.
"""

from __future__ import annotations

import json
import logging
import os
from pathlib import Path

import ee

_log = logging.getLogger(__name__)

_initialized = False
_last_init_error: str | None = None


def get_gee_last_error() -> str | None:
    """Human-readable reason the last ``ensure_gee_initialized`` attempt failed."""
    return _last_init_error


def _service_account_json_path() -> Path | None:
    raw = os.environ.get("GEE_SERVICE_ACCOUNT_KEY_PATH") or os.environ.get(
        "GOOGLE_APPLICATION_CREDENTIALS"
    )
    if not raw:
        return None
    p = Path(raw).expanduser()
    return p if p.is_file() else None


def resolve_gee_project_id() -> str | None:
    """Cloud project for ``ee.Initialize(..., project=...)``."""
    for key in ("GEE_PROJECT_ID", "GOOGLE_CLOUD_PROJECT", "GCP_PROJECT", "EARTHENGINE_PROJECT"):
        v = os.environ.get(key, "").strip()
        if v:
            return v
    path = _service_account_json_path()
    if path:
        try:
            with path.open(encoding="utf-8") as f:
                pid = str(json.load(f).get("project_id", "")).strip()
            if pid:
                return pid
        except (OSError, json.JSONDecodeError, TypeError):
            pass
    # Google Cloud SDK application-default credentials (often present after gcloud auth)
    gcloud_adc = Path.home() / ".config" / "gcloud" / "application_default_credentials.json"
    if gcloud_adc.is_file():
        try:
            with gcloud_adc.open(encoding="utf-8") as f:
                data = json.load(f)
            for k in ("quota_project_id", "project_id"):
                v = str(data.get(k, "")).strip()
                if v:
                    return v
        except (OSError, json.JSONDecodeError, TypeError):
            pass
    # Optional: single-line project id file next to Earth Engine CLI credentials
    ee_project_file = Path.home() / ".config" / "earthengine" / "project"
    if ee_project_file.is_file():
        try:
            line = ee_project_file.read_text(encoding="utf-8").strip().splitlines()[0]
            if line:
                return line.strip()
        except (OSError, IndexError):
            pass
    return None


def gee_credentials_configured() -> bool:
    """True if a known credential source exists (file on disk)."""
    if _service_account_json_path() is not None:
        return True
    default_creds = Path.home() / ".config" / "earthengine" / "credentials"
    return default_creds.is_file()


def ensure_gee_initialized() -> bool:
    """Return True if Earth Engine is ready for requests."""
    global _initialized, _last_init_error
    if _initialized:
        return True

    _last_init_error = None
    project = resolve_gee_project_id()
    key_path = _service_account_json_path()

    # Service account
    if key_path:
        email = os.environ.get("GEE_SERVICE_ACCOUNT_EMAIL", "").strip()
        if not email:
            try:
                with key_path.open(encoding="utf-8") as f:
                    email = str(json.load(f).get("client_email", "")).strip()
            except (OSError, json.JSONDecodeError, TypeError):
                email = ""

        if email:
            try:
                creds = ee.ServiceAccountCredentials(email, str(key_path))
                if project:
                    ee.Initialize(creds, project=project)
                else:
                    ee.Initialize(creds)
                _initialized = True
                return True
            except Exception as e:
                msg = f"service account init: {e!s}"
                _log.warning("Earth Engine: %s", msg)
                _last_init_error = msg[:500]

    # CLI / application-default credentials
    try:
        if project:
            ee.Initialize(project=project)
        else:
            ee.Initialize()
        _initialized = True
        return True
    except Exception as e:
        msg = f"default init: {e!s}"
        if not _last_init_error:
            _last_init_error = msg[:500]
        _log.warning("Earth Engine: %s", msg)
        return False
