"""API contract tests: auth enforcement, the farm flow end to end, and the
per-farm / per-account isolation the product depends on.

Authentication comes from the `identity` fixture in conftest, which overrides
the auth dependency. There is no bypass token in the app itself.
"""
import pytest
from fastapi.testclient import TestClient

from app.ml.yield_model import get_yield_model

BOUNDARY = {
    "type": "Polygon",
    "coordinates": [[[79.05, 10.75], [79.06, 10.75], [79.06, 10.76], [79.05, 10.76], [79.05, 10.75]]],
}

GOOD_SOIL = {
    "soil_type": "alluvial",
    "n_kg_ha": 240.0,
    "p_kg_ha": 18.0,
    "k_kg_ha": 190.0,
    "ph": 6.8,
    "oc_pct": 0.61,
    "ec_ds_m": 0.4,
    "water_available_m3": 9000.0,
}


def _make_farm(client: TestClient, name: str, *, soil: dict | None = None, area_ha: float = 1.0) -> dict:
    resp = client.post(
        "/api/v1/farms",
        json={
            "name": name,
            "lat": 10.755,
            "lon": 79.055,
            "area_ha": area_ha,
            "sowing_date": "2026-06-15",
            "soil": soil or GOOD_SOIL,
        },
    )
    assert resp.status_code == 201, resp.text
    return resp.json()


def test_healthz_no_auth_required(anon_client: TestClient) -> None:
    resp = anon_client.get("/api/v1/healthz")
    assert resp.status_code == 200
    body = resp.json()
    assert {"model_loaded", "auth_configured", "earth_engine_initialized", "model_version"} <= body.keys()
    assert "demo_mode" not in body, "demo mode was removed; healthz must not advertise it"


def test_every_farm_route_requires_auth(anon_client: TestClient) -> None:
    """No bypass token exists, so an unauthenticated caller reaches nothing."""
    for method, path in [
        ("get", "/api/v1/farms"),
        ("post", "/api/v1/farms"),
        ("get", "/api/v1/farms/any-id"),
        ("get", "/api/v1/farms/any-id/soil-card"),
        ("get", "/api/v1/farms/any-id/feasible-crops"),
        ("post", "/api/v1/farms/any-id/rank"),
        ("get", "/api/v1/dashboard"),
    ]:
        resp = getattr(anon_client, method)(path, **({"json": {}} if method == "post" else {}))
        assert resp.status_code == 401, f"{method.upper()} {path} returned {resp.status_code}, not 401"


def test_add_farm_returns_classified_soil_card(client: TestClient, identity) -> None:
    """§2.2 -> §2.3: raw readings in, classified card straight back."""
    identity.as_user("soil-card-user")
    body = _make_farm(client, "Soil card farm")

    card = body["soil_card"]
    assert card["classes"]["n_kg_ha"] == "low", "240 kg/ha is below the ICAR 280 threshold"
    assert card["classes"]["p_kg_ha"] == "medium"
    assert card["classes"]["k_kg_ha"] == "medium"
    assert card["ph"]["category"] == "neutral"
    assert card["ec"]["category"] == "normal"
    assert card["water"]["category"] in {"high", "abundant"}
    assert card["summary"] and card["caveat"]
    # The farmer's own numbers must come back untouched — this is their data.
    assert card["readings"]["n_kg_ha"] == 240.0
    assert card["readings"]["ph"] == 6.8

    client.delete(f"/api/v1/farms/{body['farm']['id']}")


def test_feasible_crops_gate_with_reasons(client: TestClient, identity) -> None:
    """§2.4: crops are excluded with a stated reason, never silently dropped."""
    identity.as_user("feasibility-user")
    # Strongly acidic + very little water: several crops must fail their gates.
    farm = _make_farm(
        client,
        "Acidic farm",
        soil={**GOOD_SOIL, "ph": 4.9, "water_available_m3": 1500.0},
    )
    farm_id = farm["farm"]["id"]

    resp = client.get(f"/api/v1/farms/{farm_id}/feasible-crops")
    assert resp.status_code == 200
    body = resp.json()

    assert body["counts"]["assessed"] > 0
    assert body["excluded"], "pH 4.9 with 1500 m3 should exclude something"
    for row in body["excluded"]:
        assert row["reasons"], f"{row['crop']} excluded with no reason given"
    for row in body["feasible"]:
        assert row["reasons"]

    client.delete(f"/api/v1/farms/{farm_id}")


