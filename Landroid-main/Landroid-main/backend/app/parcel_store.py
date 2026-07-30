"""In-memory parcel registry (hackathon prototype)."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from .geo import load_boundary_wgs84


@dataclass
class ParcelRecord:
    id: str
    name: str
    owner_user_id: str
    boundary: dict[str, Any]
    centroid: dict[str, float]
    bbox: dict[str, float]
    area_acres_approx: float
    meta: dict[str, Any] = field(default_factory=dict)


class ParcelStore:
    def __init__(self) -> None:
        self._parcels: dict[str, ParcelRecord] = {}

    def seed_default(self) -> ParcelRecord:
        g = load_boundary_wgs84()
        p = ParcelRecord(
            id="parcel-1",
            name="Kallapuram Parcel",
            owner_user_id="00000000-0000-4000-8000-0000000000b1",
            boundary=g["geojson"],
            centroid=g["centroid"],
            bbox=g["bbox"],
            area_acres_approx=g["area_acres_approx"],
            meta={"boundary_source": "seed_Boundary.geojson"},
        )
        self._parcels[p.id] = p
        return p

    def create(
        self,
        parcel_id: str,
        name: str,
        owner_user_id: str,
        boundary_metrics: dict[str, Any] | None = None,
    ) -> ParcelRecord:
        g = boundary_metrics if boundary_metrics is not None else load_boundary_wgs84()
        src = "consultant_geojson" if boundary_metrics is not None else "Boundary.geojson"
        p = ParcelRecord(
            id=parcel_id,
            name=name,
            owner_user_id=owner_user_id,
            boundary=g["geojson"],
            centroid=g["centroid"],
            bbox=g["bbox"],
            area_acres_approx=g["area_acres_approx"],
            meta={"boundary_source": src},
        )
        self._parcels[p.id] = p
        return p

    def patch_meta(self, parcel_id: str, patch: dict[str, Any]) -> ParcelRecord | None:
        p = self.get(parcel_id)
        if not p:
            return None
        merged = {**p.meta, **patch}
        p.meta = merged
        return p

    def replace_boundary(self, parcel_id: str, boundary_metrics: dict[str, Any]) -> ParcelRecord | None:
        p = self.get(parcel_id)
        if not p:
            return None
        p.boundary = boundary_metrics["geojson"]
        p.centroid = boundary_metrics["centroid"]
        p.bbox = boundary_metrics["bbox"]
        p.area_acres_approx = boundary_metrics["area_acres_approx"]
        p.meta = {**p.meta, "boundary_source": "consultant_geojson"}
        return p

    def get(self, parcel_id: str) -> ParcelRecord | None:
        return self._parcels.get(parcel_id)

    def list_ids(self) -> list[str]:
        return list(self._parcels.keys())


store = ParcelStore()
