// site/assets/live.js: the bench page's "Submissions, live" board.
//
// Read straight from GitHub's public REST API, two calls cached for five minutes: the 50 most
// recently updated pull requests, and the 100 most recently updated comments. A theme is listed
// once the bench comment job (.github/workflows/bench-comment.yml) has written its
// <!-- argus-bench-data --> line on the pull request: per theme its path, the native harness's
// verdict and the browser build's reference grade (the module's SHA-256 and gates 1-7 under a
// ruler, web/zigc/grade.mjs), for one head commit. Status: graded (for the pull request's
// current head), stale (a newer commit is waiting for its grade), merged, closed.
//
// "Re-grade here" fetches the source at the graded commit, compiles and grades it in this page,
// and compares: under the same ruler the module's SHA-256 and gates 1-7 must be the reference's.
// Nobody has to trust the board or the run that wrote it. Gate 8 is not compared (it times the
// machine). Everything read from GitHub is untrusted: only the bot's comments count, every field
// is checked against its shape, and the page shows text as text.

const REPO = 'gke0op/argus';
const CACHE_MS = 5 * 60000;
const esc = (s) => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const short = (h, n = 12) => (h ? h.slice(0, n) : '–');
const SHA40 = /^[0-9a-f]{40}$/, SHA64 = /^[0-9a-f]{64}$/, NAME = /^[A-Za-z0-9_]+$/, PART = /^[A-Za-z0-9_.-]+$/;
const isRepo = (s) => typeof s === 'string' && s.split('/').length === 2 && s.split('/').every((p) => PART.test(p) && p !== '.' && p !== '..');

/// Where the board reads: GitHub, or ?api=<same-origin path> (pulls.json, comments.json, raw/)
/// for a local check.
function source() {
  const q = new URLSearchParams(location.search).get('api');
  if (q && q.startsWith('/') && !q.startsWith('//')) {
    const base = new URL(q.endsWith('/') ? q : `${q}/`, location.origin).href;
    return { local: true, pulls: `${base}pulls.json`, comments: `${base}comments.json`, raw: `${base}raw/` };
  }
  return { local: false, pulls: `https://api.github.com/repos/${REPO}/pulls?state=all&sort=updated&direction=desc&per_page=50`, comments: `https://api.github.com/repos/${REPO}/issues/comments?sort=updated&direction=desc&per_page=100`, raw: 'https://raw.githubusercontent.com/' };
}

/// The data line of a bench comment, every field checked (as the comment job wrote it); null if
/// absent or malformed.
export function parseData(body) {
  const open = '<!-- argus-bench-data: ';
  const a = String(body).indexOf(open);
  const b = a < 0 ? -1 : body.indexOf(' -->', a);
  if (b < 0) return null;
  let d;
  try { d = JSON.parse(body.slice(a + open.length, b)); } catch { return null; }
  if (!d || !Array.isArray(d.themes)) return null;
  const sha = (x) => (typeof x === 'string' && SHA64.test(x) ? x : null);
  return {
    head: typeof d.head === 'string' && SHA40.test(d.head) ? d.head : '',
    themes: d.themes.filter((t) => t && NAME.test(t.name)).map((t) => {
      const g = t.browser;
      return {
        name: t.name,
        path: t.path === `bench/submissions/${t.name}.zig` ? t.path : '',
        native: t.native === 'PASS' || t.native === 'FAIL' ? t.native : '',
        browser: g && typeof g === 'object' ? {
          ruler: sha(g.ruler), moduleSha256: sha(g.moduleSha256),
          outcome: typeof g.outcome === 'string' && /^[a-z-]{1,32}$/.test(g.outcome) ? g.outcome : '',
          gates: Array.isArray(g.gates) && g.gates.length === 8 && g.gates.every((x) => x === true || x === false || x === null) ? g.gates : [],
        } : null,
      };
    }),
  };
}

