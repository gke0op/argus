// site/assets/bench.js: the "Run ARGUS-BENCH" page.
//   Zig: a dropped or pasted .zig is compiled in the page by Zig 0.17.0 as WebAssembly
//        (web/zigc) and run through the gates (web/wasm/gates.js, the native harness's gate
//        code in the module); so are the prebuilt builds (the skeleton, the gate fixtures) and an
//        uploaded .wasm. A pull request gets the native harness's verdict (the bench workflow).
//   WGSL: compiled by WebGPU and run through the Metal harness's checks (wgsl-harness.js).
import { mount, probeWebGPU } from './engines.js';
import { copyText } from './ui.js';

const $ = (id) => document.getElementById(id);
const REPO = 'gke0op/argus';
const WEB = new URL('../web/', import.meta.url);
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

// ---- tabs -------------------------------------------------------------------------------------
const tabs = [['tab-zig', 'pane-zig'], ['tab-wgsl', 'pane-wgsl']];
function showTab(id, push = true) {
  for (const [t, p] of tabs) {
    const on = t === id;
    $(t).setAttribute('aria-selected', String(on));
    $(t).tabIndex = on ? 0 : -1;
    $(p).hidden = !on;
  }
  if (push) history.replaceState(null, '', id === 'tab-wgsl' ? '#wgsl' : '#zig');
}
for (const [t] of tabs) $(t).addEventListener('click', () => showTab(t));
$('tab-zig').parentElement.addEventListener('keydown', (e) => {
  if (e.key !== 'ArrowRight' && e.key !== 'ArrowLeft') return;
  const next = document.activeElement === $('tab-zig') ? 'tab-wgsl' : 'tab-zig';
  showTab(next); $(next).focus();
});
if (location.hash === '#wgsl') showTab('tab-wgsl', false);

// ---- environment ------------------------------------------------------------------------------
const gpu = await probeWebGPU();
const envNotes = [];
if (!crossOriginIsolated) envNotes.push('This page is not cross-origin isolated (the service worker that adds the headers is not active yet, or was bypassed by a hard reload), so wasm runs on one thread: kernel themes are slower here than on every core.');
if (!gpu.ok) envNotes.push(`No WebGPU here (${esc(gpu.why)}), so the WGSL tab cannot run; the Zig gates can.`);
if (envNotes.length) { $('env').innerHTML = envNotes.join('<br>'); $('env').hidden = false; }

// ---- prompts ----------------------------------------------------------------------------------
async function text(url) { const r = await fetch(url); if (!r.ok) throw new Error(`${url}: HTTP ${r.status}`); return r.text(); }
const zigPrompt = $('zigPrompt').textContent.trim();
$('copyZigPrompt').addEventListener('click', (e) => copyText(zigPrompt, e.currentTarget));
$('copyZigFull').addEventListener('click', async (e) => {
  const md = await text(new URL('../BENCHMARK.md', import.meta.url));
  copyText(`${zigPrompt}\n\n----- BENCHMARK.md -----\n\n${md}`, e.currentTarget);
});
const wgslPrompt = $('wgslPrompt').textContent.trim();
$('copyWgslPrompt').addEventListener('click', (e) => copyText(wgslPrompt, e.currentTarget));
$('copyWgslFull').addEventListener('click', async (e) => {
  const [readme, prelude, tides] = await Promise.all([text(new URL('README.md', WEB)), text(new URL('prelude.wgsl', WEB)), text(new URL('themes/Tutorial_Tides.wgsl', WEB))]);
  const a = readme.indexOf('## Writing or translating a theme in WGSL');
  const b = readme.indexOf('## Verify a theme like the harness');
  const contract = a >= 0 ? readme.slice(a, b > a ? b : undefined).trim() : readme;
  copyText(`${wgslPrompt}\n\n----- The contract (web/README.md) -----\n\n${contract}\n\n----- web/prelude.wgsl (prepended to your file) -----\n\n${prelude}\n\n----- Example: web/themes/Tutorial_Tides.wgsl -----\n\n${tides}`, e.currentTarget);
});

