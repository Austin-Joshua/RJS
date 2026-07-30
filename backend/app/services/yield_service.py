"""Classical yield prediction orchestration (FR-30..34). Quantum never
touches this path (PRD §4) — this module only ever calls LightGBM."""
from app.ml.explain import per_prediction_shap
from app.ml.features import build_feature_row
from app.ml.yield_model import YieldModel, get_yield_model


def predict_yields(
    *,
    fused_signals: dict,
    area_ha: float,
    district: str,
    crops: list[str],
) -> tuple[list[dict], YieldModel | None]:
    """Returns (predictions, model). `model` is None when artifacts aren't
    trained yet — callers should surface a 503 rather than fabricate a number."""
    model = get_yield_model()
    if model is None:
        return [], None

    season = fused_signals.get("season", "kharif")
    ndvi_present = bool(fused_signals.get("ndvi"))
    predictions = []
    for crop in crops:
        row = build_feature_row(
            soil=fused_signals.get("soil", {}),
            weather=fused_signals.get("weather", {}),
            ndvi=fused_signals.get("ndvi"),
            area_ha=area_ha,
            crop=crop,
            district=district,
            season=season,
        )
        yield_t_ha, p10, p90 = model.predict_row(row)
        shap_contribs = per_prediction_shap(model, row)
        predictions.append(
            {
                "crop": crop,
                "yield_t_ha": yield_t_ha,
                "p10": p10,
                "p90": p90,
                "shap": shap_contribs,
                "confidence": "full" if ndvi_present else "reduced",
            }
        )
    return predictions, model
