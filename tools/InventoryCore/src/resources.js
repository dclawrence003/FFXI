'use strict';

const fs = require('node:fs');

const jobs = [
  null, 'WAR', 'MNK', 'WHM', 'BLM', 'RDM', 'THF', 'PLD', 'DRK', 'BST', 'BRD',
  'RNG', 'SAM', 'NIN', 'DRG', 'SMN', 'BLU', 'COR', 'PUP', 'DNC', 'SCH', 'GEO', 'RUN'
];

function field(body, name) {
  const quoted = body.match(new RegExp(`(?:^|,)${name}="((?:[^"\\\\]|\\\\.)*)"`));
  if (quoted) return quoted[1].replace(/\\"/g, '"').replace(/\\\\/g, '\\');
  const numeric = body.match(new RegExp(`(?:^|,)${name}=(-?\\d+)`));
  return numeric ? Number(numeric[1]) : null;
}

function jobList(mask) {
  if (!mask) return [];
  const result = [];
  for (let id = 1; id <= 22; id += 1) {
    if ((mask & (2 ** id)) !== 0) result.push(jobs[id]);
  }
  return result;
}

function parseItems(file) {
  const text = fs.readFileSync(file, 'utf8');
  const items = new Map();
  const record = /^\s*\[(\d+)\]\s*=\s*\{(.+)\},\s*$/gm;
  let match;
  while ((match = record.exec(text))) {
    const id = Number(match[1]);
    const body = match[2];
    const jobsMask = field(body, 'jobs');
    items.set(id, {
      id,
      name: field(body, 'en') || `Item ${id}`,
      longName: field(body, 'enl') || '',
      category: field(body, 'category') || '',
      flags: field(body, 'flags') || 0,
      stack: field(body, 'stack') || 1,
      level: field(body, 'level'),
      itemLevel: field(body, 'item_level'),
      jobsMask,
      jobs: jobList(jobsMask),
      slots: field(body, 'slots') || 0
    });
  }
  return items;
}

module.exports = { parseItems, jobList };
