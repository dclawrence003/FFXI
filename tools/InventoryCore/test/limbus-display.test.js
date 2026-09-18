'use strict';

const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');
const assert = require('node:assert/strict');

// Exercise the shipped pure renderer without a browser or live backend.
const app = fs.readFileSync(path.join(__dirname, '../public/app.js'), 'utf8');
const context = { escapeHtml: String, shortTime: String };
vm.runInNewContext(app.slice(app.indexOf('function renderRotation('),
  app.indexOf('async function loadDashboard(')), context);

for (const units of [3000, 4170, 5000]) {
  test(`Limbus history shows the actual ${units} receipt without rounding`, () => {
    const html = context.renderRotation('Temenos', {
      next: null, learned: 1, total: 4, last_bonus: units > 3000 ? { chest: 'North' } : null,
      recent: [{ chest: 'North', units, opened_at: '2026-08-31T01:32:42Z' }]
    });
    assert.ok(html.includes(`<b>${units > 3000 ? '&#9733; ' : ''}${units}</b>`));
    assert.equal(html.includes('history-chip bonus'), units > 3000);
  });
}
