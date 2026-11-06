#!/usr/bin/env node
// web/host/tools/verify.mjs — the Metal harness's check, for the WebGPU port of a theme.
//
//   node web/host/tools/verify.mjs --theme Tutorial_Tides --ref /tmp/ref/Tutorial_Tides.png --out /tmp/verify
//
// Serves web/ on 127.0.0.1, opens web/host/verify.html in headless Chrome (WebGPU on, its own
// throwaway profile), renders the same frames the harness does (1920x1200, dt = 1/30 s, seed
// 0x5EED, the date pinned to 2026-10-20T12:00:00Z), reads the gates and the GPU time, and compares
// the last frame with the Metal harness PNG (`make harness THEME=themes/X.metal OUT=ref.png`).
// Writes <out>/<Theme>_web.png, <Theme>_diff.png (|web - metal| x 8) and <Theme>.json.
// Node 22+, no dependencies. Exit 0 when the gates pass (and, with --max-mean, the diff is within it).

import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import zlib from 'node:zlib';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const WEB = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const CHROME = process.env.CHROME ?? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

const args = { theme: 'Tutorial_Tides', frames: 120, width: 1920, height: 1200, seed: '0x5EED', date: '2026-10-20T12:00:00Z', timing: 60, out: path.join(os.tmpdir(), 'argus-verify'), timeout: 600 };
for (let i = 2; i < process.argv.length; i++) {
  const k = process.argv[i].replace(/^--/, '');
  if (k === 'headed' || k === 'fullscreen') { args[k] = true; continue; }
  args[k] = process.argv[++i];
}
fs.mkdirSync(args.out, { recursive: true });

// ---- PNG -----------------------------------------------------------------------------------
function decodePNG(buf) {
  if (buf.readUInt32BE(0) !== 0x89504e47) throw new Error('not a PNG');
  let off = 8, w = 0, h = 0, depth = 0, ctype = 0;
  const idat = [];
  while (off < buf.length) {
    const len = buf.readUInt32BE(off);
    const type = buf.toString('latin1', off + 4, off + 8);
    const data = buf.subarray(off + 8, off + 8 + len);
    if (type === 'IHDR') { w = data.readUInt32BE(0); h = data.readUInt32BE(4); depth = data[8]; ctype = data[9]; if (data[12] !== 0) throw new Error('interlaced PNG'); }
    else if (type === 'IDAT') idat.push(data);
    else if (type === 'IEND') break;
    off += 12 + len;
  }
  if (depth !== 8 || (ctype !== 2 && ctype !== 6)) throw new Error(`PNG: depth ${depth} colour type ${ctype} unsupported`);
  const bpp = ctype === 6 ? 4 : 3;
  const raw = zlib.inflateSync(Buffer.concat(idat));
  const stride = w * bpp;
  const px = Buffer.alloc(w * h * bpp);
  for (let y = 0; y < h; y++) {
    const ft = raw[y * (stride + 1)];
    const src = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1));
    const row = px.subarray(y * stride, (y + 1) * stride);
    const up = y > 0 ? px.subarray((y - 1) * stride, y * stride) : null;
    for (let x = 0; x < stride; x++) {
      const a = x >= bpp ? row[x - bpp] : 0;
      const b = up ? up[x] : 0;
      const c = up && x >= bpp ? up[x - bpp] : 0;
      let v = src[x];
      if (ft === 1) v += a;
      else if (ft === 2) v += b;
      else if (ft === 3) v += (a + b) >> 1;
      else if (ft === 4) { const p = a + b - c; const pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c); v += pa <= pb && pa <= pc ? a : pb <= pc ? b : c; }
      row[x] = v & 0xff;
    }
  }
  const rgba = Buffer.alloc(w * h * 4);
  for (let i = 0; i < w * h; i++) { rgba[i * 4] = px[i * bpp]; rgba[i * 4 + 1] = px[i * bpp + 1]; rgba[i * 4 + 2] = px[i * bpp + 2]; rgba[i * 4 + 3] = bpp === 4 ? px[i * 4 + 3] : 255; }
  return { w, h, rgba };
}

function encodePNG(w, h, rgba) {
  const raw = Buffer.alloc(h * (w * 3 + 1));
  for (let y = 0; y < h; y++) {
    raw[y * (w * 3 + 1)] = 0;
    for (let x = 0; x < w; x++) {
      const s = (y * w + x) * 4, d = y * (w * 3 + 1) + 1 + x * 3;
      raw[d] = rgba[s]; raw[d + 1] = rgba[s + 1]; raw[d + 2] = rgba[s + 2];
    }
  }
  const chunk = (type, data) => {
    const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
    const td = Buffer.concat([Buffer.from(type, 'latin1'), data]);
    const crc = Buffer.alloc(4); crc.writeUInt32BE(zlib.crc32(td) >>> 0);
    return Buffer.concat([len, td, crc]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 2;
  return Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw, { level: 6 })), chunk('IEND', Buffer.alloc(0))]);
}