def test_rank_crops_is_quantum_and_not_a_sort(client: TestClient, identity) -> None:
    """§2.5 + §3: the ranking comes off the measurement distribution, and the
    response carries the circuit and the sorted-baseline comparison."""
    if get_yield_model() is None:
        pytest.skip("Model not trained — run scripts/train_model.py first")

    identity.as_user("ranking-user")
    farm = _make_farm(client, "Ranking farm")
    farm_id = farm["farm"]["id"]

    resp = client.post(f"/api/v1/farms/{farm_id}/rank", json={})
    assert resp.status_code == 200, resp.text
    body = resp.json()

    ranking = body["ranking"]
    assert ranking is not None, body.get("error")
    assert ranking["solver"] in {"sparq_rotation", "classical_exact"}
    assert len(ranking["ranked_crops"]) == len(ranking["seasons"])
    for i, row in enumerate(ranking["ranked_crops"], start=1):
        assert row["rank"] == i
        assert row["why"], "every rank must explain itself"
        assert "realised_value_rs" in row and "standalone_value_rs" in row

    q = body["quantum"]
    # One crop per season is structural, not statistical.
    assert q["simplex_rate"] == 1.0
    assert q["n_qubits"] == len(ranking["seasons"]) * len(body["feasibility"]["rotation_candidates"])
    assert q["circuit"]["operations"], "§3 requires the circuit to be visible"
    assert any(op["gate"] == "IsingXY" for op in q["circuit"]["operations"])
    assert q["measurements"], "§3 requires the measured distribution to be visible"
    assert q["measurements"][0]["rank"] == 1
    assert q["convergence"], "a real optimisation trace, not a synthetic curve"
    assert q["claim"]

    # The naive sort is reported alongside, so "why not just sort?" is answered
    # with this farm's own rupees rather than an assertion.
    assert "sorted_by_yield" in body["baselines"]
    assert "greedy_with_lookback" in body["baselines"]
    assert body["ranking"]["matched_exact_optimum"] is True

    # §2.6 — treatment advice ships with the ranking.
    assert "advisory" in body and "fertilizer" in body["advisory"]

    client.delete(f"/api/v1/farms/{farm_id}")


def test_rank_requires_a_soil_card_first(client: TestClient, identity) -> None:
    """The pipeline is farm-specific, so it cannot run without that farm's soil."""
    identity.as_user("no-soil-user")
    # Create through the legacy field route, which does not take soil readings.
    resp = client.post(
        "/api/v1/fields",
        json={"name": "No soil", "boundary_geojson": BOUNDARY, "plots": [], "sowing_date": "2026-06-01"},
    )
    assert resp.status_code == 201
    farm_id = resp.json()["id"]

    rank = client.post(f"/api/v1/farms/{farm_id}/rank", json={})
    assert rank.status_code == 409
    assert "soil card" in rank.json()["detail"].lower()

    client.delete(f"/api/v1/farms/{farm_id}")


def test_n_farms_per_account_stay_independent(client: TestClient, identity) -> None:
    """§4: results are scoped to the farm that produced them, for arbitrary N."""
    identity.as_user("multi-farm-user")

    farms = [
        _make_farm(client, "Farm A", soil={**GOOD_SOIL, "ph": 6.8, "n_kg_ha": 240.0}, area_ha=1.0),
        _make_farm(client, "Farm B", soil={**GOOD_SOIL, "ph": 7.9, "n_kg_ha": 600.0}, area_ha=2.0),
        _make_farm(client, "Farm C", soil={**GOOD_SOIL, "ph": 5.6, "n_kg_ha": 300.0}, area_ha=0.5),
    ]
    ids = [f["farm"]["id"] for f in farms]
    assert len(set(ids)) == 3

    listing = client.get("/api/v1/farms").json()
    assert listing["count"] == 3

    # Each farm's card reflects only its own readings.
    cards = {fid: client.get(f"/api/v1/farms/{fid}/soil-card").json()["soil_card"] for fid in ids}
    assert cards[ids[0]]["classes"]["n_kg_ha"] == "low"
    assert cards[ids[1]]["classes"]["n_kg_ha"] == "high"
    assert cards[ids[2]]["classes"]["n_kg_ha"] == "medium"
    assert cards[ids[1]]["ph"]["category"] == "alkaline"
    assert cards[ids[2]]["ph"]["category"] == "slightly_acidic"

    # And so does each farm's feasibility verdict — different soil, different gates.
    feasible_sets = {
        fid: {row["crop"] for row in client.get(f"/api/v1/farms/{fid}/feasible-crops").json()["feasible"]}
        for fid in ids
    }
    assert feasible_sets[ids[1]] != feasible_sets[ids[2]], "different soil must yield different shortlists"

    for fid in ids:
        client.delete(f"/api/v1/farms/{fid}")


