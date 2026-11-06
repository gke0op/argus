// web/host/argus_gpu.js — Argus's browser runtime for Metal themes, on WebGPU.
//
// A theme is web/themes/<Name>.wgsl: a one-to-one WGSL translation of themes/<Name>.metal,
// with the same `// @argus` header. This module compiles web/prelude.wgsl + the theme, runs
// the directives (state textures, steps, .bin data, stats), and draws into a canvas at device
// pixels on the browser's vsync, with the frame semantics of src/gpu/metal_theme.zig.
//
// The engine interface (shared with the other web engines; web/README.md):
//   const e = await create(canvas, opts)
//   e.name; e.frame(timeSec, dtSec); e.resize(w, h); e.stats() -> {gpuMs?, cpuMs?, wasmKB?}; e.destroy()

import { parseDirectives, dataBytes } from './directives.js';
import { FrameState, Pacer, FRAME_BYTES, STEP_DT, parseIsoUtc } from './frame.js';
import { synthetic as syntheticStats, pack as packStats, BrowserStats, STATS_BYTES } from './stats.js';

const HERE = new URL('.', import.meta.url);
export const PRELUDE_URL = new URL('../prelude.wgsl', HERE);
export const THEMES_URL = new URL('../themes/', HERE);
export const HARNESS_SEED = 0x5eed;
export const HARNESS_DATE = '2026-10-20T12:00:00Z';

let devicePromise = null;
let preludePromise = null;

// One device per page, with the optional features the runtime uses when present.
export async function getDevice() {
  if (!devicePromise) {
    devicePromise = (async () => {
      if (!navigator.gpu) throw new Error('WebGPU is not available in this browser (navigator.gpu is missing)');
      const adapter = await navigator.gpu.requestAdapter({ powerPreference: 'high-performance' });
      if (!adapter) throw new Error('WebGPU: no GPU adapter');
      const want = ['timestamp-query', 'float32-filterable', 'bgra8unorm-storage'];
      const requiredFeatures = want.filter((x) => adapter.features.has(x));
      const L = adapter.limits;
      const device = await adapter.requestDevice({
        requiredFeatures,
        requiredLimits: {
          maxComputeWorkgroupStorageSize: L.maxComputeWorkgroupStorageSize,
          maxComputeInvocationsPerWorkgroup: L.maxComputeInvocationsPerWorkgroup,
          maxComputeWorkgroupSizeX: L.maxComputeWorkgroupSizeX,
          maxComputeWorkgroupSizeY: L.maxComputeWorkgroupSizeY,
          maxStorageBufferBindingSize: L.maxStorageBufferBindingSize,
          maxBufferSize: L.maxBufferSize,
          maxTextureDimension2D: L.maxTextureDimension2D,
        },
      });
      device.lost.then((info) => { console.error(`WebGPU device lost: ${info.reason} ${info.message}`); devicePromise = null; });
      const ai = adapter.info ?? {};
      device.argusAdapter = `${ai.vendor ?? ''} ${ai.architecture ?? ''} ${ai.description ?? ''}`.trim();
      return device;
    })();
  }
  return devicePromise;
}

async function getPrelude() {
  if (!preludePromise) {
    preludePromise = fetch(PRELUDE_URL).then((r) => {
      if (!r.ok) throw new Error(`prelude: HTTP ${r.status} for ${PRELUDE_URL}`);
      return r.text();
    });
  }
  return preludePromise;
}

function themeUrl(theme) {
  if (/^[A-Za-z0-9_]+$/.test(theme)) return new URL(`${theme}.wgsl`, THEMES_URL);
  return new URL(theme, location.href);
}

