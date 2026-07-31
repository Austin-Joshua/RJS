"""Risk-aware value modelling for the allocation optimiser (SPARQ objective).

The LightGBM layer already emits a P10/P90 band per crop (FR-31), but until now
that band was only *displayed* — `plan_service` applied it post-hoc to an
assignment the optimiser had already chosen from a point estimate. The band
never influenced the decision.

This module turns that band into the optimiser's objective. Two facts make it
work, and together they are the reason this problem belongs on a quantum
optimiser rather than a greedy per-plot pick:

1. Crop yields inside one field are *correlated* — they share one monsoon. Two
   plots of the same crop fail together; two different crops do not. So the
   covariance between decision variables is real, not a modelling flourish.

2. `Var[sum_i v_i x_i] = sum_ij Cov(v_i, v_j) x_i x_j` is **quadratic in x by
   construction**. A mean-variance objective is therefore a QUBO natively — the
   risk term *is* where the couplings come from. Without it the objective is
   separable and every plot could be chosen independently.

The optimised objective is mean-variance (Markowitz):

    maximise   sum_i mu_i x_i  -  kappa * sum_ij Cov(v_i, v_j) x_i x_j

CVaR and the scenario histogram are computed too, but they are *reported*
diagnostics only — CVaR is not quadratic in x and is therefore not what the
QUBO encodes. Saying otherwise on stage would be the kind of claim PRD Section 5
exists to prevent.
"""
import math
from dataclasses import dataclass, field

# P10/P90 are the 10th/90th percentiles, so the band spans 2 * z(0.90) sigma.
Z_P90 = 1.2815515655446004

# Correlation between *different* crops' yields in the same field. They share
# rainfall, temperature and ET0, so the correlation is high but not 1 — a
# pulse and a paddy respond differently to the same dry spell. Exposed as
# config (`risk_cross_crop_rho`) rather than buried here, because it is an
# assumption a judge is entitled to interrogate.
DEFAULT_CROSS_CROP_RHO = 0.45

QUINTALS_PER_TONNE = 10.0


@dataclass
class RiskModel:
    """Analytic first/second moments of net value per (plot, crop) decision."""

    mu: dict[tuple[str, str], float]  # expected net value, Rs
    cov: dict[tuple[tuple[str, str], tuple[str, str]], float]  # Cov(v_i, v_j), Rs^2
    sigma_by_crop: dict[str, float]  # yield std dev, t/ha
    rho_cross_crop: float
    scenarios: list[dict[str, float]] = field(default_factory=list)  # yield draws, t/ha


def sigma_from_band(p10: float, p90: float) -> float:
    """Gaussian-equivalent yield std dev from the quantile model's band.

    LightGBM's two quantile boosters are fitted independently, so at small n
    they can cross (yield_model.predict_row already sorts them). A degenerate
    band means "the model is very confident", not "risk is undefined" — a
    floor keeps the covariance matrix positive-definite so the Cholesky in
    `sample_scenarios` cannot fail mid-demo.
    """
    spread = max(0.0, p90 - p10)
    return max(spread / (2.0 * Z_P90), 1e-3)