def test_accounts_are_isolated(client: TestClient, identity) -> None:
    """§4: one Google account cannot see, read or delete another's farm."""
    identity.as_user("account-one")
    mine = _make_farm(client, "Account one farm")
    mine_id = mine["farm"]["id"]
    assert client.get("/api/v1/farms").json()["count"] == 1

    identity.as_user("account-two")
    assert client.get("/api/v1/farms").json()["count"] == 0, "a new account starts empty"
    theirs = _make_farm(client, "Account two farm")
    theirs_id = theirs["farm"]["id"]
    assert theirs_id != mine_id

    # Every read path on another account's farm is refused.
    for path in (
        f"/api/v1/farms/{mine_id}",
        f"/api/v1/farms/{mine_id}/soil-card",
        f"/api/v1/farms/{mine_id}/feasible-crops",
    ):
        assert client.get(path).status_code == 403, path
    assert client.post(f"/api/v1/farms/{mine_id}/rank", json={}).status_code == 403
    assert client.delete(f"/api/v1/farms/{mine_id}").status_code == 403

    # Account two's own farm is unaffected, and still there.
    assert client.get(f"/api/v1/farms/{theirs_id}").status_code == 200
    assert client.get("/api/v1/farms").json()["count"] == 1

    identity.as_user("account-one")
    assert client.get("/api/v1/farms").json()["count"] == 1
    assert client.get(f"/api/v1/farms/{mine_id}").status_code == 200
    client.delete(f"/api/v1/farms/{mine_id}")

    identity.as_user("account-two")
    client.delete(f"/api/v1/farms/{theirs_id}")


def test_dashboard_aggregates_only_this_account(client: TestClient, identity) -> None:
    """§2.8: totals cover the caller's farms and no one else's."""
    identity.as_user("dash-user-one")
    a = _make_farm(client, "Dash A", area_ha=1.5)
    b = _make_farm(client, "Dash B", area_ha=2.5)

    identity.as_user("dash-user-two")
    c = _make_farm(client, "Other account farm", area_ha=99.0)
    other = client.get("/api/v1/dashboard").json()
    assert other["totals"]["farms"] == 1
    assert other["totals"]["total_area_ha"] == pytest.approx(99.0)

    identity.as_user("dash-user-one")
    dash = client.get("/api/v1/dashboard").json()
    assert dash["totals"]["farms"] == 2
    assert dash["totals"]["total_area_ha"] == pytest.approx(4.0)
    assert dash["totals"]["farms_awaiting_ranking"] == 2
    names = {row["name"] for row in dash["farms"]}
    assert names == {"Dash A", "Dash B"}
    assert "Other account farm" not in names
    # Farms without a ranking are surfaced as needing attention, not hidden.
    assert all("no crop ranking yet" in row["issues"] for row in dash["farms"])

    for fid in (a["farm"]["id"], b["farm"]["id"]):
        client.delete(f"/api/v1/farms/{fid}")
    identity.as_user("dash-user-two")
    client.delete(f"/api/v1/farms/{c['farm']['id']}")


