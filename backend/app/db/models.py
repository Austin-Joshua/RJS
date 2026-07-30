"""Persistence models (TRD §9 ER diagram).

ponytail: `boundary`/`geom` are stored as GeoJSON in a JSON column rather than
a PostGIS `geometry` type, so the same schema runs on both local SQLite (demo/
dev, zero setup) and Supabase Postgres. Upgrade path: switch to GeoAlchemy2
`Geometry` columns + PostGIS `ST_Centroid`/`ST_Area` once the deployment
target is fixed to Postgres, and drop the Python-side shapely centroid calc
in `app/services/fusion.py`.
"""
import uuid
from datetime import datetime, timezone

from sqlalchemy import JSON, Boolean, DateTime, Float, ForeignKey, Integer, String
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship


class Base(DeclarativeBase):
    pass


def _uuid() -> str:
    return str(uuid.uuid4())


def _now() -> datetime:
    return datetime.now(timezone.utc)


class Farmer(Base):
    __tablename__ = "farmers"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=_uuid)
    phone: Mapped[str] = mapped_column(String, unique=True)
    role: Mapped[str] = mapped_column(String, default="farmer")  # farmer | officer
    lang: Mapped[str] = mapped_column(String, default="ta")
    supabase_sub: Mapped[str | None] = mapped_column(String, nullable=True)

    fields: Mapped[list["Field"]] = relationship(back_populates="farmer", cascade="all, delete-orphan")


class Field(Base):
    __tablename__ = "fields"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=_uuid)
    farmer_id: Mapped[str] = mapped_column(ForeignKey("farmers.id"))
    name: Mapped[str] = mapped_column(String)
    boundary_geojson: Mapped[dict] = mapped_column(JSON)
    centroid_lat: Mapped[float] = mapped_column(Float)
    centroid_lon: Mapped[float] = mapped_column(Float)
    area_ha: Mapped[float] = mapped_column(Float)
    district: Mapped[str] = mapped_column(String)
    state: Mapped[str] = mapped_column(String)
    sowing_date: Mapped[str | None] = mapped_column(String, nullable=True)
    soil_override: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now)

    farmer: Mapped[Farmer] = relationship(back_populates="fields")
    plots: Mapped[list["Plot"]] = relationship(back_populates="field", cascade="all, delete-orphan")
    raster_assets: Mapped[list["RasterAsset"]] = relationship(back_populates="field", cascade="all, delete-orphan")


class Plot(Base):
    __tablename__ = "plots"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=_uuid)
    field_id: Mapped[str] = mapped_column(ForeignKey("fields.id"))
    label: Mapped[str] = mapped_column(String)
    area_ha: Mapped[float] = mapped_column(Float)
    geom_geojson: Mapped[dict | None] = mapped_column(JSON, nullable=True)

    field: Mapped[Field] = relationship(back_populates="plots")


class RasterAsset(Base):
    """Uploaded GeoTIFF metadata (TRD raster pipeline). Pixel bytes live in
    Supabase Storage, never in this table — see `app/adapters/raster_storage.py`.
    `zonal_ndvi` is computed once at upload time and cached here so the
    signals fusion pipeline (`app/services/fusion.py`) never re-runs rasterio
    per request."""

    __tablename__ = "raster_assets"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=_uuid)
    field_id: Mapped[str] = mapped_column(ForeignKey("fields.id"))
    kind: Mapped[str] = mapped_column(String, default="ndvi")  # ndvi | dem | orthomosaic
    file_name: Mapped[str] = mapped_column(String)
    storage_bucket: Mapped[str] = mapped_column(String)
    storage_path: Mapped[str] = mapped_column(String)  # key inside bucket
    band: Mapped[int] = mapped_column(Integer, default=1)
    crs: Mapped[str | None] = mapped_column(String, nullable=True)
    width: Mapped[int | None] = mapped_column(Integer, nullable=True)
    height: Mapped[int | None] = mapped_column(Integer, nullable=True)
    bounds: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    stats: Mapped[list | None] = mapped_column(JSON, nullable=True)  # per-band [{band, min, max, mean}, ...]
    zonal_ndvi: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    uploaded_at: Mapped[datetime] = mapped_column(DateTime, default=_now)

    field: Mapped[Field] = relationship(back_populates="raster_assets")


class SignalSnapshot(Base):
    __tablename__ = "signal_snapshots"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=_uuid)
    field_id: Mapped[str] = mapped_column(ForeignKey("fields.id"))
    fetched_at: Mapped[datetime] = mapped_column(DateTime, default=_now)
    data_mode: Mapped[str] = mapped_column(String)  # live | degraded | demo
    soil: Mapped[dict] = mapped_column(JSON)
    weather: Mapped[dict] = mapped_column(JSON)
    ndvi: Mapped[dict] = mapped_column(JSON)
    provenance: Mapped[dict] = mapped_column(JSON)


class OptimizationRun(Base):
    __tablename__ = "optimization_runs"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=_uuid)
    n_qubits: Mapped[int] = mapped_column(Integer)
    encoding: Mapped[str] = mapped_column(String)
    layers: Mapped[int] = mapped_column(Integer)
    qubo_meta: Mapped[dict] = mapped_column(JSON)
    qaoa_energy: Mapped[float | None] = mapped_column(Float, nullable=True)
    classical_optimum: Mapped[float] = mapped_column(Float)
    approx_ratio: Mapped[float | None] = mapped_column(Float, nullable=True)
    matched_optimum: Mapped[bool] = mapped_column(Boolean, default=False)
    t_qaoa_s: Mapped[float] = mapped_column(Float)
    t_classical_s: Mapped[float] = mapped_column(Float)
    solver_used: Mapped[str] = mapped_column(String)  # qaoa | classical_fallback
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now)


class Plan(Base):
    __tablename__ = "plans"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=_uuid)
    field_id: Mapped[str] = mapped_column(ForeignKey("fields.id"))
    run_id: Mapped[str] = mapped_column(ForeignKey("optimization_runs.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now)
    net_value_rs: Mapped[float] = mapped_column(Float)
    net_value_p10: Mapped[float] = mapped_column(Float)
    net_value_p90: Mapped[float] = mapped_column(Float)
    constraints: Mapped[dict] = mapped_column(JSON)

    assignments: Mapped[list["Assignment"]] = relationship(back_populates="plan", cascade="all, delete-orphan")
    advisory: Mapped["Advisory"] = relationship(back_populates="plan", uselist=False, cascade="all, delete-orphan")


class Assignment(Base):
    __tablename__ = "assignments"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=_uuid)
    plan_id: Mapped[str] = mapped_column(ForeignKey("plans.id"))
    plot_id: Mapped[str] = mapped_column(String)
    crop_code: Mapped[str] = mapped_column(String)
    yield_t_ha: Mapped[float] = mapped_column(Float)
    p10: Mapped[float] = mapped_column(Float)
    p90: Mapped[float] = mapped_column(Float)

    plan: Mapped[Plan] = relationship(back_populates="assignments")


class Advisory(Base):
    __tablename__ = "advisories"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=_uuid)
    plan_id: Mapped[str] = mapped_column(ForeignKey("plans.id"), unique=True)
    fertilizer: Mapped[dict] = mapped_column(JSON)
    ph: Mapped[dict] = mapped_column(JSON)
    irrigation: Mapped[dict] = mapped_column(JSON)
    why: Mapped[dict] = mapped_column(JSON)

    plan: Mapped[Plan] = relationship(back_populates="advisory")
