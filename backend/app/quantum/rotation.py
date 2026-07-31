"""Crop rotation sequencing as a QUBO — the quantum-ranked crop order.

WHY THIS IS NOT A SORT
----------------------
"Rank the feasible crops by expected profit" is `sorted()`. Putting a quantum
optimiser on that would be decorative, which is the one thing the quantum layer
must not be.

Crop *sequencing* is a different problem. A crop's realised yield depends on
what preceded it: a cereal after a legume out-yields the same cereal after
itself (broken pest cycles, inherited nitrogen, better structure), and the same
crop twice running carries a documented monoculture penalty. So the value of
assigning crop c to season t depends on the assignment at season t-1, and the
objective is quadratic in the decision variables:

    maximise  Σ_t  base_value[c_t]
                   × yield_multiplier[family(c_{t-1})][family(c_t)]
                   × (same_crop_penalty if c_t == c_{t-1})
              +    n_credit_value[c_{t-1}]

The best sequence is genuinely not the sort of the individual values. A crop
that ranks third on its own can belong in slot one because of what it sets up
for slots two and three. That is a quadratic assignment problem, it is NP-hard
in general, and it is the reason a QUBO-shaped optimiser earns its place here.

STRUCTURE REUSE
---------------
The decision structure is identical to the allocation problem in `qubo.py`:
exactly one crop per season, just as there is exactly one crop per plot. So the
SPARQ ansatz transfers unchanged — blocks are seasons instead of plots, and the
XY-ring mixer conserves one-crop-per-season by the same symmetry argument. Only
the objective differs, which is exactly how it should be.
"""
from dataclasses import dataclass, field
from typing import Any

from app.quantum.qubo import PENALTY_EPS, QUBOProblem
from app.services.crop_reference import load_rotation, rotation_cfg


@dataclass
class RotationContext:
    """Everything the response needs to explain a sequence back to the farmer."""

    seasons: list[str]
    crops: list[str]
    base_value: dict[tuple[str, str], float]  # (season, crop) -> Rs/ha-scaled net value
    families: dict[str, str]
    n_credit_rs: dict[str, float]  # crop -> Rs/ha the *next* crop saves
    eligible_seasons: dict[str, list[str]]
    yield_multiplier: dict[str, dict[str, float]]
    same_crop_multiplier: float
    max_consecutive_same_crop: int
    anchors: dict[str, str] = field(default_factory=dict)
    area_ha: float


def n_credit_rupees(crop: str, area_ha: float) -> float:
    """Fertiliser-N credit a crop leaves behind, converted to rupees.

    A legume's nitrogen fixation is only worth something if it means the next
    crop's urea bag count drops, so it is monetised through urea price rather
    than reported as an abstract agronomic score.
    """
    cfg = load_rotation()
    n_kg = rotation_cfg(crop).get("n_credit_kg_ha", 0.0)
    urea_kg = n_kg / cfg.get("urea_n_fraction", 0.46)
    return urea_kg * cfg.get("urea_price_rs_per_kg", 6.0) * area_ha


def build_rotation_context(
    *,
    seasons: list[str],
    crops: list[str],
    base_value_per_crop: dict[str, float],
    area_ha: float,
    anchors: dict[str, str] | None = None,
) -> RotationContext:
    """Assemble the agronomic coupling tables for one farm's rotation problem.

    `base_value_per_crop` is the classical layer's output — LightGBM yield x
    price - cost, per hectare, for this specific farm. Quantum never computes
    it; it consumes it.
    """
    cfg = load_rotation()
    families = {c: rotation_cfg(c).get("family", "cereal") for c in crops}
    eligible = {c: list(rotation_cfg(c).get("seasons", [])) for c in crops}

    base_value: dict[tuple[str, str], float] = {}
    for s in seasons:
        for c in crops:
            base_value[(s, c)] = base_value_per_crop.get(c, 0.0)

    return RotationContext(
        seasons=seasons,
        crops=crops,
        base_value=base_value,
        families=families,
        n_credit_rs={c: n_credit_rupees(c, area_ha) for c in crops},
        eligible_seasons=eligible,
        yield_multiplier=cfg.get("yield_multiplier", {}),
        same_crop_multiplier=cfg.get("same_crop_consecutive_multiplier", 0.82),
        max_consecutive_same_crop=int(cfg.get("max_consecutive_same_crop", 1)),
        anchors=dict(anchors or {}),
        area_ha=area_ha,
    )


