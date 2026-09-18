'use strict';

const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');
const assert = require('node:assert/strict');

const publicDir = path.join(__dirname, '../public');
const app = fs.readFileSync(path.join(publicDir, 'app.js'), 'utf8');
const roster = ['Dolomedes', 'Tackleberry'];
const currencies = {
  characters: roster,
  rows: [
    { page: 1, name: 'Zeni', character: 'Dolomedes', amount: 50 },
    { page: 1, name: 'Rems Tale Chapter 10', character: 'Dolomedes', amount: 10 },
    { page: 1, name: 'Rems Tale Chapter 2', character: 'Dolomedes', amount: 2 },
    { page: 2, name: 'Apollyon Units', character: 'Dolomedes', amount: 17612 },
    { page: 2, name: 'Kinetic Units', character: 'Dolomedes', amount: 31287 },
    { page: 2, name: 'Temenos Units', character: 'Dolomedes', amount: 60000 },
    { page: 2, name: 'Temenos Units', character: 'Tackleberry', amount: 57550 },
    { page: 3, name: 'Gallimaufry', character: 'Dolomedes', amount: 1200 },
  ],
};

// Run the complete shipped browser script against a minimal DOM, with no
// network or timers. This also exercises its actual input/refresh handlers.
async function createApp() {
  const elements = new Map();
  const intervals = [];
  const element = (selector) => {
    if (!elements.has(selector)) elements.set(selector, {
      value: selector.includes('status-mode') ? 'highlight' : '',
      innerHTML: '', textContent: '', hidden: false, listeners: new Map(),
      insertAdjacentHTML(_position, html) { this.innerHTML += html; },
      addEventListener(event, handler) { this.listeners.set(event, handler); },
    });
    return elements.get(selector);
  };
  const responses = new Map([
    ['/api/summary', { unique_items: 1, total_items: 1, actions: [] }],
    ['/api/dashboard', { generated_at: '2026-08-31T02:00:00Z', characters: [] }],
    ['/api/bag-items', [{
      character: 'Dolomedes', bag: 'inventory', name: 'Warp Ring', count: 1,
      stack_size: 1, action: 'KEEP', confidence: 'high', reason: 'Keep <safe>',
    }]],
    ['/api/status', [{ source: 'FindAll', ok: true }, { source: 'Market <offline>', ok: false }]],
    ['/api/inventory-revision', { revision: 'inventory-1' }],
    ['/api/key-items', { characters: roster, rows: [
      { id: 2, name: 'Temenos code', character: 'Dolomedes' },
      { id: 1, name: 'Apollyon code', character: 'Tackleberry' },
    ] }],
    ['/api/currencies', structuredClone(currencies)],
  ]);
  const context = vm.createContext({
    document: { querySelector: element, querySelectorAll: () => [] },
    fetch: async (url) => {
      assert.ok(responses.has(url), `Unexpected request: ${url}`);
      return { json: async () => structuredClone(responses.get(url)) };
    },
    setTimeout: (callback) => callback(),
    clearTimeout: () => {},
    setInterval: (callback) => intervals.push(callback),
  });
  vm.runInContext(app, context);
  await vm.runInContext('loadAll()', context);
  return {
    context, element, responses,
    input(selector, value) {
      element(selector).value = value;
      element(selector).listeners.get('input')();
    },
    async tick() {
      intervals[0]();
      await new Promise(setImmediate);
    },
  };
}

function matrixRows(html) {
  return Array.from(html.matchAll(/<span class="matrix-name">(?:<small>C(\d+)<\/small> )?([^<]*)<\/span>/g),
    (match) => ({ page: match[1] ? Number(match[1]) : null, name: match[2] }));
}

test('public UI punctuation remains encoding-safe', () => {
  for (const filename of ['index.html', 'app.js', 'styles.css']) {
    const bytes = fs.readFileSync(path.join(publicDir, filename));
    const source = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
    // Static punctuation belongs in entities/Unicode escapes, not re-encoded bytes.
    assert.doesNotMatch(source, /[^\t\r\n\x20-\x7e]/, filename);
  }
  const html = fs.readFileSync(path.join(publicDir, 'index.html'), 'utf8');
  assert.match(html, /VALEFOR &middot; SIX-CHARACTER ROSTER/);
  assert.match(html, /Dense bag view &middot; FindAll/);
});

test('matrix header remains in normal flow so it cannot cover the first search result', () => {
  const styles = fs.readFileSync(path.join(publicDir, 'styles.css'), 'utf8');
  const rule = styles.match(/\.matrix-head\s*\{([^}]*)\}/);
  assert.ok(rule, 'matrix-head rule is present');
  assert.doesNotMatch(rule[1], /position\s*:\s*sticky/i);
  assert.doesNotMatch(rule[1], /top\s*:/i);
});

