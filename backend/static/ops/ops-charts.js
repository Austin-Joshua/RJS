/** Interactive benchmark charts — no external deps. */
(function () {
  const SERIES = {
    sparq: { label: "SPARQ", class: "sparq", grad: "grad-sparq" },
    legacy: { label: "Legacy QAOA", class: "legacy", grad: "grad-legacy" },
    single: { label: "LightGBM", class: "classical", grad: "grad-classical" },
  };

  let tooltip = null;
  let visibleSeries = new Set(["sparq", "legacy", "single"]);

  function ensureTooltip() {
    if (tooltip) return tooltip;
    tooltip = document.createElement("div");
    tooltip.id = "chart-tooltip";
    tooltip.className = "chart-tooltip";
    tooltip.setAttribute("role", "tooltip");
    document.body.appendChild(tooltip);
    return tooltip;
  }

  function showTooltip(html, clientX, clientY) {
    const el = ensureTooltip();
    el.innerHTML = html;
    el.classList.add("visible");
    const pad = 14;
    const rect = el.getBoundingClientRect();
    let x = clientX + pad;
    let y = clientY - rect.height - pad;
    if (x + rect.width > window.innerWidth - 8) x = clientX - rect.width - pad;
    if (y < 8) y = clientY + pad;
    el.style.left = `${x}px`;
    el.style.top = `${y}px`;
  }

  function hideTooltip() {
    if (tooltip) tooltip.classList.remove("visible");
  }

  function easeOutCubic(t) {
    return 1 - Math.pow(1 - t, 3);
  }

  function animateWidth(rect, target, delayMs) {
    const goal = Math.max(0, target);
    setTimeout(() => {
      const start = performance.now();
      const duration = 720;
      function frame(now) {
        const p = Math.min(1, (now - start) / duration);
        rect.setAttribute("width", String(goal * easeOutCubic(p)));
        if (p < 1) requestAnimationFrame(frame);
      }
      requestAnimationFrame(frame);
    }, delayMs);
  }

  function gridTicks(max, count = 4) {
    const ticks = [];
    for (let i = 0; i <= count; i++) ticks.push((max / count) * i);
    return ticks;
  }

  function deltaBadge(sparq, legacy, fmt) {
    if (sparq == null || legacy == null || legacy === 0) return "";
    const pct = ((sparq - legacy) / Math.abs(legacy)) * 100;
    const sign = pct >= 0 ? "+" : "";
    const cls = pct >= 0 ? "up" : "down";
    return `<span class="delta ${cls}">${sign}${pct.toFixed(0)}% vs QAOA</span>`;
  }

  function buildDefs() {
    const ns = "http://www.w3.org/2000/svg";
    const defs = document.createElementNS(ns, "defs");
    const grads = [
      ["grad-sparq", "#3d7a52", "#2d5a3d"],
      ["grad-legacy", "#e07a5f", "#c45c3e"],
      ["grad-classical", "#6b9b7a", "#4a7c59"],
    ];
    grads.forEach(([id, a, b]) => {
      const g = document.createElementNS(ns, "linearGradient");
      g.setAttribute("id", id);
      g.setAttribute("x1", "0%");
      g.setAttribute("y1", "0%");
      g.setAttribute("x2", "100%");
      g.setAttribute("y2", "0%");
      const s1 = document.createElementNS(ns, "stop");
      s1.setAttribute("offset", "0%");
      s1.setAttribute("stop-color", a);
      const s2 = document.createElementNS(ns, "stop");
      s2.setAttribute("offset", "100%");
      s2.setAttribute("stop-color", b);
      g.appendChild(s1);
      g.appendChild(s2);
      defs.appendChild(g);
    });
    return defs;
  }

  function renderChart(containerId, cfg) {
    const host = document.getElementById(containerId);
    if (!host) return;

    const ns = "http://www.w3.org/2000/svg";
    const w = 420;
    const rowH = 54;
    const top = 48;
    const left = 118;
    const right = 16;
    const chartW = w - left - right;
    const rows = cfg.rows || [];
    const h = top + rows.length * rowH + 28;

    host.innerHTML = "";
    host.classList.add("chart-card");

    const header = document.createElement("div");
    header.className = "chart-card-header";
    header.innerHTML = `<h3>${cfg.title}</h3>${cfg.subtitle ? `<p>${cfg.subtitle}</p>` : ""}`;
    host.appendChild(header);

    const wrap = document.createElement("div");
    wrap.className = "chart-svg-wrap";
    host.appendChild(wrap);

    const svg = document.createElementNS(ns, "svg");
    svg.setAttribute("viewBox", `0 0 ${w} ${h}`);
    svg.setAttribute("class", "chart-svg");
    svg.setAttribute("role", "img");
    svg.setAttribute("aria-label", cfg.title);
    wrap.appendChild(svg);
    svg.appendChild(buildDefs());

    const defaultMax = cfg.max ?? Math.max(1, ...rows.flatMap((r) => [r.sparq, r.legacy, r.single].filter((v) => v != null))) * 1.08;

    if (!cfg.perRowScale) {
      gridTicks(defaultMax, cfg.ticks ?? 4).forEach((tick) => {
        const x = left + (tick / defaultMax) * chartW;
        const line = document.createElementNS(ns, "line");
        line.setAttribute("x1", x);
        line.setAttribute("y1", top - 8);
        line.setAttribute("x2", x);
        line.setAttribute("y2", h - 18);
        line.setAttribute("class", "chart-grid");
        svg.appendChild(line);

        const label = document.createElementNS(ns, "text");
        label.setAttribute("x", x);
        label.setAttribute("y", h - 4);
        label.setAttribute("class", "chart-tick");
        label.setAttribute("text-anchor", "middle");
        label.textContent = cfg.tickFmt ? cfg.tickFmt(tick) : tick < 10 ? tick.toFixed(1) : Math.round(tick);
        svg.appendChild(label);
      });
    }

    let animDelay = 0;

    rows.forEach((row, i) => {
      const y0 = top + i * rowH;
      const scaleMax = row.max ?? cfg.max ?? Math.max(1, ...[row.sparq, row.legacy, row.single].filter((v) => v != null)) * 1.12;
      const group = document.createElementNS(ns, "g");
      group.setAttribute("class", "chart-row");
      group.dataset.row = row.label;
      svg.appendChild(group);

      const lbl = document.createElementNS(ns, "text");
      lbl.setAttribute("x", 0);
      lbl.setAttribute("y", y0 + 22);
      lbl.setAttribute("class", "chart-label");
      lbl.textContent = row.label;
      group.appendChild(lbl);

      if (cfg.perRowScale) {
        [0, scaleMax].forEach((tick, ti) => {
          const x = left + (tick / scaleMax) * chartW;
          const tickLbl = document.createElementNS(ns, "text");
          tickLbl.setAttribute("x", x);
          tickLbl.setAttribute("y", y0 + 44);
          tickLbl.setAttribute("class", "chart-tick");
          tickLbl.setAttribute("text-anchor", ti === 0 ? "start" : "end");
          tickLbl.textContent = row.tickFmt ? row.tickFmt(tick) : tick < 10 ? tick.toFixed(2) : Math.round(tick);
          group.appendChild(tickLbl);
        });
      }

      const bars = [
        { key: "sparq", y: y0 + 2, h: 14, val: row.sparq, fmt: row.fmtSparq },
        { key: "legacy", y: y0 + 20, h: 14, val: row.legacy, fmt: row.fmtLegacy },
        { key: "single", y: y0 + 8, h: 18, val: row.single, fmt: row.fmtSingle },
      ];

      bars.forEach((b) => {
        if (b.val == null) return;
        const series = SERIES[b.key];
        const bw = (b.val / scaleMax) * chartW;
        const rect = document.createElementNS(ns, "rect");
        rect.setAttribute("x", left);
        rect.setAttribute("y", b.y);
        rect.setAttribute("height", b.h);
        rect.setAttribute("width", "0");
        rect.setAttribute("rx", "4");
        rect.setAttribute("class", `bar-rect ${series.class}`);
        rect.setAttribute("fill", `url(#${series.grad})`);
        rect.setAttribute("data-series", b.key);
        rect.style.opacity = visibleSeries.has(b.key) ? "1" : "0.15";
        group.appendChild(rect);

        const valX = left + bw + 6;
        const val = document.createElementNS(ns, "text");
        val.setAttribute("x", Math.min(valX, w - 4));
        val.setAttribute("y", b.y + b.h - 3);
        val.setAttribute("class", "chart-val");
        val.textContent = b.fmt ?? b.val;
        group.appendChild(val);

        const tipHtml = `
          <strong>${row.label}</strong><br/>
          <span class="tip-series ${series.class}">${series.label}</span><br/>
          <span class="tip-value">${b.fmt ?? b.val}</span>
          ${b.key === "sparq" && row.legacy != null ? `<br/>${deltaBadge(row.sparq, row.legacy)}` : ""}
        `;

        rect.addEventListener("mouseenter", (e) => {
          group.classList.add("hover");
          showTooltip(tipHtml, e.clientX, e.clientY);
          rect.setAttribute("filter", "url(#bar-glow)");
        });
        rect.addEventListener("mousemove", (e) => showTooltip(tipHtml, e.clientX, e.clientY));
        rect.addEventListener("mouseleave", () => {
          group.classList.remove("hover");
          hideTooltip();
          rect.removeAttribute("filter");
        });

        if (visibleSeries.has(b.key)) {
          animateWidth(rect, bw, animDelay);
          animDelay += 90;
        } else {
          rect.setAttribute("width", String(bw));
        }
      });
    });

    const glow = document.createElementNS(ns, "filter");
    glow.setAttribute("id", "bar-glow");
    const blur = document.createElementNS(ns, "feGaussianBlur");
    blur.setAttribute("stdDeviation", "1.2");
    blur.setAttribute("result", "blur");
    glow.appendChild(blur);
    const merge = document.createElementNS(ns, "feMerge");
    ["blur", "SourceGraphic"].forEach((n) => {
      const mn = document.createElementNS(ns, "feMergeNode");
      mn.setAttribute("in", n);
      merge.appendChild(mn);
    });
    glow.appendChild(merge);
    svg.querySelector("defs").appendChild(glow);

    if (cfg.footnote) {
      const foot = document.createElement("p");
      foot.className = "chart-footnote";
      foot.textContent = cfg.footnote;
      host.appendChild(foot);
    }
  }

  function bindSeriesToggles() {
    document.querySelectorAll(".chart-toggle").forEach((btn) => {
      btn.addEventListener("click", () => {
        document.querySelectorAll(".chart-toggle").forEach((b) => b.classList.remove("active"));
        btn.classList.add("active");
        const mode = btn.dataset.series;
        if (mode === "both") {
          visibleSeries = new Set(["sparq", "legacy", "single"]);
        } else if (mode === "sparq") {
          visibleSeries = new Set(["sparq"]);
        } else {
          visibleSeries = new Set(["legacy"]);
        }
        if (window.__lastChartData) window.renderBenchmarkCharts(window.__lastChartData);
      });
    });
  }

  window.renderBenchmarkCharts = function renderBenchmarkCharts(data) {
    window.__lastChartData = data;
    const s = (data.quantum || {}).sparq || {};
    const l = (data.quantum || {}).legacy_qaoa || {};
    const y = data.yield || {};

    renderChart("chart-quality", {
      title: "Solution quality",
      subtitle: "Higher is better — % of benchmark instances",
      max: 100,
      tickFmt: (v) => `${Math.round(v)}%`,
      footnote: "Simplex rate = valid one-crop-per-season plans (SPARQ only).",
      rows: [
        {
          label: "Optimum match",
          sparq: (s.optimum_match_rate ?? 0) * 100,
          legacy: (l.optimum_match_rate ?? 0) * 100,
          fmtSparq: fmtPct(s.optimum_match_rate),
          fmtLegacy: fmtPct(l.optimum_match_rate),
        },
        {
          label: "Feasible rate",
          sparq: (s.mean_feasible_rate ?? 0) * 100,
          legacy: (l.mean_feasible_rate ?? 0) * 100,
          fmtSparq: fmtPct(s.mean_feasible_rate),
          fmtLegacy: fmtPct(l.mean_feasible_rate),
        },
        {
          label: "Simplex rate",
          sparq: (s.mean_simplex_rate ?? 0) * 100,
          legacy: null,
          fmtSparq: fmtPct(s.mean_simplex_rate),
        },
      ],
    });

    renderChart("chart-runtime", {
      title: "Speed & search uplift",
      subtitle: "Wall time ↓ better · uplift ↑ better",
      footnote: "50 random rotation QUBOs · 3 QAOA layers each.",
      rows: [
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
      ],
    });

    renderChart("chart-yield", {
      title: "LightGBM temporal holdout",
      subtitle: "Classical yield model · district-aware",
      perRowScale: true,
      rows: [
        {
          label: "R² score",
          single: (y.r2 ?? 0) * 100,
          max: 100,
          fmtSingle: fmtNum(y.r2, 3),
          tickFmt: (v) => (v === 0 ? "0" : fmtNum(v / 100, 2)),
        },
        {
          label: "RMSE (t/ha)",
          single: y.rmse ?? 0,
          fmtSingle: fmtNum(y.rmse, 2),
          tickFmt: (v) => fmtNum(v, 1),
        },
        {
          label: "MAE (t/ha)",
          single: y.mae ?? 0,
          fmtSingle: fmtNum(y.mae, 2),
          tickFmt: (v) => fmtNum(v, 1),
        },
      ],
    });
  };

  window.initChartControls = bindSeriesToggles;
})();