// ---- shared result rendering -----------------------------------------------------------------
function renderGates(tbody, gates) {
  tbody.innerHTML = gates.map((g) => {
    const st = g.info ? ['info', g.info] : g.pass === null || g.pass === undefined ? ['skip', g.detail === '…' ? '…' : 'not run'] : g.pass ? ['pass', 'PASS'] : ['fail', 'FAIL'];
    return `<tr><td>${g.id}</td><td>${esc(g.name)}</td><td class="st ${st[0]}">${st[1]}</td><td class="d">${esc(g.detail ?? '')}</td></tr>`;
  }).join('');
}
function badge(el, state) {
  el.className = `badge ${state === 'PASS' ? 'pass' : state === 'FAIL' ? 'fail' : 'run'}`;
  el.textContent = state;
}
function drawFinal(canvas, rgba, w, h) {
  const ctx = canvas.getContext('2d');
  if (!rgba) { ctx.fillStyle = '#000'; ctx.fillRect(0, 0, canvas.width, canvas.height); return; }
  canvas.width = w; canvas.height = h;
  const px = rgba instanceof Uint8ClampedArray ? rgba : new Uint8ClampedArray(rgba.buffer.slice(rgba.byteOffset, rgba.byteOffset + w * h * 4));
  ctx.putImageData(new ImageData(px, w, h), 0, 0);
}
let live = null;
let liveGen = 0; // bumped by every new run, so a live view still starting for an old one is dropped
const stopLive = () => { liveGen++; live?.stop(); live = null; };
async function runLive(stage, cap, theme, extra) {
  stopLive();
  const gen = liveGen;
  cap.textContent = 'Starting live…';
  try {
    const h = await mount(stage, theme, extra);
    if (gen !== liveGen) { h.stop(); return; }
    live = h;
    const tick = () => {
      if (!live || live.theme !== theme) return;
      const r = live.readout();
      const ms = theme.kind === 'wasm' ? `CPU ${r.cpuMs?.toFixed(2) ?? '–'} ms/frame · ${r.threads ?? 1} thread${r.threads === 1 ? '' : 's'} · ${r.width}×${r.height}` : `GPU ${r.gpuMs?.toFixed(2) ?? 'n/a'} ms/frame · ${r.width}×${r.height}`;
      cap.textContent = `Live in this page: ${ms}`;
      setTimeout(tick, 500);
    };
    tick();
  } catch (e) { cap.textContent = `Live view failed: ${e.message ?? e}`; }
}

// ---- Zig: prebuilt, uploaded and in-page compiled builds -----------------------------------
let gatesMod = null;
const gatesLib = async () => (gatesMod ??= await import(new URL('wasm/gates.js', WEB)));
let busy = false;
const MB = (b) => `${(b / 1048576).toFixed(1)} MB`;
const phase = (s) => { $('zigPhase').textContent = s; };

const NOTE8_PREBUILT = 'Gate 8 here times this browser’s wasm on this machine; leaderboard times come from the native harness on an M3. Near the 16.7 ms line, judge on a quiet machine.';
function resetZigResult(title) {
  stopLive();
  $('zigResult').classList.add('on');
  badge($('zigBadge'), 'RUNNING');
  $('zigTitle').textContent = title;
  $('zigReport').textContent = '';
  $('zigDiag').hidden = true;
  $('zigMore').hidden = true;
  $('zigFull').hidden = true;
  $('zigGates').tBodies[0].innerHTML = '';
  $('zigLiveCap').textContent = 'Live, after the gates.';
  $('zigFinalCap').textContent = 'Frame 120 at 1920×1200, as the gates saw it.';
  $('zigNote8').textContent = NOTE8_PREBUILT;
  drawFinal($('zigFinal'), null);
  $('zigResult').scrollIntoView({ behavior: 'smooth', block: 'start' });
}

