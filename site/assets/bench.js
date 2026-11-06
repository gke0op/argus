// site/assets/bench.js: the "Run ARGUS-BENCH" page.
//   Zig: prebuilt wasm (the skeleton, the gate fixtures) or an uploaded build through the 8 gates
//        (web/wasm/gates.js, the native harness's gate code in the module); a pasted .zig goes to
//        a pull request (the bench workflow runs the native harness) or to the local commands.
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
    const st = g.pass === null || g.pass === undefined ? ['skip', 'not run'] : g.pass ? ['pass', 'PASS'] : ['fail', 'FAIL'];
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
async function runLive(stage, cap, theme, extra) {
  live?.stop(); live = null;
  cap.textContent = 'Starting live…';
  try {
    live = await mount(stage, theme, extra);
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

// ---- Zig: prebuilt and uploaded builds ------------------------------------------------------
let gatesMod = null;
const gatesLib = async () => (gatesMod ??= await import(new URL('wasm/gates.js', WEB)));
let busy = false;

async function gradeZig(name, opts = {}) {
  if (busy) return;
  busy = true;
  live?.stop(); live = null;
  $('zigResult').classList.add('on');
  badge($('zigBadge'), 'RUNNING');
  $('zigTitle').textContent = opts.title ?? name;
  $('zigReport').textContent = '';
  $('zigGates').tBodies[0].innerHTML = '';
  $('zigLiveCap').textContent = 'Live, after the gates.';
  drawFinal($('zigFinal'), null);
  $('zigResult').scrollIntoView({ behavior: 'smooth', block: 'start' });
  const t0 = performance.now();
  try {
    const { runGates, GATES } = await gatesLib();
    renderGates($('zigGates').tBodies[0], GATES.map((g) => ({ ...g, pass: null, detail: '…' })));
    $('zigPhase').textContent = 'watchdog 320x200';
    const res = await runGates(name, { base: new URL('wasm/build/', WEB), module: opts.module, onPhase: (p) => { $('zigPhase').textContent = p; } });
    const secs = ((performance.now() - t0) / 1000).toFixed(1);
    renderGates($('zigGates').tBodies[0], res.gates);
    badge($('zigBadge'), res.pass ? 'PASS' : 'FAIL');
    $('zigPhase').textContent = `graded in ${secs} s · ${res.threads || 1} thread${res.threads === 1 ? '' : 's'} (${res.variant || '–'})`;
    $('zigReport').textContent = res.text;
    drawFinal($('zigFinal'), res.pixels, res.width, res.height);
    window.__bench = { kind: 'zig', name, pass: res.pass, gates: res.gates.map((g) => g.pass), text: res.text, secs: Number(secs) };
    if (res.pixels && !res.timedOut) await runLive($('zigLive'), $('zigLiveCap'), { id: `bench:${name}`, label: name, kind: 'wasm', build: name }, { module: opts.module });
    else $('zigLiveCap').textContent = 'No live view: the theme did not get through its frames.';
  } catch (e) {
    badge($('zigBadge'), 'FAIL');
    $('zigReport').textContent = `ERROR: ${e.message ?? e}`;
    window.__bench = { kind: 'zig', name, error: String(e.message ?? e) };
  } finally { busy = false; }
}

$('zigBuild').addEventListener('change', () => { $('buildSrc').href = `zig/${$('zigBuild').value}.zig`; });
$('runBuild').addEventListener('click', () => gradeZig($('zigBuild').value));

async function gradeUpload(file) {
  if (!file) return;
  const { moduleFromBytes } = await import(new URL('wasm/engine.js', WEB));
  const name = file.name.replace(/\.(mt|st)?\.?wasm$/, '').replace(/[^A-Za-z0-9_]/g, '_') || 'Upload';
  try {
    const module = await moduleFromBytes(new Uint8Array(await file.arrayBuffer()));
    await gradeZig(name, { module, title: `${file.name} (uploaded)` });
  } catch (e) {
    $('zigResult').classList.add('on');
    badge($('zigBadge'), 'FAIL');
    $('zigTitle').textContent = file.name;
    $('zigReport').textContent = `Gate 1: this file is not a module the page can run: ${e.message ?? e}`;
  }
}
$('wasmFile').addEventListener('change', (e) => gradeUpload(e.target.files[0]));
const drop = $('drop');
drop.addEventListener('dragover', (e) => { e.preventDefault(); drop.classList.add('over'); });
drop.addEventListener('dragleave', () => drop.classList.remove('over'));
drop.addEventListener('drop', (e) => { e.preventDefault(); drop.classList.remove('over'); gradeUpload(e.dataTransfer.files[0]); });

// ---- Zig: a pasted source -------------------------------------------------------------------
const zigName = () => ($('zigName').value.trim().replace(/\.zig$/, '').replace(/[^A-Za-z0-9_]/g, '_') || 'Model_Theme');
$('zigName').addEventListener('input', () => { for (const el of [$('zigNameEcho'), ...document.querySelectorAll('.nameEcho')]) el.textContent = zigName(); });
$('zigPR').addEventListener('click', async (e) => {
  const src = $('zigSrc').value;
  if (!src.trim()) { $('zigHint').textContent = 'Paste the model’s answer first.'; return; }
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
  live?.stop(); live = null;
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
