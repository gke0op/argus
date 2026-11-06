// web/wasm/serve.mjs — a static server for the repository, for the dev page.
//
//   node web/wasm/serve.mjs [--port 8135] [--no-isolation]
//   open http://127.0.0.1:8135/web/wasm/
//
// It sends COOP/COEP, so the page is cross-origin isolated and runs the threaded module.
// --no-isolation leaves them out, as GitHub Pages does: the page then relies on
// coi-serviceworker.js, or falls back to one thread. Binds to 127.0.0.1 only.

import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const args = process.argv.slice(2);
const port = Number(args[args.indexOf('--port') + 1]) || 8135;
const isolate = !args.includes('--no-isolation');
const types = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8',
  '.wasm': 'application/wasm', '.json': 'application/json', '.png': 'image/png', '.txt': 'text/plain; charset=utf-8',
  '.md': 'text/plain; charset=utf-8', '.zig': 'text/plain; charset=utf-8', '.css': 'text/css', '.svg': 'image/svg+xml',
};

http.createServer((req, res) => {
  let p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  if (p.endsWith('/')) p += 'index.html';
  const file = path.resolve(root, '.' + p);
  if (!file.startsWith(root + path.sep)) { res.writeHead(403); return res.end(); }
  fs.readFile(file, (err, data) => {
    const h = { 'Cache-Control': 'no-store' };
    if (isolate) {
      h['Cross-Origin-Opener-Policy'] = 'same-origin';
      h['Cross-Origin-Embedder-Policy'] = 'require-corp';
    }
    if (err) { res.writeHead(404, h); return res.end('not found'); }
    h['Content-Type'] = types[path.extname(file)] || 'application/octet-stream';
    res.writeHead(200, h);
    res.end(data);
  });
}).listen(port, '127.0.0.1', () => {
  console.log(`serving ${root} at http://127.0.0.1:${port}/web/wasm/ (${isolate ? 'cross-origin isolated' : 'no isolation headers'})`);
});