/// The board's rows from the two API responses: one per theme a pull request adds under
/// bench/submissions/, from the bot's latest bench comment on it.
export function entriesFrom(pulls, comments, rawBase = 'https://raw.githubusercontent.com/') {
  const byPr = new Map();
  for (const p of Array.isArray(pulls) ? pulls : []) if (Number.isInteger(p?.number)) byPr.set(p.number, p);
  const latest = new Map(); // pr -> { comment, data }
  for (const c of Array.isArray(comments) ? comments : []) {
    if (c?.user?.login !== 'github-actions[bot]' || typeof c.body !== 'string' || !c.body.startsWith('<!-- argus-bench -->')) continue;
    const pr = Number(/\/issues\/(\d+)$/.exec(c.issue_url || '')?.[1]);
    const data = parseData(c.body);
    if (!byPr.has(pr) || !data) continue;
    const prev = latest.get(pr);
    if (!prev || String(c.updated_at) > String(prev.comment.updated_at)) latest.set(pr, { comment: c, data });
  }
  const entries = [];
  for (const [pr, { comment, data }] of latest) {
    const p = byPr.get(pr);
    const state = p.state === 'open' ? 'open' : p.merged_at ? 'merged' : 'closed';
    const repo = p.head?.repo?.full_name;
    for (const t of data.themes) {
      if (!t.path) continue;
      entries.push({
        pr, title: String(p.title ?? ''), author: String(p.user?.login ?? ''), state, updated: String(p.updated_at ?? ''), url: `https://github.com/${REPO}/pull/${pr}`,
        name: t.name, model: t.name.split('_')[0], headSha: data.head,
        raw: isRepo(repo) && data.head ? `${rawBase}${repo}/${data.head}/${t.path}` : '',
        status: state !== 'open' ? state : data.head && data.head === p.head?.sha ? 'graded' : 'stale',
        native: t.native ? { verdict: t.native, comment: String(comment.html_url ?? ''), at: String(comment.updated_at ?? '') } : null,
        browser: t.browser,
      });
    }
  }
  return entries.sort((x, y) => (x.updated === y.updated ? x.name.localeCompare(y.name) : x.updated < y.updated ? 1 : -1));
}

/// Both responses, from sessionStorage for five minutes, else from the API. Throws an Error with
/// .rateLimited (and .reset, a Date) when GitHub says no.
async function fetchBoth(src) {
  const key = `argus-live:${src.pulls}`;
  try { const c = JSON.parse(sessionStorage.getItem(key) || 'null'); if (c && Date.now() - c.at < CACHE_MS) return c; } catch { /* no storage: fetch */ }
  const get = async (u) => {
    const r = await fetch(u);
    if (r.status === 403 || r.status === 429) {
      const e = new Error('rate limited'); e.rateLimited = true;
      const reset = Number(r.headers.get('x-ratelimit-reset'));
      if (reset) e.reset = new Date(reset * 1000);
      throw e;
    }
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    return r.json();
  };
  const [pulls, comments] = await Promise.all([get(src.pulls), get(src.comments)]);
  const c = { at: Date.now(), pulls, comments };
  try { sessionStorage.setItem(key, JSON.stringify(c)); } catch { /* full or blocked: next load fetches again */ }
  return c;
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
  if (!sameModule) return { tone: 'bad', text: `NOT reproduced under the same ruler: module ${short(mine.moduleSha256, 16)} vs ${short(ref.moduleSha256, 16)}, gates 1–7 ${myGates} vs ${gatesText(ref.gates)}` };
  // The same module under the same ruler is the same program: its gates 1-7 follow from it. A side
  // that deferred them did so because that machine was slow (a speed probe), not because of the
  // theme, so a deferral is not a disagreement; only two run results can disagree.
  if (mine.outcome === 'deferred' && ref.outcome === 'deferred') {
    return { tone: 'ok', text: `reproduced: same module (${short(mine.moduleSha256, 16)}); gates 2–7 were too slow for the browser build on both sides (the native harness grades them)` };
  }
  if (mine.outcome === 'deferred' || ref.outcome === 'deferred') {
    const ran = mine.outcome === 'deferred' ? gatesText(ref.gates) : myGates;
    const where = mine.outcome === 'deferred' ? 'this browser was too slow to run gates 2–7 now; the reference ran them' : 'the reference deferred gates 2–7; this browser ran them';
    return { tone: 'ok', text: `reproduced: same module (${short(mine.moduleSha256, 16)}); ${where}: ${ran}` };
  }
  const sameGates = JSON.stringify((mine.gates || []).slice(0, 7)) === JSON.stringify((ref.gates || []).slice(0, 7));
  if (sameGates) return { tone: 'ok', text: `reproduced: same module (${short(mine.moduleSha256, 16)}), same gates 1–7 (${myGates})` };
  return { tone: 'bad', text: `same module (${short(mine.moduleSha256, 16)}) but different gates 1–7: ${myGates} here vs ${gatesText(ref.gates)} in the reference (a time limit hit on one machine, or a nondeterministic theme)` };
}

