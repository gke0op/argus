// web/wasm/host.js — an Argus Zig theme, compiled to wasm, live on a canvas.
//
//   import { create } from './host.js';
//   const eng = await create(canvas, { theme: 'Tutorial_Tides' });
//   eng.resize(canvas.clientWidth * devicePixelRatio, canvas.clientHeight * devicePixelRatio);
//   requestAnimationFrame(function loop(t) { eng.frame(t / 1000, dt); requestAnimationFrame(loop); });
//
// The engine interface shared with the WebGPU engines (web/host, web/cygnus):
//   create(canvas, opts) -> { name, frame(timeSec, dtSec), resize(w, h), stats(), destroy() }
// frame() never blocks (it returns a promise for that frame, or null when the Worker was still
// busy and the frame was skipped): the theme steps and draws in a Worker (on every core for a CPU kernel
// theme); the newest finished frame is shown, and a frame() that finds the Worker busy only
// adds its dt to the next step, so simulated time keeps pace with the wall clock.

import { loadModule, startEngine, canThread } from './engine.js';

// One SDK step of 0.008 is one 30 Hz Argus tick (desktop/frame_rate.zig): 0.24 per second.
const SDK_DT_PER_S = 0.008 * 30;
// After a long pause (a hidden tab) step at most this much at once.
const MAX_STEP_S = 0.25;

const VS = `#version 300 es
out vec2 uv;
void main() {
  vec2 p = vec2(float((gl_VertexID << 1) & 2), float(gl_VertexID & 2));
  uv = vec2(p.x * 0.5, 1.0 - p.y * 0.5); // theme row 0 is the top
  gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
}`;
const FS = `#version 300 es
precision mediump float;
in vec2 uv;
uniform sampler2D tex;
out vec4 color;
void main() { color = vec4(texture(tex, uv).rgb, 1.0); }`;

function makeGL(canvas) {
  const gl = canvas.getContext('webgl2', { alpha: false, antialias: false, depth: false, stencil: false, premultipliedAlpha: false, preserveDrawingBuffer: false, desynchronized: true });
  if (!gl) return null;
  const sh = (type, src) => {
    const s = gl.createShader(type);
    gl.shaderSource(s, src);
    gl.compileShader(s);
    if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s));
    return s;
  };
  const prog = gl.createProgram();
  gl.attachShader(prog, sh(gl.VERTEX_SHADER, VS));
  gl.attachShader(prog, sh(gl.FRAGMENT_SHADER, FS));
  gl.linkProgram(prog);
  if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(prog));
  const tex = gl.createTexture();
  gl.bindTexture(gl.TEXTURE_2D, tex);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
  gl.pixelStorei(gl.UNPACK_ALIGNMENT, 4);
  gl.useProgram(prog);
  return { gl, tex, w: 0, h: 0, sharedOk: true, staging: null };
}

/// Show `n` RGBA pixels (rw x rh) from `src` (a Uint8Array, maybe over shared memory).
function blitGL(g, canvas, src, rw, rh) {
  const gl = g.gl;
  if (g.w !== rw || g.h !== rh) {
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, rw, rh, 0, gl.RGBA, gl.UNSIGNED_BYTE, null);
    g.w = rw; g.h = rh;
  }
  let view = src;
  if (!g.sharedOk && src.buffer instanceof SharedArrayBuffer) {
    if (!g.staging || g.staging.length !== src.length) g.staging = new Uint8Array(src.length);
    g.staging.set(src);
    view = g.staging;
  }
  try {
    gl.texSubImage2D(gl.TEXTURE_2D, 0, 0, 0, rw, rh, gl.RGBA, gl.UNSIGNED_BYTE, view);
  } catch (e) {
    if (!g.sharedOk) throw e;
    g.sharedOk = false; // this browser will not upload from shared memory: copy first
    return blitGL(g, canvas, src, rw, rh);
  }
  gl.viewport(0, 0, canvas.width, canvas.height);
  gl.drawArrays(gl.TRIANGLES, 0, 3);
}

function make2D(canvas) {
  const ctx = canvas.getContext('2d', { alpha: false, desynchronized: true });
  if (!ctx) throw new Error('this canvas already has another kind of context: give create() a fresh canvas');
  return { ctx, img: null, off: null };
}

function blit2D(g, canvas, src, rw, rh) {
  if (!g.img || g.img.width !== rw || g.img.height !== rh) g.img = new ImageData(rw, rh);
  g.img.data.set(src);
  if (rw === canvas.width && rh === canvas.height) {
    g.ctx.putImageData(g.img, 0, 0);
  } else {
    if (!g.off || g.off.width !== rw || g.off.height !== rh) g.off = new OffscreenCanvas(rw, rh);
    g.off.getContext('2d').putImageData(g.img, 0, 0);
    g.ctx.imageSmoothingEnabled = true;
    g.ctx.drawImage(g.off, 0, 0, canvas.width, canvas.height);
  }
}

class Avg {
  constructor(n = 60) { this.n = n; this.v = []; }
  push(x) { this.v.push(x); if (this.v.length > this.n) this.v.shift(); }
  get mean() { return this.v.length ? this.v.reduce((a, b) => a + b, 0) / this.v.length : 0; }
}