def resolve_delta_curation(
    soil_card: dict[str, Any],
    rotation_candidates: list[str],
) -> dict[str, Any]:
    """Season anchors and yield floors for known regional cropping systems."""
    empty: dict[str, Any] = {"system": None, "anchors": {}, "yield_floors": {}, "note": ""}
    cfg = load_rotation().get("curated_systems", {}).get("cauvery_delta_rice_fallow", {})
    if "paddy" not in rotation_candidates:
        return empty
    water_cat = (soil_card.get("water") or {}).get("category")
    soil_type = soil_card.get("soil_type", "")
    if water_cat not in cfg.get("water_categories", []):
        return empty
    if soil_type not in cfg.get("soil_types", []):
        return empty

    anchors: dict[str, str] = {}
    for season, crop in (cfg.get("anchors") or {}).items():
        if crop in rotation_candidates:
            anchors[season] = crop
    floors: dict[str, float] = {}
    floor = cfg.get("paddy_yield_floor_t_ha")
    if floor:
        floors["paddy"] = float(floor)
    return {
        "system": "cauvery_delta_rice_fallow",
        "anchors": anchors,
        "yield_floors": floors,
        "note": cfg.get("note", ""),
    }


def transition_multiplier(ctx: RotationContext, prev_crop: str, next_crop: str) -> float:
    """Yield multiplier applied to `next_crop` when it follows `prev_crop`."""
    if prev_crop == next_crop:
        prev_family = ctx.families.get(prev_crop, "cereal")
        next_family = ctx.families.get(next_crop, "cereal")
        mult = ctx.yield_multiplier.get(prev_family, {}).get(next_family, 1.0)
        return mult * ctx.same_crop_multiplier
    # Different species: family table applies only across families (legume→cereal
    # break-crop bonus). Same-family swaps (groundnut→black gram) stay neutral.
    prev_family = ctx.families.get(prev_crop, "cereal")
    next_family = ctx.families.get(next_crop, "cereal")
    if prev_family == next_family:
        return 1.0
    return ctx.yield_multiplier.get(prev_family, {}).get(next_family, 1.0)


def eligible_crops_for_season(ctx: RotationContext, season: str) -> list[str]:
    return [c for c in ctx.crops if is_season_eligible(ctx, season, c)]


def allows_consecutive_same(ctx: RotationContext, prev_crop: str, season: str) -> bool:
    """Whether repeating `prev_crop` in `season` is allowed under rotation rules."""
    if ctx.max_consecutive_same_crop < 1:
        return True
    alternatives = [c for c in eligible_crops_for_season(ctx, season) if c != prev_crop]
    return not alternatives


def sequence_value(ctx: RotationContext, sequence: list[str]) -> float:
    """Total rupee value of a full rotation sequence — the ground-truth objective.

    Every solver (quantum, brute force, and the greedy sort baseline) is scored
    with this one function, so comparisons between them are comparisons of the
    same quantity.
    """
    total = 0.0
    for t, crop in enumerate(sequence):
        if t == 0:
            total += ctx.base_value[(ctx.seasons[t], crop)]
            continue
        prev = sequence[t - 1]
        total += ctx.base_value[(ctx.seasons[t], crop)] * transition_multiplier(ctx, prev, crop)
        total += ctx.n_credit_rs.get(prev, 0.0)
    return total


def is_season_eligible(ctx: RotationContext, season: str, crop: str) -> bool:
    return season in ctx.eligible_seasons.get(crop, [])


def is_valid_sequence(ctx: RotationContext, sequence: list[str]) -> bool:
    """Hard agronomic gate: season eligibility + no back-to-back monoculture."""
    if len(sequence) != len(ctx.seasons):
        return False
    for t, (season, crop) in enumerate(zip(ctx.seasons, sequence)):
        if not is_season_eligible(ctx, season, crop):
            return False
        if ctx.anchors.get(season) and crop != ctx.anchors[season]:
            return False
        if t > 0 and crop == sequence[t - 1] and not allows_consecutive_same(ctx, sequence[t - 1], season):
            return False
    return True


def decode_sequence(ctx: RotationContext, problem: QUBOProblem, bits: list[int]) -> list[str] | None:
    """Bitstring -> crop-per-season list, or None if any season is not one-hot."""
    sequence: list[str] = []
    for season in ctx.seasons:
        chosen = [c for (s, c) in problem.variables if s == season and bits[problem.variables.index((s, c))] == 1]
        if len(chosen) != 1:
            return None
        sequence.append(chosen[0])
    return sequence


