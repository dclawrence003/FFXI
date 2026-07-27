'use strict';

const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const configFile = process.env.FFXI_INVENTORY_CONFIG
  ? path.resolve(process.env.FFXI_INVENTORY_CONFIG)
  : path.join(root, 'config.json');
if (!fs.existsSync(configFile)) {
  throw new Error(
    `InventoryCore configuration not found: ${configFile}. ` +
    'Copy config.example.json to config.json and configure local paths.'
  );
}
const config = JSON.parse(fs.readFileSync(configFile, 'utf8'));
const runtimeDir = process.env.FFXI_INVENTORY_DATA
  ? path.resolve(process.env.FFXI_INVENTORY_DATA)
  : path.join(process.env.LOCALAPPDATA || root, 'FFXIInventory');

function ensureRuntime() {
  fs.mkdirSync(runtimeDir, { recursive: true });
}

function atomicWrite(file, contents) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const temp = `${file}.${process.pid}.tmp`;
  fs.writeFileSync(temp, contents, 'utf8');
  fs.renameSync(temp, file);
}

function htmlDecode(value = '') {
  return value
    .replace(/&#10;/g, '\n')
    .replace(/&quot;/g, '"')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>');
}

function stripMarkup(value = '') {
  return htmlDecode(value)
    .replace(/<br\s*\/?>/gi, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/\[\[([^|\]]+)\|([^\]]+)\]\]/g, '$2')
    .replace(/\[\[([^\]]+)\]\]/g, '$1')
    .replace(/\s+/g, ' ')
    .trim();
}

module.exports = { root, config, configFile, runtimeDir, ensureRuntime, atomicWrite, stripMarkup };
