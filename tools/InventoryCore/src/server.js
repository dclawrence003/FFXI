'use strict';

const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const { URL } = require('node:url');
const { root, config, runtimeDir } = require('./common');
const { openDb } = require('./db');
const { main: refreshInventory } = require('./refresh');
const { parseItems } = require('./resources');
const { buildIndex, normalize, parseWiki } = require('./wiki');
const { parseItemBasic } = require('./vendor');
const { evaluate } = require('./recommend');
const { getPriceState } = require('./ffxiah');

const host = '127.0.0.1';
const port = Number(process.env.FFXI_INVENTORY_PORT || 8787);
const publicDir = path.join(root, 'public');
const resourceItems = parseItems(config.paths.itemsResource);
const wikiIndex = buildIndex(config.paths.wikiItems);
const vendorCache = path.join(runtimeDir, 'landsandboat-item-basic.sql');
const vendorCatalog = fs.existsSync(vendorCache)
  ? parseItemBasic(fs.readFileSync(vendorCache, 'utf8'))
  : { prices: new Map(), ahCategories: new Map() };

const types = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8' };

function json(response, value) {
  response.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });
  response.end(JSON.stringify(value));
}

function lootRecommendation(itemId, db) {
  const item = resourceItems.get(itemId);
  if (!item) return null;

  item.ahCategory = vendorCatalog.ahCategories.get(itemId) || null;
  const wikiFile = wikiIndex.get(normalize(item.name)) || wikiIndex.get(normalize(item.longName));
  const parsedWiki = parseWiki(wikiFile);
  const vendorPrice = parsedWiki?.vendorPrice ?? vendorCatalog.prices.get(itemId) ?? null;
  const wiki = parsedWiki
    ? { ...parsedWiki, vendorPrice }
    : {
        vendorPrice, uses: [], hasQuestUse: false, hasUpgradeUse: false,
        hasCraftUse: false, hasProgressionUse: false, progressionFamilies: []
      };
  const owners = db.prepare(
    'SELECT character,SUM(count) count FROM inventory WHERE item_id=? GROUP BY character ORDER BY character'
  ).all(itemId);
  const auctionable = item.ahCategory && !['@NONE', '0', '99'].includes(item.ahCategory);
  const priceState = auctionable
    ? getPriceState({ id: itemId, stack: item.stack || 1 })
    : { pair: null, pending: false };
  const ah = priceState.pair?.single || null;
  const recommendation = evaluate(item, wiki, owners, config, ah);

  if (priceState.pending) {
    recommendation.reason += ' | Valefor price refresh queued';
  }
  if (!ah && priceState.pending && ['REVIEW', 'VENDOR'].includes(recommendation.action)) {
    const vendor = vendorPrice ? `; NPC resale ${vendorPrice.toLocaleString()} gil` : '';
    recommendation.action = 'REVIEW';
    recommendation.confidence = 'low';
    recommendation.reason = `${item.category || 'Item'}${vendor} | Valefor price lookup queued`;
  }

  return {
    ...recommendation,
    name: item.name,
    owners: owners.map((owner) => `${owner.character} x${owner.count}`).join(', '),
    market_pending: priceState.pending
  };
}