/// Grade a module through the gates (web/wasm/gates.js) and show it live. opts: module, title,
/// gate1 (Gate 1's line), inPage (built by the in-page compiler: Gate 8 is labelled as this
/// build's), maxPixels (live render size), extra (merged into window.__bench).
async function gradeZig(name, opts = {}) {
  if (busy && !opts.continuing) return;
  busy = true;
  if (!opts.continuing) resetZigResult(opts.title ?? name);
  const t0 = performance.now();
  try {
    const { runGates, GATES } = await gatesLib();
    renderGates($('zigGates').tBodies[0], GATES.map((g) => ({ ...g, pass: g.id === 1 && opts.gate1 ? true : null, detail: g.id === 1 && opts.gate1 ? opts.gate1 : '…' })));
    phase('gates: watchdog 320x200');
    const res = await runGates(name, { base: new URL('wasm/build/', WEB), module: opts.module, gate1: opts.gate1, onPhase: (p) => phase(`gates: ${p}${p === 'frames' ? ' (120 at 1920×1200)' : ''}`) });
    const secs = ((performance.now() - t0) / 1000).toFixed(1);
    let pass = res.pass;
    if (opts.inPage) {
      $('zigNote8').textContent = 'Gates 1–7 give the native harness’s verdict. Gate 8 here times a build from Zig’s self-hosted wasm backend (no LLVM, no SIMD, one thread), which is slower than the native harness’s ReleaseFast build: the official Gate 8 is the native harness’s, on a pull request.';
      // Gates 1-7 are the native harness's verdict; Gate 8 times this build, not the official one.
      const g8 = res.gates[7];
      if (g8.pass !== null) {
        g8.info = `here: ${g8.pass ? 'PASS' : 'FAIL'}`;
        g8.detail = `${g8.detail}\nthis browser build: Zig's self-hosted wasm backend, no SIMD, 1 thread. The official Gate 8 is the native harness's (pull request).`;
      }
      pass = res.gates.slice(0, 7).every((g) => g.pass === true);
    }
    renderGates($('zigGates').tBodies[0], res.gates);
    badge($('zigBadge'), pass ? 'PASS' : 'FAIL');
    if (opts.inPage && pass) $('zigBadge').textContent = 'PASS 1–7';
    const g8here = opts.inPage && res.report ? ` · Gate 8 here: ${res.gates[7].pass ? 'PASS' : 'FAIL'}, ${(res.report.avg_us / 1000).toFixed(1)} ms/frame in this build; the native harness decides it` : '';
    phase(`graded in ${secs} s · ${res.threads || 1} thread${res.threads === 1 ? '' : 's'} (${res.variant || '–'})${g8here}`);
    $('zigReport').textContent = res.text;
    drawFinal($('zigFinal'), res.pixels, res.width, res.height);
    window.__bench = { kind: 'zig', name, pass, gates: res.gates.map((g) => g.pass), text: res.text, secs: Number(secs), ...(opts.extra || {}) };
    busy = false; // graded: a new run may start while the live view comes up
    if (res.pixels && !res.timedOut) await startZigLive(name, opts);
    else $('zigLiveCap').textContent = 'No live view: the theme did not get through its frames.';
  } catch (e) {
    badge($('zigBadge'), 'FAIL');
    $('zigReport').textContent = `ERROR: ${e.message ?? e}`;
    window.__bench = { kind: 'zig', name, error: String(e.message ?? e), ...(opts.extra || {}) };
  } finally { busy = false; }
}

async function startZigLive(name, opts) {
  const label = opts.inPage ? 'wasm, Zig self-hosted backend (CPU, 1 thread)' : undefined;
  await runLive($('zigLive'), $('zigLiveCap'), { id: `bench:${name}`, label: name, kind: 'wasm', build: name }, { module: opts.module, maxPixels: opts.maxPixels, label });
  $('zigFull').hidden = !live;
}

$('zigFull').addEventListener('click', () => {
  const el = $('zigLive');
  (el.requestFullscreen || el.webkitRequestFullscreen)?.call(el);
});

$('zigBuild').addEventListener('change', () => { $('buildSrc').href = `zig/${$('zigBuild').value}.zig`; });
$('runBuild').addEventListener('click', () => gradeZig($('zigBuild').value));

async function gradeUpload(file) {
  if (!file || busy) return;
  const { moduleFromBytes } = await import(new URL('wasm/engine.js', WEB));
  const name = file.name.replace(/\.(mt|st)?\.?wasm$/, '').replace(/[^A-Za-z0-9_]/g, '_') || 'Upload';
  try {
    const module = await moduleFromBytes(new Uint8Array(await file.arrayBuffer()));
    await gradeZig(name, { module, title: `${file.name} (uploaded)` });
  } catch (e) {
    resetZigResult(file.name);
    badge($('zigBadge'), 'FAIL');
    $('zigReport').textContent = `Gate 1: this file is not a module the page can run: ${e.message ?? e}`;
  }
}