def build_rotation_qubo(ctx: RotationContext, *, infeasible_penalty_scale: float = 2.0) -> QUBOProblem:
    """QUBO over x[(season, crop)] with quadratic adjacent-season coupling.

    Reuses `QUBOProblem` so the whole SPARQ stack (XY-ring mixer, Dicke init,
    INTERP, sampling, feasibility filtering) applies without modification —
    "exactly one crop per season" is the same simplex structure as "exactly one
    crop per plot".

    C1 (one crop per season) is left to the mixer's symmetry, as in
    `build_simplex_qubo`. Season-ineligibility is handled as a linear penalty:
    it is a per-variable property, so it needs no coupling term.
    """
    variables = [(s, c) for s in ctx.seasons for c in ctx.crops]
    var_index = {v: i for i, v in enumerate(variables)}
    n_dec = len(variables)
    blocks = [[var_index[(s, c)] for c in ctx.crops] for s in ctx.seasons]

    # Normalise against the largest single-season value so penalty weights are
    # scale-free — same discipline as the allocation QUBO.
    max_v = max((abs(v) for v in ctx.base_value.values()), default=1.0) or 1.0
    penalty = max_v * infeasible_penalty_scale

    Q: dict[tuple[int, int], float] = {}
    offset = 0.0

    def add(i: int, j: int, w: float) -> None:
        key = (i, j) if i <= j else (j, i)
        Q[key] = Q.get(key, 0.0) + w

    # --- Linear: first season has no predecessor, so its value is unmodified.
    first_season = ctx.seasons[0]
    for c in ctx.crops:
        add(var_index[(first_season, c)], var_index[(first_season, c)], -ctx.base_value[(first_season, c)] / max_v)

    # --- Linear: season-eligibility gate. A crop that cannot be sown in a
    # season is pushed up in energy rather than removed, so the qubit layout
    # stays a clean seasons x crops grid and the mixer's block structure holds.
    for s in ctx.seasons:
        for c in ctx.crops:
            if not is_season_eligible(ctx, s, c):
                add(var_index[(s, c)], var_index[(s, c)], penalty / max_v)
            elif ctx.anchors.get(s) and c != ctx.anchors[s]:
                add(var_index[(s, c)], var_index[(s, c)], penalty / max_v)

    # --- Quadratic: the whole point. Value of crop c in season t, given crop p
    # in season t-1. Only adjacent seasons couple, which keeps the graph sparse
    # (|seasons|-1 blocks of C x C) and the circuit shallow.
    for t in range(1, len(ctx.seasons)):
        prev_season, this_season = ctx.seasons[t - 1], ctx.seasons[t]
        for p in ctx.crops:
            for c in ctx.crops:
                realised = ctx.base_value[(this_season, c)] * transition_multiplier(ctx, p, c)
                realised += ctx.n_credit_rs.get(p, 0.0)
                add(var_index[(prev_season, p)], var_index[(this_season, c)], -realised / max_v)
                if p == c and not allows_consecutive_same(ctx, p, this_season):
                    add(var_index[(prev_season, p)], var_index[(this_season, c)], penalty / max_v)

    return QUBOProblem(
        variables=variables,
        n_dec=n_dec,
        n_qubits=n_dec,  # zero slack — every qubit is a season-crop decision
        slack_bits={"water": 0, "budget": 0},
        Q=Q,
        offset=offset,
        value_raw={k: ctx.base_value[k] for k in variables},
        water_raw={k: 0.0 for k in variables},
        cost_raw={k: 0.0 for k in variables},
        water_limit=float("inf"),
        budget_limit=float("inf"),
        encoding="rotation_simplex",
        lambdas={"c1": 0.0, "eligibility": penalty / max_v + PENALTY_EPS},
        blocks=blocks,
        warm_start_bias={k: ctx.base_value[k] / max_v for k in variables},
        value_ref=max_v,
    )


# --------------------------------------------------------------------------
# Baselines. Both exist so the quantum result can be checked against something.
# --------------------------------------------------------------------------


def brute_force_rotation(ctx: RotationContext) -> dict:
    """Exact optimum over all C^T sequences — ground truth at demo scale."""
    import itertools
    import time

    start = time.monotonic()
    best_sequence: list[str] | None = None
    best_value = float("-inf")
    n_optima = 0

    for combo in itertools.product(ctx.crops, repeat=len(ctx.seasons)):
        sequence = list(combo)
        if not is_valid_sequence(ctx, sequence):
            continue
        value = sequence_value(ctx, sequence)
        if value > best_value + 1e-9:
            best_value, best_sequence, n_optima = value, sequence, 1
        elif abs(value - best_value) <= 1e-9:
            n_optima += 1

    return {
        "sequence": best_sequence,
        "value": best_value if best_sequence else 0.0,
        "num_optima": n_optima,
        "wall_time_s": time.monotonic() - start,
    }


