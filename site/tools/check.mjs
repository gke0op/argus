// site/tools/check.mjs: check the assembled site in headless Chrome, as a visitor would get it.
//
//   site/build.sh _site && zig run site/tools/serve.zig -- _site 8136 &
//   node site/tools/check.mjs --url http://127.0.0.1:8136/argus/ --out /tmp/site-check [--only home|bench|phone|nogpu]
//
// The same CDP plumbing as web/host/tools/verify.mjs (Node 22+, no dependencies). It checks:
//   home   a fresh profile's first visit: bytes loaded and time to the first frame; then every
//          theme in the picker runs (engine, size, GPU/CPU ms) with a screenshot of each
//   bench  the service worker isolates the page (one reload); the BENCHMARK.md skeleton PASSes
//          and each gate fixture FAILs its gate, in wasm; Tutorial_Tides.wgsl PASSes and the WGSL
//          fixtures FAIL, on WebGPU
//   phone  390x844 at 3x (iPhone-sized, touch): no horizontal overflow, screenshots
//   nogpu  navigator.gpu removed: the home page falls back to the wasm themes with a note
// Prints one JSON report and writes it, with the screenshots, to --out.
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const args = Object.fromEntries(process.argv.slice(2).reduce((acc, a, i, all) => {
  if (a.startsWith('--')) acc.push([a.slice(2), all[i + 1] && !all[i + 1].startsWith('--') ? all[i + 1] : true]);
  return acc;
}, []));
const BASE = String(args.url ?? 'http://127.0.0.1:8136/argus/');
const OUT = String(args.out ?? path.join(os.tmpdir(), 'argus-site-check'));
const ONLY = args.only ? String(args.only).split(',') : ['home', 'bench', 'phone', 'nogpu'];
const CHROME = process.env.CHROME ?? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
fs.mkdirSync(OUT, { recursive: true });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const say = (...a) => console.error(`[${new Date().toISOString().slice(11, 19)}]`, ...a);

async function browser() {
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'argus-site-chrome-'));
  const chrome = spawn(CHROME, [
    '--headless=new', '--enable-unsafe-webgpu', '--enable-webgpu-developer-features',
    '--remote-debugging-port=0', `--user-data-dir=${profile}`, '--no-first-run', '--no-default-browser-check',
    '--disable-background-timer-throttling', '--disable-renderer-backgrounding', '--disable-backgrounding-occluded-windows', 'about:blank',
  ], { stdio: ['ignore', 'ignore', 'pipe'] });
  let wsUrl = null;
  for (let i = 0; i < 600 && !wsUrl; i++) {
    try {
      const [p] = fs.readFileSync(path.join(profile, 'DevToolsActivePort'), 'utf8').split('\n');
      const list = await (await fetch(`http://127.0.0.1:${p}/json`)).json();
      wsUrl = list.find((t) => t.type === 'page')?.webSocketDebuggerUrl ?? null;
    } catch { /* not up yet */ }
    if (!wsUrl) await sleep(100);
  }
  if (!wsUrl) throw new Error('Chrome did not start');
  const ws = new WebSocket(wsUrl);
  await new Promise((r, j) => { ws.onopen = r; ws.onerror = j; });
  let nextId = 0;
  const pending = new Map();
  const listeners = [];
  const log = [];
  ws.onmessage = (ev) => {
    const m = JSON.parse(ev.data);
    if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); return; }
    if (m.method === 'Runtime.consoleAPICalled') log.push(`${m.params.type}: ${m.params.args.map((a) => a.value ?? a.description).join(' ')}`);
    if (m.method === 'Runtime.exceptionThrown') log.push(`exception: ${m.params.exceptionDetails.exception?.description ?? m.params.exceptionDetails.text}`);
    for (const f of listeners) f(m);
  };
  const send = (method, params = {}, ms = 30000) => new Promise((r) => {
    const id = ++nextId;
    const timer = setTimeout(() => { pending.delete(id); r({ timeout: true }); }, ms);
    pending.set(id, (m) => { clearTimeout(timer); r(m); });
    ws.send(JSON.stringify({ id, method, params }));
  });
  const evaluate = async (expr, ms = 30000) => {
    const r = await send('Runtime.evaluate', { expression: expr, returnByValue: true, awaitPromise: true }, ms);
    if (r.result?.exceptionDetails) throw new Error(r.result.exceptionDetails.exception?.description ?? r.result.exceptionDetails.text);
    return r.result?.result?.value;
  };
  const waitFor = async (expr, ms = 60000, every = 200) => {
    const t = Date.now();
    while (Date.now() - t < ms) {
      try { const v = await evaluate(expr, 5000); if (v) return v; } catch { /* page navigating */ }
      await sleep(every);
    }
    return null;
  };
  const shot = async (file) => {
    say('  shot', file);
    const s = await send('Page.captureScreenshot', { format: 'jpeg', quality: 85 }, 60000);
    say('  shot', s.timeout ? 'timed out' : 'ok');
    if (s.result?.data) fs.writeFileSync(path.join(OUT, file.replace(/\.png$/, '.jpg')), Buffer.from(s.result.data, 'base64'));
  };
  const nav = async (url) => { await send('Page.navigate', { url }); await sleep(300); };
  await send('Runtime.enable');
  await send('Page.enable');
  await send('Network.enable');
  return {
    send, evaluate, waitFor, shot, nav, listeners, log,
    close() { try { ws.close(); chrome.kill(); } catch { /* gone */ } setTimeout(() => fs.rmSync(profile, { recursive: true, force: true }), 800); },
  };
}

