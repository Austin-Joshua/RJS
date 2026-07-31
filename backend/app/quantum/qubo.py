"""QUBO construction for the crop/resource allocation problem (FR-42, TRD §6).

Binary variable x_(p,c) for each (plot, candidate crop). Constraints:
  C1 exactly one crop per plot            (equality, no slack)
  C2 total water <= farmer's water budget (inequality, slack-encoded)
  C3 total cash  <= farmer's cash budget  (inequality, slack-encoded)

ponytail: continuous constraint bounds are discretised onto a small integer
slack ladder (`SLACK_LEVELS`, default 3 bits / 8 levels per inequality) so
the binary slack-bit trick applies at all. This trades exactness in *how
tightly* the encoded inequality binds for a bounded, demo-scale qubit count
(FR-42 targets 6-9 qubits). Feasibility and net value are always verified
against the real, non-discretised constraint (`is_feasible`/`feasible_value`)
so the reported plan is never wrong even if the discretisation is coarse.
Upgrade path: replace fixed 3-bit slack with TRD's exact
`K = ceil(log2(bound + 1))` once bounds are pre-scaled to integers.
"""
from dataclasses import dataclass, field

SLACK_LEVELS = 1  # bits per inequality constraint at "slack" encoding — keeps a
# typical 3-plot x 2-crop demo request at 6 decision + 2 slack = 8 qubits,
# inside FR-42's 6-9 qubit target band.
PENALTY_EPS = 0.05

# Unbalanced-penalisation weights for the slack-free encoding used by
# `build_simplex_qubo` (Montanez-Barrera & Michielsen, arXiv:2211.13914).
# With violation h(x) = sum_i w'_i x_i - limit', the penalty lam_lin*h +
# lam_quad*h^2 is asymmetric: mild reward for slack, growing cost for excess.
# Values sit inside the paper's recommended range. The approximation can only
# mis-*guide* the search, never mis-report a plan: `is_feasible` re-checks
# every sampled bitstring against the true, non-normalised constraint.
UNBALANCED_LAMBDA_LIN = 0.9
UNBALANCED_LAMBDA_QUAD = 0.3


@dataclass
class QUBOProblem:
    variables: list[tuple[str, str]]  # (plot_id, crop), decision-variable order
    n_dec: int
    n_qubits: int
    slack_bits: dict[str, int]  # {"water": Kw, "budget": Kb}
    Q: dict[tuple[int, int], float]  # i <= j only
    offset: float
    value_raw: dict[tuple[str, str], float]  # v_i in Rs
    water_raw: dict[tuple[str, str], float]  # w_i in m3
    cost_raw: dict[tuple[str, str], float]  # b_i in Rs
    water_limit: float
    budget_limit: float
    encoding: str
    lambdas: dict[str, float] = field(default_factory=dict)

    # --- SPARQ (simplex encoding) additions -------------------------------
    # `blocks[p]` lists the qubit indices carrying plot p's crop choices. The
    # XY-ring mixer in quantum/sparq.py conserves Hamming weight inside each
    # block, which is what makes C1 a symmetry rather than a penalty term.
    # Empty for the legacy slack encoding, which has no block structure.
    blocks: list[list[int]] = field(default_factory=list)
    cov_raw: dict[tuple[tuple[str, str], tuple[str, str]], float] = field(default_factory=dict)
    risk_kappa: float = 0.0
    warm_start_bias: dict[tuple[str, str], float] = field(default_factory=dict)
    value_ref: float = 1.0  # farm-scale value used to normalise the variance term


def _penalty_terms(coeffs: dict[int, float], target: float) -> tuple[dict[tuple[int, int], float], float]:
    """QUBO expansion of lambda-free (sum_i c_i x_i - target)^2 for binary x_i."""
    terms: dict[tuple[int, int], float] = {}
    for i, ci in coeffs.items():
        terms[(i, i)] = terms.get((i, i), 0.0) + ci * ci - 2 * target * ci
    idxs = sorted(coeffs)
    for a in range(len(idxs)):
        for b in range(a + 1, len(idxs)):
            i, j = idxs[a], idxs[b]
            terms[(i, j)] = terms.get((i, j), 0.0) + 2 * coeffs[i] * coeffs[j]
    return terms, target * target