function compare(web, ref, w, h) {
  const n = w * h;
  const hist = { eq: 0, le1: 0, le2: 0, le4: 0, le8: 0, le16: 0, le32: 0, gt32: 0, gt64: 0 };
  let sum = 0, sq = 0, max = 0;
  const diff = Buffer.alloc(n * 4);
  for (let i = 0; i < n; i++) {
    let m = 0;
    for (let c = 0; c < 3; c++) {
      const d = Math.abs(web[i * 4 + c] - ref[i * 4 + c]);
      sum += d; sq += d * d; if (d > m) m = d;
      diff[i * 4 + c] = Math.min(255, d * 8);
    }
    diff[i * 4 + 3] = 255;
    if (m > max) max = m;
    if (m === 0) hist.eq++;
    if (m <= 1) hist.le1++;
    if (m <= 2) hist.le2++;
    if (m <= 4) hist.le4++;
    if (m <= 8) hist.le8++;
    if (m <= 16) hist.le16++;
    if (m <= 32) hist.le32++;
    else hist.gt32++;
    if (m > 64) hist.gt64++;
  }
  const mse = sq / (n * 3);
  const pct = {};
  for (const [k, v] of Object.entries(hist)) pct[k] = +(100 * v / n).toFixed(4);
  return { meanAbs: +(sum / (n * 3)).toFixed(4), rmse: +Math.sqrt(mse).toFixed(4), psnr: mse === 0 ? Infinity : +(10 * Math.log10(255 * 255 / mse)).toFixed(2), maxAbs: max, pixelsPct: pct, diff };
}

// ---- static server -------------------------------------------------------------------------
const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.wgsl': 'text/plain', '.json': 'application/json', '.png': 'image/png', '.bin': 'application/octet-stream', '.css': 'text/css' };
const server = http.createServer((req, res) => {
  const p = path.normalize(decodeURIComponent(new URL(req.url, 'http://x').pathname));
  const file = path.join(WEB, p);
  if (!file.startsWith(WEB)) { res.writeHead(403); res.end(); return; }
  fs.readFile(file, (err, data) => {
    if (err) { res.writeHead(404); res.end(); return; }
    res.writeHead(200, { 'Content-Type': TYPES[path.extname(file)] ?? 'application/octet-stream', 'Cache-Control': 'no-store' });
    res.end(data);
  });
});
await new Promise((r) => server.listen(0, '127.0.0.1', r));
const port = server.address().port;

// ---- Chrome over CDP ------------------------------------------------------------------------
const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'argus-verify-chrome-'));
const chrome = spawn(CHROME, [
  ...(args.headed ? [] : ['--headless=new']), '--enable-unsafe-webgpu', '--enable-webgpu-developer-features',
  '--remote-debugging-port=0', `--user-data-dir=${profile}`, '--no-first-run', '--no-default-browser-check',
  '--disable-background-timer-throttling', '--disable-renderer-backgrounding', '--disable-backgrounding-occluded-windows',
  ...(args.headed ? (args.fullscreen ? ['--start-fullscreen'] : ['--window-size=1512,945', '--window-position=0,0']) : []), 'about:blank',
], { stdio: ['ignore', 'ignore', 'pipe'] });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let cleaned = false;
function cleanup() {
  if (cleaned) return; cleaned = true;
  try { chrome.kill(); } catch { /* gone */ }
  server.close();
  setTimeout(() => fs.rmSync(profile, { recursive: true, force: true }), 500);
}
process.on('exit', cleanup);

let wsUrl = null;
for (let i = 0; i < 600 && !wsUrl; i++) {
  try {
    const [p] = fs.readFileSync(path.join(profile, 'DevToolsActivePort'), 'utf8').split('\n');
    const list = await (await fetch(`http://127.0.0.1:${p}/json`)).json();
    wsUrl = list.find((t) => t.type === 'page')?.webSocketDebuggerUrl ?? null;
  } catch { /* not up yet */ }
  if (!wsUrl) await sleep(100);
}
if (!wsUrl) { console.error('Chrome did not start'); cleanup(); process.exit(2); }
const ws = new WebSocket(wsUrl);
await new Promise((r, j) => { ws.onopen = r; ws.onerror = j; });
let nextId = 0;
const pending = new Map();
const consoleLines = [];
ws.onmessage = (ev) => {
  const m = JSON.parse(ev.data);
  if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); }
  else if (m.method === 'Runtime.consoleAPICalled') consoleLines.push(`${m.params.type}: ${m.params.args.map((a) => a.value ?? a.description).join(' ')}`);
  else if (m.method === 'Runtime.exceptionThrown') consoleLines.push(`exception: ${m.params.exceptionDetails.exception?.description ?? m.params.exceptionDetails.text}`);
};
const send = (method, params = {}, ms = 30000) => new Promise((r) => {
  const id = ++nextId;
  const timer = setTimeout(() => { pending.delete(id); r({ timeout: true }); }, ms);
  pending.set(id, (m) => { clearTimeout(timer); r(m); });
  ws.send(JSON.stringify({ id, method, params }));
});
const evaluate = async (expr, ms) => (await send('Runtime.evaluate', { expression: expr, returnByValue: true }, ms)).result?.result?.value;
let loaded = false;
const onEvent = ws.onmessage;
ws.onmessage = (ev) => { onEvent(ev); if (JSON.parse(ev.data).method === 'Page.loadEventFired') loaded = true; };

