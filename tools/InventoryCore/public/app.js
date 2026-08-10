'use strict';

const characters = ['Dolomedes', 'Tackleberry', 'Kickpuncher', 'Barneystinson', 'Smalls', 'Achoo'];
const characterRank = new Map(characters.map((name, index) => [name, index]));
const bagOrder = [
  'inventory', 'wardrobe', 'wardrobe2', 'wardrobe3', 'wardrobe4', 'wardrobe5', 'wardrobe6', 'wardrobe7', 'wardrobe8',
  'case', 'satchel', 'sack', 'safe', 'safe2', 'storage', 'locker',
  'slip 02', 'slip 03', 'slip 04', 'slip 06', 'slip 17', 'slip 19'
];
const bagRank = new Map(bagOrder.map((name, index) => [name, index]));
const statusCodes = { KEEP: 'K', UPGRADE: 'UP', AH: 'AH', HOLD: 'H', REVIEW: 'R', VENDOR: 'V', DROP: 'D' };
const $ = (selector) => document.querySelector(selector);
let allRows = [];

for (const name of characters) $('#character').insertAdjacentHTML('beforeend', `<option>${name}</option>`);

function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>"']/g, (character) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[character]));
}

function compactGil(value) {
  if (!value) return 'â€”';
  if (value >= 1000000) return `${(value / 1000000).toFixed(value >= 10000000 ? 0 : 1)}m`;
  if (value >= 1000) return `${Math.round(value / 1000)}k`;
  return String(value);
}

function displayBag(name) {
  return name.replace(/^wardrobe(\d+)$/, 'Wardrobe $1').replace(/^slip /, 'Slip ').replace(/\b\w/g, (letter) => letter.toUpperCase());
}

function valueText(row) {
  if (row.ah_median || row.stack_median) {
    return row.stack_size > 1
      ? `${compactGil(row.ah_median)}/${compactGil(row.stack_median)}`
      : compactGil(row.ah_median);
  }
  if (row.vendor_price) return `${compactGil(row.vendor_price)} NPC`;
  return row.ah_category && row.ah_category !== '@NONE' ? 'No sales' : 'â€”';
}

async function loadSummary() {
  const data = await fetch('/api/summary').then((response) => response.json());
  const actionCount = Object.fromEntries(data.actions.map((row) => [row.action, row.count]));
  $('#summary').innerHTML = [
    [data.unique_items, 'Unique'],
    [data.total_items, 'Quantity'],
    [actionCount.AH || 0, 'Auction'],
    [actionCount.VENDOR || 0, 'Vendor']
  ].map(([value, label]) => `<div class="metric"><strong>${value}</strong><span>${label}</span></div>`).join('');
}