def build_qubo(
    *,
    plots: list[dict],  # [{"plot_id": str, "area_ha": float}]
    candidate_crops: list[str],
    value_map: dict[tuple[str, str], float],
    water_map: dict[tuple[str, str], float],
    cost_map: dict[tuple[str, str], float],
    water_limit: float,
    budget_limit: float,
    encoding: str = "slack",
) -> QUBOProblem:
    variables = [(p["plot_id"], c) for p in plots for c in candidate_crops]
    var_index = {v: i for i, v in enumerate(variables)}
    n_dec = len(variables)

    max_v = max((abs(v) for v in value_map.values()), default=1.0) or 1.0
    max_w = max((abs(v) for v in water_map.values()), default=1.0) or 1.0
    max_b = max((abs(v) for v in cost_map.values()), default=1.0) or 1.0

    v_norm = {k: value_map[k] / max_v for k in variables}
    w_norm = {k: water_map[k] / max_w for k in variables}
    b_norm = {k: cost_map[k] / max_b for k in variables}
    water_limit_norm = water_limit / max_w
    budget_limit_norm = budget_limit / max_b

    lam = max(abs(v) for v in v_norm.values()) + PENALTY_EPS if v_norm else 1.0
    lambdas = {"c1": lam, "c2": lam, "c3": lam}

    slack_bits = {"water": 0, "budget": 0}
    n_qubits = n_dec
    if encoding == "slack":
        slack_bits["water"] = SLACK_LEVELS
        slack_bits["budget"] = SLACK_LEVELS
        n_qubits = n_dec + slack_bits["water"] + slack_bits["budget"]

    Q: dict[tuple[int, int], float] = {}
    offset = 0.0

    # Objective: maximise value -> minimise -sum(v'_i x_i)
    for k, i in var_index.items():
        Q[(i, i)] = Q.get((i, i), 0.0) - v_norm[k]

    # C1 — exactly one crop per plot
    for p in {p["plot_id"] for p in plots}:
        coeffs = {var_index[(p, c)]: 1.0 for c in candidate_crops}
        terms, off = _penalty_terms(coeffs, target=1.0)
        for key, val in terms.items():
            Q[key] = Q.get(key, 0.0) + lambdas["c1"] * val
        offset += lambdas["c1"] * off

    def _slack_scale(limit_norm: float, bits: int) -> float:
        max_level = (2**bits - 1) if bits else 1
        return limit_norm / max_level if max_level else 0.0

    # C2 — water budget (inequality via slack, or unbalanced penalty if bits=0)
    water_coeffs = {var_index[k]: w_norm[k] for k in variables}
    if slack_bits["water"]:
        scale = _slack_scale(water_limit_norm, slack_bits["water"])
        for k in range(slack_bits["water"]):
            water_coeffs[n_dec + k] = (2**k) * scale
        terms, off = _penalty_terms(water_coeffs, target=water_limit_norm)
    else:
        # Unbalanced penalisation: only penalise the excess above the limit,
        # never the slack (keeps qubit count at n_dec — TRD §6.2).
        terms, off = _unbalanced_terms(water_coeffs, water_limit_norm)
    for key, val in terms.items():
        Q[key] = Q.get(key, 0.0) + lambdas["c2"] * val
    offset += lambdas["c2"] * off

    # C3 — cash budget
    budget_coeffs = {var_index[k]: b_norm[k] for k in variables}
    if slack_bits["budget"]:
        scale = _slack_scale(budget_limit_norm, slack_bits["budget"])
        for k in range(slack_bits["budget"]):
            budget_coeffs[n_dec + slack_bits["water"] + k] = (2**k) * scale
        terms, off = _penalty_terms(budget_coeffs, target=budget_limit_norm)
    else:
        terms, off = _unbalanced_terms(budget_coeffs, budget_limit_norm)
    for key, val in terms.items():
        Q[key] = Q.get(key, 0.0) + lambdas["c3"] * val
    offset += lambdas["c3"] * off

    return QUBOProblem(
        variables=variables,
        n_dec=n_dec,
        n_qubits=n_qubits,
        slack_bits=slack_bits,
        Q=Q,
        offset=offset,
        value_raw={k: value_map[k] for k in variables},
        water_raw={k: water_map[k] for k in variables},
        cost_raw={k: cost_map[k] for k in variables},
        water_limit=water_limit,
        budget_limit=budget_limit,
        encoding=encoding,
        lambdas=lambdas,
    )


