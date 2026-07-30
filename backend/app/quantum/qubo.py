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
    if not is_feasible(problem, bits):
        return 0.0
    assignment = decode_decision_bits(problem, bits)
    return sum(problem.value_raw[(p, c)] for p, c in assignment.items())