def build_risk_model(
    *,
    plots: list[dict],  # [{"plot_id": str, "area_ha": float}]
    candidate_crops: list[str],
    predictions: dict[str, dict],  # crop -> {"yield_t_ha", "p10", "p90"}
    price_by_crop: dict[str, float],  # Rs per quintal
    cost_by_crop: dict[str, float],  # Rs per ha
    rho_cross_crop: float = DEFAULT_CROSS_CROP_RHO,
    n_scenarios: int = 256,
    seed: int = 42,
) -> RiskModel:
    """Analytic mean and covariance of net value across every (plot, crop).

    Net value for decision i = (p, c) is linear in the crop's yield:

        v_i = y_c * area_p * price_c * 10  -  cost_c * area_p

    so mu_i and Cov(v_i, v_j) follow in closed form from the yield moments. The
    scenarios drawn alongside are for reporting only (CVaR + the frontend
    histogram); the QUBO consumes the analytic covariance so that the same
    request always produces the same plan — a sampled covariance would make the
    demo non-reproducible.
    """
    sigma_by_crop = {
        c: sigma_from_band(predictions[c]["p10"], predictions[c]["p90"]) for c in candidate_crops
    }

    def value_scale(plot: dict, crop: str) -> float:
        """d(net value) / d(yield) — the factor carrying yield risk into rupees."""
        return plot["area_ha"] * price_by_crop.get(crop, 0.0) * QUINTALS_PER_TONNE

    mu: dict[tuple[str, str], float] = {}
    for plot in plots:
        for crop in candidate_crops:
            revenue = predictions[crop]["yield_t_ha"] * value_scale(plot, crop)
            mu[(plot["plot_id"], crop)] = revenue - cost_by_crop.get(crop, 0.0) * plot["area_ha"]

    # Cov(v_i, v_j) = scale_i * scale_j * Cov(y_ci, y_cj), and
    # Cov(y_c, y_c') = sigma_c * sigma_c' * rho(c, c') with rho(c, c) = 1.
    # Same crop on two plots therefore stays perfectly correlated: planting it
    # twice doubles exposure rather than spreading it. That is precisely the
    # signal that makes the optimiser diversify.
    cov: dict[tuple[tuple[str, str], tuple[str, str]], float] = {}
    keys = [(p["plot_id"], c) for p in plots for c in candidate_crops]
    area_by_plot = {p["plot_id"]: p for p in plots}
    for i_key in keys:
        for j_key in keys:
            pi, ci = i_key
            pj, cj = j_key
            rho = 1.0 if ci == cj else rho_cross_crop
            cov[(i_key, j_key)] = (
                value_scale(area_by_plot[pi], ci)
                * value_scale(area_by_plot[pj], cj)
                * sigma_by_crop[ci]
                * sigma_by_crop[cj]
                * rho
            )

    scenarios = sample_scenarios(
        candidate_crops=candidate_crops,
        predictions=predictions,
        sigma_by_crop=sigma_by_crop,
        rho_cross_crop=rho_cross_crop,
        n_scenarios=n_scenarios,
        seed=seed,
    )

    return RiskModel(
        mu=mu,
        cov=cov,
        sigma_by_crop=sigma_by_crop,
        rho_cross_crop=rho_cross_crop,
        scenarios=scenarios,
    )


def _cholesky(matrix: list[list[float]]) -> list[list[float]]:
    """Lower-triangular Cholesky factor, with a jitter retry.

    Hand-rolled rather than pulled from numpy so this module stays importable
    in the same "no heavyweight import at request time" spirit as the rest of
    app/quantum. n = number of candidate crops (<= 5), so cost is irrelevant.
    """
    n = len(matrix)
    for jitter in (0.0, 1e-9, 1e-6, 1e-3):
        chol = [[0.0] * n for _ in range(n)]
        ok = True
        for i in range(n):
            for j in range(i + 1):
                total = sum(chol[i][k] * chol[j][k] for k in range(j))
                if i == j:
                    diag = matrix[i][i] + jitter - total
                    if diag <= 0.0:
                        ok = False
                        break
                    chol[i][j] = math.sqrt(diag)
                else:
                    chol[i][j] = (matrix[i][j] - total) / chol[j][j]
            if not ok:
                break
        if ok:
            return chol
    # Fully degenerate correlation matrix — fall back to independent draws
    # rather than raising. An uncorrelated risk model is a weaker model, not a
    # broken one, and the farmer still gets a plan.
    return [[1.0 if i == j else 0.0 for j in range(n)] for i in range(n)]