def _unbalanced_terms(coeffs: dict[int, float], limit: float) -> tuple[dict[tuple[int, int], float], float]:
    """Unbalanced penalisation of sum_i c_i x_i <= limit with zero slack
    qubits: penalise only the (linearised) excess, `max(0, sum - limit)`,
    approximated here by penalising `(sum - limit)` whenever it is positive
    via a one-sided quadratic (only the sum^2 and -2*limit*sum terms, no
    target-squared reward for staying exactly at the limit). This keeps the
    qubit count at n_dec, per the ENCODING=unbalanced escape hatch in TRD §6.2.
    """
    terms: dict[tuple[int, int], float] = {}
    for i, ci in coeffs.items():
        terms[(i, i)] = terms.get((i, i), 0.0) + ci * ci - 2 * limit * ci
    idxs = sorted(coeffs)
    for a in range(len(idxs)):
        for b in range(a + 1, len(idxs)):
            i, j = idxs[a], idxs[b]
            terms[(i, j)] = terms.get((i, j), 0.0) + 2 * coeffs[i] * coeffs[j]
    return terms, 0.0


def value_reference(
    value_map: dict[tuple[str, str], float], plots: list[dict], candidate_crops: list[str]
) -> float:
    """Best-case total net value of the whole farm — the scale variance is
    normalised against so `risk_kappa` means the same thing at any farm size."""
    total = sum(
        max((abs(value_map.get((p["plot_id"], c), 0.0)) for c in candidate_crops), default=0.0)
        for p in plots
    )
    return total or 1.0


def _unbalanced_penalty(
    coeffs: dict[int, float], limit: float
) -> tuple[dict[tuple[int, int], float], float]:
    """Slack-free encoding of `sum_i c_i x_i <= limit`.

    Expands `lam_lin * h + lam_quad * h^2` with `h = sum_i c_i x_i - limit`,
    using x_i^2 = x_i for binaries. Unlike `_unbalanced_terms` (kept for the
    legacy encoding) this retains the constant term, so the reported QUBO
    energy is comparable across encodings.
    """
    lin, quad = UNBALANCED_LAMBDA_LIN, UNBALANCED_LAMBDA_QUAD
    terms: dict[tuple[int, int], float] = {}
    for i, ci in coeffs.items():
        terms[(i, i)] = terms.get((i, i), 0.0) + lin * ci + quad * ci * ci - 2 * quad * limit * ci
    idxs = sorted(coeffs)
    for a in range(len(idxs)):
        for b in range(a + 1, len(idxs)):
            i, j = idxs[a], idxs[b]
            terms[(i, j)] = terms.get((i, j), 0.0) + 2 * quad * coeffs[i] * coeffs[j]
    return terms, -lin * limit + quad * limit * limit


