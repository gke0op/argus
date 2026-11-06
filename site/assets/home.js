// site/assets/home.js: the live hero (theme picker, telemetry), copy buttons, the sortable
// leaderboard.
import { THEMES, byId, mount, probeWebGPU } from './engines.js';
import { sortable, copyButtons } from './ui.js';

const $ = (id) => document.getElementById(id);
const stage = $('stage'), picker = $('picker'), caption = $('caption'), teleBody = $('teleBody'), poster = $('poster');
const hero = $('hero');
const q = new URLSearchParams(location.search);

copyButtons();
document.querySelectorAll('table.lb').forEach(sortable);

// Solid top bar once the hero is scrolled past.
new IntersectionObserver(([e]) => document.body.classList.toggle('solid', !e.isIntersecting), { rootMargin: '-60px 0px 0px 0px' }).observe(hero);

let gpu = { ok: false, why: 'checking' };
let current = null;   // the mounted handle
let loading = null;   // id being loaded
let half = q.get('res') === 'half';
let note = '', err = '';
let firstFrameMs = null;

function chips() {
  picker.textContent = '';
  for (const t of THEMES) {
    if (t.fallbackOnly && gpu.ok) continue;
    const b = document.createElement('button');
    b.type = 'button';
    b.className = 'chip';
    b.dataset.id = t.id;
    b.innerHTML = `${t.label}${t.tag ? ` <small>${t.tag}</small>` : ''}`;
    if (t.kind !== 'wasm' && !gpu.ok) { b.disabled = true; b.title = 'Needs WebGPU'; }
    b.addEventListener('click', () => select(t.id));
    picker.append(b);
  }
}

function mark(id) {
  for (const b of picker.querySelectorAll('.chip')) b.setAttribute('aria-pressed', String(b.dataset.id === id));
  const t = byId(id);
  caption.innerHTML = t ? `<b>${t.label}${t.tag ? ` (${t.tag})` : ''}</b> · ${t.line} <a href="https://github.com/gke0op/argus/blob/main/${t.src}"><code>${t.src}</code></a>` : '';
}

async function select(id, { replace = false } = {}) {
  const t = byId(id);
  if (!t || loading === id) return;
  if (t.kind !== 'wasm' && !gpu.ok) return;
  loading = id;
  mark(id);
  note = ''; err = '';
  const u = new URL(location.href);
  u.searchParams.set('theme', id);
  history[replace ? 'replaceState' : 'pushState'](null, '', u);
  current?.stop();
  current = null;
  try {
    const h = await mount(stage, t, {
      scale: (globalThis.devicePixelRatio || 1) * (half ? 0.5 : 1),
      // performance.now() is time since navigation start: the page's time to first frame.
      onFirstFrame: () => { if (firstFrameMs === null) firstFrameMs = performance.now(); poster.style.opacity = '0'; },
      onError: (e) => { err = String(e.message ?? e); },
    });
    if (loading !== id) { h.stop(); return; }
    current = h;
    h.setPaused(!visible);
    if (t.kind === 'wasm' && !crossOriginIsolated) {
      note = 'One thread: this page is not cross-origin isolated, so wasm threads are off.';
      // Threads need isolation: ask for it now (a service worker, then one reload back to this
      // theme). If the browser refuses, the theme stays on one thread with this note.
      if (!replace || q.get('theme') === id) enableThreads();
    }
  } catch (e) {
    err = `${t.label}: ${e.message ?? e}`;
    console.error(e);
  } finally {
    if (loading === id) loading = null;
  }
}

const f = (x, d = 2) => (x == null || !Number.isFinite(x) ? '–' : x.toFixed(d));
function row(k, v, cls = '') { return `<div class="row ${cls}"><span class="k">${k}</span><span class="v">${v}</span></div>`; }

