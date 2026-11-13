// site/assets/live.js: the bench page's "Submissions, live" board.
//
// The feed (bench/feed.zig, published by .github/workflows/bench-feed.yml on the bench-feed
// branch) lists every theme a pull request adds under bench/submissions/: the model, the pull
// request, its status (waiting for a grade, graded, stale: a grade for an older commit, merged,
// closed), the native harness's verdict, and the browser build's reference grade (the module's
// SHA-256 and gates 1-7 under a ruler: web/zigc/grade.mjs).
//
// "Re-grade here" fetches the theme's source at the pull request's head commit, compiles and
// grades it in this page, and compares: under the same ruler the module's SHA-256 and gates 1-7
// must be the reference's. Nobody has to trust the feed or the CI run that wrote it: any
// browser can check it. Gate 8 is not compared (it times the machine).
//
// The page shows feed text (titles, logins, names) as text only.

const FEED = 'https://raw.githubusercontent.com/gke0op/argus/bench-feed/feed.json';
const REFRESH_MS = 60000;
const esc = (s) => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const short = (h, n = 12) => (h ? h.slice(0, n) : '–');

/// The feed URL: ?feed=<same-origin path> for a local check, else the published one.
function feedUrl() {
  const q = new URLSearchParams(location.search).get('feed');
  if (q && q.startsWith('/') && !q.startsWith('//')) return new URL(q, location.origin).href;
  return FEED;
}
/// A source URL from the feed is fetched only from raw.githubusercontent.com (or this origin
/// when the feed itself is local).
function sourceOk(url, local) {
  try {
    const u = new URL(url);
    return (u.protocol === 'https:' && u.hostname === 'raw.githubusercontent.com') || (local && u.origin === location.origin);
  } catch { return false; }
}

function gatesText(gates) {
  if (!Array.isArray(gates) || gates.length !== 8) return '–';
  const first7 = gates.slice(0, 7);
  if (first7.some((g) => g === false)) return `FAIL ${first7.map((g, i) => (g === false ? i + 1 : 0)).filter(Boolean).join(',')}`;
  if (first7.every((g) => g === true)) return 'PASS';
  return gates[0] === true ? 'Gate 1 PASS, 2–7 not run' : '–';
}

/// Compare this browser's grade with the reference. Returns { tone: 'ok'|'bad'|'info', text }.
export function compare(ref, mine) {
  const myGates = gatesText(mine.gates);
  if (!ref || !ref.outcome) return { tone: 'info', text: `no reference yet; here: gates 1–7 ${myGates}, module ${short(mine.moduleSha256, 16)}` };
  if (!mine.ruler || !ref.ruler || mine.ruler !== ref.ruler) {
    return { tone: 'info', text: `a different ruler (the site changed since the reference: ${short(ref.ruler)} → ${short(mine.ruler)}), so the modules are not comparable; gates 1–7 here ${myGates}, reference ${gatesText(ref.gates)}` };
  }
  const sameModule = !!mine.moduleSha256 && mine.moduleSha256 === ref.moduleSha256;
  const sameGates = JSON.stringify((mine.gates || []).slice(0, 7)) === JSON.stringify((ref.gates || []).slice(0, 7)) && (mine.outcome === 'deferred') === (ref.outcome === 'deferred');
  if (sameModule && sameGates) return { tone: 'ok', text: `reproduced: same module (${short(mine.moduleSha256, 16)}), same gates 1–7 (${myGates})` };
  return { tone: 'bad', text: `NOT reproduced under the same ruler: module ${short(mine.moduleSha256, 16)} vs ${short(ref.moduleSha256, 16)}, gates 1–7 ${myGates} vs ${gatesText(ref.gates)}` };
}

