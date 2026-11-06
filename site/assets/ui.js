// site/assets/ui.js: small shared page helpers (copy buttons, sortable tables).

/// Every button[data-copy="id"] copies the text of #id.
export function copyButtons(root = document) {
  for (const b of root.querySelectorAll('button[data-copy]')) {
    b.addEventListener('click', async () => {
      const el = document.getElementById(b.dataset.copy);
      await copyText(el.value ?? el.innerText, b);
    });
  }
}

export async function copyText(text, button) {
  const was = button?.textContent;
  try {
    await navigator.clipboard.writeText(text);
    if (button) button.textContent = 'Copied';
  } catch {
    // No clipboard permission (an http page, an old browser): select a hidden textarea instead.
    const ta = document.createElement('textarea');
    ta.value = text; ta.style.position = 'fixed'; ta.style.opacity = '0';
    document.body.append(ta); ta.select();
    const ok = document.execCommand('copy');
    ta.remove();
    if (button) button.textContent = ok ? 'Copied' : 'Copy failed';
  }
  if (button) setTimeout(() => { button.textContent = was; }, 1400);
}

// A cell's sort key: the leading number ("2.19 (1.89–6.63)" -> 2.19, "3/3" -> 1, "8 (0–8)" -> 8),
// a tier's rank, or the text. "-" sorts last.
const TIERS = { platinum: 4, gold: 3, silver: 2, bronze: 1 };
function key(td) {
  const s = td.textContent.trim();
  if (s === '-' || s === '–' || s === '') return { n: null, s };
  const frac = /^(\d+)\/(\d+)/.exec(s);
  if (frac) return { n: Number(frac[1]) / Number(frac[2]), s };
  const tier = TIERS[s.replace(/[^a-z]/gi, '').toLowerCase()];
  if (tier) return { n: tier, s };
  const num = /^-?\d+(\.\d+)?/.exec(s);
  if (num) return { n: Number(num[0]), s };
  return { n: null, s };
}

/// Click a header button to sort by that column (again to reverse).
export function sortable(table) {
  const tbody = table.tBodies[0];
  const original = [...tbody.rows];
  table.querySelectorAll('thead th').forEach((th, col) => {
    const btn = th.querySelector('button') ?? th;
    btn.addEventListener('click', () => {
      const dir = th.getAttribute('aria-sort') === 'ascending' ? 'descending' : 'ascending';
      table.querySelectorAll('thead th').forEach((o) => o.removeAttribute('aria-sort'));
      th.setAttribute('aria-sort', dir);
      const sign = dir === 'ascending' ? 1 : -1;
      const rows = [...original].sort((a, b) => {
        const ka = key(a.cells[col]), kb = key(b.cells[col]);
        if (ka.n !== null && kb.n !== null && ka.n !== kb.n) return (ka.n - kb.n) * sign;
        if (ka.n === null && kb.n !== null) return 1;
        if (kb.n === null && ka.n !== null) return -1;
        return ka.s.localeCompare(kb.s) * sign || original.indexOf(a) - original.indexOf(b);
      });
      tbody.append(...rows);
    });
  });
}