/// opts: theme (build name, default Tutorial_Tides), base (URL of web/wasm/build/), threads
/// ('auto' | number of Workers; 1 = single-threaded module), blit ('auto' | 'webgl2' | '2d'),
/// renderScale (1 = the canvas's full size; 0.5 = half each way, upscaled), scale (the theme's
/// `scale`, default devicePixelRatio).
export async function create(canvas, opts = {}) {
  const name = opts.theme || 'Tutorial_Tides';
  const base = opts.base || new URL('./build/', import.meta.url);
  const threads = opts.threads ?? 'auto';
  const m = opts.module ?? await loadModule(base, name, { threads }); // opts.module: see engine.js moduleFromBytes
  const engine = await startEngine({ module: m.module, threaded: m.threaded, threads });

  let blitMode = opts.blit || 'auto';
  let g = null;
  if (blitMode !== '2d') {
    try { g = makeGL(canvas); } catch { g = null; }
    if (g) blitMode = 'webgl2';
  }
  if (!g) { g = make2D(canvas); blitMode = '2d'; }
  const present = blitMode === 'webgl2' ? blitGL : blit2D;

  const renderScale = opts.renderScale ?? 1;
  const themeScale = opts.scale ?? (typeof devicePixelRatio !== 'undefined' ? devicePixelRatio : 1);
  const live = { w: 0, h: 0, ptr: 0 };
  let want = { w: canvas.width || 1, h: canvas.height || 1 };
  let busy = false;
  let pendingS = 0;
  let destroyed = false;
  let lastError = null;
  const cpu = new Avg(), blit = new Avg();
  const presented = [];
  let dropped = 0;
  let nanSeen = false;

  async function reinit() {
    const rw = Math.max(1, Math.round(want.w * renderScale));
    const rh = Math.max(1, Math.round(want.h * renderScale));
    const r = await engine.leader.call('liveInit', { w: rw, h: rh, scale: themeScale });
    if (!r.ptr) throw new Error(`${name} refused ${rw}x${rh}`);
    Object.assign(live, { w: rw, h: rh, ptr: r.ptr });
  }

  async function step(dtS) {
    if (live.w !== Math.max(1, Math.round(want.w * renderScale)) || live.h !== Math.max(1, Math.round(want.h * renderScale))) await reinit();
    const sdkDt = Math.min(dtS, MAX_STEP_S) * SDK_DT_PER_S;
    const r = await engine.leader.call('frame', { dt: sdkDt, w: live.w, h: live.h, ptr: live.ptr });
    if (destroyed) return;
    cpu.push(r.cpuMs);
    if (r.nan) nanSeen = true;
    const t0 = performance.now();
    const src = r.pixels ? new Uint8Array(r.pixels.buffer) : new Uint8Array(engine.memory.buffer, live.ptr, live.w * live.h * 4);
    present(g, canvas, src, live.w, live.h);
    blit.push(performance.now() - t0);
    presented.push(performance.now());
    while (presented.length && presented[0] < performance.now() - 1000) presented.shift();
  }

  // A frame() that finds the Worker busy is not lost: its time is added to the next step, and
  // that step starts as soon as the current frame is on the canvas, not at the next frame()
  // call. So a theme that costs 18 ms runs at ~55 FPS on a 60 Hz display, not at 30.
  let catchUp = false;
  function run(dt) {
    busy = true;
    return step(dt).catch((e) => { lastError = e; console.error(e); }).finally(() => {
      busy = false;
      if (catchUp && !destroyed) {
        catchUp = false;
        const next = pendingS;
        pendingS = 0;
        run(next);
      }
    });
  }

  return {
    name,
    variant: m.variant,
    frame(timeSec, dtSec) {
      if (destroyed) return null;
      pendingS += Math.max(0, dtSec || 0);
      if (busy) { dropped++; catchUp = true; return null; }
      const dt = pendingS;
      pendingS = 0;
      // Returns a promise that settles when this frame is on the canvas (null if skipped).
      return run(dt);
    },
    /// Throughput: `frames` frames back to back (step + draw + upload + draw call), no rAF, at
    /// dtSec each. Resolves to { frames, ms, msPerFrame, fps }. (The canvas shows each frame;
    /// with a GPU blit the upload is queued, so this is the CPU side of the cost.)
    async bench(frames = 120, dtSec = 1 / 60) {
      while (busy) await new Promise((r) => setTimeout(r, 1));
      const t0 = performance.now();
      for (let i = 0; i < frames; i++) { busy = true; try { await step(dtSec); } finally { busy = false; } }
      const ms = performance.now() - t0;
      return { frames, ms, msPerFrame: ms / frames, fps: 1000 * frames / ms, cpuMs: cpu.mean, blitMs: blit.mean, w: live.w, h: live.h, threads: engine.threads };
    },
    resize(w, h) {
      want = { w: Math.max(1, w | 0), h: Math.max(1, h | 0) };
      canvas.width = want.w;
      canvas.height = want.h;
    },
    stats() {
      return {
        cpuMs: cpu.mean,            // step + draw in the Worker(s), mean of the last 60 frames
        blitMs: blit.mean,          // upload + draw on the page's thread
        wasmKB: m.bytes / 1024,
        fps: presented.length,      // frames shown in the last second
        threads: engine.threads,
        lanes: engine.info.lanes,   // SIMD lanes per kernel call (0: an SDK theme)
        variant: m.variant,         // 'mt' (threads) or 'st'
        isolated: canThread(),
        blit: blitMode + (blitMode === 'webgl2' && g.sharedOk === false ? ' (copy)' : ''),
        renderW: live.w,
        renderH: live.h,
        dropped,
        nan: nanSeen,
        error: lastError ? String(lastError.message || lastError) : null,
      };
    },
    destroy() {
      destroyed = true;
      engine.terminate();
    },
  };
}