function tele() {
  let html = '';
  if (current) {
    const r = current.readout();
    html += row('engine', r.engine);
    if (r.kind === 'wasm') {
      html += row('CPU / frame', `${f(r.cpuMs)} ms`);
      html += row('blit', `${f(r.blitMs)} ms`, 'wide');
      html += row('wasm', `${f(r.wasmKB, 1)} KB · ${r.variant ?? '–'}`);
      html += row('threads', `${r.threads ?? '–'}${r.isolated ? '' : ' (not isolated)'}`);
      html += row('render', `${r.width}×${r.height}${r.width !== r.canvasW ? ` → ${r.canvasW}×${r.canvasH}` : ''}`, 'wide');
    } else {
      html += row('GPU / frame', r.gpuMs == null ? 'n/a here' : `${f(r.gpuMs)} ms`);
      html += row('CPU / frame', `${f(r.cpuMs)} ms`);
      if (r.kind === 'cygnus') {
        html += row('wasm', `${r.wasmKB ?? '–'} KB · 1 thread`);
        html += row('trace', r.traceMs == null ? `${r.rowsDone ?? 0} / ${r.traceH ?? '–'} rows` : `${f(r.traceMs / 1000)} s`);
      } else {
        html += row('wasm', 'none');
      }
      html += row('size', `${r.width}×${r.height}`, 'wide');
    }
    html += row('display', `${f(r.hz, 0)} Hz`);
    if (firstFrameMs != null) html += row('first frame', `${f(firstFrameMs, 0)} ms`, 'wide');
    if (r.kind === 'wgsl' && r.gpuMs == null && r.cpuMs != null && current.engine.stats().frame > 60) note ||= 'No timestamp-query here, so GPU time is not measured.';
    if (r.statsSources && !r.statsSources.all) note ||= 'In the app these are your Mac’s; a browser knows only a few about itself.';
  } else if (loading) {
    html += row('engine', 'loading…');
  }
  if (!gpu.ok && gpu.why !== 'checking') html += `<div class="note">No WebGPU: ${gpu.why}. The GPU themes need it (Chrome or Edge 113+, Safari 26+); the Zig themes compiled to wasm run here instead.</div>`;
  if (note) html += `<div class="note">${note}${note.startsWith('One thread') ? ' <button type="button" id="isoBtn">reload with threads</button>' : ''}</div>`;
  if (err) html += `<div class="err">${err.replace(/&/g, '&amp;').replace(/</g, '&lt;')}</div>`;
  teleBody.innerHTML = html;
  if (current) {
    const r = current.readout();
    const ms = r.kind === 'wasm' ? `CPU ${f(r.cpuMs)} ms · ${r.threads ?? 1}T` : `GPU ${r.gpuMs == null ? 'n/a' : f(r.gpuMs) + ' ms'}`;
    $('teleSum').textContent = `${ms} · ${f(r.hz, 0)} Hz`;
  }
  $('isoBtn')?.addEventListener('click', enableThreads);
}
setInterval(tele, 500);

// Cross-origin isolation for wasm threads: coi-serviceworker.js registers a service worker that
// adds COOP/COEP (GitHub Pages can't send headers) and reloads once. Only on request here, so the
// first visit to the home page never reloads before its first frame.
function enableThreads() {
  const s = document.createElement('script');
  s.src = new URL('../coi-serviceworker.js', import.meta.url).href;
  document.head.append(s);
}

$('bareBtn').addEventListener('click', () => hero.classList.toggle('bare'));
// Narrow screens: the readout starts folded to one line, so it never covers the caption.
if (matchMedia('(max-width: 640px)').matches) { $('tele').classList.add('min'); $('teleBtn').textContent = '+'; }
$('teleBtn').addEventListener('click', () => { $('tele').classList.toggle('min'); $('teleBtn').textContent = $('tele').classList.contains('min') ? '+' : '–'; });
$('resBtn').textContent = half ? 'half res' : 'native res';
$('resBtn').addEventListener('click', () => {
  half = !half;
  $('resBtn').textContent = half ? 'half res' : 'native res';
  const u = new URL(location.href);
  half ? u.searchParams.set('res', 'half') : u.searchParams.delete('res');
  history.replaceState(null, '', u);
  const id = current?.theme.id;
  if (id) { loading = null; select(id, { replace: true }); }
});
addEventListener('keydown', (e) => {
  if (e.target.closest?.('input, textarea, select') || e.metaKey || e.ctrlKey || e.altKey) return;
  if (e.key === 'h') hero.classList.toggle('bare');
});
addEventListener('popstate', () => { const id = new URLSearchParams(location.search).get('theme'); if (id && id !== current?.theme.id) select(id, { replace: true }); });
// A hidden hero costs GPU for nothing: pause it while scrolled away or the tab is hidden.
let visible = true;
new IntersectionObserver(([e]) => { visible = e.isIntersecting; current?.setPaused(!visible); }).observe(hero);

gpu = await probeWebGPU();
chips();
const want = q.get('theme');
const first = (want && byId(want) && (gpu.ok || byId(want).kind === 'wasm')) ? want : gpu.ok ? 'Cygnus_A' : 'Tutorial_Tides_wasm';
tele();
await select(first, { replace: true });
window.__site = { current: () => current, firstFrameMs: () => firstFrameMs, gpu: () => gpu, visible: () => visible };
