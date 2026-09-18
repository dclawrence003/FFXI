'use strict';

const fs = require('node:fs');
const path = require('node:path');

const ignoredBags = new Set(['key items']);

function parseFindAll(file, character) {
  const lines = fs.readFileSync(file, 'utf8').split(/\r?\n/);
  const rows = [];
  let bag = null;
  for (const line of lines) {
    const bagMatch = line.match(/^\["(.+)"\] = \{$/);
    if (bagMatch) {
      bag = bagMatch[1];
      continue;
    }
    if (/^\s*\},/.test(line)) {
      bag = null;
      continue;
    }
    const item = line.match(/^\s*\["(\d+)"\] = (\d+),$/);
    if (bag && item && !ignoredBags.has(bag)) {
      rows.push({ character, bag, itemId: Number(item[1]), count: Number(item[2]) });
    }
  }
  return rows;
}

function readAll(directory, characterNames) {
  const rows = [];
  const sources = [];
  for (const character of characterNames) {
    const file = path.join(directory, `${character}.lua`);
    if (!fs.existsSync(file)) {
      sources.push({ character, file, ok: false, updatedAt: null });
      continue;
    }
    rows.push(...parseFindAll(file, character));
    sources.push({
      character,
      file,
      ok: true,
      updatedAt: fs.statSync(file).mtime.toISOString()
    });
  }
  return { rows, sources };
}

function syncInventory(db, snapshot, syncedAt = new Date().toISOString()) {
  if (!snapshot || !Array.isArray(snapshot.rows) || !Array.isArray(snapshot.sources)) {
    throw new TypeError('A complete FindAll snapshot is required.');
  }

  db.exec('BEGIN IMMEDIATE');
  try {
    db.exec('DELETE FROM inventory;');
    const insertInventory = db.prepare(
      'INSERT INTO inventory(character,bag,item_id,count) VALUES (?,?,?,?)'
    );
    for (const row of snapshot.rows) {
      insertInventory.run(row.character, row.bag, row.itemId, row.count);
    }

    db.prepare("DELETE FROM source_status WHERE source LIKE 'FindAll:%' OR source='Inventory snapshot'").run();
    const insertStatus = db.prepare(`INSERT INTO source_status(source,ok,updated_at,details)
      VALUES (?,?,?,?) ON CONFLICT(source) DO UPDATE SET
      ok=excluded.ok,updated_at=excluded.updated_at,details=excluded.details`);
    for (const source of snapshot.sources) {
      insertStatus.run(`FindAll:${source.character}`, source.ok ? 1 : 0, source.updatedAt, source.file);
    }
    insertStatus.run('Inventory snapshot', 1, syncedAt, `${snapshot.rows.length} bag entries`);
    db.exec('COMMIT');
  } catch (error) {
    try { db.exec('ROLLBACK'); } catch { /* transaction was already closed */ }
    throw error;
  }

  return { rows: snapshot.rows.length, syncedAt };
}

module.exports = { parseFindAll, readAll, syncInventory };
