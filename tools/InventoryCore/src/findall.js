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

module.exports = { parseFindAll, readAll };
