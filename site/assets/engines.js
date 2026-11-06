// site/assets/engines.js: the site's theme list and one way to run any of them.
//
// Three engines share create(canvas, opts) -> { name, frame(timeSec, dtSec), resize(w, h),
// stats(), destroy() } (web/README.md): Metal themes translated to WGSL (web/host), Cygnus A on
// WebGPU with its theme in wasm (web/cygnus), and Zig themes as SIMD128 wasm on Workers
// (web/wasm). mount() gives each a fresh canvas (a canvas keeps its first context type), sizes
// it to device pixels, drives it from requestAnimationFrame and normalises the readout.

const WEB = new URL('../web/', import.meta.url);

// One line each, from the README's theme list. `kind`: 'cygnus' | 'wgsl' | 'wasm'.
export const THEMES = [
  { id: 'Cygnus_A', label: 'Cygnus A', kind: 'cygnus', src: 'themes/Cygnus_A.zig',
    line: 'The quasar in Cygnus A: a spinning black hole and its disk, every pixel traced along exact Kerr light paths.' },
  { id: 'Night_Tide', label: 'Night Tide', kind: 'wgsl', src: 'themes/Night_Tide.metal',
    line: 'A night on the coast; the flashes in the surf follow published dinoflagellate research.' },
  { id: 'Lizard_Island', label: 'Lizard Island', kind: 'wgsl', src: 'themes/Lizard_Island.metal',
    line: 'A diver’s drift over a real Great Barrier Reef lagoon at metre scale.' },
  { id: 'Orion_Nebula', label: 'Orion Nebula', kind: 'wgsl', src: 'themes/Orion_Nebula.metal',
    line: 'The heart of M42, built from telescope measurements; as the view swings round, its 3D shape appears.' },
  { id: 'Ebru_Studio', label: 'Ebru Studio', kind: 'wgsl', src: 'themes/Ebru_Studio.metal',
    line: 'A Turkish marbling bath worked by a restless hand under studio lights.' },
  { id: 'Roulette_Chrome', label: 'Roulette Chrome', kind: 'wgsl', src: 'themes/Roulette_Chrome.metal',
    line: 'A single-zero wheel from above; the ball’s laps, bounces and pocket come from the physics.' },
  { id: 'Aventurine_Horoscope', label: 'Aventurine Horoscope', kind: 'wgsl', src: 'themes/Aventurine_Horoscope.metal',
    line: 'Today’s real sky as Western astrology reads it: planets in signs, retrogrades, aspects, the Moon’s phase.' },
  { id: 'Phosphor_Terminal', label: 'Phosphor Terminal', kind: 'wgsl', src: 'themes/Phosphor_Terminal.metal',
    line: 'Vital signs on a green-phosphor VT320 terminal. In the app they are your Mac’s; here, what a browser knows about itself.' },
  { id: 'Tutorial_Reef', label: 'Tutorial Reef', kind: 'wgsl', src: 'themes/Tutorial_Reef.metal',
    line: 'The second tutorial: a reaction-diffusion reef that remembers between frames.' },
  { id: 'Tutorial_Tides', label: 'Tutorial Tides', kind: 'wgsl', src: 'themes/Tutorial_Tides.metal',
    line: 'The first tutorial: an aurora over a night sea in five small steps.' },
  { id: 'Tutorial_Tides_wasm', label: 'Tutorial Tides', tag: 'Zig → wasm', kind: 'wasm', build: 'Tutorial_Tides', src: 'themes/cpu/Tutorial_Tides.zig',
    line: 'The same aurora from its Zig CPU port, as SIMD128 wasm on every core.' },
  { id: 'Cygnus_A_wasm', label: 'Cygnus A', tag: 'CPU · wasm', kind: 'wasm', build: 'Cygnus_A', src: 'themes/Cygnus_A.zig', fallbackOnly: true,
    line: 'Cygnus A’s Zig theme as wasm on one CPU thread (the app draws it on the GPU).' },
];

export const byId = (id) => THEMES.find((t) => t.id === id);

let gpuProbe = null;
/// Whether the WebGPU engines can run here: { ok, why }.
export function probeWebGPU() {
  if (!gpuProbe) {
    gpuProbe = (async () => {
      if (!navigator.gpu) return { ok: false, why: 'this browser has no WebGPU (navigator.gpu is missing)' };
      try {
        const a = await navigator.gpu.requestAdapter({ powerPreference: 'high-performance' });
        if (!a) return { ok: false, why: 'WebGPU is present but found no GPU adapter' };
        return { ok: true, adapter: a };
      } catch (e) {
        return { ok: false, why: `WebGPU: ${e.message ?? e}` };
      }
    })();
  }
  return gpuProbe;
}

const median = (a) => { if (!a.length) return NaN; const s = [...a].sort((x, y) => x - y); return s[s.length >> 1]; };

