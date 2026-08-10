'use strict';

const path = require('node:path');
const { DatabaseSync } = require('node:sqlite');
const { runtimeDir, ensureRuntime } = require('./common');

function initializeDb(db) {
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
    CREATE TABLE IF NOT EXISTS character_state (
      character TEXT PRIMARY KEY, gil INTEGER, observed_at TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS key_items (
      character TEXT NOT NULL, item_id INTEGER NOT NULL, name TEXT NOT NULL,
      observed_at TEXT NOT NULL, PRIMARY KEY(character,item_id)
    );
    CREATE TABLE IF NOT EXISTS currencies (
      character TEXT NOT NULL, page INTEGER NOT NULL, name TEXT NOT NULL,
      amount INTEGER NOT NULL, observed_at TEXT NOT NULL,
      PRIMARY KEY(character,page,name)
    );
    CREATE TABLE IF NOT EXISTS limbus_chest_targets (
      area TEXT NOT NULL, target_id INTEGER NOT NULL, chest TEXT NOT NULL,
      learned_at TEXT NOT NULL, PRIMARY KEY(area,target_id)
    );
    CREATE TABLE IF NOT EXISTS limbus_chest_events (
      id INTEGER PRIMARY KEY AUTOINCREMENT, character TEXT NOT NULL,
      area TEXT NOT NULL, chest TEXT, target_id INTEGER NOT NULL,
      units INTEGER NOT NULL, opened_at TEXT NOT NULL, signature TEXT NOT NULL UNIQUE
    );
    CREATE INDEX IF NOT EXISTS idx_limbus_character_area_time
      ON limbus_chest_events(character,area,opened_at DESC);
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

function openDb() {
  ensureRuntime();
  return initializeDb(new DatabaseSync(path.join(runtimeDir, 'inventory.db')));
}

module.exports = { openDb, initializeDb };
