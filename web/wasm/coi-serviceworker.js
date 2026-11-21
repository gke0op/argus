// web/wasm/coi-serviceworker.js — cross-origin isolation where the server cannot send headers.
//
// Threads in wasm need SharedArrayBuffer, which a page gets only when it is cross-origin
// isolated: served with Cross-Origin-Opener-Policy: same-origin and Cross-Origin-Embedder-Policy:
// require-corp. GitHub Pages cannot send headers, so this file, the approach of
// coi-serviceworker (github.com/gzuidhof/coi-serviceworker, MIT), adds them from a service
// worker: loaded as a page script it registers itself and reloads the page once; as the service
// worker it copies every response with the three headers added. When that is impossible (no
// service workers, not a secure context, a hard reload that bypasses the worker), the page stays
// unisolated and engine.js runs the single-threaded module instead.
//
// Use: <script src="coi-serviceworker.js"></script> first in <head>, a classic script, served
// from the folder whose pages it should cover (its scope).

if (typeof window === 'undefined') {
  self.addEventListener('install', () => self.skipWaiting());
  self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));
  self.addEventListener('fetch', (e) => {
    const req = e.request;
    if (req.cache === 'only-if-cached' && req.mode !== 'same-origin') return;
    e.respondWith(fetch(req).then((res) => {
      if (res.status === 0) return res; // opaque: cannot be copied
      const h = new Headers(res.headers);
      h.set('Cross-Origin-Opener-Policy', 'same-origin');
      h.set('Cross-Origin-Embedder-Policy', 'require-corp');
      h.set('Cross-Origin-Resource-Policy', 'cross-origin');
      return new Response(res.body, { status: res.status, statusText: res.statusText, headers: h });
    }));
  });
} else {
  (() => {
    if (window.crossOriginIsolated || !window.isSecureContext || !('serviceWorker' in navigator)) return;
    const KEY = 'argus-coi-reloaded';
    let reloaded = false;
    try { reloaded = sessionStorage.getItem(KEY) === '1'; sessionStorage.removeItem(KEY); } catch { /* storage blocked: still try once */ }
    if (reloaded) return; // reloaded once and still not isolated: run single-threaded
    const reload = () => {
      try { sessionStorage.setItem(KEY, '1'); } catch { return; } // cannot guard against a loop
      location.reload();
    };
    navigator.serviceWorker.register(document.currentScript.src).then((reg) => {
      if (navigator.serviceWorker.controller) return reload(); // controlled, yet no headers (hard reload)
      if (reg.active) return reload();
      const sw = reg.installing || reg.waiting;
      if (sw) sw.addEventListener('statechange', () => { if (sw.state === 'activated') reload(); });
    }, (err) => console.warn('coi-serviceworker: not registered, threads off:', err));
  })();
}