function renderBags() {
  const search = $('#search').value.trim().toLowerCase();
  const character = $('#character').value;
  const action = $('#action').value;
  const mode = document.querySelector('input[name="status-mode"]:checked').value;
  let rows = allRows.filter((row) =>
    (!character || row.character === character) &&
    (!search || row.name.toLowerCase().includes(search))
  );
  if (action && mode === 'only') rows = rows.filter((row) => row.action === action);

  const groups = new Map();
  for (const row of rows) {
    const key = `${row.bag}\u0000${row.character}`;
    if (!groups.has(key)) groups.set(key, { bag: row.bag, character: row.character, rows: [] });
    groups.get(key).rows.push(row);
  }
  const panels = [...groups.values()].sort((a, b) =>
    (bagRank.get(a.bag) ?? 999) - (bagRank.get(b.bag) ?? 999) ||
    (characterRank.get(a.character) ?? 999) - (characterRank.get(b.character) ?? 999) ||
    a.bag.localeCompare(b.bag)
  );

  $('#bag-board').innerHTML = panels.map((panel) => {
    panel.rows.sort((a, b) => a.name.localeCompare(b.name));
    const quantity = panel.rows.reduce((sum, row) => sum + row.count, 0);
    const itemRows = panel.rows.map((row) => {
      const matches = !action || row.action === action;
      const classes = `${row.action} ${action ? (matches ? 'match' : 'nonmatch') : ''}`;
      const tooltip = `${row.action} Â· ${row.confidence} confidence\n${row.reason}\n${row.ah_median ? `Valefor single median: ${Number(row.ah_median).toLocaleString()} gil` : 'No Valefor single median'}${row.stack_median ? `\nValefor stack median: ${Number(row.stack_median).toLocaleString()} gil` : ''}${row.vendor_price ? `\nNPC resale: ${Number(row.vendor_price).toLocaleString()} gil each` : ''}`;
      return `<div class="bag-row ${classes}" title="${escapeHtml(tooltip)}">
        <span class="status-code">${statusCodes[row.action] || '?'}</span>
        <span class="item-name">${escapeHtml(row.name)}</span>
        <span class="qty">${row.count}/${row.stack_size || 1}</span>
        <span class="value">${escapeHtml(valueText(row))}</span>
      </div>`;
    }).join('');
    return `<section class="bag-card">
      <header class="bag-head">
        <div class="bag-title"><strong>${escapeHtml(displayBag(panel.bag))}</strong> Â· ${escapeHtml(panel.character)}</div>
        <div class="bag-count">${panel.rows.length} slots Â· ${quantity} qty</div>
      </header>
      <div class="bag-cols"><span>St</span><span>Item</span><span>Have/Max</span><span>Each/Stack</span></div>
      ${itemRows}
    </section>`;
  }).join('');
  $('#empty').hidden = panels.length > 0;
}

async function loadItems() {
  allRows = await fetch('/api/bag-items').then((response) => response.json());
  renderBags();
}

async function loadStatus() {
  const rows = await fetch('/api/status').then((response) => response.json());
  $('#status').innerHTML = rows.map((row) => `<span class="source ${row.ok ? '' : 'bad'}">${row.ok ? 'â—' : 'â—‹'} ${escapeHtml(row.source)}</span>`).join('');
}

let keyItemData = { characters, rows: [] };
let currencyData = { characters, rows: [] };

function formatNumber(value) {
  return value === null || value === undefined ? '--' : Number(value).toLocaleString();
}