test('inventory headers, tooltips, missing prices and status icons render cleanly', async () => {
  const ui = await createApp();
  const bags = ui.element('#bag-board').innerHTML;
  assert.match(bags, /Inventory<\/strong> &middot; Dolomedes/);
  assert.match(bags, /1 slots &middot; 1 qty/);
  assert.ok(bags.includes('KEEP \u00b7 high confidence'));
  assert.ok(bags.includes('<span class="value">\u2014</span>'));
  assert.match(bags, /Keep &lt;safe&gt;/);
  assert.equal(ui.context.compactGil(null), '\u2014');
  assert.equal(ui.context.compactGil(1500), '2k');
  const status = ui.element('#status').innerHTML;
  assert.match(status, /&#9679; FindAll/);
  assert.match(status, /&#9675; Market &lt;offline&gt;/);
});

test('currencies sort globally by name, retain page badges and sort chapter numbers naturally', async () => {
  const ui = await createApp();
  assert.deepEqual(matrixRows(ui.element('#currencies-board').innerHTML), [
    { page: 2, name: 'Apollyon Units' },
    { page: 3, name: 'Gallimaufry' },
    { page: 2, name: 'Kinetic Units' },
    { page: 1, name: 'Rems Tale Chapter 2' },
    { page: 1, name: 'Rems Tale Chapter 10' },
    { page: 2, name: 'Temenos Units' },
    { page: 1, name: 'Zeni' },
  ]);
});

test('currency input matches units and area names regardless of case or surrounding whitespace', async () => {
  const ui = await createApp();
  for (const query of ['Teme', 'Temenos', 'TEMENOS', 'temenos', '  TeMeNoS  ', '\u00a0Temenos\u00a0']) {
    ui.input('#currency-search', query);
    assert.deepEqual(matrixRows(ui.element('#currencies-board').innerHTML), [{ page: 2, name: 'Temenos Units' }], query);
  }
  for (const query of ['Apol', 'Apollyon', 'APOLLYON', 'apollyon', ' ApOlLyOn ']) {
    ui.input('#currency-search', query);
    assert.deepEqual(matrixRows(ui.element('#currencies-board').innerHTML), [{ page: 2, name: 'Apollyon Units' }], query);
  }
  ui.input('#currency-search', 'UNITS');
  assert.deepEqual(matrixRows(ui.element('#currencies-board').innerHTML).map((row) => row.name),
    ['Apollyon Units', 'Kinetic Units', 'Temenos Units']);
  ui.input('#currency-search', 'Rems');
  assert.deepEqual(matrixRows(ui.element('#currencies-board').innerHTML).map((row) => row.name),
    ['Rems Tale Chapter 2', 'Rems Tale Chapter 10']);
  ui.input('#currency-search', 'no such currency');
  assert.match(ui.element('#currencies-board').innerHTML, /No matching entries/);
  ui.input('#currency-search', '');
  assert.equal(matrixRows(ui.element('#currencies-board').innerHTML).length, 7);
});

test('matrix renderer normalizes search itself rather than relying on its caller', async () => {
  const ui = await createApp();
  ui.context.renderMatrix('#currencies-board', currencies, ' TEMENOS ', 'amount');
  const html = ui.element('#currencies-board').innerHTML;
  assert.deepEqual(matrixRows(html), [{ page: 2, name: 'Temenos Units' }]);
  assert.match(html, /60,000/);
  assert.match(html, /57,550/);
});

test('currency filter and balances survive background and manual data refreshes', async () => {
  const ui = await createApp();
  ui.input('#currency-search', ' TeMeNoS ');
  const updated = structuredClone(currencies);
  updated.rows.find((row) => row.name === 'Temenos Units' && row.character === 'Dolomedes').amount = 57000;
  ui.responses.set('/api/currencies', updated);
  await ui.tick();
  assert.deepEqual(matrixRows(ui.element('#currencies-board').innerHTML), [{ page: 2, name: 'Temenos Units' }]);
  assert.match(ui.element('#currencies-board').innerHTML, /57,000/);
  await ui.element('#refresh').listeners.get('click')();
  assert.deepEqual(matrixRows(ui.element('#currencies-board').innerHTML), [{ page: 2, name: 'Temenos Units' }]);
});

test('inventory automatically reloads when the FindAll snapshot changes', async () => {
  const ui = await createApp();
  assert.match(ui.element('#bag-board').innerHTML, /Warp Ring/);
  ui.responses.set('/api/bag-items', [{
    character: 'Dolomedes', bag: 'inventory', name: 'Mumuu Ring', count: 1,
    stack_size: 1, action: 'KEEP', confidence: 'high', reason: 'Current item',
  }]);
  ui.responses.set('/api/inventory-revision', { revision: 'inventory-2' });
  await ui.tick();
  assert.doesNotMatch(ui.element('#bag-board').innerHTML, /Warp Ring/);
  assert.match(ui.element('#bag-board').innerHTML, /Mumuu Ring/);
});

test('identically named currencies on different pages stay separate and data is not mutated', async () => {
  const ui = await createApp();
  const data = { characters: roster, rows: [
    { page: 3, name: 'Shared Points', character: 'Dolomedes', amount: 3 },
    { page: 1, name: 'Shared Points', character: 'Dolomedes', amount: 1 },
  ] };
  const before = structuredClone(data);
  ui.context.renderMatrix('#currencies-board', data, '', 'amount');
  assert.deepEqual(matrixRows(ui.element('#currencies-board').innerHTML), [
    { page: 1, name: 'Shared Points' }, { page: 3, name: 'Shared Points' },
  ]);
  assert.deepEqual(data, before);
});

test('key items and inventory share the same search normalization', async () => {
  const ui = await createApp();
  ui.input('#key-search', ' APOLLYON ');
  const html = ui.element('#key-items-board').innerHTML;
  assert.deepEqual(matrixRows(html), [{ page: null, name: 'Apollyon code' }]);
  assert.match(html, /&#10003;/);
  assert.match(html, /&middot;/);
  ui.input('#search', ' WARP ');
  assert.match(ui.element('#bag-board').innerHTML, /Warp Ring/);
  assert.equal(ui.element('#empty').hidden, true);
});