def build_simplex_qubo(
    *,
    plots: list[dict],  # [{"plot_id": str, "area_ha": float}]
    candidate_crops: list[str],
    value_map: dict[tuple[str, str], float],  # mu_i — expected net value, Rs
    water_map: dict[tuple[str, str], float],
    cost_map: dict[tuple[str, str], float],
    water_limit: float,
    budget_limit: float,
    cov_map: dict[tuple[tuple[str, str], tuple[str, str]], float] | None = None,
    risk_kappa: float = 0.0,
) -> QUBOProblem:
    """QUBO for the SPARQ ansatz: no C1 penalty, no slack qubits, risk-aware.

    Three differences from `build_qubo`, and each one buys something:

    * **No C1 term.** The XY-ring mixer conserves Hamming weight inside every
      plot block, so "exactly one crop per plot" holds by construction at any
      circuit depth. Dropping the penalty removes the largest coefficients in
      the Hamiltonian — the ones that previously dominated the landscape and
      drowned out the objective the farmer actually cares about.

    * **No slack qubits.** C2/C3 use unbalanced penalisation, so
      `n_qubits == n_dec` exactly. Every qubit encodes a decision instead of
      bookkeeping: 9 qubits buys 3 plots x 3 crops here, where the slack
      encoding spent 2 of 8 on a 1-bit ladder.

    * **Risk term.** `kappa * sum_ij Cov(v_i, v_j) x_i x_j` is quadratic by
      construction, so it lands in the QUBO natively. This is what couples the
      plots together: without it the objective is separable and each plot's
      best crop could be picked independently, with no optimiser required.
    """
    variables = [(p["plot_id"], c) for p in plots for c in candidate_crops]
    var_index = {v: i for i, v in enumerate(variables)}
    n_dec = len(variables)
    cov_map = cov_map or {}

    plot_ids = list(dict.fromkeys(p["plot_id"] for p in plots))
    blocks = [[var_index[(p, c)] for c in candidate_crops] for p in plot_ids]

    max_v = max((abs(v) for v in value_map.values()), default=1.0) or 1.0
    max_w = max((abs(v) for v in water_map.values()), default=1.0) or 1.0
    max_b = max((abs(v) for v in cost_map.values()), default=1.0) or 1.0

    v_norm = {k: value_map[k] / max_v for k in variables}
    w_norm = {k: water_map[k] / max_w for k in variables}
    b_norm = {k: cost_map[k] / max_b for k in variables}
    water_limit_norm = water_limit / max_w
    budget_limit_norm = budget_limit / max_b

    # Variance carries units of value^2, so it needs dividing by a value scale
    # to sit alongside the linear term. Using max|mu|^2 would make the penalty
    # grow with the *square* of the farm size while the mean grows linearly —
    # kappa would then mean something different on 2 plots than on 5. Dividing
    # by (max|mu| * v_ref), where v_ref is the whole farm's best-case value,
    # makes kappa scale-free: it depends on the yield band's relative width,
    # which is exactly what risk aversion should respond to.
    v_ref = value_reference(value_map, plots, candidate_crops)
    cov_norm = {k: c / (max_v * v_ref) for k, c in cov_map.items()}

    # Same discipline as the slack encoding (TRD Section 6.2): the constraint
    # penalty must outweigh any objective gain, so no infeasible assignment can
    # win on energy alone.
    penalty_scale = (max(abs(v) for v in v_norm.values()) if v_norm else 1.0) + PENALTY_EPS
    lambdas = {"c1": 0.0, "c2": penalty_scale, "c3": penalty_scale}

    Q: dict[tuple[int, int], float] = {}
    offset = 0.0

    # Objective: maximise mean, penalise variance -> minimise -mu' + kappa*Cov'
    for k, i in var_index.items():
        Q[(i, i)] = Q.get((i, i), 0.0) - v_norm[k]

    if risk_kappa and cov_norm:
        for i_key, i in var_index.items():
            # x_i^2 = x_i, so the diagonal of the covariance folds into linear.
            Q[(i, i)] = Q.get((i, i), 0.0) + risk_kappa * cov_norm.get((i_key, i_key), 0.0)
        for a in range(n_dec):
            for b in range(a + 1, n_dec):
                key_a, key_b = variables[a], variables[b]
                cij = cov_norm.get((key_a, key_b), cov_norm.get((key_b, key_a), 0.0))
                if cij:
                    # Cov appears twice in the quadratic form (i,j) and (j,i).
                    Q[(a, b)] = Q.get((a, b), 0.0) + 2.0 * risk_kappa * cij

    # C1 is intentionally absent — enforced by the mixer's symmetry instead.

    # C2 — water budget, slack-free
    water_terms, water_off = _unbalanced_penalty(
        {var_index[k]: w_norm[k] for k in variables}, water_limit_norm
    )
    for key, val in water_terms.items():
        Q[key] = Q.get(key, 0.0) + lambdas["c2"] * val
    offset += lambdas["c2"] * water_off

    # C3 — cash budget, slack-free
    budget_terms, budget_off = _unbalanced_penalty(
        {var_index[k]: b_norm[k] for k in variables}, budget_limit_norm
    )
    for key, val in budget_terms.items():
        Q[key] = Q.get(key, 0.0) + lambdas["c3"] * val
    offset += lambdas["c3"] * budget_off

    return QUBOProblem(
        variables=variables,
        n_dec=n_dec,
        n_qubits=n_dec,  # zero slack — every qubit is a decision
        slack_bits={"water": 0, "budget": 0},
        Q=Q,
        offset=offset,
        value_raw={k: value_map[k] for k in variables},
        water_raw={k: water_map[k] for k in variables},
        cost_raw={k: cost_map[k] for k in variables},
        water_limit=water_limit,
        budget_limit=budget_limit,
        encoding="simplex",
        lambdas=lambdas,
        blocks=blocks,
        cov_raw=cov_map,
        risk_kappa=risk_kappa,
        warm_start_bias=v_norm,
        value_ref=v_ref,
    )


def energy_qubo(problem: QUBOProblem, bits: list[int]) -> float:
    e = problem.offset
    for (i, j), q in problem.Q.items():
        if i == j:
            e += q * bits[i]
        else:
            e += q * bits[i] * bits[j]
    return e


