from app.services.ai import compute_land_health, compute_land_valuation, compute_ndvi_zones


def test_land_health_score_bounds() -> None:
    result = compute_land_health(
        ndvi_current=0.45,
        ndvi_history=[0.4, 0.42, 0.44],
        rainfall_adequacy=65.0,
        soil_quality=70.0,
        temperature_suitability=60.0,
    )
    assert 0 <= result.score <= 100
    assert result.status in {"Healthy", "Moderate", "At Risk"}
    assert len(result.signals) == 4


def test_plant_zone_percentages() -> None:
    result = compute_ndvi_zones(current_ndvi=0.43, previous_ndvi=0.5)
    total = sum(zone.percentage for zone in result.zones)
    assert 99.5 <= total <= 100.5
    assert 0 <= result.confidence <= 100


def test_valuation_contains_top_drivers() -> None:
    valuation = compute_land_valuation(
        health_score=62.0,
        soil_quality=68.0,
        rainfall_adequacy=61.0,
        location_score=72.0,
        night_lights_index=0.42,
    )
    assert valuation.low_per_acre_inr < valuation.mid_per_acre_inr < valuation.high_per_acre_inr
    assert len(valuation.top_drivers) == 3