function api(url, response) {
  const db = openDb();
  try {
    if (url.pathname === '/api/status') {
      return json(response, db.prepare('SELECT * FROM source_status ORDER BY source').all());
    }
    if (url.pathname === '/api/summary') {
      const totals = db.prepare(`SELECT COUNT(DISTINCT i.item_id) unique_items, SUM(i.count) total_items,
        COUNT(DISTINCT i.character) characters FROM inventory i`).get();
      const actions = db.prepare('SELECT action,COUNT(*) count FROM recommendations GROUP BY action ORDER BY count DESC').all();
      return json(response, { ...totals, actions });
    }
    if (url.pathname === '/api/loot') {
      const itemId = Number(url.searchParams.get('id'));
      const row = Number.isInteger(itemId) && itemId > 0
        ? lootRecommendation(itemId, db)
        : null;
      if (!row) {
        response.writeHead(404, { 'Content-Type': 'application/json; charset=utf-8' });
        response.end(JSON.stringify({ error: 'Unknown item' }));
        return;
      }
      return json(response, row);
    }
    if (url.pathname === '/api/items') {
      const search = `%${(url.searchParams.get('q') || '').toLowerCase()}%`;
      const character = url.searchParams.get('character') || '';
      const action = url.searchParams.get('action') || '';
      const rows = db.prepare(`
        SELECT x.*, GROUP_CONCAT(x.character || ' (' || x.bags || ') x' || x.count, '; ') owners
        FROM (
          SELECT it.id,it.name,it.category,it.level,it.item_level,it.jobs,it.description,it.vendor_price,it.wiki_file,it.wiki_uses,it.ah_category,
            r.action,r.confidence,r.reason,r.best_character,r.best_job,
            ah.median ah_median,ah.last ah_last,ah.stock ah_stock,ah.sales_per_day,ah.last_sale_at,ah.fetched_at ah_fetched_at,ah.url ah_url,
            inv.character,GROUP_CONCAT(inv.bag, ', ') bags,SUM(inv.count) count
          FROM items it JOIN recommendations r ON r.item_id=it.id JOIN inventory inv ON inv.item_id=it.id
          LEFT JOIN ah_prices ah ON ah.item_id=it.id
          WHERE lower(it.name) LIKE ? AND (?='' OR inv.character=?) AND (?='' OR r.action=?)
          GROUP BY it.id,inv.character
        ) x GROUP BY x.id ORDER BY
          CASE x.action WHEN 'KEEP' THEN 1 WHEN 'UPGRADE' THEN 2 WHEN 'AH' THEN 3 WHEN 'HOLD' THEN 4 WHEN 'REVIEW' THEN 5 WHEN 'VENDOR' THEN 6 ELSE 7 END,
          x.name LIMIT 1000`).all(search, character, character, action, action);
      return json(response, rows);
    }
    if (url.pathname === '/api/bag-items') {
      const rows = db.prepare(`
        SELECT inv.character,inv.bag,inv.item_id id,inv.count,
          it.name,it.category,it.item_level,it.vendor_price,it.ah_category,it.stack_size,
          r.action,r.confidence,r.reason,
          ah.median ah_median,ah.stock ah_stock,ah.sales_per_day,ah.last_sale_at,ah.url ah_url,
          ah.stack_median,ah.stack_stock,ah.stack_sales_per_day,ah.stack_last_sale_at,ah.stack_url
        FROM inventory inv
        JOIN items it ON it.id=inv.item_id
        JOIN recommendations r ON r.item_id=inv.item_id
        LEFT JOIN ah_prices ah ON ah.item_id=inv.item_id
        ORDER BY inv.character,inv.bag,it.name`).all();
      return json(response, rows);
    }
    response.writeHead(404).end();
  } finally {
    db.close();
  }
}

const server = http.createServer((request, response) => {
  const url = new URL(request.url, `http://${host}:${port}`);
  if (url.pathname.startsWith('/api/')) return api(url, response);
  const requested = url.pathname === '/' ? 'index.html' : url.pathname.slice(1);
  const file = path.resolve(publicDir, requested);
  if (!file.startsWith(publicDir) || !fs.existsSync(file)) {
    response.writeHead(404).end('Not found');
    return;
  }
  response.writeHead(200, { 'Content-Type': types[path.extname(file)] || 'application/octet-stream' });
  fs.createReadStream(file).pipe(response);
});

server.listen(port, host, () => {
  console.log(`FFXI Inventory dashboard: http://${host}:${port}`);
  console.log('Watching FindAll for inventory changes...');
});

let refreshTimer = null;
fs.watch(config.paths.findAll, { persistent: true }, (_event, filename) => {
  if (!filename || !filename.toLowerCase().endsWith('.lua')) return;
  clearTimeout(refreshTimer);
  refreshTimer = setTimeout(async () => {
    try {
      console.log(`FindAll changed (${filename}); refreshing InventoryCore.`);
      await refreshInventory();
    } catch (error) {
      console.error(`Automatic refresh failed: ${error.stack || error.message}`);
    }
  }, 5000);
});