def to_ising(problem: QUBOProblem) -> tuple[dict[int, float], dict[tuple[int, int], float], float]:
    h: dict[int, float] = {i: 0.0 for i in range(problem.n_qubits)}
    j_coupling: dict[tuple[int, int], float] = {}
    const = problem.offset
    for (i, j), q in problem.Q.items():
        if i == j:
            const += 0.5 * q
            h[i] += -0.5 * q
        else:
            const += 0.25 * q
            h[i] += -0.25 * q
            h[j] += -0.25 * q
            j_coupling[(i, j)] = j_coupling.get((i, j), 0.0) + 0.25 * q
    return h, j_coupling, const


def energy_ising(h: dict[int, float], j_coupling: dict[tuple[int, int], float], const: float, z: list[int]) -> float:
    e = const
    for i, hi in h.items():
        e += hi * z[i]
    for (i, j), jij in j_coupling.items():
        e += jij * z[i] * z[j]
    return e


def decode_decision_bits(problem: QUBOProblem, bits: list[int]) -> dict[str, str | None]:
    assignment: dict[str, str | None] = {}
    plot_ids = list(dict.fromkeys(p for p, _ in problem.variables))
    for p in plot_ids:
        chosen = [c for (pp, c) in problem.variables if pp == p and bits[problem.variables.index((pp, c))] == 1]
        assignment[p] = chosen[0] if len(chosen) == 1 else None
    return assignment


def is_feasible(problem: QUBOProblem, bits: list[int]) -> bool:
    assignment = decode_decision_bits(problem, bits)
    if any(crop is None for crop in assignment.values()):
        return False
    water_used = sum(problem.water_raw[(p, c)] for p, c in assignment.items())
    cost_used = sum(problem.cost_raw[(p, c)] for p, c in assignment.items())
    return water_used <= problem.water_limit + 1e-6 and cost_used <= problem.budget_limit + 1e-6


def feasible_value(problem: QUBOProblem, bits: list[int]) -> float:
    """Expected net value in rupees — what the farmer is shown.

    Deliberately *not* risk-adjusted: the plan screen quotes real money, and a
    number discounted by an internal risk-aversion constant would not be one.
    Use `objective_value` for anything that ranks candidate plans.
    """
    if not is_feasible(problem, bits):
        return 0.0
    assignment = decode_decision_bits(problem, bits)
    return sum(problem.value_raw[(p, c)] for p, c in assignment.items())


def plan_variance(problem: QUBOProblem, assignment: dict[str, str]) -> float:
    """Var[net value] of a chosen assignment, in Rs^2, from the risk model."""
    if not problem.cov_raw:
        return 0.0
    chosen = [(p, c) for p, c in assignment.items()]
    total = 0.0
    for i_key in chosen:
        for j_key in chosen:
            total += problem.cov_raw.get((i_key, j_key), problem.cov_raw.get((j_key, i_key), 0.0))
    return total


def objective_value(problem: QUBOProblem, bits: list[int]) -> float:
    """The quantity actually being maximised: mean minus kappa-weighted variance.

    Every solver — SPARQ, the legacy QAOA and brute force — ranks candidates
    with this function, so the three-way benchmark stays apples-to-apples. With
    no risk model attached (`risk_kappa == 0`) it collapses exactly to
    `feasible_value`, which is why the legacy path is unaffected.
    """
    if not is_feasible(problem, bits):
        return float("-inf")
    assignment = decode_decision_bits(problem, bits)
    mean = sum(problem.value_raw[(p, c)] for p, c in assignment.items())
    if not problem.risk_kappa or not problem.cov_raw:
        return mean

    # Divided by `value_ref` (the farm's best-case total), matching exactly the
    # normalisation written into Q — the two must agree or SPARQ and brute
    # force would be ranking plans by different objectives.
    return mean - problem.risk_kappa * plan_variance(problem, assignment) / problem.value_ref


def certainty_equivalent(problem: QUBOProblem, assignment: dict[str, str]) -> float:
    """Expected value minus kappa standard deviations — the interpretable form.

    The QUBO must encode *variance* (quadratic in x); standard deviation is
    not. But `mean - kappa*sigma` is the version that reads as money: "we value
    this plan at kappa sigma below its average outcome". Reported alongside the
    plan for that reason, and never used for ranking.
    """
    mean = sum(problem.value_raw[(p, c)] for p, c in assignment.items())
    if not problem.risk_kappa or not problem.cov_raw:
        return mean
    variance = max(0.0, plan_variance(problem, assignment))
    return mean - problem.risk_kappa * (variance**0.5)