function shortTime(value) {
  if (!value) return 'Waiting for telemetry';
  return new Date(value).toLocaleString([], { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' });
}

function renderRotation(area, rotation) {
  const next = rotation.next || `Learning ${rotation.learned}/${rotation.total}`;
  const bonus = rotation.last_bonus?.chest || '--';
  const recent = rotation.recent.length
    ? rotation.recent.map((event) => `<span class="history-chip ${event.units === 5000 ? 'bonus' : ''}" title="${escapeHtml(shortTime(event.opened_at))}">${escapeHtml(event.chest || 'Learning')} <b>${event.units === 5000 ? '&#9733; 5000' : '3000'}</b></span>`).join('')
    : '<span class="muted">No chests recorded yet.</span>';
  return `<div class="rotation">
    <div class="rotation-name">${escapeHtml(area)}</div>
    <div class="rotation-fact"><span>Next</span><strong>${escapeHtml(next)}</strong></div>
    <div class="rotation-fact"><span>Last bonus</span><strong class="bonus-text">${escapeHtml(bonus)}</strong></div>
    <div class="history">${recent}</div>
  </div>`;
}

async function loadDashboard() {
  const data = await fetch('/api/dashboard').then((response) => response.json());
  $('#dashboard-time').textContent = `Updated ${shortTime(data.generated_at)}`;
  $('#gil-board').innerHTML = data.characters.map((row) => `<div class="gil-card">
    <span>${escapeHtml(row.character)}</span>
    <strong>${formatNumber(row.gil)}</strong>
    <small>gil &middot; ${escapeHtml(shortTime(row.observed_at))}</small>
  </div>`).join('');
  $('#limbus-board').innerHTML = data.characters.map((row) => `<article class="limbus-card">
    <header><strong>${escapeHtml(row.character)}</strong></header>
    ${renderRotation('Temenos', row.areas.Temenos)}
    ${renderRotation('Apollyon', row.areas.Apollyon)}
  </article>`).join('');
}

function pivotRows(data, value) {
  const roster = data.characters?.length ? data.characters : characters;
  const grouped = new Map();
  for (const row of data.rows || []) {
    const key = value === 'amount' ? `${row.page}\0${row.name}` : `${row.id}\0${row.name}`;
    if (!grouped.has(key)) grouped.set(key, { name: row.name, page: row.page, values: new Map() });
    grouped.get(key).values.set(row.character, value === 'amount' ? row.amount : true);
  }
  return { roster, groups: [...grouped.values()] };
}

function renderMatrix(target, data, search, value) {
  const { roster, groups } = pivotRows(data, value);
  const filtered = groups.filter((row) => !search || row.name.toLowerCase().includes(search));
  const headings = roster.map((name) => `<span title="${escapeHtml(name)}">${escapeHtml(name.slice(0, 5))}</span>`).join('');
  const rows = filtered.map((row) => `<div class="matrix-row">
    <span class="matrix-name">${row.page ? `<small>C${row.page}</small> ` : ''}${escapeHtml(row.name)}</span>
    ${roster.map((name) => {
      const found = row.values.get(name);
      if (value === 'amount') return `<span class="matrix-value ${found ? 'owned' : ''}">${formatNumber(found ?? 0)}</span>`;
      return `<span class="matrix-value ${found ? 'owned' : ''}">${found ? '&#10003;' : '&middot;'}</span>`;
    }).join('')}
  </div>`).join('');
  $(target).innerHTML = `<section class="matrix-card">
    <div class="matrix-head"><span>Item</span>${headings}</div>
    ${rows || '<p class="empty">No matching entries.</p>'}
  </section>`;
}

async function loadKeyItems() {
  keyItemData = await fetch('/api/key-items').then((response) => response.json());
  renderMatrix('#key-items-board', keyItemData, $('#key-search').value.trim().toLowerCase(), 'owned');
}

async function loadCurrencies() {
  currencyData = await fetch('/api/currencies').then((response) => response.json());
  renderMatrix('#currencies-board', currencyData, $('#currency-search').value.trim().toLowerCase(), 'amount');
}

function activateTab(id) {
  document.querySelectorAll('.tab-panel').forEach((panel) => {
    panel.hidden = panel.id !== id;
    panel.classList.toggle('active', panel.id === id);
  });
  document.querySelectorAll('.tab').forEach((button) => button.classList.toggle('active', button.dataset.tab === id));
}

let timer;
function debounceRender() {
  clearTimeout(timer);
  timer = setTimeout(renderBags, 100);
}
$('#search').addEventListener('input', debounceRender);
$('#character').addEventListener('change', renderBags);
$('#action').addEventListener('change', renderBags);
document.querySelectorAll('input[name="status-mode"]').forEach((radio) => radio.addEventListener('change', renderBags));
$('#key-search').addEventListener('input', () => renderMatrix('#key-items-board', keyItemData, $('#key-search').value.trim().toLowerCase(), 'owned'));
$('#currency-search').addEventListener('input', () => renderMatrix('#currencies-board', currencyData, $('#currency-search').value.trim().toLowerCase(), 'amount'));
document.querySelectorAll('.tab').forEach((button) => button.addEventListener('click', () => activateTab(button.dataset.tab)));
const loadAll = () => Promise.all([loadDashboard(), loadSummary(), loadItems(), loadStatus(), loadKeyItems(), loadCurrencies()]);
$('#refresh').addEventListener('click', loadAll);
loadAll();
setInterval(() => {
  loadDashboard().catch(() => {});
  loadKeyItems().catch(() => {});
  loadCurrencies().catch(() => {});
}, 3000);