def sample_scenarios(
    *,
    candidate_crops: list[str],
    predictions: dict[str, dict],
    sigma_by_crop: dict[str, float],
    rho_cross_crop: float,
    n_scenarios: int,
    seed: int,
) -> list[dict[str, float]]:
    """Correlated yield draws, one dict of {crop: t/ha} per scenario.

    Seeded so a given request replays identically — the analytics panel and the
    plan must agree, and demo-day reproducibility is worth more than fresh
    entropy.
    """
    import random

    rng = random.Random(seed)
    n = len(candidate_crops)
    corr = [[1.0 if i == j else rho_cross_crop for j in range(n)] for i in range(n)]
    chol = _cholesky(corr)

    scenarios: list[dict[str, float]] = []
    for _ in range(n_scenarios):
        z = [rng.gauss(0.0, 1.0) for _ in range(n)]
        correlated = [sum(chol[i][k] * z[k] for k in range(i + 1)) for i in range(n)]
        draw: dict[str, float] = {}
        for i, crop in enumerate(candidate_crops):
            mean = predictions[crop]["yield_t_ha"]
            # Yield is physically non-negative; clipping (rather than using a
            # lognormal) keeps the analytic covariance above exactly consistent
            # with these draws in the bulk of the distribution, which is where
            # the mean-variance objective lives.
            draw[crop] = max(0.0, mean + sigma_by_crop[crop] * correlated[i])
        scenarios.append(draw)
    return scenarios


def evaluate_plan_risk(
    *,
    assignment: dict[str, str],
    plots: list[dict],
    risk: RiskModel,
    price_by_crop: dict[str, float],
    cost_by_crop: dict[str, float],
    cvar_beta: float = 0.2,
) -> dict:
    """Profit distribution of a chosen plan, for the analytics panel.

    Reported, never optimised: CVaR is not quadratic in x, so the QUBO cannot
    encode it. What the QUBO optimises is the mean-variance surrogate. Keeping
    that distinction visible in the payload is the point.
    """
    area_by_plot = {p["plot_id"]: p["area_ha"] for p in plots}
    profits: list[float] = []
    for draw in risk.scenarios:
        total = 0.0
        for plot_id, crop in assignment.items():
            area = area_by_plot.get(plot_id, 0.0)
            total += draw[crop] * area * price_by_crop.get(crop, 0.0) * QUINTALS_PER_TONNE
            total -= cost_by_crop.get(crop, 0.0) * area
        profits.append(total)

    profits.sort()
    if not profits:
        return {"expected_rs": 0.0, "std_rs": 0.0, "cvar_rs": 0.0, "cvar_beta": cvar_beta}

    mean = sum(profits) / len(profits)
    variance = sum((p - mean) ** 2 for p in profits) / len(profits)
    tail_n = max(1, int(len(profits) * cvar_beta))
    cvar = sum(profits[:tail_n]) / tail_n

    return {
        "expected_rs": round(mean, 2),
        "std_rs": round(math.sqrt(variance), 2),
        "cvar_rs": round(cvar, 2),
        "cvar_beta": cvar_beta,
        "worst_case_rs": round(profits[0], 2),
        "best_case_rs": round(profits[-1], 2),
        "n_scenarios": len(profits),
    }


def profit_histogram(
    *,
    assignment: dict[str, str],
    plots: list[dict],
    risk: RiskModel,
    price_by_crop: dict[str, float],
    cost_by_crop: dict[str, float],
    bins: int = 24,
) -> list[dict[str, float]]:
    """Binned profit distribution for the frontend's risk chart."""
    area_by_plot = {p["plot_id"]: p["area_ha"] for p in plots}
    profits = []
    for draw in risk.scenarios:
        total = 0.0
        for plot_id, crop in assignment.items():
            area = area_by_plot.get(plot_id, 0.0)
            total += draw[crop] * area * price_by_crop.get(crop, 0.0) * QUINTALS_PER_TONNE
            total -= cost_by_crop.get(crop, 0.0) * area
        profits.append(total)

    if not profits:
        return []
    lo, hi = min(profits), max(profits)
    if hi - lo < 1e-9:
        return [{"centre_rs": round(lo, 2), "count": len(profits)}]

    width = (hi - lo) / bins
    counts = [0] * bins
    for p in profits:
        idx = min(bins - 1, int((p - lo) / width))
        counts[idx] += 1
    return [{"centre_rs": round(lo + (i + 0.5) * width, 2), "count": counts[i]} for i in range(bins)]
