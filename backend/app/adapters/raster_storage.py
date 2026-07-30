"""Supabase Storage client for uploaded raster GeoTIFFs.

Unlike the read-only signal adapters (weather/soil/NDVI), this adapter backs
a user-triggered write path (raster upload/delete) — failures raise instead
of silently degrading, so `app/api/v1/rasters.py` can surface a clear HTTP
error rather than pretending the upload succeeded.

Requires SUPABASE_SERVICE_ROLE_KEY (Dashboard -> Settings -> API ->
"service_role"): the bucket is private, so the anon key can't write to it.
"""
from __future__ import annotations

import httpx

from app.core.config import get_settings


def _headers() -> dict[str, str]:
    settings = get_settings()
    if not settings.supabase_url or not settings.supabase_service_role_key:
        raise RuntimeError(
            "Raster storage is not configured: set SUPABASE_URL and "
            "SUPABASE_SERVICE_ROLE_KEY in .env"
        )
    return {
        "Authorization": f"Bearer {settings.supabase_service_role_key}",
        "apikey": settings.supabase_service_role_key,
    }


def _object_url(bucket: str, path: str) -> str:
    settings = get_settings()
    return f"{settings.supabase_url}/storage/v1/object/{bucket}/{path}"


def upload(bucket: str, path: str, content: bytes, content_type: str = "image/tiff") -> None:
    headers = {**_headers(), "Content-Type": content_type, "x-upsert": "true"}
    try:
        resp = httpx.post(_object_url(bucket, path), headers=headers, content=content, timeout=60.0)
        resp.raise_for_status()
    except httpx.HTTPError as e:
        raise RuntimeError(f"Failed to upload raster to Supabase Storage: {e}") from e


def download(bucket: str, path: str) -> bytes:
    try:
        resp = httpx.get(_object_url(bucket, path), headers=_headers(), timeout=60.0)
        resp.raise_for_status()
    except httpx.HTTPError as e:
        raise RuntimeError(f"Failed to download raster from Supabase Storage: {e}") from e
    return resp.content


def delete(bucket: str, path: str) -> None:
    try:
        resp = httpx.delete(_object_url(bucket, path), headers=_headers(), timeout=30.0)
        resp.raise_for_status()
    except httpx.HTTPError as e:
        raise RuntimeError(f"Failed to delete raster from Supabase Storage: {e}") from e