def test_soil_card_history_is_kept(client: TestClient, identity) -> None:
    """Re-testing soil after treatment is the reason to open the app twice."""
    identity.as_user("history-user")
    farm = _make_farm(client, "History farm", soil={**GOOD_SOIL, "n_kg_ha": 200.0})
    farm_id = farm["farm"]["id"]

    resp = client.post(
        f"/api/v1/farms/{farm_id}/soil-card",
        json={**GOOD_SOIL, "n_kg_ha": 420.0},
    )
    assert resp.status_code == 201
    assert resp.json()["soil_card"]["classes"]["n_kg_ha"] == "medium"

    body = client.get(f"/api/v1/farms/{farm_id}/soil-card").json()
    assert body["soil_card"]["readings"]["n_kg_ha"] == 420.0, "latest card wins"
    assert len(body["history"]) == 2, "the earlier reading is retained"

    client.delete(f"/api/v1/farms/{farm_id}")


def test_analytics_model_metrics_served_verbatim(client: TestClient) -> None:
    resp = client.get("/api/v1/analytics/model-metrics")
    if resp.status_code == 503:
        pytest.skip("metrics.json not generated — run scripts/train_model.py first")
    body = resp.json()
    assert "protocols" in body and "training_data_source" in body


def test_clay_soil_still_gets_a_plan(client: TestClient, identity) -> None:
    """Clay is the most common Cauvery delta soil. Black gram is the standard
    rice-fallow pulse grown on exactly that soil, so gating it on drainage left
    delta farmers with one crop and no plan — contradicting our own crops.yaml."""
    identity.as_user("clay-user")
    farm = _make_farm(client, "Delta clay", soil={**GOOD_SOIL, "soil_type": "clay"})
    farm_id = farm["farm"]["id"]

    body = client.get(f"/api/v1/farms/{farm_id}/feasible-crops").json()
    feasible = {r["crop"] for r in body["feasible"]}
    assert "paddy" in feasible, "paddy belongs on clay"
    assert "black_gram" in feasible, "black gram is the rice-fallow crop for delta clay"
    # Still a hard gate where it is agronomically real.
    excluded = {r["crop"] for r in body["excluded"]}
    assert "groundnut" in excluded, "groundnut needs friable soil for pegging"
    assert len(body["rotation_candidates"]) >= 2

    client.delete(f"/api/v1/farms/{farm_id}")


def test_single_feasible_crop_still_answers(client: TestClient, identity) -> None:
    """One crop is not an error — the farmer should be told to grow it. And no
    circuit is run, because a one-element search space has nothing to optimise."""
    if get_yield_model() is None:
        pytest.skip("Model not trained")

    identity.as_user("single-crop-user")
    # Very little water: only the lowest-demand crop clears the gate.
    farm = _make_farm(client, "Dry plot", soil={**GOOD_SOIL, "water_available_m3": 2000.0})
    farm_id = farm["farm"]["id"]

    body = client.post(f"/api/v1/farms/{farm_id}/rank", json={}).json()
    if len(body["feasibility"]["rotation_candidates"]) != 1:
        pytest.skip("this soil profile did not reduce to exactly one candidate")

    assert body["ranking"] is not None, "one feasible crop must still produce an answer"
    assert body["ranking"]["solver"] == "single_candidate"
    assert body["ranking"]["ranked_crops"]
    assert body["quantum"] is None if "quantum" in body else True
    assert "no quantum step was run" in body["note"]
    assert body["advisory"]["fertilizer"] is not None
    # And it survives the round trip to storage.
    assert client.get(f"/api/v1/farms/{farm_id}/rotation-plan").status_code == 200

    client.delete(f"/api/v1/farms/{farm_id}")


def test_no_feasible_crop_explains_itself(client: TestClient, identity) -> None:
    identity.as_user("no-crop-user")
    farm = _make_farm(client, "Barren", soil={**GOOD_SOIL, "ph": 3.0, "water_available_m3": 10.0})
    farm_id = farm["farm"]["id"]

    body = client.post(f"/api/v1/farms/{farm_id}/rank", json={}).json()
    assert body["ranking"] is None
    assert "No crop passed" in body["error"]
    # The per-crop reasons are still there, so the farmer knows what to fix.
    assert body["feasibility"]["excluded"]
    assert all(r["reasons"] for r in body["feasibility"]["excluded"])

    client.delete(f"/api/v1/farms/{farm_id}")


