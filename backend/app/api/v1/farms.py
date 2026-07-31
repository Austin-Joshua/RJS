"""The farm flow (brief §2): add farm -> soil card -> feasible crops ->
quantum-ranked rotation -> treatment advice -> dashboard.

Every route resolves the farm through `load_owned_field`, which 404s an unknown
id and 403s another account's farm. There is no route here that reads a farm
without that check, so per-user isolation (§4) is a property of the routing
layer rather than something each handler has to remember.

Naming: the persisted entity is `models.Field` and the product calls it a farm.
The API speaks the product's language; the model name predates it.
"""
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.adapters.district_lookup import resolve_district
from app.api.v1.dependencies import CurrentUser, get_current_user, get_db, load_owned_field, require_farmer
from app.db import models
from app.schemas.requests import FarmCreateRequest, RankCropsRequest, SoilReadingsIn
from app.services.crop_feasibility import shortlist
from app.services.fusion import fuse_field
from app.services.geo_utils import compute_centroid_and_area
from app.services.rotation_service import rank_crops_for_field
from app.services.soil_card import build_soil_card

router = APIRouter(prefix="/farms", tags=["farms"])


def _get_or_create_farmer(db: Session, user: CurrentUser) -> models.Farmer:
    farmer = db.get(models.Farmer, user.id)
    if farmer is None:
        farmer = models.Farmer(id=user.id, phone=user.id, role=user.role)
        db.add(farmer)
        db.commit()
    return farmer


def _square_boundary(lat: float, lon: float, area_ha: float) -> dict[str, Any]:
    """Approximate square polygon around a point, for farmers who gave a pin.

    Only used so downstream geometry consumers (NDVI, district lookup) have a
    polygon to work with. The farmer's stated `area_ha` is what the economics
    use — this shape is never treated as a survey boundary.
    """
    import math

    side_m = math.sqrt(area_ha * 10_000.0)
    d_lat = (side_m / 2.0) / 111_320.0
    d_lon = (side_m / 2.0) / (111_320.0 * max(0.2, math.cos(math.radians(lat))))
    return {
        "type": "Polygon",
        "coordinates": [
            [
                [lon - d_lon, lat - d_lat],
                [lon + d_lon, lat - d_lat],
                [lon + d_lon, lat + d_lat],
                [lon - d_lon, lat + d_lat],
                [lon - d_lon, lat - d_lat],
            ]
        ],
    }


def _farm_summary(field: models.Field) -> dict[str, Any]:
    latest_card = field.soil_cards[0] if field.soil_cards else None
    latest_plan = field.rotation_plans[0] if field.rotation_plans else None
    return {
        "id": field.id,
        "name": field.name,
        "centroid": {"lat": field.centroid_lat, "lon": field.centroid_lon},
        "area_ha": field.area_ha,
        "district": field.district,
        "state": field.state,
        "sowing_date": field.sowing_date,
        "created_at": field.created_at.isoformat() if field.created_at else None,
        "soil_card": latest_card.card if latest_card else None,
        "has_soil_card": latest_card is not None,
        "latest_ranking": (
            {
                # Flat list for the client — DB stores {"sequence":[…]}.
                "sequence": (latest_plan.sequence or {}).get("sequence", []),
                "total_value_rs": latest_plan.total_value_rs,
                "solver": latest_plan.solver,
                "created_at": latest_plan.created_at.isoformat() if latest_plan.created_at else None,
            }
            if latest_plan
            else None
        ),
    }


def _persist_soil_card(db: Session, field: models.Field, soil: SoilReadingsIn) -> models.SoilCard:
    card = build_soil_card(
        field_id=field.id,
        area_ha=field.area_ha,
        soil_type=soil.soil_type,
        n_kg_ha=soil.n_kg_ha,
        p_kg_ha=soil.p_kg_ha,
        k_kg_ha=soil.k_kg_ha,
        ph=soil.ph,
        oc_pct=soil.oc_pct,
        ec_ds_m=soil.ec_ds_m,
        moisture_pct=soil.moisture_pct,
        water_available_m3=soil.water_available_m3,
    )
    next_version = (
        db.query(models.SoilCard).filter(models.SoilCard.field_id == field.id).count() + 1
    )
    row = models.SoilCard(
        field_id=field.id,
        version=next_version,
        soil_type=soil.soil_type,
        readings=card.readings,
        classes=card.classes,
        card=card.to_dict(),
    )
    db.add(row)

    # Mirror onto the field so the yield model's feature builder uses the
    # farmer's own readings instead of the district baseline. This is the
    # farm-specific personalisation the brief requires (§4) — without it every
    # farm in a district would share one soil profile.
    field.soil_override = {
        "n_kg_ha": soil.n_kg_ha,
        "p_kg_ha": soil.p_kg_ha,
        "k_kg_ha": soil.k_kg_ha,
        "ph": soil.ph,
        "oc_pct": soil.oc_pct,
        "ec_ds_m": soil.ec_ds_m,
        "source": "farmer_entry",
    }
    db.commit()
    db.refresh(row)
    return row