// ---- Zig: compiled in this page (web/zigc: zig.wasm, Zig 0.17.0) ---------------------------
let zcPromise = null;
const loading = { compiler: [0, 0], std: [0, 0] };
function onLoadProgress(m) {
  if (m.phase === 'starting') { if (busy) phase('starting the compiler…'); return; }
  loading[m.phase] = [m.loaded, m.total];
  if (!busy) return;
  const part = (k, label) => { const [a, b] = loading[k]; return b ? `${label} ${MB(a)} / ${MB(b)}` : `${label} …`; };
  phase(`loading ${part('compiler', 'the compiler')} · ${part('std', 'std')}${m.cached ? ' (cached)' : ''}`);
}
/// The compiler, loaded on first use (or first sign of use: a drag, a paste, the editor's focus).
function zigc() {
  zcPromise ??= import(new URL('zigc/client.js', WEB)).then((m) => m.getCompiler({ onProgress: onLoadProgress }));
  return zcPromise;
}
const warm = () => { zigc().catch(() => {}); };

function showDiagnostics(log, name) {
  const el = $('zigDiag');
  const html = esc(log).replace(/^(theme\/[A-Za-z0-9_]+\.zig):(\d+):(\d+):/gm, (all, file, l, c) =>
    file === `theme/${name}.zig` ? `<a href="#zigSrc" data-line="${l}" data-col="${c}">${file}:${l}:${c}</a>:` : all);
  el.innerHTML = html;
  el.hidden = false;
}
$('zigDiag').addEventListener('click', (e) => {
  const a = e.target.closest('a[data-line]');
  if (!a) return;
  e.preventDefault();
  const ta = $('zigSrc');
  const lines = ta.value.split('\n');
  const l = Math.min(lines.length, Number(a.dataset.line)) - 1;
  let off = 0;
  for (let i = 0; i < l; i++) off += lines[i].length + 1;
  off += Math.max(0, Number(a.dataset.col) - 1);
  ta.focus();
  ta.setSelectionRange(off, Math.min(ta.value.length, off + 1));
  const lh = parseFloat(getComputedStyle(ta).lineHeight) || 20;
  ta.scrollTop = Math.max(0, l * lh - ta.clientHeight / 2);
});

/// One 320x200 step + draw, timed (after a first one): how fast this build is, before the gates
/// spend 120 frames at 1920x1200 on it. undefined if it did not answer within 10 s.
async function speedProbe(m) {
  const { startEngine } = await import(new URL('wasm/engine.js', WEB));
  const eng = await startEngine({ module: m.module, threaded: false, threads: 1 });
  try {
    const run = (async () => {
      const { ptr } = await eng.leader.call('liveInit', { w: 320, h: 200, scale: 2 });
      if (!ptr) return null;
      await eng.leader.call('frame', { dt: 0.008, w: 320, h: 200, ptr });
      return (await eng.leader.call('frame', { dt: 0.008, w: 320, h: 200, ptr })).cpuMs;
    })();
    return await Promise.race([run, new Promise((res) => setTimeout(() => res(undefined), 10000))]);
  } catch { return null; } finally { eng.terminate(); }
}

const GATE_BUDGET_S = 90; // run the gates without asking when 120 frames at 1920x1200 take less