def test_water_scenario_reranks_without_persist(client: TestClient, identity) -> None:
    """Survival slider: cut water → heavy crops drop → plan shifts; dry-run skips DB."""
    if get_yield_model() is None:
        pytest.skip("Model not trained")

    identity.as_user("scenario-user")
    farm = _make_farm(client, "Wet farm", soil={**GOOD_SOIL, "water_available_m3": 12000.0})
    farm_id = farm["farm"]["id"]

    wet = client.post(
        f"/api/v1/farms/{farm_id}/rank",
        json={"water_available_m3": 12000.0, "persist": False},
    ).json()
    assert wet["scenario"]["persisted"] is False
    wet_crops = set(wet["feasibility"]["rotation_candidates"])
    assert "paddy" in wet_crops

    dry = client.post(
        f"/api/v1/farms/{farm_id}/rank",
        json={"water_available_m3": 2500.0, "persist": False},
    ).json()
    dry_crops = set(dry["feasibility"]["rotation_candidates"])
    assert "paddy" not in dry_crops
    assert dry_crops  # something drought-tolerant remains
    assert "pipeline" in wet and "rotation_candidates" in wet["pipeline"]
    assert "pipeline" in dry
  if wet.get("ranking") and dry.get("ranking"):
      assert wet["ranking"]["sequence"] != dry["ranking"]["sequence"]
    assert client.get(f"/api/v1/farms/{farm_id}/rotation-plan").status_code == 404

    client.delete(f"/api/v1/farms/{farm_id}")


def test_budget_scenario_excludes_expensive_crop(client: TestClient, identity) -> None:
    if get_yield_model() is None:
        pytest.skip("Model not trained")

    identity.as_user("budget-user")
    farm = _make_farm(client, "Budget farm", soil={**GOOD_SOIL, "water_available_m3": 12000.0})
    farm_id = farm["farm"]["id"]

    body = client.post(
        f"/api/v1/farms/{farm_id}/rank",
        json={"budget_rs": 15000.0, "persist": False},
    ).json()
    excluded = {e["crop"] for e in body["pipeline"]["excluded_crops"]}
    assert "paddy" in excluded or "sugarcane" in excluded

    client.delete(f"/api/v1/farms/{farm_id}")


def test_ops_summary_public(client: TestClient) -> None:
    resp = client.get("/api/v1/ops/summary")
    assert resp.status_code == 200
    data = resp.json()
    assert "yield" in data and "quantum" in data
    assert "events" in data


def test_ranking_is_reproducible(client: TestClient, identity) -> None:
    """Same farm, same soil, same answer — the farmer must not get a different
    plan each time they open the app."""
    if get_yield_model() is None:
        pytest.skip("Model not trained")

    identity.as_user("repeat-user")
    farm = _make_farm(client, "Repeat farm")
    farm_id = farm["farm"]["id"]

    a = client.post(f"/api/v1/farms/{farm_id}/rank", json={}).json()
    b = client.post(f"/api/v1/farms/{farm_id}/rank", json={}).json()
    assert a["ranking"]["sequence"] == b["ranking"]["sequence"]
    assert a["ranking"]["total_value_rs"] == pytest.approx(b["ranking"]["total_value_rs"])
    # The newest plan is the one served back.
    saved = client.get(f"/api/v1/farms/{farm_id}/rotation-plan").json()
    assert saved["ranking"]["sequence"] == b["ranking"]["sequence"]

    client.delete(f"/api/v1/farms/{farm_id}")


def test_crop_ranking_answers_best_crop_for_my_land(client: TestClient, identity) -> None:
    """Planting order and profitability order are different questions; §2.5 asks
    for the second, so both ship."""
    if get_yield_model() is None:
        pytest.skip("Model not trained")

    identity.as_user("crop-rank-user")
    farm = _make_farm(client, "Rank farm")
    farm_id = farm["farm"]["id"]

    ranking = client.post(f"/api/v1/farms/{farm_id}/rank", json={}).json()["ranking"]
    ranked = ranking["crop_ranking"]
    assert ranked, "brief §2.5 asks for the crops ordered best-first"
    assert [r["rank"] for r in ranked] == list(range(1, len(ranked) + 1))
    values = [r["standalone_value_rs"] for r in ranked]
    assert values == sorted(values, reverse=True), "must be ordered by profitability"
    assert any(r["in_plan"] for r in ranked)
    for r in ranked:
        assert ("seasons_in_plan" in r) and (bool(r["seasons_in_plan"]) == r["in_plan"])

    client.delete(f"/api/v1/farms/{farm_id}")