// The workgroup size an entry point declares: `@workgroup_size(X[, Y[, Z]]) fn name(`, with
// literal or `const` sizes.
function workgroupSize(code, name) {
  const at = code.search(new RegExp(`\\bfn\\s+${name}\\s*\\(`));
  if (at < 0) return null;
  const head = code.slice(Math.max(0, code.lastIndexOf('}', at)), at);
  const m = /@workgroup_size\s*\(([^)]*)\)/.exec(head);
  if (!m) throw new Error(`${name}: no @workgroup_size`);
  const val = (tok) => {
    tok = tok.trim();
    if (/^\d+u?$/.test(tok)) return parseInt(tok, 10);
    const c = new RegExp(`const\\s+${tok}\\s*(?::\\s*\\w+)?\\s*=\\s*(\\d+)u?\\s*;`).exec(code);
    if (!c) throw new Error(`${name}: can't resolve workgroup size '${tok}'`);
    return parseInt(c[1], 10);
  };
  const parts = m[1].split(',').filter((t) => t.trim().length > 0).map(val);
  return [parts[0], parts[1] ?? 1];
}

// WGSL without its comments (line and block; block comments nest in WGSL), for the searches below.
function stripComments(code) {
  let out = '', i = 0, depth = 0;
  while (i < code.length) {
    if (depth === 0 && code.startsWith('//', i)) { const e = code.indexOf('\n', i); i = e < 0 ? code.length : e; continue; }
    if (code.startsWith('/*', i)) { depth++; i += 2; continue; }
    if (depth > 0 && code.startsWith('*/', i)) { depth--; i += 2; continue; }
    if (depth === 0) out += code[i];
    i++;
  }
  return out;
}

const hasEntry = (code, name) => new RegExp(`@compute[^;{}]*\\bfn\\s+${name}\\s*\\(`).test(code);

function formatCompileMessages(msgs, label, preludeLines) {
  return msgs.map((m) => {
    const line = m.lineNum - preludeLines;
    const where = line >= 1 ? `${label}:${line}:${m.linePos}` : `prelude.wgsl:${m.lineNum}:${m.linePos}`;
    return `${where}: ${m.type}: ${m.message}`;
  }).join('\n');
}

/**
 * Creates a Metal-theme engine.
 *   canvas    an HTMLCanvasElement / OffscreenCanvas to present to, or null with opts.offscreen
 *   opts.theme      'Tutorial_Tides' (looked up in web/themes/) or a URL to a .wgsl file
 *   opts.source     WGSL source instead of fetching (opts.dataBase: where its .bin lives)
 *   opts.seed       f.seed (default: random per load, as the app; the harness uses 0x5EED)
 *   opts.date       'system' (default) or 'YYYY-MM-DDTHH:MM:SSZ': pinned, advancing with the clock
 *   opts.utcOffset  f.utc_offset_s with a pinned date (default 0)
 *   opts.stats      'browser' (default: what the browser can read, the rest synthetic) or
 *                   'synthetic' (the harness feed: a new sample every 30 ticks)
 *   opts.pixelRatio canvas pixels per CSS pixel (default devicePixelRatio)
 *   opts.autoResize follow the canvas's displayed size (default true for a DOM canvas)
 *   opts.offscreen  { width, height, format } render into a texture instead (the verify page)
 *   opts.device     a GPUDevice to use (default: the shared one)
 */