const report = { base: BASE, at: new Date().toISOString(), host: `${os.cpus()[0]?.model} · load ${os.loadavg().map((x) => x.toFixed(1)).join(' ')}` };
const desktop = { width: 1512, height: 982, deviceScaleFactor: 2, mobile: false };

// ---- home: first visit, then every theme ------------------------------------------------------
if (ONLY.includes('home')) {
  const b = await browser();
  await b.send('Emulation.setDeviceMetricsOverride', desktop);
  const bytes = new Map();
  b.listeners.push((m) => {
    if (m.method === 'Network.responseReceived') bytes.set(m.params.requestId, { url: m.params.response.url, len: 0, t: m.params.timestamp });
    if (m.method === 'Network.loadingFinished' && bytes.has(m.params.requestId)) bytes.get(m.params.requestId).len = m.params.encodedDataLength;
  });
  await b.nav(BASE);
  const ffMs = await b.waitFor('window.__site?.firstFrameMs()', 60000, 50);
  const atFirst = [...bytes.values()].map((x) => ({ ...x }));
  await b.waitFor('(() => { const r = window.__site?.current()?.readout(); return r && r.traceMs != null; })()', 90000);
  const cyg = await b.evaluate('window.__site.current().readout()');
  await b.shot('home-cygnus.png');
  const files = [...bytes.values()];
  report.home = {
    firstFrameMs: ffMs, cygnus: cyg,
    bytesAtFirstFrame: atFirst.reduce((s, x) => s + x.len, 0), requestsAtFirstFrame: atFirst.length,
    bytesTotal: files.reduce((s, x) => s + x.len, 0), requestsTotal: files.length,
    files: files.map((x) => `${x.len}\t${x.url.replace(BASE, '')}`),
    themes: [],
  };
  const all = await b.evaluate('[...document.querySelectorAll("#picker .chip")].map((c) => c.dataset.id)');
  const ids = args.themes ? all.filter((id) => String(args.themes).split(',').includes(id)) : all;
  // Each theme on its own page load (?theme=), as a shared link opens it; up to 3 minutes each:
  // a cold shader cache makes the big WGSL themes' first build slow (Roulette_Chrome: 19 s).
  const ready = (id) => `(() => { const c = window.__site?.current(); if (!c || c.theme.id !== '${id}') return false; const r = c.readout(); return r.hz > 0 && (r.gpuMs != null || r.cpuMs != null) && (r.kind !== 'cygnus' || r.traceMs != null); })()`;
  b.close();
  for (const id of ids) {
    say('theme', id);
    // A fresh browser per theme: one tab reused across the heavy themes stopped producing
    // frames in headless Chrome (a harness artefact; a fresh browser runs each one cleanly).
    const tb = await browser();
    await tb.send('Emulation.setDeviceMetricsOverride', desktop);
    const t = Date.now();
    await tb.nav(`${BASE}?theme=${id}`);
    say('  nav done');
    const ok = await tb.waitFor(ready(id), 180000, 300);
    say('  ready', !!ok);
    await sleep(2500);
    const r = await tb.evaluate(`(() => { const c = window.__site?.current(); return c && c.theme.id === '${id}' ? c.readout() : null; })()`);
    const err = await tb.evaluate('document.querySelector("#teleBody .err")?.textContent ?? null');
    const ff = await tb.evaluate('window.__site?.firstFrameMs() ?? null');
    await tb.shot(`theme-${id}.png`);
    tb.close();
    report.home.themes.push({ id, ok: !!ok && !err, err, readyS: (Date.now() - t) / 1000, firstFrameMs: ff, engine: r?.engine, size: r ? `${r.width}x${r.height}` : null, gpuMs: r?.gpuMs, cpuMs: r?.cpuMs, hz: r?.hz, threads: r?.threads, wasmKB: r?.wasmKB, isolated: r?.isolated });
  }
  // The picker itself: switch three engines on one page by clicking.
  const pb = await browser();
  await pb.send('Emulation.setDeviceMetricsOverride', desktop);
  await pb.nav(`${BASE}?theme=Cygnus_A`);
  await pb.waitFor(ready('Cygnus_A'), 60000);
  report.home.picker = [];
  for (const id of ['Night_Tide', 'Tutorial_Tides_wasm', 'Ebru_Studio']) {
    await pb.evaluate(`document.querySelector('#picker .chip[data-id="${id}"]').click(), true`);
    const ok = await pb.waitFor(ready(id), 120000, 300);
    const url = await pb.evaluate('location.search');
    report.home.picker.push({ id, ok: !!ok, url, pressed: await pb.evaluate('document.querySelector(".chip[aria-pressed=true]")?.dataset.id') });
  }
  report.home.log = [...b.log.slice(-10), ...pb.log.slice(-10)];
  pb.close();
  b.close();
}

