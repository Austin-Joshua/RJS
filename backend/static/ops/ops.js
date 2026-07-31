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

function esc(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function chartMax(rows) {
  const vals = rows.flatMap((r) => [r.sparq, r.legacy, r.single].filter((v) => v != null));
  return Math.max(1, ...vals) * 1.12;
}

function renderGroupedChart(containerId, title, rows) {
  const el = document.getElementById(containerId);
  if (!el) return;

  const w = 300;
  const rowH = 46;
  const h = 36 + rows.length * rowH;
  const left = 108;
  const chartW = w - left - 12;

  let svg = `<svg viewBox="0 0 ${w} ${h}" role="img" aria-label="${esc(title)}">`;
  svg += `<text x="0" y="14" class="chart-title">${esc(title)}</text>`;
  svg += `<line x1="${left}" y1="${h - 6}" x2="${w - 8}" y2="${h - 6}" class="chart-axis" />`;

  rows.forEach((row, i) => {
    const y0 = 24 + i * rowH;
    const scaleMax = row.max ?? chartMax([row]);
    svg += `<text x="0" y="${y0 + 12}" class="chart-label">${esc(row.label)}</text>`;

    if (row.sparq != null) {
      const bw = Math.max(0, (row.sparq / scaleMax) * chartW);
      svg += `<rect x="${left}" y="${y0}" width="${bw}" height="12" class="bar sparq" rx="2" />`;
      svg += `<text x="${left + bw + 3}" y="${y0 + 10}" class="chart-val">${esc(row.fmtSparq ?? row.sparq)}</text>`;
    }
    if (row.legacy != null) {
      const bw = Math.max(0, (row.legacy / scaleMax) * chartW);
      svg += `<rect x="${left}" y="${y0 + 16}" width="${bw}" height="12" class="bar legacy" rx="2" />`;
      svg += `<text x="${left + bw + 3}" y="${y0 + 26}" class="chart-val">${esc(row.fmtLegacy ?? row.legacy)}</text>`;
    }
    if (row.single != null) {
      const bw = Math.max(0, (row.single / scaleMax) * chartW);
      svg += `<rect x="${left}" y="${y0 + 4}" width="${bw}" height="16" class="bar classical" rx="2" />`;
      svg += `<text x="${left + bw + 3}" y="${y0 + 16}" class="chart-val">${esc(row.fmtSingle ?? row.single)}</text>`;
    }
  });

  svg += "</svg>";
  el.innerHTML = svg;
}

function renderBenchmarkCharts(data) {
  const s = (data.quantum || {}).sparq || {};
  const l = (data.quantum || {}).legacy_qaoa || {};
  const y = data.yield || {};

  renderGroupedChart("chart-quality", "Solution quality", [
    {
      label: "Optimum match",
      sparq: (s.optimum_match_rate ?? 0) * 100,
      legacy: (l.optimum_match_rate ?? 0) * 100,
      max: 100,
      fmtSparq: fmtPct(s.optimum_match_rate),
      fmtLegacy: fmtPct(l.optimum_match_rate),
    },
    {
      label: "Feasible rate",
      sparq: (s.mean_feasible_rate ?? 0) * 100,
      legacy: (l.mean_feasible_rate ?? 0) * 100,
      max: 100,
      fmtSparq: fmtPct(s.mean_feasible_rate),
      fmtLegacy: fmtPct(l.mean_feasible_rate),
    },
    {
      label: "Simplex rate",
      sparq: (s.mean_simplex_rate ?? 0) * 100,
      legacy: null,
      max: 100,
      fmtSparq: fmtPct(s.mean_simplex_rate),
    },
  ]);

  renderGroupedChart("chart-runtime", "Speed & search uplift", [
    {
      label: "Wall time (s)",
      sparq: s.mean_t_s ?? 0,
      legacy: l.mean_t_s ?? 0,
      fmtSparq: fmtNum(s.mean_t_s, 2) + " s",
      fmtLegacy: fmtNum(l.mean_t_s, 2) + " s",
    },
    {
      label: "Uplift vs feasible",
      sparq: s.mean_uplift_vs_feasible_uniform ?? 0,
      legacy: l.mean_uplift_vs_feasible_uniform ?? 0,
      fmtSparq: fmtNum(s.mean_uplift_vs_feasible_uniform, 2) + "×",
      fmtLegacy: fmtNum(l.mean_uplift_vs_feasible_uniform, 2) + "×",
    },
    {
      label: "Mean qubits",
      sparq: s.mean_n_qubits ?? 0,
      legacy: l.mean_n_qubits ?? 0,
      fmtSparq: String(s.mean_n_qubits ?? "—"),
      fmtLegacy: String(l.mean_n_qubits ?? "—"),
    },
  ]);

  renderGroupedChart("chart-yield", "LightGBM temporal holdout", [
    {
      label: "R²",
      single: (y.r2 ?? 0) * 100,
      max: 100,
      fmtSingle: fmtNum(y.r2, 3),
    },
    {
      label: "RMSE (t/ha)",
      single: y.rmse ?? 0,
      fmtSingle: fmtNum(y.rmse, 2),
    },
    {
      label: "MAE (t/ha)",
      single: y.mae ?? 0,
      fmtSingle: fmtNum(y.mae, 2),
    },
  ]);
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
loadSummary().catch((e) => appendLog({ ts: "", stage: "error", message: String(e) }));
connectSse();
