'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { runtimeDir, ensureRuntime, atomicWrite } = require('./common');

const sourceUrl = 'https://raw.githubusercontent.com/LandSandBoat/server/base/sql/item_basic.sql';
const cacheFile = path.join(runtimeDir, 'landsandboat-item-basic.sql');
const ttlMs = 7 * 24 * 60 * 60 * 1000;

function parseItemBasic(sql) {
  const prices = new Map();
  const ahCategories = new Map();
  const rows = /INSERT INTO `item_basic` VALUES \((\d+),([\s\S]*?)\);/g;
  let match;
  while ((match = rows.exec(sql))) {
    const tail = match[2].match(/,([^,]+),(\d+)\s*$/);
    if (!tail) continue;
    ahCategories.set(Number(match[1]), tail[1].trim());
    const price = Number(tail[2]);
    if (price > 0) prices.set(Number(match[1]), price);
  }
  return { prices, ahCategories };
}

function parseBaseSell(sql) {
  return parseItemBasic(sql).prices;
}

async function loadVendorPrices() {
  ensureRuntime();
  let refreshed = false;
  const fresh = fs.existsSync(cacheFile) && Date.now() - fs.statSync(cacheFile).mtimeMs < ttlMs;
  if (!fresh) {
    const response = await fetch(sourceUrl, {
      headers: { 'User-Agent': 'FFXI-InventoryCore/0.2 (personal vendor-price cache)' },
      signal: AbortSignal.timeout(30000)
    });
    if (!response.ok) throw new Error(`LandSandBoat vendor source returned HTTP ${response.status}`);
    atomicWrite(cacheFile, await response.text());
    refreshed = true;
  }
  const parsed = parseItemBasic(fs.readFileSync(cacheFile, 'utf8'));
  return { ...parsed, refreshed, sourceUrl, cacheFile };
}

module.exports = { parseBaseSell, parseItemBasic, loadVendorPrices };
