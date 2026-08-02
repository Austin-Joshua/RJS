"""Throwaway: does real TN yield data show lower-tail dependence a Gaussian copula misses?"""
from itertools import combinations

import numpy as np
import pandas as pd
from scipy.stats import multivariate_normal, norm, rankdata

df = pd.read_csv("data/training/yield_training_set.csv")
piv = df.pivot_table(index=["district", "year"], columns="crop", values="yield_t_ha").dropna().reset_index()
crops = [c for c in piv.columns if c not in ("district", "year")]
print("joint district-year rows:", len(piv), "crops:", crops)

# Detrend per (district, crop): yields trend upward, and a trend would show up as
# spurious dependence. Residuals are what the risk model actually cares about.
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
n = len(R)
U = R.apply(lambda s: rankdata(s) / (n + 1))


def emp_lambda(u, v, q, lower=True):
    if lower:
        return float(np.mean((u <= q) & (v <= q)) / q)
    return float(np.mean((u >= 1 - q) & (v >= 1 - q)) / q)


def gauss_lambda(rho, q):
    z = norm.ppf(q)
    return float(multivariate_normal.cdf([z, z], mean=[0, 0], cov=[[1, rho], [rho, 1]]) / q)


hdr = f"{'pair':24s} {'rho':>6s} {'empLo.2':>8s} {'gauLo.2':>8s} {'empLo.1':>8s} {'gauLo.1':>8s} {'empUp.2':>8s}"
print("\n" + hdr)
print("-" * len(hdr))
d2, d1 = [], []
for a, b in combinations(crops, 2):
    u, v = U[a].to_numpy(), U[b].to_numpy()
    rho = float(np.corrcoef(norm.ppf(u), norm.ppf(v))[0, 1])
    e2, g2 = emp_lambda(u, v, 0.2), gauss_lambda(rho, 0.2)
    e1, g1 = emp_lambda(u, v, 0.1), gauss_lambda(rho, 0.1)
    eu2 = emp_lambda(u, v, 0.2, lower=False)
    d2.append(e2 - g2)
    d1.append(e1 - g1)
    print(f"{a + '|' + b:24s} {rho:6.3f} {e2:8.3f} {g2:8.3f} {e1:8.3f} {g1:8.3f} {eu2:8.3f}")

d2, d1 = np.array(d2), np.array(d1)
print(f"\nmean lower-tail excess over Gaussian:  q=.2 {d2.mean():+.3f}   q=.1 {d1.mean():+.3f}")
print(f"pairs exceeding Gaussian: q=.2 {(d2 > 0).sum()}/{len(d2)}   q=.1 {(d1 > 0).sum()}/{len(d1)}")

# Also: what the *current* code assumes -- one constant rho for every pair.
rhos = [float(np.corrcoef(norm.ppf(U[a]), norm.ppf(U[b]))[0, 1]) for a, b in combinations(crops, 2)]
print(f"\nempirical pairwise rho: min {min(rhos):.3f} max {max(rhos):.3f} mean {np.mean(rhos):.3f}")
print("risk.py currently hardcodes risk_cross_crop_rho = 0.45 for every pair")
