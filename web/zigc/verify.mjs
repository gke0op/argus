#!/usr/bin/env node
// web/zigc/verify.mjs — drive the bench page's in-browser Zig compile in a real browser.
//
//   site/build.sh _site && node web/zigc/verify.mjs [--root _site] [--port 8139] [--browser Safari] [--out DIR] [--query 'only=X']
//
// Serves ROOT under /argus/ on 127.0.0.1 (as GitHub Pages: no COOP/COEP headers), opens
// /argus/web/zigc/verify.html (which drives /argus/bench/ in a frame, see that file) with
// `open -a <browser>` when --browser is given (no WebDriver: Safari's remote automation can stay
// off), and waits for the page to POST its result to /__report. Writes <out>/zigc_<browser>.json
// and exits 0 when every case gave its expected verdict. Without --browser it prints the URL
// to open by hand. Node 22+, no dependencies.
import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';

const args = { root: '_site', port: '8139', out: path.join(os.tmpdir(), 'argus-zigc-verify'), browser: '', query: '', timeout: '1800' };
for (let i = 2; i < process.argv.length; i++) args[process.argv[i].replace(/^--/, '')] = process.argv[++i];
const ROOT = path.resolve(args.root);
const PREFIX = '/argus';
const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.mjs': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.wasm': 'application/wasm', '.gz': 'application/gzip', '.zig': 'text/plain; charset=utf-8', '.md': 'text/markdown; charset=utf-8', '.svg': 'image/svg+xml', '.png': 'image/png', '.jpg': 'image/jpeg', '.wgsl': 'text/plain; charset=utf-8', '.txt': 'text/plain; charset=utf-8' };
fs.mkdirSync(args.out, { recursive: true });

const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://x');
  if (req.method === 'POST' && url.pathname === '/__report') {
    let body = '';
    req.on('data', (c) => { body += c; });
    req.on('end', () => {
      res.end('ok');
      const r = JSON.parse(body);
      const name = (args.browser || 'browser').replace(/\W+/g, '_').toLowerCase();
      const file = path.join(args.out, `zigc_${name}.json`);
      fs.writeFileSync(file, JSON.stringify(r, null, 2));
      for (const c of [...(r.cases || []), ...(r.cached ? [{ ...r.cached, name: 'Bench_Skeleton (cached)' }] : [])]) {
        const z = c.zigc || {};
        console.log(`${c.ok ? 'ok  ' : 'BAD '} ${String(c.scenario || c.name).padEnd(24)} ${String(c.outcome ?? '').padEnd(16)} ${String(c.badge ?? '').padEnd(16)} ${String(c.secs ?? '').padStart(6)} s  sema ${z.semaMs ?? '-'} ms  build ${z.buildMs ?? '-'} ms  download ${z.downloadBytes ?? '-'} B${z.ms320 ? `  320x200 ${z.ms320.toFixed(1)} ms` : ''}${z.cacheDropped ? `  cache dropped: ${z.cacheDropped}` : ''}`);
      }
      console.log(`${r.ua}\n${r.error ? 'ERROR ' + r.error : r.pass ? 'ALL OK' : 'SOME BAD'} -> ${file}`);
      server.close();
      process.exit(r.pass ? 0 : 1);
    });
    return;
  }
  if (!url.pathname.startsWith(PREFIX + '/')) { res.writeHead(404); return res.end(); }
  let p = path.join(ROOT, decodeURIComponent(url.pathname.slice(PREFIX.length)));
  if (!p.startsWith(ROOT)) { res.writeHead(403); return res.end(); }
  if (fs.existsSync(p) && fs.statSync(p).isDirectory()) p = path.join(p, 'index.html');
  if (!fs.existsSync(p)) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { 'content-type': TYPES[path.extname(p)] || 'application/octet-stream', 'cache-control': 'no-cache' });
  fs.createReadStream(p).pipe(res);
});
server.listen(Number(args.port), '127.0.0.1', () => {
  const u = `http://127.0.0.1:${args.port}${PREFIX}/web/zigc/verify.html${args.query ? '?' + args.query : ''}`;
  console.log(`serving ${ROOT} at http://127.0.0.1:${args.port}${PREFIX}/ ; verify page: ${u}`);
  if (args.browser) spawn('open', ['-a', args.browser, u], { stdio: 'ignore' });
});
setTimeout(() => { console.log('timed out waiting for /__report'); process.exit(2); }, Number(args.timeout) * 1000);
