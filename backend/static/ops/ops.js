const API = "/api/v1/ops";

const logEl = document.getElementById("log");
const waterSlider = document.getElementById("water-slider");
const budgetSlider = document.getElementById("budget-slider");
const waterVal = document.getElementById("water-val");
const budgetVal = document.getElementById("budget-val");
const demoResult = document.getElementById("demo-result");
const runBtn = document.getElementById("run-demo");

function fmtRs(n) {
  if (n == null) return "—";
  return "₹" + Math.round(n).toLocaleString("en-IN");
}

function fmtPct(n) {
  if (n == null) return "—";
  return (n * 100).toFixed(1) + "%";
}

function fmtNum(n, d = 2) {
  if (n == null) return "—";
  return Number(n).toFixed(d);
}

function renderDl(el, entries) {
  el.innerHTML = entries
    .map(([k, v]) => `<dt>${k}</dt><dd>${v}</dd>`)
    .join("");
}

async function loadSummary() {
  const r = await fetch(`${API}/summary`);
  if (!r.ok) throw new Error(`Summary ${r.status}`);
  const data = await r.json();

  const y = data.yield || {};
  renderDl(document.getElementById("yield-metrics"), [
    ["R² (temporal)", fmtNum(y.r2, 3)],
    ["RMSE", fmtNum(y.rmse, 2)],
    ["MAE", fmtNum(y.mae, 2)],
    ["Training rows", y.row_count ?? "—"],
  ]);

  const s = (data.quantum || {}).sparq || {};
  renderDl(document.getElementById("sparq-metrics"), [
    ["Optimum match", fmtPct(s.optimum_match_rate)],
    ["Feasible rate", fmtPct(s.mean_feasible_rate)],
    ["Simplex rate", fmtPct(s.mean_simplex_rate)],
    ["Uplift vs feasible", fmtNum(s.mean_uplift_vs_feasible_uniform, 2) + "×"],
    ["Wall time", fmtNum(s.mean_t_s, 2) + " s"],
    ["Qubits", s.mean_n_qubits ?? "—"],
  ]);

  const l = (data.quantum || {}).legacy_qaoa || {};
  renderDl(document.getElementById("legacy-metrics"), [
    ["Optimum match", fmtPct(l.optimum_match_rate)],
    ["Feasible rate", fmtPct(l.mean_feasible_rate)],
    ["Uplift vs feasible", fmtNum(l.mean_uplift_vs_feasible_uniform, 2) + "×"],
    ["Wall time", fmtNum(l.mean_t_s, 2) + " s"],
    ["Qubits", l.mean_n_qubits ?? "—"],
  ]);

  renderBenchmarkCharts(data);

  (data.events || []).forEach(appendLog);
}

function highlightStage(stage) {
  const map = {
    demo_rank: "rank_start",
    rank_start: "rank_start",
    gates_done: "gates_done",
    yield_done: "yield_done",
    sparq_start: "sparq_start",
    sparq_layer: "sparq_layer",
    sparq_cvar: "sparq_layer",
    rank_complete: "rank_complete",
  };
  const key = map[stage] || stage;
  document.querySelectorAll(".step").forEach((el) => {
    el.classList.toggle("active", el.dataset.stage === key);
  });
}

function appendLog(ev) {
  const line = document.createElement("div");
  line.className = "log-line";
  const ts = (ev.ts || "").slice(11, 19);
  line.innerHTML = `<span class="ts">${ts}</span> <span class="stage">[${ev.stage}]</span> ${ev.message}`;
  logEl.appendChild(line);
  logEl.scrollTop = logEl.scrollHeight;
  highlightStage(ev.stage);
}

function connectSse() {
  const es = new EventSource(`${API}/events`);
  es.onmessage = (e) => {
    try {
      appendLog(JSON.parse(e.data));
    } catch (_) {}
  };
  es.onerror = () => {
    es.close();
    setTimeout(connectSse, 3000);
  };
}

function updateSliderLabels() {
  waterVal.textContent = waterSlider.value + " m³";
  budgetVal.textContent = fmtRs(Number(budgetSlider.value));
}

async function runDemo() {
  runBtn.disabled = true;
  demoResult.textContent = "Running quantum rank…";
  try {
    const r = await fetch(`${API}/demo-rank`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        water_available_m3: Number(waterSlider.value),
        budget_rs: Number(budgetSlider.value),
      }),
    });
    const body = await r.json();
    if (!r.ok) {
      demoResult.textContent = body.detail || `Error ${r.status}`;
      return;
    }
    const pipe = body.pipeline || {};
    const ranking = body.ranking;
    const seq = ranking?.sequence?.join(" → ") || "(no plan)";
    const candidates = (pipe.rotation_candidates || []).join(", ");
    const excluded = (pipe.excluded_crops || [])
      .map((e) => e.crop)
      .join(", ");
    const curation = body.rotation_model?.curation;
    const curationLine = curation?.system
      ? `<br/><strong>Curation:</strong> ${curation.note || curation.system}`
      : "";
    demoResult.innerHTML = `
      <strong>Sequence:</strong> ${seq}<br/>
      <strong>Candidates:</strong> ${candidates || "—"}<br/>
      <strong>Excluded:</strong> ${excluded || "none"}<br/>
      <strong>Water band:</strong> ${pipe.water_category || "—"} ·
      <strong>Solver:</strong> ${ranking?.solver || "—"}${curationLine}
    `;
  } catch (err) {
    demoResult.textContent = String(err);
  } finally {
    runBtn.disabled = false;
  }
}

waterSlider.addEventListener("input", updateSliderLabels);
budgetSlider.addEventListener("input", updateSliderLabels);
runBtn.addEventListener("click", runDemo);

updateSliderLabels();
initChartControls();
loadSummary().catch((e) => appendLog({ ts: "", stage: "error", message: String(e) }));
connectSse();
