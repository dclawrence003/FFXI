'use strict';

const path = require('node:path');
process.env.FFXI_INVENTORY_CONFIG = path.join(__dirname, 'config.fixture.json');

const test = require('node:test');
const assert = require('node:assert/strict');
const { DatabaseSync } = require('node:sqlite');
const { initializeDb } = require('../src/db');
const {
  ingestTelemetry,
  recordLimbusChest,
  computeRotation,
  dashboard,
  keyItemView,
  currencyView
} = require('../src/telemetry');
const config = require('./config.fixture.json');

function memoryDb() {
  return initializeDb(new DatabaseSync(':memory:'));
}

test('telemetry atomically replaces character key items and currency pages', () => {
  const db = memoryDb();
  ingestTelemetry(db, {
    character: 'Tackleberry',
    gil: 1234567,
    key_items: [{ id: 10, name: 'Apollyon verification key' }],
    currencies: {
      1: { 'Nyzul Isle Investigation Tokens': 42000 },
      2: { 'Temenos Units': 9000, 'Apollyon Units': 12000 }
    }
  }, config);

  assert.equal(dashboard(db, config).characters.find((row) => row.character === 'Tackleberry').gil, 1234567);
  assert.deepEqual(keyItemView(db, config).rows.map((row) => row.name), ['Apollyon verification key']);
  assert.deepEqual(currencyView(db, config).rows.map((row) => row.amount), [42000, 12000, 9000]);

  ingestTelemetry(db, {
    character: 'Tackleberry',
    key_items: [],
    currencies: { 1: { 'Nyzul Isle Investigation Tokens': 43000 } }
  }, config);
  assert.equal(keyItemView(db, config).rows.length, 0);
  assert.equal(currencyView(db, config).rows.find((row) => row.page === 1).amount, 43000);
  assert.equal(currencyView(db, config).rows.filter((row) => row.page === 2).length, 2);
  db.close();
});

test('rotation chooses the least recently opened learned sector and keeps five events', () => {
  const events = [
    { chest: 'North', units: 3000, opened_at: '2026-08-09T05:00:00Z' },
    { chest: 'Central', units: 5000, opened_at: '2026-08-09T04:00:00Z' },
    { chest: 'East', units: 3000, opened_at: '2026-08-09T03:00:00Z' },
    { chest: 'West', units: 3000, opened_at: '2026-08-09T02:00:00Z' },
    { chest: 'North', units: 3000, opened_at: '2026-08-09T01:00:00Z' },
    { chest: 'Central', units: 3000, opened_at: '2026-08-09T00:00:00Z' }
  ];
  const rotation = computeRotation(events, ['North', 'West', 'East', 'Central']);
  assert.equal(rotation.next, 'West');
  assert.equal(rotation.last_bonus.chest, 'Central');
  assert.equal(rotation.recent.length, 5);
});

test('authoritative targets override stale labels and duplicate signatures are ignored', () => {
  const db = memoryDb();
  recordLimbusChest(db, {
    character: 'Tackleberry', area: 'Temenos', chest: 'North', target_id: 16929364,
    units: 5000, signature: 'tack-east'
  }, config);
  recordLimbusChest(db, {
    character: 'Tackleberry', area: 'Temenos', chest: 'North', target_id: 16929364,
    units: 5000, signature: 'tack-east'
  }, config);

  const events = db.prepare('SELECT character,chest FROM limbus_chest_events ORDER BY id').all();
  assert.equal(events.length, 1);
  assert.equal(events[0].character, 'Tackleberry');
  assert.equal(events[0].chest, 'East');
  db.close();
});

test('roaming unit rewards are rejected while explicit manual repairs remain valid', () => {
  const db = memoryDb();
  assert.throws(() => recordLimbusChest(db, {
    character: 'Dolomedes', area: 'Temenos', chest: 'North', target_id: 16929269,
    units: 3000, signature: 'roaming-question-mark'
  }, config), /Unrecognized Limbus rotation chest target/);

  recordLimbusChest(db, {
    character: 'Dolomedes', area: 'Temenos', chest: 'East', target_id: 910003,
    units: 3000, signature: 'Dolomedes:Temenos:East:3000:1:manual'
  }, config);
  const events = db.prepare('SELECT chest,target_id FROM limbus_chest_events').all();
  assert.equal(events.length, 1);
  assert.equal(events[0].chest, 'East');
  assert.equal(events[0].target_id, 910003);
  db.close();
});
