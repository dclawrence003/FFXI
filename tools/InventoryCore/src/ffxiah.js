'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { runtimeDir, ensureRuntime, atomicWrite } = require('./common');

const cacheFile = path.join(runtimeDir, 'ffxiah-valefor.json');
const serverId = 9;
const ttlMs = 12 * 60 * 60 * 1000;
const inFlight = new Map();

function median(values) {
  if (!values.length) return null;
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[middle] : Math.round((sorted[middle - 1] + sorted[middle]) / 2);
}

function parsePage(html, itemId, mode = 'single') {
  const server = html.match(/Site\.server\s*=\s*"([^"]+)"/)?.[1];
  if (server !== 'Valefor') throw new Error(`FFXIAH returned ${server || 'an unknown server'} instead of Valefor`);
  const salesJson = html.match(/Item\.sales\s*=\s*(\[[\s\S]*?\]);/)?.[1] || '[]';
  const sales = JSON.parse(salesJson);
  const stock = Number(html.match(/<span class=stock>(\d+)<\/span>/i)?.[1] || 0);
  const prices = sales.map((sale) => Number(sale.price)).filter(Number.isFinite);
  const newest = sales.reduce((value, sale) => Math.max(value, Number(sale.saleon) || 0), 0);
  const oldest = sales.reduce((value, sale) => Math.min(value, Number(sale.saleon) || value), newest || 0);
  const nowSeconds = Date.now() / 1000;
  const observedDays = oldest ? Math.max(1, Math.min(90, (nowSeconds - oldest) / 86400)) : 90;
  const recentSales = sales.filter((sale) => nowSeconds - Number(sale.saleon) <= 90 * 86400).length;
  return {
    itemId,
    server: 'Valefor',
    stock,
    median: median(prices),
    last: prices.length ? Number(sales[0].price) : null,
    saleCount: sales.length,
    salesPerDay: Number((recentSales / observedDays).toFixed(3)),
    lastSaleAt: newest ? new Date(newest * 1000).toISOString() : null,
    fetchedAt: new Date().toISOString(),
    mode,
    url: `https://www.ffxiah.com/item/${itemId}${mode === 'stack' ? '?stack=1' : ''}`
  };
}

function readCache() {
  ensureRuntime();
  if (!fs.existsSync(cacheFile)) return {};
  try {
    return JSON.parse(fs.readFileSync(cacheFile, 'utf8'));
  } catch {
    return {};
  }
}

async function fetchPrice(itemId, mode) {
  const url = `https://www.ffxiah.com/item/${itemId}${mode === 'stack' ? '?stack=1' : ''}`;
  const response = await fetch(url, {
    headers: {
      'Cookie': `sid=${serverId}`,
      'User-Agent': 'FFXI-InventoryCore/0.2 (personal, cached price lookup)',
      'Accept': 'text/html'
    },
    redirect: 'follow',
    signal: AbortSignal.timeout(15000)
  });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  return parsePage(await response.text(), itemId, mode);
}

async function updatePrices(items) {
  const oldCache = readCache();
  const cache = { ...oldCache };
  for (const item of items) {
    const existing = oldCache[item.id] || {};
    cache[item.id] = existing.single || existing.stack
      ? existing
      : { single: null, stack: existing.median !== undefined ? existing : null };
  }
  const now = Date.now();
  const pending = [];
  for (const item of items) {
    for (const mode of item.stack > 1 ? ['single', 'stack'] : ['single']) {
      const fetchedAt = cache[item.id]?.[mode]?.fetchedAt;
      if (!fetchedAt || now - Date.parse(fetchedAt) > ttlMs) pending.push({ id: item.id, mode });
    }
  }
  const errors = [];
  let cursor = 0;
  const workers = Array.from({ length: 3 }, async () => {
    while (cursor < pending.length) {
      const job = pending[cursor++];
      try {
        cache[job.id] = cache[job.id] || { single: null, stack: null };
        cache[job.id][job.mode] = await fetchPrice(job.id, job.mode);
      } catch (error) {
        errors.push(`${job.id}/${job.mode}: ${error.message}`);
      }
      await new Promise((resolve) => setTimeout(resolve, 250));
    }
  });
  await Promise.all(workers);
  atomicWrite(cacheFile, JSON.stringify(cache, null, 2));
  return {
    prices: new Map(items.filter((item) => cache[item.id]).map((item) => [item.id, cache[item.id]])),
    fetched: pending.length - errors.length,
    cached: items.reduce((sum, item) => sum + (item.stack > 1 ? 2 : 1), 0) - pending.length,
    errors
  };
}

function modesFor(item) {
  return item.stack > 1 ? ['single', 'stack'] : ['single'];
}

function needsRefresh(pair, item) {
  return modesFor(item).some((mode) => {
    const fetchedAt = pair?.[mode]?.fetchedAt;
    return !fetchedAt || Date.now() - Date.parse(fetchedAt) > ttlMs;
  });
}

function queuePrice(item) {
  const key = Number(item.id);
  if (inFlight.has(key)) return true;
  const initialCache = readCache();
  if (!needsRefresh(initialCache[key], item)) return false;

  const task = (async () => {
    const cache = readCache();
    const pair = cache[key] || { single: null, stack: null };
    for (const mode of modesFor(item)) {
      const fetchedAt = pair[mode]?.fetchedAt;
      if (!fetchedAt || Date.now() - Date.parse(fetchedAt) > ttlMs) {
        pair[mode] = await fetchPrice(key, mode);
        await new Promise((resolve) => setTimeout(resolve, 250));
      }
    }
    // Re-read after the network waits so concurrent first-time lookups merge
    // their results instead of the last completed lookup replacing the rest.
    const latestCache = readCache();
    latestCache[key] = pair;
    atomicWrite(cacheFile, JSON.stringify(latestCache, null, 2));
  })()
    .catch((error) => console.error(`FFXIAH live lookup ${key}: ${error.message}`))
    .finally(() => inFlight.delete(key));

  inFlight.set(key, task);
  return true;
}

function getPriceState(item) {
  const pair = readCache()[Number(item.id)] || null;
  return {
    pair,
    pending: queuePrice(item)
  };
}

module.exports = { parsePage, updatePrices, getPriceState };