async function compileAndGrade(name, source, title) {
  if (busy) return;
  if (!source.trim()) { $('zigHint').textContent = 'Paste the model’s answer first, or drop a .zig file.'; $('zigSrc').focus(); return; }
  busy = true;
  resetZigResult(title ?? `${name}.zig`);
  const t0 = performance.now();
  let info = null, c = null;
  try {
    const { GATES } = await gatesLib();
    renderGates($('zigGates').tBodies[0], GATES.map((g) => ({ ...g, pass: null, detail: '…' })));
    phase('loading the compiler…');
    const zc = await zigc();
    info = await zc.ready;
    const tLoad = performance.now() - t0;
    c = await zc.compile(name, source, (p) => phase(p === 'sema' ? 'compiling: Gate 1, type-checking for a 64-bit target (wasm64)…' : 'compiling: building the module (wasm32, Zig’s wasm backend)…'));
    const extra = { compile: { loadMs: Math.round(tLoad), semaMs: Math.round(c.gate1.ms), buildMs: c.build ? Math.round(c.build.ms) : null, wasmKB: c.wasm ? Math.round(c.wasm.length / 1024) : null, cachedDownloads: info.cachedDownloads, downloadBytes: info.downloadBytes, restoredCacheFiles: info.restoredCacheFiles, ok: c.ok, gate1: c.gate1.ok } };
    window.__zigc = extra.compile;
    if (!c.gate1.ok) {
      const gates = GATES.map((g) => ({ ...g, pass: g.id === 1 ? false : null, detail: g.id === 1 ? `zig build-obj -fno-emit-bin -target wasm64-freestanding failed (${(c.gate1.ms / 1000).toFixed(1)} s):\n${c.gate1.log}` : 'not run' }));
      renderGates($('zigGates').tBodies[0], gates);
      showDiagnostics(c.gate1.log, name);
      badge($('zigBadge'), 'FAIL');
      phase(`Gate 1 failed: Zig 0.17.0’s own errors, as the native harness reports them · ${((performance.now() - t0) / 1000).toFixed(1)} s`);
      $('zigReport').textContent = `${c.gate1.log}\n\n${(await gatesLib()).reportText({ name, gates, variant: 'st', threads: 0 })}`;
      $('zigLiveCap').textContent = 'No live view: the theme does not compile.';
      window.__bench = { kind: 'zig', name, pass: false, gates: gates.map((g) => g.pass), text: $('zigReport').textContent, ...extra };
      busy = false;
      return;
    }
    const sema = `type-checks with Zig 0.17.0 in this page for wasm64 (64-bit usize, as aarch64-macos), ${(c.gate1.ms / 1000).toFixed(1)} s`;
    if (!c.ok) {
      const gates = GATES.map((g) => ({ ...g, pass: g.id === 1 ? true : null, detail: g.id === 1 ? sema : 'not run: this page’s compiler could not build it (see above)' }));
      renderGates($('zigGates').tBodies[0], gates);
      showDiagnostics(`This theme passes Gate 1, but Zig’s self-hosted wasm backend, the only one in this page’s compiler, could not build it. That is a limit of the browser build, not a verdict: the native harness (a pull request) builds it with LLVM.\n\n${c.build.log}`, name);
      badge($('zigBadge'), 'RUN'); $('zigBadge').textContent = 'NOT GRADED HERE';
      phase('Gate 1 passed; gates 2–8 need the native harness for this theme');
      $('zigReport').textContent = c.build.log;
      window.__bench = { kind: 'zig', name, pass: null, gates: gates.map((g) => g.pass), text: c.build.log, ...extra };
      busy = false;
      return;
    }
    const { moduleFromBytes } = await import(new URL('wasm/engine.js', WEB));
    const module = await moduleFromBytes(c.wasm);
    const gate1 = `${sema}; built wasm32-freestanding, ${(c.wasm.length / 1024).toFixed(0)} KB, in ${(c.build.ms / 1000).toFixed(1)} s (Zig’s wasm backend, no SIMD, 1 thread)`;
    renderGates($('zigGates').tBodies[0], GATES.map((g) => ({ ...g, pass: g.id === 1 ? true : null, detail: g.id === 1 ? gate1 : '…' })));
    phase('timing one frame at 320×200…');
    const ms320 = await speedProbe(module);
    // The live view renders as many pixels as this build draws in ~25 ms (at most 1920x1200).
    const maxPixels = ms320 > 0 ? Math.max(320 * 200, Math.min(1920 * 1200, Math.round(320 * 200 * 25 / ms320))) : undefined;
    const projected = ms320 > 0 ? ms320 * ((1920 * 1200) / (320 * 200)) * 121 / 1000 : 0;
    extra.compile.ms320 = ms320 ?? null;
    extra.compile.projectedGatesS = Math.round(projected);
    const grade = () => gradeZig(name, { module, gate1, inPage: true, maxPixels, extra, continuing: true });
    if (projected > GATE_BUDGET_S) {
      const mins = Math.ceil(projected / 60);
      const gates = GATES.map((g) => ({ ...g, pass: g.id === 1 ? true : null, detail: g.id === 1 ? gate1 : `not run yet: about ${mins} min in this build` }));
      renderGates($('zigGates').tBodies[0], gates);
      badge($('zigBadge'), 'RUN'); $('zigBadge').textContent = 'GATE 1 PASS';
      phase(`this build draws 320×200 in ${ms320.toFixed(0)} ms, so the gates’ 120 frames at 1920×1200 would take about ${mins} min here`);
      showDiagnostics(`Gates 2–8 are not run yet. This build draws a 320×200 frame in ${ms320.toFixed(0)} ms; the gates need 120 frames at 1920×1200, about ${mins} min here. Zig’s self-hosted wasm backend turns @Vector code into slow scalar code (Tutorial_Tides runs about 60× slower than LLVM’s wasm in Chrome), and natively this theme is far faster. The native harness grades it in seconds: submit a pull request, or run the gates here anyway.`, name);
      $('zigDiag').style.borderLeftColor = 'var(--warn)';
      $('zigMore').hidden = false;
      $('zigGatesAnyway').textContent = `Run the gates here anyway (about ${mins} min)`;
      $('zigGatesAnyway').onclick = () => { if (busy) return; stopLive(); $('zigFull').hidden = true; $('zigMore').hidden = true; $('zigDiag').hidden = true; busy = true; grade(); };
      $('zigFinalCap').textContent = 'No gate frame yet: the gates have not run.';
      window.__bench = { kind: 'zig', name, pass: null, gates: gates.map((g) => g.pass), deferred: true, ...extra };
      busy = false;
      await startZigLive(name, { module, inPage: true, maxPixels });
      return;
    }
    await grade();
  } catch (e) {
    badge($('zigBadge'), 'FAIL');
    $('zigReport').textContent = `ERROR: ${e.message ?? e}`;
    phase('the in-page compiler failed');
    window.__bench = { kind: 'zig', name, error: String(e.message ?? e) };
    busy = false;
  }
}

