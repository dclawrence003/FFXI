'use strict';

const path = require('node:path');
const { DatabaseSync } = require('node:sqlite');
const { runtimeDir, ensureRuntime } = require('./common');

function openDb() {
  ensureRuntime();
  const db = new DatabaseSync(path.join(runtimeDir, 'inventory.db'));
  db.exec(`
    PRAGMA journal_mode = WAL;
    CREATE TABLE IF NOT EXISTS items (
      id INTEGER PRIMARY KEY, name TEXT NOT NULL, long_name TEXT, category TEXT,
      level INTEGER, item_level INTEGER, jobs TEXT, description TEXT, flags_text TEXT,
      vendor_price INTEGER, wiki_file TEXT, wiki_uses TEXT, ah_category TEXT, stack_size INTEGER
    );
    CREATE TABLE IF NOT EXISTS inventory (
      character TEXT NOT NULL, bag TEXT NOT NULL, item_id INTEGER NOT NULL, count INTEGER NOT NULL,
      PRIMARY KEY (character, bag, item_id)
    );
    CREATE TABLE IF NOT EXISTS recommendations (
      item_id INTEGER PRIMARY KEY, action TEXT NOT NULL, confidence TEXT NOT NULL, reason TEXT NOT NULL,
      best_character TEXT, best_job TEXT, updated_at TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS ah_prices (
      item_id INTEGER PRIMARY KEY, server TEXT NOT NULL, stock INTEGER, median INTEGER, last INTEGER,
      sale_count INTEGER, sales_per_day REAL, last_sale_at TEXT, fetched_at TEXT, url TEXT,
      stack_stock INTEGER, stack_median INTEGER, stack_last INTEGER, stack_sale_count INTEGER,
      stack_sales_per_day REAL, stack_last_sale_at TEXT, stack_fetched_at TEXT, stack_url TEXT
    );
    CREATE TABLE IF NOT EXISTS source_status (
      source TEXT PRIMARY KEY, ok INTEGER NOT NULL, updated_at TEXT, details TEXT
    );
  `);
  const itemColumns = new Set(db.prepare('PRAGMA table_info(items)').all().map((column) => column.name));
  if (!itemColumns.has('ah_category')) db.exec('ALTER TABLE items ADD COLUMN ah_category TEXT');
  if (!itemColumns.has('stack_size')) db.exec('ALTER TABLE items ADD COLUMN stack_size INTEGER');
  const ahColumns = new Set(db.prepare('PRAGMA table_info(ah_prices)').all().map((column) => column.name));
  const ahAdditions = [
    ['stack_stock', 'INTEGER'], ['stack_median', 'INTEGER'], ['stack_last', 'INTEGER'],
    ['stack_sale_count', 'INTEGER'], ['stack_sales_per_day', 'REAL'],
    ['stack_last_sale_at', 'TEXT'], ['stack_fetched_at', 'TEXT'], ['stack_url', 'TEXT']
  ];
  for (const [name, type] of ahAdditions) {
    if (!ahColumns.has(name)) db.exec(`ALTER TABLE ah_prices ADD COLUMN ${name} ${type}`);
  }
  return db;
}

module.exports = { openDb };
