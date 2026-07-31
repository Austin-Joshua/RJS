"""Runs the SPARQ vs. legacy-QAOA vs. brute-force sweep (TRD §6.6) and writes
`models/<version>/benchmark.json`, served verbatim by
`GET /analytics/quantum-benchmark`.

Both ansaetze see the same instances and are ranked by the same objective, so
the table this prints is a measurement, not a marketing claim. The row that
matters most is `uplift_vs_feasible_uniform`: P(optimum) divided by uniform
sampling over the C^P valid assignments. The legacy penalty-based ansatz scored
~1.0x on the easier 2^n baseline, i.e. no better than guessing.
"""
import json

from app.core.config import get_settings
from app.quantum.benchmark import run_suite


def _fmt(value, spec: str) -> str:
    return format(value, spec) if value is not None else "n/a"


def main(n_instances: int = 50, n_plots: int = 3, n_crops: int = 3) -> None:
    settings = get_settings()
    settings.model_dir.mkdir(parents=True, exist_ok=True)

    result = run_suite(
        n_instances=n_instances,
        layers=settings.sparq_layers,
        timeout_s=settings.qaoa_timeout_s,
        n_plots=n_plots,
        n_crops=n_crops,
        risk_kappa=settings.risk_kappa,
    )

    sparq, legacy = result["sparq"], result["baseline_qaoa"]
    rows = [
        ("qubits used", "mean_n_qubits", ".1f", ""),
        ("optimum match", "optimum_match_rate", ".1%", "target >= 90%"),
        ("approx ratio", "mean_approximation_ratio", ".4f", "target >= 0.98"),
        ("one-hot rate", "mean_simplex_rate", ".1%", "structural, expect 100%"),
        ("feasible rate", "mean_feasible_rate", ".1%", "target >= 95%"),
        ("uplift vs 2^n", "mean_uplift_vs_uniform", ".1f", "target >= 20x"),
        ("uplift vs C^P", "mean_uplift_vs_feasible_uniform", ".2f", "the honest baseline"),
        ("wall clock s", "mean_t_s", ".2f", ""),
    ]

    print(f"\n{n_instances} instances, {n_plots} plots x {n_crops} crops, p={result['qaoa_layers']}, "
          f"kappa={result['risk_kappa']}\n")
    print(f"{'':16}{'SPARQ':>12}{'legacy QAOA':>14}   note")
    print("-" * 62)
    for label, key, spec, note in rows:
        print(f"{label:16}{_fmt(sparq.get(key), spec):>12}{_fmt(legacy.get(key), spec):>14}   {note}")
    print()

    with open(settings.model_dir / "benchmark.json", "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2)
    print(f"Wrote {settings.model_dir / 'benchmark.json'}")


if __name__ == "__main__":
    main()