def _latest_soil_card(field: models.Field) -> models.SoilCard:
    if not field.soil_cards:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="This farm has no soil card yet. Add soil readings before requesting crops.",
        )
    return field.soil_cards[0]


# --------------------------------------------------------------------------
# §2.2 / §2.3 — add a farm, get its soil card back
# --------------------------------------------------------------------------


@router.post("", status_code=status.HTTP_201_CREATED)
async def create_farm(
    payload: FarmCreateRequest, db: Session = Depends(get_db), user: CurrentUser = Depends(require_farmer)
) -> dict[str, Any]:
    farmer = _get_or_create_farmer(db, user)

    if payload.boundary_geojson:
        lat, lon, area_ha = compute_centroid_and_area(payload.boundary_geojson)
        boundary = payload.boundary_geojson
    elif payload.lat is not None and payload.lon is not None and payload.area_ha:
        lat, lon, area_ha = payload.lat, payload.lon, payload.area_ha
        boundary = _square_boundary(lat, lon, area_ha)
    else:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Provide either boundary_geojson, or lat + lon + area_ha.",
        )

    district, state = resolve_district(lat, lon) or ("Thanjavur", "Tamil Nadu")

    field = models.Field(
        farmer_id=farmer.id,
        name=payload.name,
        boundary_geojson=boundary,
        centroid_lat=lat,
        centroid_lon=lon,
        area_ha=area_ha,
        district=district,
        state=state,
        sowing_date=payload.sowing_date,
    )
    db.add(field)
    db.flush()
    db.add(models.Plot(field_id=field.id, label="Plot 1", area_ha=area_ha, geom_geojson=None))
    db.commit()
    db.refresh(field)

    card = _persist_soil_card(db, field, payload.soil)
    db.refresh(field)
    return {"farm": _farm_summary(field), "soil_card": card.card}


@router.get("")
async def list_farms(db: Session = Depends(get_db), user: CurrentUser = Depends(get_current_user)) -> dict[str, Any]:
    """Every farm on this account, and nothing from any other account."""
    query = db.query(models.Field)
    if user.role == "farmer":
        query = query.filter(models.Field.farmer_id == user.id)
    farms = query.order_by(models.Field.created_at.desc()).all()
    return {"farms": [_farm_summary(f) for f in farms], "count": len(farms)}


@router.get("/{farm_id}")
async def get_farm(
    farm_id: str, db: Session = Depends(get_db), user: CurrentUser = Depends(get_current_user)
) -> dict[str, Any]:
    field = load_owned_field(farm_id, db, user)
    return {"farm": _farm_summary(field)}


@router.delete("/{farm_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_farm(
    farm_id: str, db: Session = Depends(get_db), user: CurrentUser = Depends(require_farmer)
) -> None:
    field = load_owned_field(farm_id, db, user)
    db.delete(field)
    db.commit()


@router.post("/{farm_id}/soil-card", status_code=status.HTTP_201_CREATED)
async def add_soil_card(
    farm_id: str,
    payload: SoilReadingsIn,
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(require_farmer),
) -> dict[str, Any]:
    """Record a fresh soil test. Previous cards are kept as history."""
    field = load_owned_field(farm_id, db, user)
    card = _persist_soil_card(db, field, payload)
    return {"soil_card": card.card}


@router.get("/{farm_id}/soil-card")
async def get_soil_card(
    farm_id: str, db: Session = Depends(get_db), user: CurrentUser = Depends(get_current_user)
) -> dict[str, Any]:
    field = load_owned_field(farm_id, db, user)
    card = _latest_soil_card(field)
    return {
        "soil_card": card.card,
        "history": [
            {
                "id": c.id,
                "version": c.version,
                "created_at": c.created_at.isoformat() if c.created_at else None,
                "classes": c.classes,
            }
            for c in field.soil_cards
        ],
    }


# --------------------------------------------------------------------------
# §2.4 — feasible crop shortlist (classical gates)
# --------------------------------------------------------------------------


@router.get("/{farm_id}/feasible-crops")
async def get_feasible_crops(
    farm_id: str, db: Session = Depends(get_db), user: CurrentUser = Depends(get_current_user)
) -> dict[str, Any]:
    field = load_owned_field(farm_id, db, user)
    card = _latest_soil_card(field)
    return shortlist(soil_card=card.card, area_ha=field.area_ha)