export async function create(canvas, opts = {}) {
  const device = opts.device ?? await getDevice();
  const label = opts.theme ? `${String(opts.theme).replace(/^.*\//, '').replace(/\.wgsl$/, '')}.wgsl` : 'theme.wgsl';
  const name = label.replace(/\.wgsl$/, '');

  // ---- source, directives, data ------------------------------------------------------------
  let src = opts.source;
  let srcUrl = null;
  if (src === undefined) {
    srcUrl = themeUrl(opts.theme);
    const r = await fetch(srcUrl);
    if (!r.ok) throw new Error(`${label}: HTTP ${r.status} for ${srcUrl}`);
    src = await r.text();
  }
  const dir = parseDirectives(src);
  const prelude = await getPrelude();

  const offscreen = opts.offscreen ?? null;
  const ctx = offscreen ? null : canvas.getContext('webgpu');
  if (!offscreen && !ctx) throw new Error('canvas.getContext("webgpu") returned null');
  const dpr = opts.pixelRatio ?? (globalThis.devicePixelRatio || 1);

  let outW, outH;
  if (offscreen) { outW = offscreen.width; outH = offscreen.height; }
  else if (opts.width && opts.height) { outW = opts.width; outH = opts.height; }
  else {
    outW = Math.max(1, Math.round((canvas.clientWidth || canvas.width) * dpr));
    outH = Math.max(1, Math.round((canvas.clientHeight || canvas.height) * dpr));
  }
  const maxSide = device.limits.maxTextureDimension2D;
  outW = Math.min(outW, maxSide); outH = Math.min(outH, maxSide);

  // The output format: write straight into the canvas's own texture.
  let outFormat;
  if (offscreen) outFormat = offscreen.format ?? 'rgba32float';
  else {
    outFormat = navigator.gpu.getPreferredCanvasFormat() === 'bgra8unorm' && device.features.has('bgra8unorm-storage')
      ? 'bgra8unorm' : 'rgba8unorm';
    canvas.width = outW; canvas.height = outH;
    ctx.configure({ device, format: outFormat, usage: GPUTextureUsage.STORAGE_BINDING, alphaMode: 'opaque' });
  }

  const bare = stripComments(src);
  const hasInit = hasEntry(bare, 'argus_init');
  const hasStep = hasEntry(bare, 'argus_step');
  if (!hasEntry(bare, 'argus_draw')) throw new Error(`no \`@compute ... fn argus_draw(...)\` in ${label}`);
  let stateful = hasInit || hasStep || dir.stateW !== 0;
  const stateFollowsOutput = stateful && dir.stateW === 0;
  if (stateFollowsOutput) { dir.stateW = outW; dir.stateH = outH; }
  const stateFormat = dir.stateF32 ? 'rgba32float' : 'rgba16float';
  const stateFilterable = !dir.stateF32 || device.features.has('float32-filterable');

  let dataBuf = null;
  if (dir.dataName) {
    if (!hasInit) throw new Error(`${label}: data file ${dir.dataName} needs ${dataBytes(dir)} bytes and an argus_init`);
    const base = opts.dataBase ? new URL(opts.dataBase, location.href) : (srcUrl ?? THEMES_URL);
    const durl = new URL(dir.dataName, base);
    const r = await fetch(durl);
    if (!r.ok) throw new Error(`${label}: data file ${dir.dataName} (${dir.dataW}x${dir.dataH}) missing: HTTP ${r.status}`);
    dataBuf = await r.arrayBuffer();
    if (dataBuf.byteLength !== dataBytes(dir)) {
      throw new Error(`${label}: data file ${dir.dataName} is ${dataBuf.byteLength} bytes, needs ${dataBytes(dir)}`);
    }
  }

  // ---- compile -----------------------------------------------------------------------------
  const head = prelude.replaceAll('ARGUS_STATE_FORMAT', stateFormat).replaceAll('ARGUS_OUT_FORMAT', outFormat);
  const preludeLines = head.split('\n').length; // the theme starts on the line after
  const code = `${head}\n${src}`;
  device.pushErrorScope('validation');
  const module = device.createShaderModule({ label, code });
  const info = await module.getCompilationInfo();
  const scopeErr = await device.popErrorScope();
  const errors = info.messages.filter((m) => m.type === 'error');
  if (errors.length) throw new Error(formatCompileMessages(errors, label, preludeLines));
  if (scopeErr) throw new Error(`${label}: ${scopeErr.message}`);
  const warnings = info.messages.filter((m) => m.type !== 'error');
  if (warnings.length) console.warn(formatCompileMessages(warnings, label, preludeLines));

  const C = GPUShaderStage.COMPUTE;
  const samplerEntries = [5, 6, 7, 8, 9].map((b) => ({ binding: b, visibility: C, sampler: { type: 'filtering' } }));
  const frameEntry = { binding: 0, visibility: C, buffer: { type: 'uniform', minBindingSize: 48 } };
  const statsEntry = dir.stats ? [{ binding: 1, visibility: C, buffer: { type: 'read-only-storage', minBindingSize: STATS_BYTES } }] : [];
  const stateRead = { binding: 2, visibility: C, texture: { sampleType: stateFilterable ? 'float' : 'unfilterable-float' } };
  const stateWrite = { binding: 3, visibility: C, storageTexture: { access: 'write-only', format: stateFormat } };
  const dataEntry = dataBuf ? [{ binding: 4, visibility: C, texture: { sampleType: 'float' } }] : [];

  const L = {
    init: device.createBindGroupLayout({ label: `${name} init`, entries: [frameEntry, ...statsEntry, stateWrite, ...dataEntry, ...samplerEntries] }),
    step: device.createBindGroupLayout({ label: `${name} step`, entries: [frameEntry, ...statsEntry, stateRead, stateWrite, ...samplerEntries] }),
    draw: device.createBindGroupLayout({ label: `${name} draw`, entries: [frameEntry, ...statsEntry, ...(stateful ? [stateRead] : []), ...samplerEntries] }),
    out: device.createBindGroupLayout({ label: `${name} out`, entries: [{ binding: 0, visibility: C, storageTexture: { access: 'write-only', format: outFormat } }] }),
  };

  const bareCode = stripComments(code);
  async function pipe(entry, layouts) {
    const wg = workgroupSize(bareCode, entry);
    try {
      const p = await device.createComputePipelineAsync({
        label: `${name} ${entry}`,
        layout: device.createPipelineLayout({ bindGroupLayouts: layouts }),
        compute: { module, entryPoint: entry },
      });
      return { p, wg };
    } catch (e) {
      throw new Error(`${label}: ${entry}: ${e.message}`);
    }
  }
  const [drawP, initP, stepP, clearP] = await Promise.all([
    pipe('argus_draw', [L.draw, L.out]),
    hasInit ? pipe('argus_init', [L.init]) : null,
    hasStep ? pipe('argus_step', [L.step]) : null,
    stateful && !hasInit ? pipe('argus_clear_state', [L.init]) : null,
  ]);

  // ---- resources ---------------------------------------------------------------------------
  const frameBufStep = device.createBuffer({ label: 'ArgusFrame (init/step)', size: 48, usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST });
  const frameBufDraw = device.createBuffer({ label: 'ArgusFrame (draw)', size: 48, usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST });
  const frameBytes = new ArrayBuffer(48);
  const frameView = new DataView(frameBytes);
  const statsBuf = dir.stats ? device.createBuffer({ label: 'ArgusStats', size: 432, usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST }) : null;
  const statsBytes = new ArrayBuffer(432);
  const statsView = new DataView(statsBytes);

  const mk = (o) => device.createSampler(o);
  const samplers = [
    mk({ magFilter: 'linear', minFilter: 'linear' }),
    mk({ magFilter: 'linear', minFilter: 'linear', addressModeU: 'repeat', addressModeV: 'repeat' }),
    mk({ magFilter: 'linear', minFilter: 'linear', addressModeU: 'repeat' }),
    mk({ magFilter: 'linear', minFilter: 'linear', addressModeV: 'repeat' }),
    mk({ magFilter: 'nearest', minFilter: 'nearest' }),
  ];
  const samplerBinds = samplers.map((sm, i) => ({ binding: 5 + i, resource: sm }));
  const frameBind = (buf) => ({ binding: 0, resource: { buffer: buf } });
  const statsBind = statsBuf ? [{ binding: 1, resource: { buffer: statsBuf, size: STATS_BYTES } }] : [];

  let dataTex = null;
  if (dataBuf) {
    dataTex = device.createTexture({ label: dir.dataName, size: [dir.dataW, dir.dataH], format: dir.dataF16 ? 'rgba16float' : 'rgba8unorm', usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_DST });
    device.queue.writeTexture({ texture: dataTex }, dataBuf, { bytesPerRow: dir.dataW * (dir.dataF16 ? 8 : 4) }, [dir.dataW, dir.dataH]);
    dataBuf = null;
  }

  let tex = [null, null];
  let groups = null;
  let cur = 0;
  let needsInit = true;
  function makeState() {
    for (const t of tex) t?.destroy();
    tex = [0, 1].map((i) => device.createTexture({
      label: `${name} state ${i}`, size: [dir.stateW, dir.stateH], format: stateFormat,
      usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.STORAGE_BINDING,
    }));
    const v = tex.map((t) => t.createView());
    groups = {
      init: [0, 1].map((c) => device.createBindGroup({ layout: L.init, entries: [frameBind(frameBufStep), ...statsBind, { binding: 3, resource: v[c] }, ...(dataTex ? [{ binding: 4, resource: dataTex.createView() }] : []), ...samplerBinds] })),
      step: [0, 1].map((c) => device.createBindGroup({ layout: L.step, entries: [frameBind(frameBufStep), ...statsBind, { binding: 2, resource: v[c] }, { binding: 3, resource: v[c ^ 1] }, ...samplerBinds] })),
      draw: [0, 1].map((c) => device.createBindGroup({ layout: L.draw, entries: [frameBind(frameBufDraw), ...statsBind, { binding: 2, resource: v[c] }, ...samplerBinds] })),
    };
    cur = 0;
    needsInit = true;
  }
  if (stateful) makeState();
  else groups = { draw: [device.createBindGroup({ layout: L.draw, entries: [frameBind(frameBufDraw), ...statsBind, ...samplerBinds] })] };

  let offTex = null;
  let offGroup = null;
  function makeOffscreen() {
    offTex?.destroy();
    offTex = device.createTexture({ label: `${name} out`, size: [outW, outH], format: outFormat, usage: GPUTextureUsage.STORAGE_BINDING | GPUTextureUsage.COPY_SRC });
    offGroup = device.createBindGroup({ layout: L.out, entries: [{ binding: 0, resource: offTex.createView() }] });
  }
  if (offscreen) makeOffscreen();

  // ---- frame state, stats, timing -----------------------------------------------------------
  let seed = opts.seed;
  if (seed === undefined || seed === null) seed = crypto.getRandomValues(new Uint32Array(1))[0];
  const wall = (!opts.date || opts.date === 'system') ? { kind: 'system' } : { kind: 'fixed', unixS: parseIsoUtc(opts.date), utcOffsetS: opts.utcOffset ?? 0 };
  const fr = new FrameState({ width: outW, height: outH, stateW: stateful ? dir.stateW : 0, stateH: stateful ? dir.stateH : 0, seed, wall });
  const pacer = new Pacer();
  const browserStats = dir.stats && opts.stats !== 'synthetic' ? new BrowserStats() : null;

  const timing = { gpuMs: null, cpuMs: null, gpuHist: [], cpuHist: [] };
  let ts = null;
  if (device.features.has('timestamp-query')) {
    ts = {
      set: device.createQuerySet({ type: 'timestamp', count: 2 }),
      resolve: device.createBuffer({ size: 16, usage: GPUBufferUsage.QUERY_RESOLVE | GPUBufferUsage.COPY_SRC }),
      free: [0, 1, 2, 3].map(() => device.createBuffer({ size: 16, usage: GPUBufferUsage.MAP_READ | GPUBufferUsage.COPY_DST })),
    };
  }
  const pushHist = (h, v) => { h.push(v); if (h.length > 240) h.shift(); };
  let destroyed = false;

  function dispatch(pass, pp, w, h, ...bgs) {
    pass.setPipeline(pp.p);
    bgs.forEach((g, i) => pass.setBindGroup(i, g));
    pass.dispatchWorkgroups(Math.ceil(w / pp.wg[0]), Math.ceil(h / pp.wg[1]));
  }

  // metal_theme.zig Theme.encodeTimes: f.time advances by clockDt; argus_step runs with
  // f.dt = stepDt, or is skipped when stepDt is null (a draw-only frame between ticks).
  function encodeTimes(clockDt, stepDt) {
    if (destroyed) return;
    const t0 = performance.now();
    fr.forEncode(stepDt !== null);
    fr.fillWall();
    fr.pack(frameView, stepDt ?? clockDt);
    device.queue.writeBuffer(frameBufStep, 0, frameBytes);
    fr.pack(frameView, Math.fround(clockDt));
    device.queue.writeBuffer(frameBufDraw, 0, frameBytes);
    if (statsBuf) {
      const st = browserStats ? browserStats.sample(performance.now()) : syntheticStats(Math.floor(fr.frame / 30) + 1);
      packStats(st, statsView);
      device.queue.writeBuffer(statsBuf, 0, statsBytes);
    }

    const out = offscreen ? offGroup : device.createBindGroup({ layout: L.out, entries: [{ binding: 0, resource: ctx.getCurrentTexture().createView() }] });
    const enc = device.createCommandEncoder();
    const pass = enc.beginComputePass(ts ? { timestampWrites: { querySet: ts.set, beginningOfPassWriteIndex: 0, endOfPassWriteIndex: 1 } } : undefined);
    if (stateful) {
      if (needsInit) {
        needsInit = false;
        dispatch(pass, initP ?? clearP, dir.stateW, dir.stateH, groups.init[cur]);
      }
      if (stepP && stepDt !== null) {
        for (let i = 0; i < dir.steps; i++) {
          dispatch(pass, stepP, dir.stateW, dir.stateH, groups.step[cur]);
          cur ^= 1;
        }
      }
      dispatch(pass, drawP, outW, outH, groups.draw[cur], out);
    } else {
      dispatch(pass, drawP, outW, outH, groups.draw[0], out);
    }
    pass.end();
    let rb = null;
    if (ts && ts.free.length) {
      rb = ts.free.pop();
      enc.resolveQuerySet(ts.set, 0, 2, ts.resolve, 0);
      enc.copyBufferToBuffer(ts.resolve, 0, rb, 0, 16);
    }
    device.queue.submit([enc.finish()]);
    if (rb) {
      rb.mapAsync(GPUMapMode.READ).then(() => {
        const q = new BigInt64Array(rb.getMappedRange());
        const ms = Number(q[1] - q[0]) / 1e6;
        rb.unmap();
        if (destroyed) { rb.destroy(); return; }
        ts.free.push(rb);
        if (ms > 0 && ms < 1000) { pushHist(timing.gpuHist, ms); timing.gpuMs = ms; if (browserStats) browserStats.gpuMs = ms; }
      }, () => {});
    }
    fr.advanceClock(clockDt);
    const cpu = performance.now() - t0;
    pushHist(timing.cpuHist, cpu);
    timing.cpuMs = cpu;
  }

  const median = (h) => { if (!h.length) return undefined; const a = [...h].sort((x, y) => x - y); return a[a.length >> 1]; };

  let observer = null;
  const engine = {
    name,
    kind: 'metal-wgsl',
    info: { adapter: device.argusAdapter, outFormat, stateFormat: stateful ? stateFormat : null, directives: dir, seed: fr.seed, stateFilterable },
    // Draw one display frame. dtSec is the time since the previous frame (the browser's vsync
    // interval); timeSec is the caller's clock, unused: f.time is the theme's own wrapped clock.
    frame(timeSec, dtSec) {
      const { clockDt, stepDt } = pacer.advance(dtSec);
      if (browserStats) browserStats.frameMs = dtSec * 1000;
      encodeTimes(clockDt, stepDt);
    },
    // The harness's fixed step: clock and state step both advance by dt (1/30 s), every call.
    harnessFrame(dt = STEP_DT) { encodeTimes(Math.fround(dt), Math.fround(dt)); },
    encodeTimes,
    resize(w, h) {
      w = Math.max(1, Math.min(Math.round(w), maxSide));
      h = Math.max(1, Math.min(Math.round(h), maxSide));
      if (w === outW && h === outH) return;
      outW = w; outH = h;
      fr.width = w; fr.height = h;
      if (offscreen) makeOffscreen();
      else { canvas.width = w; canvas.height = h; }
      if (stateFollowsOutput) { dir.stateW = w; dir.stateH = h; fr.stateW = w; fr.stateH = h; makeState(); }
    },
    stats() {
      return { gpuMs: median(timing.gpuHist), cpuMs: median(timing.cpuHist), width: outW, height: outH, frame: fr.frame, time: fr.time };
    },
    gpuSamples() { return [...timing.gpuHist]; },
    statsSources() { return browserStats ? browserStats.sources : (dir.stats ? { all: 'synthetic (the Metal harness feed)' } : null); },
    // The verify page: the output texture's texels (rgba32float -> Float32Array, else Uint8Array).
    async readback() {
      if (!offscreen) throw new Error('readback needs opts.offscreen');
      const bpp = { rgba32float: 16, rgba16float: 8 }[outFormat] ?? 4;
      const bpr = Math.ceil((outW * bpp) / 256) * 256;
      const buf = device.createBuffer({ size: bpr * outH, usage: GPUBufferUsage.MAP_READ | GPUBufferUsage.COPY_DST });
      const enc = device.createCommandEncoder();
      enc.copyTextureToBuffer({ texture: offTex }, { buffer: buf, bytesPerRow: bpr }, [outW, outH]);
      device.queue.submit([enc.finish()]);
      await buf.mapAsync(GPUMapMode.READ);
      const src8 = new Uint8Array(buf.getMappedRange());
      const dst = new Uint8Array(outW * outH * bpp);
      for (let y = 0; y < outH; y++) dst.set(src8.subarray(y * bpr, y * bpr + outW * bpp), y * outW * bpp);
      buf.unmap(); buf.destroy();
      return bpp === 16 ? new Float32Array(dst.buffer) : dst;
    },
    destroy() {
      if (destroyed) return;
      destroyed = true;
      observer?.disconnect();
      browserStats?.destroy();
      for (const t of tex) t?.destroy();
      offTex?.destroy(); dataTex?.destroy();
      frameBufStep.destroy(); frameBufDraw.destroy(); statsBuf?.destroy();
      if (ts) { ts.set.destroy(); ts.resolve.destroy(); for (const b of ts.free) b.destroy(); }
      if (ctx) ctx.unconfigure();
    },
  };

  // Follow the canvas's displayed size in device pixels.
  if (!offscreen && opts.autoResize !== false && typeof ResizeObserver !== 'undefined' && canvas instanceof HTMLCanvasElement) {
    observer = new ResizeObserver((entries) => {
      const e = entries[entries.length - 1];
      const box = e.devicePixelContentBoxSize?.[0];
      const w = box ? box.inlineSize : Math.round(e.contentRect.width * dpr);
      const h = box ? box.blockSize : Math.round(e.contentRect.height * dpr);
      if (w > 0 && h > 0) engine.resize(w, h);
    });
    try { observer.observe(canvas, { box: 'device-pixel-content-box' }); } catch { observer.observe(canvas); }
  }
  return engine;
}

// A requestAnimationFrame loop at the display's refresh rate for any engine with this interface.
// Returns stop().
export function runLoop(engine, onFrame) {
  let last = null;
  let raf = 0;
  let stopped = false;
  const tick = (now) => {
    if (stopped) return;
    const dt = last === null ? 1 / 30 : (now - last) / 1000;
    last = now;
    engine.frame(now / 1000, dt);
    onFrame?.(now, dt);
    raf = requestAnimationFrame(tick);
  };
  raf = requestAnimationFrame(tick);
  return () => { stopped = true; cancelAnimationFrame(raf); };
}