/// Run theme `t` full-size in `stage` (an element; the canvas fills it). Returns a handle:
/// { theme, engine, readout(), stop() }. opts.scale: device pixels per CSS pixel (default
/// devicePixelRatio, i.e. native resolution); opts.onFirstFrame(ms since mount).
export async function mount(stage, t, opts = {}) {
  const canvas = document.createElement('canvas');
  canvas.setAttribute('aria-label', `${t.label}${t.tag ? ` (${t.tag})` : ''}, running live`);
  canvas.setAttribute('role', 'img');
  stage.querySelector('canvas')?.remove();
  stage.prepend(canvas);
  const t0 = performance.now();
  const ratio = () => opts.scale ?? (globalThis.devicePixelRatio || 1);
  const px = () => {
    const r = canvas.getBoundingClientRect();
    return [Math.max(1, Math.round(r.width * ratio())), Math.max(1, Math.round(r.height * ratio()))];
  };
  let engine, kind = t.kind, label, sizeObs = null;
  try {
    if (t.kind === 'cygnus') {
      const { create } = await import(new URL('cygnus/cygnus.js', WEB));
      [canvas.width, canvas.height] = px();
      engine = await create(canvas, {});
      label = 'WebGPU (WGSL) + wasm';
      sizeObs = new ResizeObserver(() => { const [w, h] = px(); if (w !== canvas.width || h !== canvas.height) engine.resize(w, h); });
      sizeObs.observe(canvas);
    } else if (t.kind === 'wgsl' || t.kind === 'wgsl-source') {
      const { create } = await import(new URL('host/argus_gpu.js', WEB));
      engine = await create(canvas, t.source ? { theme: t.label, source: t.source, pixelRatio: ratio() } : { theme: t.id, pixelRatio: ratio() });
      kind = 'wgsl';
      label = 'WebGPU (WGSL)';
    } else {
      const { create } = await import(new URL('wasm/host.js', WEB));
      const [w, h] = px();
      // Zig themes draw every pixel on the CPU: past the harness's 1920x1200 (or opts.maxPixels,
      // for a slower build) they render at that many pixels and the blit scales them up (shown
      // in the readout).
      const renderScale = Math.min(1, Math.sqrt((opts.maxPixels ?? 1920 * 1200) / (w * h)));
      canvas.width = w; canvas.height = h;
      engine = await create(canvas, { theme: t.build, base: new URL('wasm/build/', WEB), renderScale, module: opts.module });
      engine.resize(w, h);
      label = opts.label ?? 'wasm SIMD128 (CPU)';
      sizeObs = new ResizeObserver(() => { const [nw, nh] = px(); if (nw !== canvas.width || nh !== canvas.height) engine.resize(nw, nh); });
      sizeObs.observe(canvas);
    }
  } catch (e) {
    canvas.remove();
    throw e;
  }

  const intervals = [];
  let raf = 0, last = null, stopped = false, firstMs = null, paused = false;
  const tick = (now) => {
    if (stopped) return;
    if (paused) { last = null; raf = requestAnimationFrame(tick); return; }
    const dt = last === null ? 1 / 30 : Math.min(0.25, (now - last) / 1000);
    if (last !== null) { intervals.push(now - last); if (intervals.length > 120) intervals.shift(); }
    last = now;
    try { engine.frame(now / 1000, dt); } catch (e) { stopped = true; opts.onError?.(e); return; }
    if (firstMs === null) {
      // The frame is presented by the next animation frame.
      requestAnimationFrame(() => { firstMs = performance.now() - t0; opts.onFirstFrame?.(firstMs); });
      firstMs = -1;
    }
    raf = requestAnimationFrame(tick);
  };
  raf = requestAnimationFrame(tick);

  return {
    theme: t,
    engine,
    canvas,
    readout() {
      const s = engine.stats() || {};
      const iv = median(intervals);
      const r = {
        engine: label, kind,
        width: s.width ?? s.renderW ?? canvas.width, height: s.height ?? s.renderH ?? canvas.height,
        canvasW: canvas.width, canvasH: canvas.height,
        hz: Number.isFinite(iv) ? 1000 / iv : NaN, frameMs: iv,
        gpuMs: s.gpuMs, cpuMs: s.cpuMs, blitMs: s.blitMs,
        wasmKB: s.wasmFileKB ?? s.wasmKB, threads: s.threads, variant: s.variant, isolated: globalThis.crossOriginIsolated === true,
        firstMs: firstMs > 0 ? firstMs : null, error: s.error,
      };
      if (kind === 'cygnus') { r.traceMs = s.traceMs; r.rowsDone = s.rowsDone; r.traceH = s.height; r.wasmKB = s.wasmFileKB; r.threads = 1; }
      if (kind === 'wgsl') { r.adapter = engine.info?.adapter; r.statsSources = engine.statsSources?.(); }
      return r;
    },
    // Off screen or in a hidden tab: draw nothing (the simulation resumes where it was).
    setPaused(p) { paused = !!p; },
    stop() {
      stopped = true;
      cancelAnimationFrame(raf);
      sizeObs?.disconnect();
      try { engine.destroy(); } catch { /* already gone */ }
    },
  };
}