// ---- bench ---------------------------------------------------------------------------------
if (ONLY.includes('bench')) {
  const b = await browser();
  await b.send('Emulation.setDeviceMetricsOverride', desktop);
  await b.nav(`${BASE}bench/`);
  const iso = await b.waitFor('crossOriginIsolated', 15000);
  report.bench = { isolated: !!iso, zig: [], wgsl: [] };
  await b.waitFor('document.readyState === "complete" && !!document.getElementById("runBuild")', 15000);
  await sleep(500);
  const zigCases = [
    ['Bench_Skeleton', true, []], ['Gate0_Control', true, []], ['Gate1_Compile', false, [1]], ['Gate2_Alloc', false, [2]],
    ['Gate3_Watchdog', false, [3]], ['Gate4_Stride', false, [3, 4]], ['Gate5_Alpha', false, [5]], ['Gate6_Frozen', false, [6]],
    ['Gate7_NaN', false, [7]], ['Gate8_Budget', false, [8]], ['Fixture_Hang', false, [3]], ['Tutorial_Tides', null, []],
  ];
  for (const [name, expectPass, expectFail] of zigCases) {
    say('zig', name);
    await b.evaluate(`window.__bench = null; document.getElementById('zigBuild').value = '${name}'; document.getElementById('runBuild').click(), true`);
    const r = await b.waitFor(`window.__bench && window.__bench.name === '${name}' ? window.__bench : null`, 120000, 250);
    const failed = r?.gates ? r.gates.map((g, i) => (g === false ? i + 1 : 0)).filter(Boolean) : null;
    const asExpected = r && (expectPass === null || r.pass === expectPass) && (expectPass !== false || JSON.stringify(failed) === JSON.stringify(expectFail));
    report.bench.zig.push({ name, pass: r?.pass, failedGates: failed, asExpected, secs: r?.secs, verdictLine: r?.text?.split('\n').find((l) => l.includes('Verdict')), avgLine: r?.text?.split('\n').find((l) => l.includes('Avg Frame')), error: r?.error });
    if (name === 'Bench_Skeleton' || name === 'Gate7_NaN') { await sleep(1500); await b.evaluate('document.getElementById("zigResult").scrollIntoView(), true'); await b.shot(`bench-zig-${name}.png`); }
  }
  await b.evaluate('document.getElementById("tab-wgsl").click(), true');
  const wgslCases = [
    ['../web/themes/Tutorial_Tides.wgsl', true, []], ['../web/themes/Tutorial_Reef.wgsl', true, []], ['fixtures/Fixture_Compile.wgsl', false, [1]],
    ['fixtures/Fixture_NaN.wgsl', false, [3]], ['fixtures/Fixture_Frozen.wgsl', false, [5]], ['fixtures/Fixture_Budget.wgsl', false, [6]],
  ];
  for (const [file, expectPass, expectFail] of wgslCases) {
    const name = file.replace(/^.*\//, '').replace('.wgsl', '');
    say('wgsl', name);
    await b.evaluate(`(async () => { window.__bench = null; const s = document.getElementById('wgslExample'); s.value = '${file}'; s.dispatchEvent(new Event('change')); for (let i = 0; i < 50 && document.getElementById('wgslName').value !== '${name}'; i++) await new Promise((r) => setTimeout(r, 100)); await new Promise((r) => setTimeout(r, 300)); document.getElementById('runWgsl').click(); return true; })()`);
    const r = await b.waitFor(`window.__bench && window.__bench.name === '${name}' ? window.__bench : null`, 180000, 250);
    const failed = r?.gates ? r.gates.map((g, i) => (g === false ? i + 1 : 0)).filter(Boolean) : null;
    const asExpected = r && r.pass === expectPass && (expectPass || JSON.stringify(failed) === JSON.stringify(expectFail));
    report.bench.wgsl.push({ name, pass: r?.pass, failedGates: failed, asExpected, secs: r?.secs, gpu: r?.gpu, verdictLine: r?.text?.split('\n').find((l) => l.includes('Verdict')), error: r?.error });
    if (name === 'Tutorial_Tides' || name === 'Fixture_Compile') { await sleep(2000); await b.evaluate('document.getElementById("wgslResult").scrollIntoView(), true'); await b.shot(`bench-wgsl-${name}.png`); }
  }
  report.bench.log = b.log.slice(-20);
  b.close();
}

// ---- phone ---------------------------------------------------------------------------------
if (ONLY.includes('phone')) {
  const b = await browser();
  await b.send('Emulation.setDeviceMetricsOverride', { width: 390, height: 844, deviceScaleFactor: 3, mobile: true });
  await b.send('Emulation.setTouchEmulationEnabled', { enabled: true, maxTouchPoints: 5 });
  await b.nav(BASE);
  await b.waitFor('window.__site?.firstFrameMs()', 60000);
  await sleep(4000);
  const home = await b.evaluate('({ overflow: document.scrollingElement.scrollWidth - innerWidth, readout: window.__site.current()?.readout() })');
  await b.shot('phone-home.png');
  await b.evaluate('document.getElementById("bench").scrollIntoView(), true');
  await sleep(500);
  await b.shot('phone-leaderboard.png');
  await b.nav(`${BASE}bench/`);
  await b.waitFor('document.getElementById("runBuild")', 15000);
  await sleep(1500);
  const bench = await b.evaluate('({ overflow: document.scrollingElement.scrollWidth - innerWidth })');
  await b.shot('phone-bench.png');
  report.phone = { home, bench };
  b.close();
}

// ---- no WebGPU -----------------------------------------------------------------------------
if (ONLY.includes('nogpu')) {
  const b = await browser();
  await b.send('Emulation.setDeviceMetricsOverride', desktop);
  await b.send('Page.addScriptToEvaluateOnNewDocument', { source: 'Object.defineProperty(Navigator.prototype, "gpu", { get: () => undefined, configurable: true });' });
  await b.nav(BASE);
  await b.waitFor('window.__site?.firstFrameMs()', 60000);
  await sleep(3000);
  report.nogpu = await b.evaluate('({ theme: window.__site.current()?.theme.id, readout: window.__site.current()?.readout(), note: document.querySelector("#teleBody .note")?.textContent, chips: [...document.querySelectorAll("#picker .chip")].map((c) => c.dataset.id + (c.disabled ? " (disabled)" : "")) })');
  await b.shot('nogpu-home.png');
  b.close();
}

fs.writeFileSync(path.join(OUT, 'report.json'), JSON.stringify(report, null, 2));
console.log(JSON.stringify(report, null, 2));
process.exit(0);
