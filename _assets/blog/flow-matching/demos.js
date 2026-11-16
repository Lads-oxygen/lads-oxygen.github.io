(() => {
  "use strict";
  const script = document.currentScript;
  const explorer = document.querySelector("#fm-explorer");
  const sampler = document.querySelector("#fm-sampler");
  const notebook = document.querySelector("#fm-notebook");
  const heldColour = "#536a80";
  const config = { responsive: true, displayModeBar: false, scrollZoom: false };

  function layout([xrange, yrange]) {
    const axis = range => ({ range, visible: false, fixedrange: true, constrain: "domain" });
    return {
      margin: { l: 8, r: 8, t: 8, b: 8 },
      paper_bgcolor: "transparent", plot_bgcolor: "transparent",
      font: { color: "#43556a" },
      showlegend: false, hovermode: false,
      xaxis: axis(xrange), yaxis: { ...axis(yrange), scaleanchor: "x", scaleratio: 1 }
    };
  }

  function bounds(clouds) {
    return [0, 1].map(axis => {
      let lo = Infinity;
      let hi = -Infinity;
      for (const cloud of clouds) {
        for (const value of cloud[axis]) {
          lo = Math.min(lo, value);
          hi = Math.max(hi, value);
        }
      }
      return [lo - 0.2, hi + 0.2];
    });
  }

  function markers([x, y], color, size = 5, opacity = 0.82, symbol = "circle") {
    return { type: "scatter", x, y, mode: "markers", marker: { color, size, opacity, symbol } };
  }

  function trail(frames, color, opacity) {
    const x = [];
    const y = [];
    for (let point = 0; point < frames[0][0].length; point++) {
      for (const frame of frames) {
        x.push(frame[0][point]);
        y.push(frame[1][point]);
      }
      x.push(null);
      y.push(null);
    }
    return { type: "scatter", x, y, mode: "lines", line: { color, width: 1 }, opacity };
  }

  function timeColour(t) {
    const blue = [39, 101, 163];
    const red = [194, 52, 66];
    return "rgb(" + blue.map((start, i) => Math.round(start + t * (red[i] - start))).join(",") + ")";
  }

  function timedTrails(frames, { last = frames.length - 1, opacity = 0.75 } = {}) {
    const end = frames.length - 1;
    const bands = 10;
    const traces = [];
    function at(index) {
      const lo = Math.floor(index);
      const hi = Math.ceil(index);
      return frames[lo].map((row, axis) =>
        row.map((value, i) => value + (index - lo) * (frames[hi][axis][i] - value)));
    }
    for (let band = 0; band < bands; band++) {
      const left = end * band / bands;
      const right = Math.min(last, end * (band + 1) / bands);
      if (left >= right) break;
      const vertices = [at(left), ...frames.slice(Math.floor(left) + 1, Math.ceil(right)), at(right)];
      traces.push(trail(vertices, timeColour((left + right) / (2 * end)), opacity));
    }
    return traces;
  }

  function metricText(value) {
    return value < 0.00005 && value > 0 ? value.toExponential(2) : value.toFixed(4);
  }

  function initialise(data) {
    const { models } = data;
    const time = explorer.querySelector("input");
    const pairing = explorer.querySelector("#fm-pairing");
    const play = explorer.querySelector("#fm-play");
    const reset = explorer.querySelector("#fm-reset");
    const timeLabel = explorer.querySelector("output");
    const explorerPlots = [...explorer.querySelectorAll(".fm-plot")];
    const explorerBounds = bounds(Object.values(models).flatMap(model =>
      [...model.segments, ...model.integrated]));
    time.max = data.times.length - 1;
    let playback = null;

    function renderExplorer() {
      const frame = Number(time.value);
      const t = data.times[frame].toFixed(2);
      timeLabel.value = t;
      time.setAttribute("aria-valuetext", t);
      const selected = models[pairing.value];
      return Promise.all(["segments", "integrated"].map((mode, i) => {
        const states = selected[mode];
        const traces = [
          trail(states, "#8495a8", 0.2),
          ...timedTrails(states, { last: frame }),
          markers(states[frame], timeColour(data.times[frame]), 7, 0.9)
        ];
        return Plotly.react(explorerPlots[i], traces, layout(explorerBounds), config);
      }));
    }

    function pause() {
      clearTimeout(playback);
      playback = null;
      play.textContent = "Play";
    }

    function scheduleFrame() {
      const timer = setTimeout(async () => {
        time.stepUp();
        await renderExplorer();
        if (playback !== timer) return;
        if (time.value === time.max) pause();
        else scheduleFrame();
      }, 65);
      playback = timer;
    }

    const field = sampler.querySelector("#fm-field");
    const stepSlider = sampler.querySelector("#fm-budget");
    const stepStops = sampler.querySelector(".fm-budget-stops");
    const method = sampler.querySelector("#fm-method");
    const generated = sampler.querySelector("#fm-generated");
    const heldOut = sampler.querySelector("#fm-held-out");
    const generatedTitle = generated.querySelector("p");
    const generatedPlot = generated.querySelector(".fm-plot");
    const heldOutPlot = heldOut.querySelector(".fm-plot");
    const metricsTable = sampler.querySelector("table");
    const solverRows = metricsTable.createTBody();
    const allSolves = Object.values(models).flatMap(model =>
      [model.reference, ...Object.values(model.budgets).flatMap(Object.values)]);
    const pathCount = models.independent.reference.path[0][0].length;
    const firstPoints = cloud => cloud.map(row => row.slice(0, pathCount));
    const starts = firstPoints(data.initial);
    const sampleBounds = bounds([starts, data.held_out,
      ...allSolves.flatMap(solve => [solve.endpoint, ...solve.path])]);
    // The saved runs are indexed by field evaluations. Heun needs two per step.
    const stepChoices = data.budgets.filter(steps => data.budgets.includes(2 * steps));
    stepSlider.max = stepChoices.length - 1;
    stepSlider.value = Math.max(0, stepChoices.indexOf(4));
    for (const steps of stepChoices) {
      const stop = document.createElement("span");
      stop.textContent = steps;
      stepStops.append(stop);
    }

    function renderMetrics(solvers) {
      solverRows.replaceChildren(...solvers.map(([id, label, result, evaluations]) => {
        const row = document.createElement("tr");
        if (id === method.value) row.dataset.selected = "";
        const name = document.createElement("th");
        name.scope = "row";
        name.textContent = label;
        row.append(name);
        row.insertCell().textContent = evaluations;
        row.insertCell().textContent = metricText(result.metric.sw2);
        return row;
      }));
    }

    function renderSampler() {
      const model = models[field.value];
      const stop = stepSlider.valueAsNumber;
      const steps = stepChoices[stop];
      stepSlider.setAttribute("aria-valuetext", steps + (steps === 1 ? " solver step" : " solver steps"));
      stepStops.querySelector(".fm-current-stop")?.classList.remove("fm-current-stop");
      stepStops.children[stop].classList.add("fm-current-stop");
      const solvers = [
        ["euler", "Euler", model.budgets[steps].euler, steps],
        ["heun", "Heun", model.budgets[2 * steps].heun, 2 * steps],
        ["reference", "Tsit5", model.reference, model.reference.nfe]
      ];
      const [ , label, result] = solvers.find(([id]) => id === method.value);
      generatedTitle.textContent = label;
      generatedPlot.setAttribute("aria-label", label + " generated samples and starting points");
      const traces = [markers(result.endpoint, timeColour(1), 4.5, 0.54)];
      traces.push(...timedTrails(result.path));
      traces.push(markers(starts, timeColour(0), 6, 0.95, "circle-open"));
      traces.push(markers(firstPoints(result.endpoint), timeColour(1), 6, 0.95));
      renderMetrics(solvers);
      return Promise.all([
        Plotly.react(generatedPlot, traces, layout(sampleBounds), config),
        Plotly.react(heldOutPlot, [markers(data.held_out, heldColour, 4.5, 0.68)], layout(sampleBounds), config)
      ]);
    }

    time.addEventListener("input", () => {
      pause();
      renderExplorer();
    });
    pairing.addEventListener("change", renderExplorer);
    play.addEventListener("click", () => {
      if (playback !== null) return pause();
      if (time.value === time.max) {
        time.value = time.min;
        renderExplorer();
      }
      play.textContent = "Pause";
      scheduleFrame();
    });
    reset.addEventListener("click", () => {
      pause();
      time.value = time.min;
      renderExplorer();
    });
    for (const control of [field, method]) control.addEventListener("change", renderSampler);
    stepSlider.addEventListener("input", renderSampler);
    return Promise.all([renderExplorer(), renderSampler()]).then(() => {
      play.disabled = false;
      reset.disabled = false;
    });
  }

  notebook.addEventListener("click", async event => {
    if (event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return;
    event.preventDefault();
    try {
      const response = await fetch(notebook.href);
      if (!response.ok) throw new Error("HTTP " + response.status);
      // Give the download a binary MIME type even when the server serves .jl as text.
      const file = new Blob([await response.arrayBuffer()], { type: "application/octet-stream" });
      const url = URL.createObjectURL(file);
      const download = document.createElement("a");
      download.href = url;
      download.download = notebook.download;
      download.click();
      setTimeout(() => URL.revokeObjectURL(url), 60_000);
    } catch {
      location.href = notebook.href;
    }
  });

  fetch(new URL("results.json", script.src))
    .then(response => {
      if (!response.ok) throw new Error("HTTP " + response.status);
      return response.json();
    })
    .then(initialise)
    .then(() => {
      for (const demo of [explorer, sampler]) demo.querySelector(".fm-status").hidden = true;
    })
    .catch(error => {
      for (const demo of [explorer, sampler]) {
        demo.querySelector(".fm-status").textContent =
          "The plot could not load. You can rerun the experiment with the Pluto notebook linked at the end of the post.";
      }
      console.error(error);
    });
})();