# --------------------------------------------------------------------------
# §2.5 — quantum-ranked crop rotation
# --------------------------------------------------------------------------


@router.post("/{farm_id}/rank")
async def rank_crops(
    farm_id: str,
    payload: RankCropsRequest | None = None,
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(require_farmer),
) -> dict[str, Any]:
    """Run the full pipeline for this farm and persist the result.

    Recomputed per farm on every call — nothing is shared with, or copied from,
    another farm or another account (§4).
    """
    field = load_owned_field(farm_id, db, user)
    card = _latest_soil_card(field)
    payload = payload or RankCropsRequest()

    fused = await fuse_field(
        district=field.district,
        lat=field.centroid_lat,
        lon=field.centroid_lon,
        sowing_date=field.sowing_date,
        boundary_geojson=field.boundary_geojson,
        soil_override=field.soil_override,
    )

    try:
        result = await rank_crops_for_field(
            field=field,
            soil_card=card.card,
            fused_signals=fused,
            candidate_crops=payload.candidate_crops,
            price_overrides=payload.price_overrides,
            water_available_m3=payload.water_available_m3,
            budget_rs=payload.budget_rs,
        )
    except RuntimeError as exc:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(exc)) from exc

    # Echo the survival-slider inputs so the Quantum Lab can label the run.
    result["scenario"] = {
        "water_available_m3": payload.water_available_m3
        if payload.water_available_m3 is not None
        else (card.card.get("water") or {}).get("available_m3"),
        "budget_rs": payload.budget_rs,
        "persisted": bool(payload.persist and result.get("ranking") is not None),
    }

    if result.get("ranking") is None:
        return result

    # Slider what-if: recompute live without flooding rotation_plan history.
    if not payload.persist:
        return result

    advisory = result.get("advisory")

    row = models.RotationPlan(
        field_id=field.id,
        soil_card_id=card.id,
        version=db.query(models.RotationPlan).filter(models.RotationPlan.field_id == field.id).count() + 1,
        solver=result["ranking"]["solver"],
        seasons={"seasons": result["ranking"]["seasons"]},
        sequence={"sequence": result["ranking"]["sequence"]},
        ranked_crops={
            "ranked_crops": result["ranking"]["ranked_crops"],
            "crop_ranking": result["ranking"]["crop_ranking"],
        },
        total_value_rs=result["ranking"]["total_value_rs"],
        matched_exact_optimum=result["ranking"]["matched_exact_optimum"],
        feasibility=result["feasibility"],
        # Absent on the single-candidate path, where there is no ordering to
        # search and therefore no circuit, no baselines, and no rotation
        # coefficients to report. Persist empty rather than assuming they exist.
        baselines=result.get("baselines") or {},
        quantum=result.get("quantum") or {},
        rotation_model=result.get("rotation_model") or {},
        advisory=advisory,
    )
    db.add(row)
    db.commit()
    result["rotation_plan_id"] = row.id
    return result


@router.get("/{farm_id}/rotation-plan")
async def get_rotation_plan(
    farm_id: str, db: Session = Depends(get_db), user: CurrentUser = Depends(get_current_user)
) -> dict[str, Any]:
    field = load_owned_field(farm_id, db, user)
    if not field.rotation_plans:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="No crop ranking generated for this farm yet."
        )
    plan = field.rotation_plans[0]
    return {
        "rotation_plan_id": plan.id,
        "created_at": plan.created_at.isoformat() if plan.created_at else None,
        "ranking": {
            "solver": plan.solver,
            "seasons": plan.seasons.get("seasons", []),
            "sequence": plan.sequence.get("sequence", []),
            "ranked_crops": plan.ranked_crops.get("ranked_crops", []),
            "crop_ranking": plan.ranked_crops.get("crop_ranking", []),
            "total_value_rs": plan.total_value_rs,
            "matched_exact_optimum": plan.matched_exact_optimum,
        },
        "feasibility": plan.feasibility,
        # Empty on a single-candidate plan — the UI omits the comparison and
        # quantum panels rather than rendering hollow ones.
        "baselines": plan.baselines or None,
        "quantum": plan.quantum or None,
        "rotation_model": plan.rotation_model or None,
        "advisory": plan.advisory,
    }


# --------------------------------------------------------------------------
# §2.6 — soil treatment advice
# --------------------------------------------------------------------------


@router.get("/{farm_id}/advisory")
async def get_farm_advisory(
    farm_id: str, db: Session = Depends(get_db), user: CurrentUser = Depends(get_current_user)
) -> dict[str, Any]:
    field = load_owned_field(farm_id, db, user)
    if not field.rotation_plans or field.rotation_plans[0].advisory is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No advice yet — rank crops for this farm first.",
        )
    return field.rotation_plans[0].advisory
