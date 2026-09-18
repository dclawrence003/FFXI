'use strict';

const path = require('node:path');
process.env.FFXI_INVENTORY_CONFIG = path.join(__dirname, 'config.fixture.json');

const test = require('node:test');
const assert = require('node:assert/strict');
const { DatabaseSync } = require('node:sqlite');
const { initializeDb } = require('../src/db');
const { syncInventory } = require('../src/findall');

test('FindAll snapshot replacement removes stale inventory and preserves unrelated status', () => {
  const db = initializeDb(new DatabaseSync(':memory:'));
  db.prepare('INSERT INTO inventory(character,bag,item_id,count) VALUES (?,?,?,?)')
    .run('Dolomedes', 'inventory', 1, 1);
  db.prepare('INSERT INTO source_status(source,ok,updated_at,details) VALUES (?,?,?,?)')
    .run('Telemetry:Dolomedes', 1, 'old', 'keep me');

  const snapshot = {
    rows: [
      { character: 'Dolomedes', bag: 'inventory', itemId: 2, count: 3 },
      { character: 'Tackleberry', bag: 'safe', itemId: 3, count: 1 },
    ],
    sources: [
      { character: 'Dolomedes', file: 'Dolo.lua', ok: true, updatedAt: 'source-1' },
      { character: 'Tackleberry', file: 'Tackle.lua', ok: false, updatedAt: null },
    ],
  };
  syncInventory(db, snapshot, 'snapshot-2');

  assert.deepEqual(db.prepare('SELECT character,bag,item_id,count FROM inventory ORDER BY character').all().map((row) => ({ ...row })), [
    { character: 'Dolomedes', bag: 'inventory', item_id: 2, count: 3 },
    { character: 'Tackleberry', bag: 'safe', item_id: 3, count: 1 },
  ]);
  assert.equal(db.prepare("SELECT details FROM source_status WHERE source='Telemetry:Dolomedes'").get().details, 'keep me');
  assert.deepEqual(db.prepare("SELECT source,ok,updated_at FROM source_status WHERE source LIKE 'FindAll:%' ORDER BY source").all().map((row) => ({ ...row })), [
    { source: 'FindAll:Dolomedes', ok: 1, updated_at: 'source-1' },
    { source: 'FindAll:Tackleberry', ok: 0, updated_at: null },
  ]);
  assert.equal(db.prepare("SELECT updated_at FROM source_status WHERE source='Inventory snapshot'").get().updated_at, 'snapshot-2');
  db.close();
});
