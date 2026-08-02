"""Throwaway #2: is there NON-Gaussian dependence structure worth a quantum model?

Baseline is the FAIR one: a full pairwise-correlation Gaussian copula (not the
one-parameter equicorrelation thing risk.py currently ships). If a properly fit
Gaussian copula already explains the data, a Born machine has nothing to win and
we must not claim it does.
"""
from itertools import combinations

import numpy as np
import pandas as pd
from scipy.stats import norm, rankdata

RNG = np.random.default_rng(0)

df = pd.read_csv("data/training/yield_training_set.csv")
piv = df.pivot_table(index=["district", "year"], columns="crop", values="yield_t_ha").dropna().reset_index()
crops = [c for c in piv.columns if c not in ("district", "year")]

res = {}
for c in crops:
    parts = []
    for _, g in piv.groupby("district"):
        y = g[c].to_numpy(dtype=float)
        t = g["year"].to_numpy(dtype=float)
        A = np.vstack([np.ones_like(t), t - t.mean()]).T
        beta, *_ = np.linalg.lstsq(A, y, rcond=None)
        parts.append(pd.Series(y - A @ beta, index=g.index))
    res[c] = pd.concat(parts).sort_index()
R = pd.DataFrame(res)
years = piv["year"].to_numpy()
n = len(R)
U = R.apply(lambda s: rankdata(s) / (n + 1)).to_numpy()
Z = norm.ppf(U)

print(f"rows {n}   crops {len(crops)}   distinct years {len(np.unique(years))}")
print("NOTE: residuals in the same year share one monsoon across districts, so the")
print(f"      effective sample size is nearer {len(np.unique(years))} year-blocks than {n} rows.\n")

# ---- 1. Higher-order (joint, all-crop) tail behaviour -----------------------
# This is the scenario that actually drives CVaR: everything failing at once.
corr = np.corrcoef(Z, rowvar=False)
big = RNG.multivariate_normal(np.zeros(len(crops)), corr, size=400_000)
print("P(ALL crops below their q-quantile together)")
print(f"{'q':>5s} {'empirical':>10s} {'gaussian':>10s} {'ratio':>7s}")
for q in (0.5, 0.4, 0.3, 0.2):
    emp = float(np.mean(np.all(U <= q, axis=1)))
    gau = float(np.mean(np.all(norm.cdf(big) <= q, axis=1)))
    ratio = emp / gau if gau > 0 else float("nan")
    print(f"{q:5.2f} {emp:10.4f} {gau:10.4f} {ratio:7.2f}")

# ---- 2. Is a full Gaussian copula an adequate fit? --------------------------
# Cramer-von Mises distance between empirical copula and fitted Gaussian copula,
# with a parametric-bootstrap null so the number has a reference distribution.
def cvm(u_sample: np.ndarray, ref: np.ndarray) -> float:
    """Sum over data points of (C_emp - C_model)^2, evaluated at the data."""
    tot = 0.0
    for row in u_sample:
        c_emp = float(np.mean(np.all(u_sample <= row, axis=1)))
        c_mod = float(np.mean(np.all(ref <= row, axis=1)))
        tot += (c_emp - c_mod) ** 2
    return tot


ref_u = norm.cdf(RNG.multivariate_normal(np.zeros(len(crops)), corr, size=60_000))
stat = cvm(U, ref_u)
null = []
for _ in range(60):
    sim = RNG.multivariate_normal(np.zeros(len(crops)), corr, size=n)
    sim_u = np.apply_along_axis(lambda s: rankdata(s) / (n + 1), 0, sim)
    sim_corr = np.corrcoef(norm.ppf(sim_u), rowvar=False)
    sim_ref = norm.cdf(RNG.multivariate_normal(np.zeros(len(crops)), sim_corr, size=20_000))
    null.append(cvm(sim_u, sim_ref))
null = np.array(null)
pval = float(np.mean(null >= stat))
print(f"\nCramer-von Mises vs fitted Gaussian copula: stat {stat:.4f}")
print(f"  parametric-bootstrap null mean {null.mean():.4f}  p-value {pval:.3f}")
print(f"  -> {'REJECT Gaussian (non-Gaussian structure present)' if pval < 0.1 else 'CANNOT reject Gaussian on this data'}")

# ---- 3. The number that actually matters: portfolio CVaR --------------------
# Equal-weight 3-crop portfolio, CVaR at 20%. How wrong is each copula?
sub = [crops.index(c) for c in ("paddy", "groundnut", "black_gram")]
sd = R.to_numpy()[:, sub].std(axis=0, ddof=1)


def cvar(sample_u: np.ndarray, beta: float = 0.2) -> float:
    losses = (norm.ppf(sample_u) * sd).sum(axis=1)
    losses.sort()
    return float(losses[: max(1, int(len(losses) * beta))].mean())


emp_cvar = cvar(U[:, sub])
sub_corr = np.corrcoef(Z[:, sub], rowvar=False)
gau_cvar = cvar(norm.cdf(RNG.multivariate_normal(np.zeros(3), sub_corr, size=200_000)))
equi = np.full((3, 3), 0.45)
np.fill_diagonal(equi, 1.0)
equi_cvar = cvar(norm.cdf(RNG.multivariate_normal(np.zeros(3), equi, size=200_000)))
print(f"\nCVaR20 of equal-weight paddy/groundnut/black_gram residual portfolio (t/ha):")
print(f"  empirical (real data)          {emp_cvar:8.3f}")
print(f"  Gaussian copula, fitted rho    {gau_cvar:8.3f}   error {abs(gau_cvar - emp_cvar) / abs(emp_cvar) * 100:5.1f}%")
print(f"  equicorrelation rho=0.45 (ship){equi_cvar:8.3f}   error {abs(equi_cvar - emp_cvar) / abs(emp_cvar) * 100:5.1f}%")

print("\npairwise Spearman-implied rho, fitted:")
for a, b in combinations(range(len(crops)), 2):
    print(f"  {crops[a]:12s} {crops[b]:12s} {corr[a, b]:+.3f}")
