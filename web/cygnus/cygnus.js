// ============================================================================
// ARGUS WEB // web/cygnus/cygnus.js
//
// Cygnus A in the browser, built like the app's GPU path (src/gpu/bh_gpu.zig + presenter.zig):
//   - the CPU side is the real theme, compiled to wasm (cygnus.wasm from cygnus_wasm.zig): its
//     tables and every frame's step() state are the bytes the Metal presenter uploads;
//   - the GPU side is opus_black_hole.metal ported to WGSL (cygnus.wgsl);
//   - on create and on every resize: meter the exposure, then trace the Kerr geodesics once
//     into the record buffers, in row tiles, so the image appears row by row while frames keep
//     presenting (rows not traced yet draw black), then the footprint pass;
//   - every frame: step() in wasm, then one shade pass straight into the canvas.
//
//   const e = await create(canvas, opts);   e.frame(timeSec, dtSec); e.resize(w, h);
//   e.stats() -> { gpuMs, cpuMs, wasmKB, traceMs, traceGpuMs, rowsDone, height, exposure };
//   e.destroy();
//
// opts: device (share one), hdr (rgba16float canvas, extended tone mapping), headroom (HDR
// display headroom; 1 = the app's SDR curve), incl (degrees; default the theme's 88),
// tileMs (target GPU time per trace tile, default 12), onTraceDone(stats).
// ============================================================================

const HERE = new URL('.', import.meta.url);
const FRAME_BYTES = 1320; // bh_tables.Frame
const FRAME_BUF = 1328; // padded to whole vec4s (the shader reads it as array<vec4u, 83>)
const PARAMS_BYTES = 128; // bh_tables.TraceParams
const VIEW_BYTES = 32; // bh_tables.View
const METER_W = 192;
const ZIG_TICK_DT = 0.008; // src/desktop/frame_rate.zig: step per 1/30 s logic tick
const TICK_S = 1 / 30;
const OUT_SRGB = 1;
const OUT_EXT_SRGB = 3;

export const name = 'Cygnus A';

export async function getDevice() {
  if (!navigator.gpu) throw new Error('WebGPU is not available in this browser');
  const adapter = await navigator.gpu.requestAdapter({ powerPreference: 'high-performance' });
  if (!adapter) throw new Error('no WebGPU adapter');
  const features = adapter.features.has('timestamp-query') ? ['timestamp-query'] : [];
  const lim = adapter.limits;
  return adapter.requestDevice({
    requiredFeatures: features,
    requiredLimits: {
      maxStorageBufferBindingSize: lim.maxStorageBufferBindingSize,
      maxBufferSize: lim.maxBufferSize,
    },
  });
}

async function loadWasm() {
  const bytes = await (await fetch(new URL('cygnus.wasm', HERE))).arrayBuffer();
  const { instance } = await WebAssembly.instantiate(bytes, {});
  return { x: instance.exports, bytes: bytes.byteLength };
}

// GPU time of one pass, read back asynchronously from a small pool of query sets.
class PassTimer {
  constructor(device, n = 16) {
    this.device = device;
    this.ok = device.features.has('timestamp-query');
    this.free = [];
    if (!this.ok) return;
    for (let i = 0; i < n; i++) {
      this.free.push({
        qs: device.createQuerySet({ type: 'timestamp', count: 2 }),
        res: device.createBuffer({ size: 16, usage: GPUBufferUsage.QUERY_RESOLVE | GPUBufferUsage.COPY_SRC }),
        read: device.createBuffer({ size: 16, usage: GPUBufferUsage.MAP_READ | GPUBufferUsage.COPY_DST }),
      });
    }
  }
  // { writes, done(encoder), after(cb) } or null when no slot is free (the pass goes untimed).
  take() {
    if (!this.ok || !this.free.length) return null;
    const s = this.free.pop();
    return {
      writes: { querySet: s.qs, beginningOfPassWriteIndex: 0, endOfPassWriteIndex: 1 },
      resolve: (enc) => {
        enc.resolveQuerySet(s.qs, 0, 2, s.res, 0);
        enc.copyBufferToBuffer(s.res, 0, s.read, 0, 16);
      },
      after: (cb) => {
        s.read.mapAsync(GPUMapMode.READ).then(() => {
          const t = new BigInt64Array(s.read.getMappedRange());
          const ms = Number(t[1] - t[0]) / 1e6;
          s.read.unmap();
          this.free.push(s);
          if (ms >= 0 && ms < 1e4) cb(ms);
        }, () => this.free.push(s));
      },
    };
  }
}