export function mountLive({ root, grade, shown }) {
  if (!root) return;
  const url = feedUrl();
  const local = url !== FEED;
  const body = root.querySelector('tbody');
  const status = root.querySelector('#liveStatus');
  const modelSel = root.querySelector('#liveModel');
  let feed = null, lastOk = 0, busyRow = null;
  const results = new Map(); // `${pr}:${name}:${headSha}` -> compare() result

  const statusPill = (e) => {
    const t = { waiting: 'waiting for the native grade', graded: 'graded', stale: 'new commit: waiting', merged: 'merged', closed: 'closed' }[e.status] || e.status;
    return `<span class="pill ${esc(e.status)}">${esc(t)}</span>`;
  };
  const native = (e) => (e.native ? `<a href="${esc(e.native.comment)}" class="v ${e.native.verdict === 'PASS' ? 'pass' : 'fail'}">${esc(e.native.verdict)}</a>${e.status === 'stale' ? ' <span class="small mute">(older commit)</span>' : ''}` : '<span class="mute">–</span>');
  const reference = (e) => {
    const b = e.browser;
    if (!b || !b.outcome) return '<span class="mute">–</span>';
    return `${esc(b.outcome === 'deferred' ? 'Gate 1 PASS, rest deferred' : `gates 1–7 ${gatesText(b.gates)}`)}<br><code title="module SHA-256 ${esc(b.moduleSha256 || '?')} under ruler ${esc(b.ruler || '?')}">${esc(short(b.moduleSha256, 12))}</code>`;
  };

  function render() {
    if (!feed) return;
    const model = modelSel.value;
    const models = [...new Set(feed.entries.map((e) => e.model))].sort();
    const want = ['', ...models];
    if ([...modelSel.options].map((o) => o.value).join('|') !== want.join('|')) {
      modelSel.innerHTML = want.map((m) => `<option value="${esc(m)}">${m ? esc(m) : 'every model'}</option>`).join('');
      modelSel.value = models.includes(model) ? model : '';
    }
    modelSel.hidden = models.length < 2;
    const rows = feed.entries.filter((e) => !modelSel.value || e.model === modelSel.value);
    if (!rows.length) {
      body.innerHTML = `<tr><td colspan="7" class="mute">No submissions yet. Ask a model for a theme (step 1), grade it here (step 2), then <b>Submit a pull request</b>: it shows up here within minutes, waiting, and graded once the native harness has run.</td></tr>`;
      return;
    }
    body.innerHTML = rows.map((e) => {
      const key = `${e.pr}:${e.name}:${e.headSha}`;
      const r = results.get(key);
      const can = e.raw && sourceOk(new URL(e.raw, url).href, local);
      return `<tr data-i="${feed.entries.indexOf(e)}">
        <td><b>${esc(e.model)}</b></td>
        <td><code>${esc(e.name)}</code></td>
        <td><a href="${esc(e.url)}">#${e.pr}</a> <span class="small">${esc(e.title)}</span><br><span class="small mute">${esc(e.author)} · ${esc((e.updated || '').replace('T', ' ').replace('Z', ' UTC'))}</span></td>
        <td>${statusPill(e)}</td>
        <td>${native(e)}</td>
        <td>${reference(e)}</td>
        <td>${can ? `<button type="button" class="regrade" data-i="${feed.entries.indexOf(e)}"${busyRow !== null ? ' disabled' : ''}>Re-grade here</button>` : '<span class="mute small">no source</span>'}${r ? `<div class="cmp ${r.tone}">${esc(r.text)}</div>` : ''}</td>
      </tr>`;
    }).join('');
  }

  async function load() {
    try {
      const r = await fetch(url, { cache: 'no-cache' });
      if (!r.ok) throw new Error(r.status === 404 ? 'no feed published yet' : `HTTP ${r.status}`);
      const f = await r.json();
      if (!f || !Array.isArray(f.entries)) throw new Error('not a feed');
      feed = f; lastOk = Date.now();
      render();
      tick();
    } catch (e) {
      status.textContent = feed ? `could not refresh (${e.message}); showing the feed from ${ago(lastOk)}` : `The feed did not load (${e.message}). Submissions are listed on GitHub: pull requests touching bench/submissions/.`;
      if (!feed) body.innerHTML = '<tr><td colspan="7" class="mute">–</td></tr>';
    }
  }
  const ago = (t) => { const m = Math.round((Date.now() - t) / 60000); return m < 1 ? 'just now' : `${m} min ago`; };
  function tick() {
    if (!feed) return;
    const n = feed.entries.length, open = feed.entries.filter((e) => e.state === 'open').length;
    status.textContent = `${n} submission${n === 1 ? '' : 's'}, ${open} open · feed written ${String(feed.generated).replace('T', ' ').replace('Z', ' UTC')}, fetched ${ago(lastOk)}${local ? ' · local feed' : ''}`;
  }

  body.addEventListener('click', async (ev) => {
    const btn = ev.target.closest('button.regrade');
    if (!btn || busyRow !== null) return;
    const e = feed.entries[Number(btn.dataset.i)];
    busyRow = btn.dataset.i;
    render();
    const key = `${e.pr}:${e.name}:${e.headSha}`;
    let res;
    try {
      const src0 = new URL(e.raw, url).href;
      if (!sourceOk(src0, local)) throw new Error('the source is not on raw.githubusercontent.com');
      const r = await fetch(src0, { cache: 'no-cache' });
      if (!r.ok) throw new Error(`the source did not download (HTTP ${r.status})`);
      const src = await r.text();
      const out = await grade(e.name, src, `${e.name}.zig (pull request #${e.pr})`);
      const b = out.bench || {}, z = out.zigc || {};
      const mine = { ruler: z.ruler || null, moduleSha256: z.moduleSha256 || null, gates: b.gates || null, outcome: b.outcome === 'deferred' ? 'deferred' : b.outcome };
      res = b.outcome === 'cancelled' ? { tone: 'info', text: 'cancelled' } : compare(e.browser, mine);
      window.__live = { entry: { pr: e.pr, name: e.name }, mine, ref: e.browser, result: res };
    } catch (err) {
      res = { tone: 'bad', text: String(err.message ?? err) };
      window.__live = { entry: { pr: e.pr, name: e.name }, error: res.text, result: res };
    }
    results.set(key, res);
    shown?.(res);
    busyRow = null;
    render();
  });
  modelSel.addEventListener('change', render);

  load();
  setInterval(() => { if (document.visibilityState === 'visible') load(); else tick(); }, REFRESH_MS);
  document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible' && Date.now() - lastOk > REFRESH_MS) load(); });
  if (location.hash === '#live') root.scrollIntoView({ block: 'start' });
  window.__liveReady = true;
}
