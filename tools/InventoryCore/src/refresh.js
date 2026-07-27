'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { config, runtimeDir, ensureRuntime, atomicWrite } = require('./common');
const { parseItems } = require('./resources');
const { readAll } = require('./findall');
const { buildIndex, normalize, parseWiki } = require('./wiki');
const { evaluate } = require('./recommend');
const { updatePrices } = require('./ffxiah');
const { loadVendorPrices } = require('./vendor');
const { openDb } = require('./db');

function luaQuote(value) {
  return `"${String(value).replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\r?\n/g, ' ')}"`;
}

async function main() {
  ensureRuntime();
  console.log('Reading Windower resources...');
  const resources = parseItems(config.paths.itemsResource);
  console.log(`Loaded ${resources.size.toLocaleString()} item records.`);
  const findAll = readAll(config.paths.findAll, Object.keys(config.characters));
  const uniqueIds = [...new Set(findAll.rows.map((row) => row.itemId))];
  console.log(`Found ${findAll.rows.length.toLocaleString()} bag entries and ${uniqueIds.length.toLocaleString()} unique items.`);
  console.log('Indexing local BG Wiki item pages...');
  const wikiIndex = buildIndex(config.paths.wikiItems);
  console.log('Loading static NPC resale prices...');
  const vendorResult = await loadVendorPrices();
  console.log(`Loaded ${vendorResult.prices.size.toLocaleString()} NPC resale prices${vendorResult.refreshed ? ' (source refreshed)' : ' (cached)'}.`);
  const ahCandidates = uniqueIds.filter((id) => {
    const category = vendorResult.ahCategories.get(id);
    return category && category !== '@NONE' && category !== '0' && category !== '99';
  }).map((id) => ({ id, stack: resources.get(id)?.stack || 1 }));
  console.log(`Updating cached Valefor AH prices for ${ahCandidates.length} auctionable items...`);
  const ahResult = await updatePrices(ahCandidates);
  console.log(`FFXIAH: ${ahResult.fetched} fetched, ${ahResult.cached} cached, ${ahResult.errors.length} errors.`);
  const db = openDb();
  const now = new Date().toISOString();

  db.exec('BEGIN IMMEDIATE');
  try {
    db.exec('DELETE FROM inventory; DELETE FROM items; DELETE FROM recommendations; DELETE FROM ah_prices; DELETE FROM source_status;');
    const insertInventory = db.prepare('INSERT INTO inventory(character,bag,item_id,count) VALUES (?,?,?,?)');
    for (const row of findAll.rows) insertInventory.run(row.character, row.bag, row.itemId, row.count);

    const insertItem = db.prepare(`INSERT INTO items
      (id,name,long_name,category,level,item_level,jobs,description,flags_text,vendor_price,wiki_file,wiki_uses,ah_category,stack_size)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)`);
    const insertRec = db.prepare(`INSERT INTO recommendations
      (item_id,action,confidence,reason,best_character,best_job,updated_at) VALUES (?,?,?,?,?,?,?)`);
    const insertAh = db.prepare(`INSERT INTO ah_prices
      (item_id,server,stock,median,last,sale_count,sales_per_day,last_sale_at,fetched_at,url,
       stack_stock,stack_median,stack_last,stack_sale_count,stack_sales_per_day,stack_last_sale_at,stack_fetched_at,stack_url)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`);
    const cache = {};

    for (const id of uniqueIds) {
      const item = resources.get(id) || {
        id, name: `Item ${id}`, longName: '', category: '', level: null, itemLevel: null, jobs: []
      };
      item.ahCategory = vendorResult.ahCategories.get(id) || null;
      const wikiFile = wikiIndex.get(normalize(item.name)) || wikiIndex.get(normalize(item.longName));
      const parsedWiki = parseWiki(wikiFile);
      const vendorPrice = parsedWiki?.vendorPrice ?? vendorResult.prices.get(id) ?? null;
      const wiki = parsedWiki
        ? { ...parsedWiki, vendorPrice }
        : {
            vendorPrice, uses: [], hasQuestUse: false, hasUpgradeUse: false,
            hasCraftUse: false, hasProgressionUse: false, progressionFamilies: []
          };
      const byOwner = new Map();
      for (const row of findAll.rows) {
        if (row.itemId !== id) continue;
        byOwner.set(row.character, (byOwner.get(row.character) || 0) + row.count);
      }
      const owners = [...byOwner].map(([character, count]) => ({ character, count }));
      const ahPair = ahResult.prices.get(id) || null;
      const ah = ahPair?.single || null;
      const recommendation = evaluate(item, wiki, owners, config, ah);
      insertItem.run(
        id, item.name, item.longName, item.category, item.level, item.itemLevel,
        JSON.stringify(item.jobs), wiki?.description || '', wiki?.flagsText || '',
        wiki?.vendorPrice ?? null, wiki?.file || null, JSON.stringify(wiki?.uses || []), item.ahCategory, item.stack || 1
      );
      insertRec.run(
        id, recommendation.action, recommendation.confidence, recommendation.reason,
        recommendation.bestCharacter, recommendation.bestJob, now
      );
      if (ahPair?.single || ahPair?.stack) {
        const single = ahPair.single || {};
        const stack = ahPair.stack || {};
        insertAh.run(
          id, single.server || stack.server || config.server,
          single.stock ?? null, single.median ?? null, single.last ?? null, single.saleCount ?? null,
          single.salesPerDay ?? null, single.lastSaleAt ?? null, single.fetchedAt ?? null, single.url ?? null,
          stack.stock ?? null, stack.median ?? null, stack.last ?? null, stack.saleCount ?? null,
          stack.salesPerDay ?? null, stack.lastSaleAt ?? null, stack.fetchedAt ?? null, stack.url ?? null
        );
      }
      cache[id] = { ...recommendation, name: item.name, owners };
    }

    const statusInsert = db.prepare('INSERT INTO source_status(source,ok,updated_at,details) VALUES (?,?,?,?)');
    statusInsert.run('Windower resources', 1, fs.statSync(config.paths.itemsResource).mtime.toISOString(), `${resources.size} items`);
    statusInsert.run('BG Wiki', 1, now, `${wikiIndex.size} indexed pages`);
    statusInsert.run(
      'NPC resale:LandSandBoat',
      1,
      fs.statSync(vendorResult.cacheFile).mtime.toISOString(),
      `${vendorResult.prices.size} prices; weekly cache; BG Wiki overrides`
    );
    for (const source of findAll.sources) {
      statusInsert.run(`FindAll:${source.character}`, source.ok ? 1 : 0, source.updatedAt, source.file);
    }
    statusInsert.run(
      'FFXIAH:Valefor',
      ahResult.errors.length === 0 ? 1 : 0,
      now,
      `${ahResult.prices.size}/${ahCandidates.length} priced; 12-hour cache; ${ahResult.errors.length} errors`
    );
    db.exec('COMMIT');

    const jsonFile = path.join(runtimeDir, 'recommendations.json');
    atomicWrite(jsonFile, JSON.stringify({ generatedAt: now, server: config.server, items: cache }, null, 2));
    const luaLines = [
      'return {',
      `  generated_at=${luaQuote(now)},`,
      `  server=${luaQuote(config.server)},`,
      '  items={'
    ];
    for (const [id, row] of Object.entries(cache)) {
      const ownerText = row.owners.map((owner) => `${owner.character} x${owner.count}`).join(', ');
      luaLines.push(`    [${id}]={name=${luaQuote(row.name)},action=${luaQuote(row.action)},confidence=${luaQuote(row.confidence)},reason=${luaQuote(row.reason)},owners=${luaQuote(ownerText)}},`);
    }
    luaLines.push('  }', '}');
    const addonData = path.join(config.paths.lootAdvisor, 'data', 'recommendations.lua');
    atomicWrite(addonData, `${luaLines.join('\n')}\n`);
    console.log(`Database: ${path.join(runtimeDir, 'inventory.db')}`);
    console.log(`LootAdvisor cache: ${addonData}`);
  } catch (error) {
    db.exec('ROLLBACK');
    throw error;
  } finally {
    db.close();
  }
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error.stack || error.message);
    process.exitCode = 1;
  });
}
module.exports = { main };