# --------------------------------------------------------------------------
# Developer login — an operator-configured convenience, not a shipped bypass
# --------------------------------------------------------------------------


def _reload_settings(monkeypatch, **env):
    """Rebuild Settings from a patched environment (it is lru_cached)."""
    from app.core.config import Settings, get_settings

    for key, value in env.items():
        monkeypatch.setenv(key, value)
    get_settings.cache_clear()
    monkeypatch.setattr("app.core.security.get_settings", lambda: Settings())
    return Settings()


def test_dev_login_is_inert_unless_configured(anon_client: TestClient, monkeypatch) -> None:
    """Default deployment has no dev credential at all, so nothing opens a door."""
    from app.core.config import Settings, get_settings

    get_settings.cache_clear()
    monkeypatch.delenv("DEV_LOGIN_USER", raising=False)
    monkeypatch.delenv("DEV_LOGIN_TOKEN", raising=False)
    monkeypatch.setattr("app.core.security.get_settings", lambda: Settings(_env_file=None))

    assert Settings(_env_file=None).dev_login_enabled is False
    for token in ("demo-farmer", "demo", "anything"):
        resp = anon_client.get("/api/v1/farms", headers={"Authorization": f"Bearer {token}"})
        assert resp.status_code == 401, f"'{token}' must not authenticate"

    get_settings.cache_clear()


def test_dev_login_requires_both_settings(monkeypatch) -> None:
    """Half-configured is off — a user id without a secret opens nothing."""
    from app.core.config import Settings

    assert Settings(_env_file=None, dev_login_user="x", dev_login_token="").dev_login_enabled is False
    assert Settings(_env_file=None, dev_login_user="", dev_login_token="s3cret").dev_login_enabled is False
    assert Settings(_env_file=None, dev_login_user="x", dev_login_token="s3cret").dev_login_enabled is True


def test_dev_login_rejects_a_wrong_token(anon_client: TestClient, monkeypatch) -> None:
    from app.core.config import get_settings

    _reload_settings(monkeypatch, DEV_LOGIN_USER="seeded-demo", DEV_LOGIN_TOKEN="correct-horse")
    bad = anon_client.get("/api/v1/farms", headers={"Authorization": "Bearer wrong-horse"})
    assert bad.status_code == 401
    get_settings.cache_clear()


def test_dev_login_account_is_still_isolated(anon_client: TestClient, monkeypatch) -> None:
    """The dev account is a normal account. Enabling the login must not let it
    read anyone else's farms — it only provides a way in without Google."""
    from app.core.config import get_settings

    _reload_settings(monkeypatch, DEV_LOGIN_USER="devlogin-user", DEV_LOGIN_TOKEN="tok-abc123")
    headers = {"Authorization": "Bearer tok-abc123"}

    created = anon_client.post(
        "/api/v1/farms",
        headers=headers,
        json={"name": "Dev farm", "lat": 10.755, "lon": 79.055, "area_ha": 1.0, "soil": GOOD_SOIL},
    )
    assert created.status_code == 201
    farm_id = created.json()["farm"]["id"]

    listing = anon_client.get("/api/v1/farms", headers=headers).json()
    assert listing["count"] == 1, "a fresh dev account sees only its own farm"
    assert {f["name"] for f in listing["farms"]} == {"Dev farm"}

    anon_client.delete(f"/api/v1/farms/{farm_id}", headers=headers)
    get_settings.cache_clear()


def test_healthz_reports_dev_login_state(anon_client: TestClient, monkeypatch) -> None:
    """A deployed instance with this on must be visible at a glance."""
    from app.core.config import Settings, get_settings

    get_settings.cache_clear()
    monkeypatch.setattr("app.api.v1.health.get_settings",
                        lambda: Settings(_env_file=None, dev_login_user="u", dev_login_token="t"))
    assert anon_client.get("/api/v1/healthz").json()["dev_login_enabled"] is True

    monkeypatch.setattr("app.api.v1.health.get_settings", lambda: Settings(_env_file=None))
    assert anon_client.get("/api/v1/healthz").json()["dev_login_enabled"] is False
    get_settings.cache_clear()