$('zigCompile').addEventListener('click', () => compileAndGrade(zigName(), $('zigSrc').value));
$('zigSrc').addEventListener('focus', warm, { once: true });
$('zigSrc').addEventListener('keydown', (e) => { if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) { e.preventDefault(); compileAndGrade(zigName(), $('zigSrc').value); } });

/// A .zig file: into the editor, then compiled. A .wasm: graded as an upload.
async function takeFile(file) {
  if (!file) return;
  if (/\.wasm$/i.test(file.name)) return gradeUpload(file);
  const { themeName } = await import(new URL('zigc/zigc.js', WEB));
  const name = themeName(file.name);
  const src = await file.text();
  showTab('tab-zig');
  $('zigName').value = name;
  $('zigName').dispatchEvent(new Event('input'));
  $('zigSrc').value = src;
  return compileAndGrade(name, src, file.name);
}
$('zigFile').addEventListener('change', (e) => { takeFile(e.target.files[0]); e.target.value = ''; });
$('wasmFile').addEventListener('change', (e) => { gradeUpload(e.target.files[0]); e.target.value = ''; });

// Drop anywhere on the page.
const dropAll = $('dropAll');
let dragDepth = 0;
const hasFiles = (e) => [...(e.dataTransfer?.types || [])].includes('Files');
document.addEventListener('dragenter', (e) => { if (!hasFiles(e)) return; dragDepth++; dropAll.classList.add('on'); warm(); });
document.addEventListener('dragleave', (e) => { if (!hasFiles(e)) return; if (--dragDepth <= 0) { dragDepth = 0; dropAll.classList.remove('on'); } });
document.addEventListener('dragover', (e) => { if (hasFiles(e)) e.preventDefault(); });
document.addEventListener('drop', (e) => {
  if (!hasFiles(e)) return;
  e.preventDefault();
  dragDepth = 0; dropAll.classList.remove('on');
  takeFile(e.dataTransfer.files[0]);
});

