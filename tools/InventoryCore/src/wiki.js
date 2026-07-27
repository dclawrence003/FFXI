'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { stripMarkup } = require('./common');

function normalize(value) {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, '');
}

function buildIndex(root) {
  const index = new Map();
  const pending = [root];
  while (pending.length) {
    const directory = pending.pop();
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
      const full = path.join(directory, entry.name);
      if (entry.isDirectory()) pending.push(full);
      else if (entry.isFile() && entry.name.endsWith('.md')) {
        index.set(normalize(path.basename(entry.name, '.md')), full);
      }
    }
  }
  return index;
}

function cell(text, label) {
  const pattern = new RegExp(`<strong>${label}:<\\/strong><\\/td>\\s*<td[^>]*>([\\s\\S]*?)<\\/td>`, 'i');
  const match = text.match(pattern);
  return match ? stripMarkup(match[1]) : '';
}

const progressionRules = [
  ['Artifact armor', /\b(?:Reforged\s+)?Artifact Armor\b|\b(?:Apollyon|Temenos) AF\+1 items?\b/i],
  ['Relic armor', /\b(?:Reforged\s+)?Relic Armor\b/i],
  ['Empyrean armor', /\b(?:Reforged\s+)?Empyrean Armor\b/i],
  ['Limbus armor', /\bLimbus\b.{0,180}\b(?:AF\+1|armor|equipment|Homam|Nashira|Murzim|Shedir)\b|\b(?:AF\+1|armor|equipment|Homam|Nashira|Murzim|Shedir)\b.{0,180}\bLimbus\b/is],
  ['Salvage armor', /\bSalvage (?:Armor|equipment)\b/i],
  ['Abjuration armor', /\bAbjuration (?:Armor|equipment|gear)\b|\b(?:Purified|Cursed) (?:Abjuration )?(?:Armor|equipment|gear)\b|\bRe-cursing\b/i],
  ['Ambuscade armor', /\bAmbuscade (?:Armor|equipment)\b/i],
  ['Odyssey armor', /\bOdyssey\b.{0,100}\b(?:Armor|equipment|augment)\b|\b(?:Armor|equipment)\b.{0,100}\bOdyssey\b/is],
  ['Relic weapon', /\bRelic Weapons?\b/i],
  ['Mythic weapon', /\bMythic Weapons?\b/i],
  ['Empyrean weapon', /\bEmpyrean Weapons?\b/i],
  ['Aeonic weapon', /\bAeonic Weapons?\b/i],
  ['Ergon weapon', /\bErgon Weapons?\b/i],
  ['Prime weapon', /\bPrime Weapons?\b/i],
  ['Ultimate weapon augment', /\b(?:REMA(?:P)?|REMEA|REAM|Ultimate Weapon) (?:weapons?|augments?)\b/i]
];

function progressionContext(text) {
  const marker = text.search(/Used in the following Item Upgrades/i);
  const upgradeSection = marker >= 0 ? text.slice(marker, marker + 40000) : '';
  const lines = text.split(/\r?\n/);
  const directUseLines = [];
  for (let index = 0; index < lines.length; index += 1) {
    const neighborhood = lines.slice(Math.max(0, index - 1), index + 2).join(' ');
    if (/(?:used?|required|trade|upgrade|augment|creation process|trial|requisite|obtain)/i.test(neighborhood)) {
      directUseLines.push(neighborhood);
    }
  }
  return `${upgradeSection}\n${directUseLines.join('\n')}`;
}

function detectProgressionFamilies(text) {
  const context = progressionContext(text);
  return progressionRules
    .filter(([, pattern]) => pattern.test(context))
    .map(([family]) => family);
}

function parseWiki(file) {
  if (!file || !fs.existsSync(file)) return null;
  const text = fs.readFileSync(file, 'utf8');
  const resale = text.match(/(?:\*{0,2}NPC Resale(?: Price)?\*{0,2}|Resale Price|Resale):[^0-9]{0,120}([\d,]+)\s*(?:\[\[)?Gil/i);
  const headings = [...text.matchAll(/^#{2,4}\s+(.+)$/gm)].map((match) => stripMarkup(match[1]));
  const useWords = /(quest|upgrade|synthesis|craft|synergy|redeemed|used in|trial|augment)/i;
  const uses = headings.filter((heading) => useWords.test(heading)).slice(0, 8);
  const focusedUses = `${uses.join(' ')} ${text.match(/Used in the following \[\[(?:Synthesis|Synergy)\]\][\s\S]{0,100}/i)?.[0] || ''}`;
  const progressionFamilies = detectProgressionFamilies(text);
  return {
    file,
    description: cell(text, 'Description'),
    flagsText: cell(text, 'Flags'),
    wikiJobs: cell(text, 'Jobs'),
    vendorPrice: resale ? Number(resale[1].replace(/,/g, '')) : null,
    uses,
    hasQuestUse: /\bquest\b/i.test(uses.join(' ')) || /Used in (?:the following )?(?:quests?|missions?)/i.test(text),
    hasUpgradeUse: /Used in the following Item Upgrades/i.test(text) || /(item upgrades|upgraded?\s+(?:from|to)|requisite item)/i.test(uses.join(' ')),
    hasCraftUse: /(synthesis|synergy|craft)/i.test(focusedUses),
    hasProgressionUse: progressionFamilies.length > 0,
    progressionFamilies
  };
}

module.exports = { normalize, buildIndex, parseWiki, detectProgressionFamilies };
