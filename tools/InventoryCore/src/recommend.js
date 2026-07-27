'use strict';

const roleRank = { primary: 100, secondary: 75, future: 45 };

function evaluate(item, wiki, owners, config, ah = null) {
  const isGear = item.category === 'Armor' || item.category === 'Weapon';
  const matches = [];
  if (isGear && item.jobs.length) {
    for (const [character, profile] of Object.entries(config.characters)) {
      for (const job of item.jobs) {
        let role = null;
        if (profile.primary.includes(job)) role = 'primary';
        else if (profile.secondary.includes(job)) role = 'secondary';
        else if (config.policy.keepFutureJobGear) role = 'future';
        if (role) matches.push({ character, job, role, score: roleRank[role] });
      }
    }
    matches.sort((a, b) => b.score - a.score || a.character.localeCompare(b.character));
  }

  const teamCount = owners.reduce((sum, owner) => sum + owner.count, 0);
  const isProgressionReagent = wiki?.hasProgressionUse && !isGear && item.category !== 'Maze';
  if (isProgressionReagent) {
    const families = wiki.progressionFamilies?.join(', ') || 'equipment progression';
    return {
      action: 'UPGRADE',
      confidence: 'high',
      reason: `Protected upgrade reagent: ${families}`,
      bestCharacter: null,
      bestJob: null
    };
  }
  if (isGear && matches.length) {
    const best = matches[0];
    if (best.role === 'future') {
      return {
        action: 'KEEP',
        confidence: 'medium',
        reason: `Future-job equipment usable by the level-99 roster; team owns ${teamCount}`,
        bestCharacter: null,
        bestJob: best.job
      };
    }
    const label = best.role === 'future' ? 'future-job option' : `${best.role} ${best.job}`;
    return {
      action: 'KEEP',
      confidence: best.role === 'future' ? 'medium' : 'high',
      reason: `${best.character}: ${label}; team owns ${teamCount}`,
      bestCharacter: best.character,
      bestJob: best.job
    };
  }
  if (wiki?.hasUpgradeUse || wiki?.hasQuestUse) {
    return {
      action: 'KEEP',
      confidence: 'high',
      reason: wiki.hasUpgradeUse ? 'Local wiki indicates an upgrade use' : 'Local wiki indicates a quest use',
      bestCharacter: null,
      bestJob: null
    };
  }
  const vendorPrice = wiki?.vendorPrice || 0;
  const ahMedian = ah?.median || 0;
  const isTradeableMaterial = item.category === 'General' && item.flags === 4;
  const isAuctionable = item.ahCategory && !['@NONE', '0', '99'].includes(item.ahCategory);
  const protectedConsumableCategories = new Set(['@NINJA_TOOLS', '@AMMO', '@MEDICINE', '@FOOD', '@CRYSTALS']);
  const isVendorSafe = isTradeableMaterial && !protectedConsumableCategories.has(item.ahCategory);
  const lastSaleAgeDays = ah?.lastSaleAt
    ? (Date.now() - Date.parse(ah.lastSaleAt)) / 86400000
    : Infinity;
  if (isAuctionable && ahMedian && lastSaleAgeDays <= 60 && ahMedian >= Math.max(1000, vendorPrice * 1.5)) {
    return {
      action: 'AH',
      confidence: ah.salesPerDay >= 0.1 ? 'high' : 'medium',
      reason: `Valefor median ${ahMedian.toLocaleString()} gil; ${ah.salesPerDay.toFixed(3)}/day; stock ${ah.stock}`,
      bestCharacter: 'Dolomedes',
      bestJob: null
    };
  }
  if (isAuctionable && ahMedian >= Math.max(50000, vendorPrice * 10)) {
    return {
      action: 'AH',
      confidence: 'low',
      reason: `Valefor median ${ahMedian.toLocaleString()} gil, but last sale is ${Math.round(lastSaleAgeDays)} days old; expect a slow sale`,
      bestCharacter: 'Dolomedes',
      bestJob: null
    };
  }
  if (isVendorSafe && vendorPrice && (!ahMedian || lastSaleAgeDays > 120 || ahMedian < vendorPrice * 1.25)) {
    const ahReason = !ahMedian ? 'no Valefor sales' : lastSaleAgeDays > 120 ? 'Valefor sales are stale' : 'AH premium is too small';
    return {
      action: 'VENDOR',
      confidence: ah ? 'high' : 'medium',
      reason: `${vendorPrice.toLocaleString()} gil NPC resale; ${ahReason}`,
      bestCharacter: 'Dolomedes',
      bestJob: null
    };
  }
  if (wiki?.hasCraftUse) {
    return {
      action: 'HOLD',
      confidence: 'medium',
      reason: 'Possible crafting use; Dolomedes is the designated crafter',
      bestCharacter: 'Dolomedes',
      bestJob: null
    };
  }
  if (config.policy.dropAllowlist.includes(item.id)) {
    return { action: 'DROP', confidence: 'high', reason: 'Explicit drop allowlist', bestCharacter: null, bestJob: null };
  }
  if (isVendorSafe && wiki?.vendorPrice) {
    return {
      action: 'VENDOR',
      confidence: 'low',
      reason: `${wiki.vendorPrice.toLocaleString()} gil NPC resale; no usable Valefor history`,
      bestCharacter: 'Dolomedes',
      bestJob: null
    };
  }
  return {
    action: 'REVIEW',
    confidence: 'low',
    reason: 'No decisive local use or price evidence; never auto-drop',
    bestCharacter: null,
    bestJob: null
  };
}

module.exports = { evaluate };