export async function create(canvas, opts = {}) {
  const device = opts.device ?? (await getDevice());
  const ownDevice = !opts.device;
  const [code, wasm] = await Promise.all([fetch(new URL('cygnus.wgsl', HERE)).then((r) => r.text()), loadWasm()]);
  const X = wasm.x;
  const mem = () => X.memory.buffer;

  // ---- the theme (wasm): tables built once, exactly as the app's dylib builds them -----------
  if (!X.cyg_init(16, 10)) throw new Error('Cygnus A: theme init failed');
  const incl = opts.incl != null ? (opts.incl * Math.PI) / 180 : -1;

  const module = device.createShaderModule({ label: 'cygnus.wgsl', code });
  const info = await module.getCompilationInfo();
  const errs = info.messages.filter((m) => m.type === 'error');
  if (errs.length) throw new Error('cygnus.wgsl: ' + errs.map((m) => `${m.lineNum}:${m.linePos} ${m.message}`).join('\n'));

  const hdr = !!opts.hdr;
  const format = hdr ? 'rgba16float' : navigator.gpu.getPreferredCanvasFormat();
  const ctx = canvas.getContext('webgpu');
  ctx.configure({ device, format, alphaMode: 'opaque', ...(hdr ? { toneMapping: { mode: 'extended' } } : {}) });
  const headroom = hdr ? Math.max(1, opts.headroom ?? 1) : 1;

  const cp = (entryPoint) => device.createComputePipelineAsync({ label: entryPoint, layout: 'auto', compute: { module, entryPoint } });
  const [pMeter, pTrace, pFoot, pProbe, pShadeC, pShadeF] = await Promise.all([
    cp('bh_meter'),
    cp('bh_trace'),
    cp('bh_footprint'),
    cp('bh_probe'),
    cp('bh_shade'),
    device.createRenderPipelineAsync({
      label: 'fs_shade',
      layout: 'auto',
      vertex: { module, entryPoint: 'vs_full' },
      fragment: { module, entryPoint: 'fs_shade', targets: [{ format }] },
      primitive: { topology: 'triangle-list' },
    }),
  ]);

  const U = GPUBufferUsage;
  const upload = (label, ptr, len, usage = U.STORAGE) => {
    const b = device.createBuffer({ label, size: Math.ceil(len / 4) * 4, usage: usage | U.COPY_DST });
    device.queue.writeBuffer(b, 0, mem(), ptr, len);
    return b;
  };
  const statBuf = upload('Static', X.cyg_static_ptr(), X.cyg_static_len());
  const ttabBuf = upload('ttab', X.cyg_ttab_ptr(), X.cyg_ttab_len());
  const noiseBuf = upload('noise', X.cyg_noise_ptr(), X.cyg_noise_len());
  const frameBuf = device.createBuffer({ label: 'Frame', size: FRAME_BUF, usage: U.UNIFORM | U.COPY_DST });
  const viewBuf = device.createBuffer({ label: 'View', size: VIEW_BYTES, usage: U.UNIFORM | U.COPY_DST });
  const viewBytes = new ArrayBuffer(VIEW_BYTES);
  const viewU = new Uint32Array(viewBytes);
  const viewF = new Float32Array(viewBytes);
  const timer = new PassTimer(device);

  const timing = { gpu: [], cpu: [] };
  const push = (arr, x) => {
    arr.push(x);
    if (arr.length > 120) arr.shift();
  };
  const mean = (arr) => (arr.length ? arr.reduce((a, b) => a + b, 0) / arr.length : null);

  // ---- one traced image (bh_gpu.Engine) ------------------------------------------------------
  function traceParams(w, h, exposure, row0 = 0) {
    const p = X.cyg_trace_params(w, h, incl);
    const bytes = new ArrayBuffer(PARAMS_BYTES);
    new Uint8Array(bytes).set(new Uint8Array(mem(), p, PARAMS_BYTES));
    const f = new Float32Array(bytes);
    const u = new Uint32Array(bytes);
    f[20] = exposure; // TraceParams.exposure
    u[23] = row0; // TraceParams.row0
    return bytes;
  }

  class Engine {
    constructor(w, h) {
      this.w = w;
      this.h = h;
      const n = w * h;
      const sto = U.STORAGE | U.COPY_SRC; // COPY_SRC: verify/ reads the records back
      this.params = device.createBuffer({ label: 'TraceParams', size: PARAMS_BYTES, usage: U.UNIFORM | U.COPY_DST });
      this.recA = device.createBuffer({ label: 'rec_a', size: n * 4, usage: sto });
      this.recB = device.createBuffer({ label: 'rec_b', size: n * 4, usage: sto });
      this.bg = device.createBuffer({ label: 'bg', size: n * 4, usage: sto });
      this.bfrac = device.createBuffer({ label: 'bfrac', size: Math.ceil(n / 4) * 4, usage: sto });
      this.tq = device.createBuffer({ label: 'tq', size: Math.ceil(n / 2) * 4, usage: sto });
      this.exposure = 1;
      this.rowsDone = 0;
      this.done = false;
      this.cancelled = false;
      this.traceGpuMs = 0;
      this.tilesTimed = 0;
      this.tiles = 0;
      const B = (buffer) => ({ buffer });
      this.gTrace = device.createBindGroup({
        layout: pTrace.getBindGroupLayout(0),
        entries: [
          { binding: 0, resource: B(this.params) }, { binding: 1, resource: B(statBuf) }, { binding: 2, resource: B(ttabBuf) },
          { binding: 3, resource: B(this.recA) }, { binding: 4, resource: B(this.bg) }, { binding: 5, resource: B(this.tq) },
          { binding: 6, resource: B(this.bfrac) }, { binding: 7, resource: B(this.recB) },
        ],
      });
      this.gFoot = device.createBindGroup({
        layout: pFoot.getBindGroupLayout(0),
        entries: [{ binding: 0, resource: B(this.params) }, { binding: 3, resource: B(this.recA) }, { binding: 7, resource: B(this.recB) }, { binding: 11, resource: B(this.tq) }],
      });
      const g0 = (pipe) => device.createBindGroup({
        layout: pipe.getBindGroupLayout(0),
        entries: [{ binding: 0, resource: B(this.params) }, { binding: 1, resource: B(statBuf) }, { binding: 2, resource: B(ttabBuf) }],
      });
      const g1 = (pipe, extra) => device.createBindGroup({
        layout: pipe.getBindGroupLayout(1),
        entries: [
          { binding: 0, resource: B(this.recA) }, { binding: 1, resource: B(this.recB) }, { binding: 2, resource: B(this.bg) },
          { binding: 3, resource: B(this.bfrac) }, { binding: 4, resource: B(noiseBuf) }, { binding: 5, resource: B(frameBuf) },
          { binding: 6, resource: B(viewBuf) }, ...extra,
        ],
      });
      this.gShadeF = [g0(pShadeF), g1(pShadeF, [])];
      this.g0ShadeC = g0(pShadeC);
      this.g1ShadeC = (tex) => g1(pShadeC, [{ binding: 7, resource: tex.createView() }]);
    }

    // Exposure: the theme's rule (99th-percentile inner-disk luminance at 7) on the GPU's own
    // trace of a 192-wide grid, reduced by the theme's own exposureFrom (wasm).
    async meter() {
      const p = new Uint32Array(traceParams(this.w, this.h, 1));
      const gw = p[24];
      const gh = p[25];
      device.queue.writeBuffer(this.params, 0, p);
      const n = gw * gh;
      const lum = device.createBuffer({ size: n * 4, usage: U.STORAGE | U.COPY_SRC });
      const read = device.createBuffer({ size: n * 4, usage: U.MAP_READ | U.COPY_DST });
      const g = device.createBindGroup({
        layout: pMeter.getBindGroupLayout(0),
        entries: [{ binding: 0, resource: { buffer: this.params } }, { binding: 1, resource: { buffer: statBuf } }, { binding: 2, resource: { buffer: ttabBuf } }, { binding: 8, resource: { buffer: lum } }],
      });
      const enc = device.createCommandEncoder();
      const pass = enc.beginComputePass();
      pass.setPipeline(pMeter);
      pass.setBindGroup(0, g);
      pass.dispatchWorkgroups(Math.ceil(gw / 8), Math.ceil(gh / 8));
      pass.end();
      enc.copyBufferToBuffer(lum, 0, read, 0, n * 4);
      device.queue.submit([enc.finish()]);
      await read.mapAsync(GPUMapMode.READ);
      const sp = X.cyg_scratch(n);
      new Float32Array(mem(), sp, n).set(new Float32Array(read.getMappedRange()));
      read.unmap();
      lum.destroy();
      read.destroy();
      this.exposure = X.cyg_exposure_from(n);
      return this.exposure;
    }

    // Queues the trace in row tiles (multiples of the 8-row workgroup), at most two in flight so
    // frames interleave; each tile's GPU time steers the next tile's height toward tileMs.
    // traceExposure (verification only) traces with another exposure than the shade uses: the
    // offline renderer traces with TraceParams.exposure = 1 and sets the metered one afterwards.
    async start(exposure, traceExposure) {
      this.exposure = exposure ?? (await this.meter());
      this.traceExposure = traceExposure ?? this.exposure;
      if (this.cancelled) return;
      this.t0 = performance.now();
      this.next = 0;
      this.inFlight = 0;
      this.rowsPerTile = 8 * Math.max(1, Math.round(16384 / this.w)); // ~16k-pixel first tile per 8 rows
      this.rowsPerTile = Math.max(8, Math.min(64, this.rowsPerTile));
      this.target = opts.tileMs ?? 12;
      this.finished = new Promise((res) => (this.resolveDone = res));
      this.pump();
      return this.finished;
    }

    pump() {
      while (!this.cancelled && this.inFlight < 2 && this.next < this.h) this.tile();
      if (!this.cancelled && this.inFlight === 0 && this.next >= this.h && !this.footQueued) this.footprint();
    }

    tile() {
      const row0 = this.next;
      const rows = Math.min(this.rowsPerTile, this.h - row0);
      this.next += rows;
      this.inFlight++;
      this.tiles++;
      device.queue.writeBuffer(this.params, 0, traceParams(this.w, this.h, this.traceExposure, row0));
      const t = timer.take();
      const enc = device.createCommandEncoder();
      const pass = enc.beginComputePass(t ? { timestampWrites: t.writes } : {});
      pass.setPipeline(pTrace);
      pass.setBindGroup(0, this.gTrace);
      pass.dispatchWorkgroups(Math.ceil(this.w / 8), Math.ceil(rows / 8));
      pass.end();
      if (t) t.resolve(enc);
      device.queue.submit([enc.finish()]);
      const t0 = performance.now();
      if (t) t.after((ms) => {
        this.traceGpuMs += ms;
        this.tilesTimed++;
        // Steer the tile height (whole workgroups) toward the target GPU time.
        const per8 = ms / Math.ceil(rows / 8);
        if (per8 > 0) this.rowsPerTile = 8 * Math.max(1, Math.min(32, Math.round(this.target / per8)));
      });
      device.queue.onSubmittedWorkDone().then(() => {
        this.inFlight--;
        this.rowsDone = Math.max(this.rowsDone, row0 + rows);
        if (!t) {
          const per8 = (performance.now() - t0) / Math.ceil(rows / 8);
          if (per8 > 0) this.rowsPerTile = 8 * Math.max(1, Math.min(32, Math.round(this.target / per8)));
        }
        this.pump();
      });
    }

    footprint() {
      this.footQueued = true;
      const t = timer.take();
      const enc = device.createCommandEncoder();
      const pass = enc.beginComputePass(t ? { timestampWrites: t.writes } : {});
      pass.setPipeline(pFoot);
      pass.setBindGroup(0, this.gFoot);
      pass.dispatchWorkgroups(Math.ceil(this.w / 8), Math.ceil(this.h / 8));
      pass.end();
      if (t) t.resolve(enc);
      device.queue.submit([enc.finish()]);
      if (t) t.after((ms) => { this.footGpuMs = ms; });
      device.queue.onSubmittedWorkDone().then(() => {
        if (this.cancelled) return;
        this.tq.destroy(); // the footprints are in the records now (bh_gpu: tq is freed)
        this.tq = null;
        this.traceMs = performance.now() - this.t0;
        this.rowsDone = this.h;
        this.done = true;
        this.resolveDone(this);
        opts.onTraceDone?.(api.stats());
      });
    }

    destroy() {
      this.cancelled = true;
      this.resolveDone?.(this);
      for (const b of [this.params, this.recA, this.recB, this.bg, this.bfrac, this.tq]) b?.destroy();
    }
  }

  // ---- presenting -----------------------------------------------------------------------------
  let eng = null;
  let pending = null; // resize waiting out its debounce

  function retrace(w, h, exposure, traceExposure) {
    eng?.destroy();
    eng = new Engine(w, h);
    return eng.start(exposure, traceExposure);
  }

  function writeView(e, outW, outH, mode, hr) {
    viewU[0] = e.w;
    viewU[1] = e.h;
    viewU[2] = outW;
    viewU[3] = outH;
    viewU[4] = e.done ? e.h : e.rowsDone;
    viewF[5] = e.exposure;
    viewF[6] = hr;
    viewU[7] = mode;
    device.queue.writeBuffer(viewBuf, 0, viewBytes);
  }

  function writeFrame() {
    const fp = X.cyg_frame();
    device.queue.writeBuffer(frameBuf, 0, mem(), fp, FRAME_BYTES);
  }

  function frame(timeSec, dtSec) {
    if (!eng) return;
    const c0 = performance.now();
    // The app's pacer (src/desktop/frame_rate.zig): step 0.008 per 1/30 s, at most one tick.
    const d = Math.min(Math.max(dtSec || 0, 0), TICK_S) * (ZIG_TICK_DT / TICK_S);
    if (d > 0) X.cyg_step(d);
    writeFrame();
    const tex = ctx.getCurrentTexture();
    writeView(eng, tex.width, tex.height, hdr ? OUT_EXT_SRGB : OUT_SRGB, headroom);
    const t = timer.take();
    const enc = device.createCommandEncoder();
    const pass = enc.beginRenderPass({
      colorAttachments: [{ view: tex.createView(), loadOp: 'clear', storeOp: 'store', clearValue: [0, 0, 0, 1] }],
      ...(t ? { timestampWrites: t.writes } : {}),
    });
    pass.setPipeline(pShadeF);
    pass.setBindGroup(0, eng.gShadeF[0]);
    pass.setBindGroup(1, eng.gShadeF[1]);
    pass.draw(3);
    pass.end();
    if (t) t.resolve(enc);
    device.queue.submit([enc.finish()]);
    if (t) t.after((ms) => push(timing.gpu, ms));
    push(timing.cpu, performance.now() - c0);
  }

  function resize(w, h) {
    w = Math.max(1, Math.round(w));
    h = Math.max(1, Math.round(h));
    canvas.width = w;
    canvas.height = h;
    if (eng && eng.w === w && eng.h === h) return;
    // Until the new size settles the current trace is shown scaled (bh_shade maps each output
    // pixel to the traced one); then it is traced again at the new size, row by row.
    clearTimeout(pending);
    pending = setTimeout(() => retrace(w, h), eng ? 150 : 0);
  }

  function stats() {
    return {
      gpuMs: mean(timing.gpu),
      cpuMs: mean(timing.cpu),
      wasmKB: Math.round(mem().byteLength / 1024),
      wasmFileKB: Math.round(wasm.bytes / 1024),
      traceMs: eng?.traceMs ?? null,
      traceGpuMs: eng?.done ? eng.traceGpuMs + (eng.footGpuMs ?? 0) : null,
      traceTiles: eng?.tiles ?? 0,
      tilesTimed: eng?.tilesTimed ?? 0,
      rowsDone: eng ? (eng.done ? eng.h : eng.rowsDone) : 0,
      width: eng?.w ?? 0,
      height: eng?.h ?? 0,
      exposure: eng?.exposure ?? null,
      simTimeM: X.cyg_time_m(),
      timestamps: timer.ok,
    };
  }

  // ---- verification hooks (web/cygnus/verify/) -----------------------------------------------
  const verify = {
    // Trace at w x h now (no debounce); resolves when the trace and footprints are done.
    trace: (w, h, exposure, traceExposure) => retrace(w, h, exposure, traceExposure),
    // n steps of dt, as the offline renderer's --skip (dt = 0.008 * 30 / fps).
    step: (n, dt) => { for (let i = 0; i < n; i++) X.cyg_step(dt); },
    // The current frame through the compute bh_shade into RGBA8, sRGB, SDR (the offline
    // renderer's encoding). Returns Uint8Array w * h * 4.
    async readRGBA() {
      const e = eng;
      const w = e.w;
      const h = e.h;
      writeFrame();
      writeView(e, w, h, OUT_SRGB, 1);
      const tex = device.createTexture({ size: [w, h], format: 'rgba8unorm', usage: GPUTextureUsage.STORAGE_BINDING | GPUTextureUsage.COPY_SRC });
      const bpr = Math.ceil((w * 4) / 256) * 256;
      const buf = device.createBuffer({ size: bpr * h, usage: U.MAP_READ | U.COPY_DST });
      const enc = device.createCommandEncoder();
      const pass = enc.beginComputePass();
      pass.setPipeline(pShadeC);
      pass.setBindGroup(0, e.g0ShadeC);
      pass.setBindGroup(1, e.g1ShadeC(tex));
      pass.dispatchWorkgroups(Math.ceil(w / 16), Math.ceil(h / 8));
      pass.end();
      enc.copyTextureToBuffer({ texture: tex }, { buffer: buf, bytesPerRow: bpr }, [w, h]);
      device.queue.submit([enc.finish()]);
      await buf.mapAsync(GPUMapMode.READ);
      const src = new Uint8Array(buf.getMappedRange());
      const out = new Uint8Array(w * h * 4);
      for (let y = 0; y < h; y++) out.set(src.subarray(y * bpr, y * bpr + w * 4), y * w * 4);
      buf.unmap();
      buf.destroy();
      tex.destroy();
      return out;
    },
    // Kinds (0 sky, 1 disk, 2 hole) of the first thing each (alpha, beta) ray meets, no disk.
    async probe(ab) {
      const n = ab.length / 2;
      const params = device.createBuffer({ size: PARAMS_BYTES, usage: U.UNIFORM | U.COPY_DST });
      device.queue.writeBuffer(params, 0, traceParams(64, 64, 1));
      const inb = device.createBuffer({ size: n * 8, usage: U.STORAGE | U.COPY_DST });
      device.queue.writeBuffer(inb, 0, ab);
      const out = device.createBuffer({ size: n * 4, usage: U.STORAGE | U.COPY_SRC });
      const read = device.createBuffer({ size: n * 4, usage: U.MAP_READ | U.COPY_DST });
      const g = device.createBindGroup({
        layout: pProbe.getBindGroupLayout(0),
        entries: [{ binding: 0, resource: { buffer: params } }, { binding: 9, resource: { buffer: inb } }, { binding: 10, resource: { buffer: out } }],
      });
      const enc = device.createCommandEncoder();
      const pass = enc.beginComputePass();
      pass.setPipeline(pProbe);
      pass.setBindGroup(0, g);
      pass.dispatchWorkgroups(Math.ceil(n / 64));
      pass.end();
      enc.copyBufferToBuffer(out, 0, read, 0, n * 4);
      device.queue.submit([enc.finish()]);
      await read.mapAsync(GPUMapMode.READ);
      const kinds = new Uint32Array(read.getMappedRange()).slice();
      read.unmap();
      for (const b of [params, inb, out, read]) b.destroy();
      return kinds;
    },
    // src/gpu_bench.zig's contourSweep on the WGSL probe: the theme's Bardeen contour (766
    // points), each edge bisected along the ray from the shadow centre, f64 brackets and f32
    // rays, CONTOUR_ITERS times; statistics by the theme's own contourStats.
    async contour() {
      const N = X.cyg_contour_n();
      const pts = new Float64Array(mem(), X.cyg_contour(), 2 * N).slice();
      const c = new Float64Array(mem(), X.cyg_contour_centre(), 2).slice();
      const u = new Float64Array(2 * N);
      const d = new Float64Array(N);
      const lo = new Float64Array(N);
      const hi = new Float64Array(N);
      for (let i = 0; i < N; i++) {
        const dx = pts[2 * i] - c[0];
        const dy = pts[2 * i + 1] - c[1];
        d[i] = Math.sqrt(dx * dx + dy * dy);
        u[2 * i] = dx / d[i];
        u[2 * i + 1] = dy / d[i];
        lo[i] = 0.9 * d[i];
        hi[i] = 1.1 * d[i];
      }
      const ab = new Float32Array(2 * N);
      const at = (t) => {
        for (let i = 0; i < N; i++) {
          ab[2 * i] = c[0] + u[2 * i] * t[i];
          ab[2 * i + 1] = c[1] + u[2 * i + 1] * t[i];
        }
      };
      const bad = new Uint8Array(N);
      for (const inner of [true, false]) {
        at(inner ? lo : hi);
        const k = await verify.probe(ab);
        for (let i = 0; i < N; i++) if ((k[i] === 2) !== inner) bad[i] = 1;
      }
      const iters = X.cyg_contour_iters();
      const mid = new Float64Array(N);
      for (let it = 0; it < iters; it++) {
        for (let i = 0; i < N; i++) mid[i] = 0.5 * (lo[i] + hi[i]);
        at(mid);
        const k = await verify.probe(ab);
        for (let i = 0; i < N; i++) {
          if (k[i] === 2) lo[i] = 0.5 * (lo[i] + hi[i]);
          else hi[i] = 0.5 * (lo[i] + hi[i]);
        }
      }
      const off = new Float64Array(mem(), X.cyg_contour_offsets(), N);
      for (let i = 0; i < N; i++) off[i] = bad[i] ? NaN : 0.5 * (lo[i] + hi[i]) - d[i];
      const s = new Float64Array(mem(), X.cyg_contour_stats(), 8);
      return { points: N, iters, max: s[0], maxAt: [s[1], s[2]], rms: s[3], rmsOffAxis: s[4], maxOffAxis: s[5], maxPolar: s[6], bracketFailures: s[7], offsets: Float64Array.from(off) };
    },
    // One traced buffer (rec_a, rec_b, bg, bfrac) back as a Uint32Array.
    async readBuffer(which) {
      const b = { rec_a: eng.recA, rec_b: eng.recB, bg: eng.bg, bfrac: eng.bfrac }[which];
      const read = device.createBuffer({ size: b.size, usage: U.MAP_READ | U.COPY_DST });
      const enc = device.createCommandEncoder();
      enc.copyBufferToBuffer(b, 0, read, 0, b.size);
      device.queue.submit([enc.finish()]);
      await read.mapAsync(GPUMapMode.READ);
      const out = new Uint32Array(read.getMappedRange()).slice();
      read.unmap();
      read.destroy();
      return out;
    },
    get engine() { return eng; },
    exports: X,
  };

  const api = {
    name,
    frame,
    resize,
    stats,
    destroy() {
      clearTimeout(pending);
      eng?.destroy();
      eng = null;
      for (const b of [statBuf, ttabBuf, noiseBuf, frameBuf, viewBuf]) b.destroy();
      ctx.unconfigure();
      if (ownDevice) device.destroy();
    },
    verify,
  };
  if (!opts.noTrace) resize(canvas.width || canvas.clientWidth || 1920, canvas.height || canvas.clientHeight || 1080);
  return api;
}