await send('Runtime.enable');
await send('Page.enable');
// --live N: the dev page itself (canvas, requestAnimationFrame, the browser's pacing) for N
// seconds; reports the engine's stats and the display interval, and saves a screenshot.
if (args.live) {
  const vw = +(args.vw ?? 1512), vh = +(args.vh ?? 982), dpr = +(args.dpr ?? 2);
  // Headless has no real display: emulate a 14" MacBook Pro's. Headed (--headed) uses the real window.
  if (!args.headed) await send('Emulation.setDeviceMetricsOverride', { width: vw, height: vh, deviceScaleFactor: dpr, mobile: false });
  await send('Page.navigate', { url: `http://127.0.0.1:${port}/index.html?theme=${encodeURIComponent(args.theme)}${args.seed ? `&seed=${args.seed}` : ''}` });
  for (let i = 0; i < 300 && !loaded; i++) await sleep(50);
  await sleep(+args.live * 1000);
  const v = await evaluate(`JSON.stringify((() => { const e = window.__engine && window.__engine(); if (!e) return { error: document.getElementById('err').textContent || 'no engine' };
    const cv = document.getElementById('c'); return { theme: e.name, dpr: devicePixelRatio, css: [cv.clientWidth, cv.clientHeight], canvasPx: [cv.width, cv.height], frames: (() => { const ft = window.__frameTimes ? window.__frameTimes() : []; const so = [...ft].sort((a, b) => a - b); const med = so[so.length >> 1] || 0; return { n: ft.length, medianMs: med, p95Ms: so[Math.floor(so.length * 0.95)] || 0, late: ft.filter((x) => x > med * 1.5).length }; })(), stats: e.stats(), info: e.info, hud: document.getElementById('read').innerText, err: document.getElementById('err').textContent, sources: e.statsSources() }; })())`, 10000);
  const shot = await send('Page.captureScreenshot', { format: 'png' }, 30000);
  if (shot.result?.data) fs.writeFileSync(path.join(args.out, `${args.theme}_live.png`), Buffer.from(shot.result.data, 'base64'));
  const r = v ? JSON.parse(v) : { error: 'evaluate failed' };
  if (consoleLines.length) r.console = consoleLines.slice(0, 40);
  console.log(JSON.stringify(r, null, 2));
  cleanup();
  process.exit(r.error || r.err ? 1 : 0);
}

const q = new URLSearchParams({ theme: args.theme, frames: args.frames, width: args.width, height: args.height, seed: args.seed, date: args.date, timing: args.timing });
await send('Page.navigate', { url: `http://127.0.0.1:${port}/host/verify.html?${q}` });

for (let i = 0; i < 300 && !loaded; i++) await sleep(50);
let result = null;
const deadline = Date.now() + args.timeout * 1000;
while (Date.now() < deadline) {
  const v = await evaluate('JSON.stringify(window.__verify ?? null)', 5000);
  if (v && v !== 'null') { const o = JSON.parse(v); if (o.status !== 'running') { result = o; break; } }
  await sleep(250);
}
if (!result) result = { status: 'error', error: `timed out after ${args.timeout} s` };
if (consoleLines.length) result.console = consoleLines.slice(0, 40);

let ok = result.status === 'done' && result.gates.pass;
if (result.status === 'done') {
  // The frame comes over in 1 MB slices: one 12 MB CDP message doesn't make it.
  const len = await evaluate('window.__pixels.length', 30000);
  let b64 = '';
  for (let i = 0; i < len; i += 1 << 20) {
    const part = await evaluate(`window.__pixels.slice(${i}, ${i + (1 << 20)})`, 30000);
    if (typeof part !== 'string') throw new Error('pixel transfer failed');
    b64 += part;
  }
  const web = Buffer.from(b64, 'base64');
  const w = +args.width, h = +args.height;
  fs.writeFileSync(path.join(args.out, `${args.theme}_web.png`), encodePNG(w, h, web));
  if (args.ref) {
    const ref = decodePNG(fs.readFileSync(args.ref));
    if (ref.w !== w || ref.h !== h) throw new Error(`reference is ${ref.w}x${ref.h}, render is ${w}x${h}`);
    const c = compare(web, ref.rgba, w, h);
    fs.writeFileSync(path.join(args.out, `${args.theme}_diff.png`), encodePNG(w, h, c.diff));
    delete c.diff;
    result.compare = { ref: args.ref, ...c };
    if (args['max-mean'] !== undefined && c.meanAbs > +args['max-mean']) ok = false;
  }
}
fs.writeFileSync(path.join(args.out, `${args.theme}.json`), JSON.stringify(result, null, 2));
console.log(JSON.stringify(result, null, 2));
cleanup();
process.exit(ok ? 0 : 1);