export function mountLive({ root, grade, shown }) {
  if (!root) return;
  const src = source();
  const body = root.querySelector('tbody');
  const status = root.querySelector('#liveStatus');
  const modelSel = root.querySelector('#liveModel');
  let feed = null, lastOk = 0, busyRow = null;
  const results = new Map(); // `${pr}:${name}:${headSha}` -> compare() result
  const sourceOk = (u) => u.startsWith(src.raw);

  const statusPill = (e) => {
    const t = { graded: 'graded', stale: 'new commit: waiting', merged: 'merged', closed: 'closed' }[e.status] || e.status;
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
      body.innerHTML = `<tr><td colspan="7" class="mute">No submissions yet. Ask a model for a theme (step 1), grade it here (step 2), then <b>Submit a pull request</b>: it shows up here once the native harness has graded it, a few minutes later.</td></tr>`;
      return;
    }
    body.innerHTML = rows.map((e) => {
      const key = `${e.pr}:${e.name}:${e.headSha}`;
      const r = results.get(key);
      const can = e.raw && sourceOk(e.raw);
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
      const c = await fetchBoth(src);
      feed = { entries: entriesFrom(c.pulls, c.comments, src.raw), at: c.at };
      lastOk = c.at;
      render();
      tick();
    } catch (e) {
      const prs = `<a href="https://github.com/${REPO}/pulls">the pull requests on GitHub</a>`;
      status.innerHTML = e.rateLimited
        ? `GitHub’s API allows 60 requests an hour from this network without signing in, and they are used up${e.reset ? `; it opens again at ${esc(e.reset.toLocaleTimeString())}` : ''}. Meanwhile, see ${prs}.`
        : feed ? `could not refresh (${esc(e.message)}); showing the list from ${ago(lastOk)}` : `The list did not load (${esc(e.message)}). See ${prs}.`;
      if (!feed) body.innerHTML = '<tr><td colspan="7" class="mute">–</td></tr>';
    }
  }
  const ago = (t) => { const m = Math.round((Date.now() - t) / 60000); return m < 1 ? 'just now' : `${m} min ago`; };
  function tick() {
    if (!feed) return;
    const n = feed.entries.length, open = feed.entries.filter((e) => e.state === 'open').length;
    status.textContent = `${n} submission${n === 1 ? '' : 's'}, ${open} open · read from GitHub ${ago(lastOk)}${src.local ? ' · local stub' : ''}`;
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
      if (!sourceOk(e.raw)) throw new Error('the source is not on raw.githubusercontent.com');
      const r = await fetch(e.raw);
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
  // The cache decides when GitHub is asked again (every five minutes at most).
  setInterval(() => { if (document.visibilityState === 'visible') load(); else tick(); }, 60000);
  document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') load(); });
  if (location.hash === '#live') root.scrollIntoView({ block: 'start' });
  window.__liveReady = true;
}
