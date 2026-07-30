"""Runs the 50-instance QAOA vs. brute-force sweep (TRD §6.6) and writes
`models/<version>/benchmark.json`, served verbatim by
`GET /analytics/quantum-benchmark`."""
import json

from app.core.config import get_settings
from app.quantum.benchmark import run_suite


def main(n_instances: int = 50) -> None:
    settings = get_settings()
    settings.model_dir.mkdir(parents=True, exist_ok=True)

    result = run_suite(n_instances=n_instances, layers=settings.qaoa_layers, timeout_s=settings.qaoa_timeout_s)

    def _fmt(value, spec) -> str:
        return format(value, spec) if value is not None else "n/a"

    print(f"optimum_match_rate: {_fmt(result['optimum_match_rate'], '.2%')} (target >= 90%)")
    print(f"mean_approximation_ratio: {_fmt(result['mean_approximation_ratio'], '.4f')} (target >= 0.98)")
    print(f"mean_uplift_vs_uniform: {_fmt(result['mean_uplift_vs_uniform'], '.2f')}x (target >= 20x)")
    print(f"mean_feasible_rate: {_fmt(result['mean_feasible_rate'], '.2%')} (target >= 95%)")

    with open(settings.model_dir / "benchmark.json", "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2)
    print(f"Wrote {settings.model_dir / 'benchmark.json'}")


if __name__ == "__main__":
    main()