def greedy_sort_rotation(ctx: RotationContext) -> dict:
    """The naive baseline: rank crops by standalone value, fill seasons in order.

    This is what "reorder the list by expected yield" means if taken literally,
    and it exists in the codebase specifically so the response can show what it
    costs. When greedy and the optimiser disagree, the rupee gap between them is
    the concrete answer to "why not just sort?".
    """
    import time

    start = time.monotonic()
    sequence: list[str] = []
    for season in ctx.seasons:
        candidates = [c for c in ctx.crops if is_season_eligible(ctx, season, c)]
        if sequence and not allows_consecutive_same(ctx, sequence[-1], season):
            candidates = [c for c in candidates if c != sequence[-1]] or candidates
        ranked = sorted(candidates, key=lambda c: ctx.base_value[(season, c)], reverse=True)
        sequence.append(ranked[0] if ranked else ctx.crops[0])

    return {
        "sequence": sequence,
        "value": sequence_value(ctx, sequence) if is_valid_sequence(ctx, sequence) else 0.0,
        "valid": is_valid_sequence(ctx, sequence),
        "wall_time_s": time.monotonic() - start,
    }


def greedy_myopic_rotation(ctx: RotationContext) -> dict:
    """A *smart* classical heuristic: at each season pick the crop with the best
    value given only the previous choice.

    This is the steel-man baseline. Plain sorting ignores rotation entirely and
    is easy to beat; this one uses the coupling but only one step at a time, so
    it still cannot trade a weaker season-1 crop for a much stronger season-2/3.
    Reporting the gap against *this* is the honest version of "why not just do
    it classically and greedily?".
    """
    import time

    start = time.monotonic()
    sequence: list[str] = []
    for t, season in enumerate(ctx.seasons):
        candidates = [c for c in ctx.crops if is_season_eligible(ctx, season, c)]
        if not candidates:
            sequence.append(ctx.crops[0])
            continue
        if t == 0:
            best = max(candidates, key=lambda c: ctx.base_value[(season, c)])
        else:
            prev = sequence[-1]
            if not allows_consecutive_same(ctx, prev, season):
                candidates = [c for c in candidates if c != prev] or candidates
            best = max(
                candidates,
                key=lambda c: ctx.base_value[(season, c)] * transition_multiplier(ctx, prev, c)
                + ctx.n_credit_rs.get(prev, 0.0),
            )
        sequence.append(best)

    valid = is_valid_sequence(ctx, sequence)
    return {
        "sequence": sequence,
        "value": sequence_value(ctx, sequence) if valid else 0.0,
        "valid": valid,
        "wall_time_s": time.monotonic() - start,
    }


def explain_sequence(ctx: RotationContext, sequence: list[str]) -> list[dict]:
    """Per-season breakdown for the UI — why each crop sits where it does."""
    rows: list[dict] = []
    for t, crop in enumerate(sequence):
        season = ctx.seasons[t]
        base = ctx.base_value[(season, crop)]
        if t == 0:
            rows.append(
                {
                    "season": season,
                    "crop": crop,
                    "base_value_rs": round(base, 2),
                    "rotation_multiplier": 1.0,
                    "n_credit_rs": 0.0,
                    "realised_value_rs": round(base, 2),
                    "reason": (
                        f"Curated {season} {crop} for the delta rice-fallow system."
                        if ctx.anchors.get(season) == crop
                        else "First season of the cycle — no predecessor effect."
                    ),
                }
            )
            continue

        prev = sequence[t - 1]
        mult = transition_multiplier(ctx, prev, crop)
        credit = ctx.n_credit_rs.get(prev, 0.0)
        realised = base * mult + credit

        if prev == crop:
            reason = f"Same crop as {ctx.seasons[t-1]} — monoculture penalty applied."
        elif mult > 1.0:
            reason = f"Follows {prev} ({ctx.families.get(prev)}) — break-crop benefit."
        elif mult < 1.0:
            reason = f"Follows {prev} ({ctx.families.get(prev)}) — carryover penalty."
        else:
            reason = f"Follows {prev} — neutral rotation effect."
        if credit > 0:
            reason += f" {prev} leaves ~Rs{credit:,.0f} of nitrogen credit."

        rows.append(
            {
                "season": season,
                "crop": crop,
                "base_value_rs": round(base, 2),
                "rotation_multiplier": round(mult, 4),
                "n_credit_rs": round(credit, 2),
                "realised_value_rs": round(realised, 2),
                "reason": reason,
            }
        )
    return rows
