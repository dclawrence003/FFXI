'use strict';

const path = require('node:path');
process.env.FFXI_INVENTORY_CONFIG = path.join(__dirname, 'config.fixture.json');

const test = require('node:test');
const assert = require('node:assert/strict');
const { jobList } = require('../src/resources');
const { evaluate } = require('../src/recommend');
const { parseBaseSell } = require('../src/vendor');
const { parseItemBasic } = require('../src/vendor');
const { detectProgressionFamilies } = require('../src/wiki');
const config = require('./config.fixture.json');

test('Windower job mask maps RNG and SAM', () => {
  assert.deepEqual(jobList(6144), ['RNG', 'SAM']);
});

test('primary role wins gear recommendation', () => {
  const result = evaluate(
    { category: 'Armor', jobs: ['SAM'] },
    null,
    [{ character: 'Tackleberry', count: 1 }],
    config
  );
  assert.equal(result.action, 'KEEP');
  assert.equal(result.bestCharacter, 'Kickpuncher');
  assert.equal(result.confidence, 'high');
});

test('unknown materials are never auto-dropped', () => {
  const result = evaluate({ id: 1, category: 'General', jobs: [] }, null, [], config);
  assert.equal(result.action, 'REVIEW');
});

test('JSE armor materials receive the dedicated upgrade recommendation', () => {
  const result = evaluate(
    { id: 9001, category: 'General', jobs: [] },
    { hasProgressionUse: true, progressionFamilies: ['Artifact armor'] },
    [],
    config
  );
  assert.equal(result.action, 'UPGRADE');
  assert.equal(result.confidence, 'high');
});

test('local wiki progression detector recognizes REMAP and armor families', () => {
  assert.deepEqual(
    detectProgressionFamilies('Used in the following Item Upgrades\n[[Reforged Empyrean Armor +3]]'),
    ['Empyrean armor']
  );
  assert.deepEqual(
    detectProgressionFamilies('Used in the following Item Upgrades\n[[Ultimate Weapon Augments]]\nUsed to upgrade REMEA weapons with attributes.'),
    ['Ultimate weapon augment']
  );
  assert.deepEqual(
    detectProgressionFamilies('A tiny key used to obtain abjurations via the Gobbie Mystery Box.'),
    []
  );
});

test('future-job gear is kept without arbitrary character assignment', () => {
  const result = evaluate(
    { category: 'Armor', jobs: ['DRK'] },
    null,
    [{ character: 'Achoo', count: 1 }],
    config
  );
  assert.equal(result.action, 'KEEP');
  assert.equal(result.bestCharacter, null);
  assert.equal(result.confidence, 'medium');
});

test('recent Valefor sale can produce an AH recommendation', () => {
  const result = evaluate(
    { id: 3544, category: 'General', flags: 4, jobs: [], ahCategory: '@MATERIALS' },
    { vendorPrice: 11000, hasUpgradeUse: false, hasQuestUse: false, hasCraftUse: true },
    [{ character: 'Tackleberry', count: 2 }],
    config,
    { median: 1200000, lastSaleAt: new Date().toISOString(), salesPerDay: 0.05, stock: 1 }
  );
  assert.equal(result.action, 'AH');
});

test('vendor wins when AH has no history', () => {
  const result = evaluate(
    { id: 8719, category: 'General', flags: 4, jobs: [] },
    { vendorPrice: 11000, hasUpgradeUse: false, hasQuestUse: false, hasCraftUse: true },
    [],
    config,
    { median: null, lastSaleAt: null, salesPerDay: 0, stock: 0 }
  );
  assert.equal(result.action, 'VENDOR');
});

test('usable scrolls are not vendor recommendations', () => {
  const result = evaluate(
    { id: 4849, category: 'Usable', flags: 1540, jobs: [] },
    { vendorPrice: 6862, hasUpgradeUse: false, hasQuestUse: false, hasCraftUse: false },
    [],
    config,
    null
  );
  assert.equal(result.action, 'REVIEW');
});

test('auctionable song scrolls can receive an AH recommendation', () => {
  const result = evaluate(
    { id: 5078, category: 'Usable', flags: 2052, ahCategory: '@SONGS', jobs: [] },
    { vendorPrice: 3000, hasUpgradeUse: false, hasQuestUse: false, hasCraftUse: false },
    [],
    config,
    { median: 50000, lastSaleAt: new Date().toISOString(), salesPerDay: 0.2, stock: 1 }
  );
  assert.equal(result.action, 'AH');
});

test('ninja tools are protected from vendor recommendations', () => {
  const result = evaluate(
    { id: 1179, category: 'General', flags: 4, ahCategory: '@NINJA_TOOLS', jobs: [] },
    { vendorPrice: 25, hasUpgradeUse: false, hasQuestUse: false, hasCraftUse: false },
    [],
    config,
    { median: null, lastSaleAt: null, salesPerDay: 0, stock: 0 }
  );
  assert.equal(result.action, 'REVIEW');
});

test('LandSandBoat BaseSell rows are parsed by item ID', () => {
  const sql = "INSERT INTO `item_basic` VALUES (8719,0,'piece_of_maliyakaleya_coral','maliya._coral','x',@GENERAL_TYPE,12,@FLAG_MYSTERY_BOX,@BONECRAFT,11000);";
  assert.equal(parseBaseSell(sql).get(8719), 11000);
});

test('multiline LandSandBoat equipment rows retain AH category', () => {
  const sql = "INSERT INTO `item_basic` VALUES (26335,0,'klouskap_sash','klouskap_sash','x',@EQUIPMENT_TYPE,1,@FLAG_MYSTERY_BOX |\n@FLAG_CANEQUIP,@WAIST,10202);";
  const parsed = parseItemBasic(sql);
  assert.equal(parsed.ahCategories.get(26335), '@WAIST');
  assert.equal(parsed.prices.get(26335), 10202);
});

test('FFXIAH parser records explicit single and stack modes', () => {
  const { parsePage } = require('../src/ffxiah');
  const html = 'Site.server = "Valefor"; Item.sales = [{"saleon":1780000000,"price":60000}]; <span class=stock>2</span>';
  assert.equal(parsePage(html, 3522, 'stack').mode, 'stack');
  assert.match(parsePage(html, 3522, 'single').url, /item\/3522$/);
});