// Paste anywhere: Zig source pasted outside a field, or into the empty editor, compiles at once.
const looksLikeZig = (s) => /@import\s*\(|\bexport\s+fn\b|\bpub\s+fn\b|\bconst\s+std\b/.test(s);
document.addEventListener('paste', (e) => {
  const text = e.clipboardData?.getData('text/plain') || '';
  const t = e.target;
  const inField = t instanceof HTMLElement && (t.closest('input, textarea, select, [contenteditable]'));
  if (inField && t !== $('zigSrc')) return;
  if (!looksLikeZig(text)) return;
  if (t === $('zigSrc')) {
    if ($('zigSrc').value.trim()) return; // editing an existing source: the user compiles
    setTimeout(() => compileAndGrade(zigName(), $('zigSrc').value), 0);
    return;
  }
  e.preventDefault();
  showTab('tab-zig');
  $('zigSrc').value = text;
  compileAndGrade(zigName(), text);
});

// ---- Zig: a pasted source -------------------------------------------------------------------
const zigName = () => ($('zigName').value.trim().replace(/\.zig$/, '').replace(/[^A-Za-z0-9_]/g, '_') || 'Model_Theme');
$('zigName').addEventListener('input', () => { for (const el of [$('zigNameEcho'), ...document.querySelectorAll('.nameEcho')]) el.textContent = zigName(); });
$('zigPR').addEventListener('click', async (e) => {
  const src = $('zigSrc').value;
  if (!src.trim()) { $('zigHint').textContent = 'Paste the model’s answer first, or drop a .zig file.'; return; }
  await copyText(src, e.currentTarget);
  const u = new URL(`https://github.com/${REPO}/new/main`);
  u.searchParams.set('filename', `bench/submissions/${zigName()}.zig`);
  window.open(u.href, '_blank', 'noopener');
  $('zigHint').textContent = 'The source is on your clipboard: paste it into GitHub’s editor, then “Propose changes”. GitHub forks the repository for you if needed.';
});
$('zigCmd').addEventListener('click', (e) => {
  const n = zigName();
  copyText([
    'git clone https://github.com/gke0op/argus.git && cd argus && make zig',
    `# save the answer as themes/${n}.zig, then:`,
    `make harness THEME=themes/${n}.zig OUT=/tmp/${n}.png   # the native harness: the verdict`,
    `make web-wasm THEME=themes/${n}.zig                      # web/wasm/build/${n}.{st,mt}.wasm, to upload here`,
  ].join('\n'), e.currentTarget);
});

// ---- WGSL -----------------------------------------------------------------------------------
$('wgslExample').addEventListener('change', async () => {
  const v = $('wgslExample').value;
  if (!v) return;
  $('wgslSrc').value = await text(new URL(v, location.href));
  $('wgslName').value = v.replace(/^.*\//, '').replace(/\.wgsl$/, '');
});
let harnessMod = null;
$('runWgsl').addEventListener('click', async () => {
  if (busy) return;
  const src = $('wgslSrc').value;
  if (!src.trim()) { $('wgslSrc').focus(); return; }
  if (!gpu.ok) { $('wgslResult').classList.add('on'); badge($('wgslBadge'), 'FAIL'); $('wgslReport').textContent = `No WebGPU in this browser: ${gpu.why}`; return; }
  busy = true;
  stopLive();
  const name = $('wgslName').value.trim().replace(/[^A-Za-z0-9_]/g, '_') || 'Model_Theme';
  $('wgslResult').classList.add('on');
  badge($('wgslBadge'), 'RUNNING');
  $('wgslTitle').textContent = `${name}.wgsl`;
  $('wgslReport').textContent = '';
  $('wgslLiveCap').textContent = 'Live, after the checks.';
  drawFinal($('wgslFinal'), null);
  $('wgslResult').scrollIntoView({ behavior: 'smooth', block: 'start' });
  const t0 = performance.now();
  try {
    harnessMod ??= await import('./wgsl-harness.js');
    renderGates($('wgslGates').tBodies[0], harnessMod.GATES.map((g) => ({ ...g, pass: null, detail: '…' })));
    const res = await harnessMod.runWgslHarness(src, { name, onPhase: (p) => { $('wgslPhase').textContent = p; } });
    const secs = ((performance.now() - t0) / 1000).toFixed(1);
    renderGates($('wgslGates').tBodies[0], res.gates);
    badge($('wgslBadge'), res.pass ? 'PASS' : 'FAIL');
    $('wgslPhase').textContent = `graded in ${secs} s${res.runError ? ` · run failed: ${res.runError}` : ''}`;
    $('wgslReport').textContent = res.text;
    drawFinal($('wgslFinal'), res.last, res.width, res.height);
    window.__bench = { kind: 'wgsl', name, pass: res.pass, gates: res.gates.map((g) => g.pass), text: res.text, secs: Number(secs), gpu: res.gpu };
    if (res.gates[0]?.pass && !res.runError) {
      await runLive($('wgslLive'), $('wgslLiveCap'), { id: `bench:${name}`, label: name, kind: 'wgsl-source', source: src }, {});
    } else $('wgslLiveCap').textContent = 'No live view: the theme did not compile or run.';
  } catch (e) {
    badge($('wgslBadge'), 'FAIL');
    $('wgslReport').textContent = `ERROR: ${e.message ?? e}`;
    window.__bench = { kind: 'wgsl', name, error: String(e.message ?? e) };
  } finally { busy = false; }
});

// For web/zigc/verify.html, which drives this page in a frame.
window.__benchReady = true;
