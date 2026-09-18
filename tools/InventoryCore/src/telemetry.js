'use strict';

const LIMBUS_SECTORS = {
  Temenos: ['North', 'West', 'East', 'Central'],
  Apollyon: ['NW', 'SW', 'NE', 'SE']
};

const LIMBUS_FINAL_TARGETS = {
  Temenos: {
    16929362: 'North', 16929363: 'West',
    16929364: 'East', 16929365: 'Central'
  },
  Apollyon: {
    16933563: 'NW', 16933564: 'SW',
    16933565: 'NE', 16933566: 'SE'
  }
};

const LIMBUS_MANUAL_TARGETS = {
  Temenos: { 910001: 'North', 910002: 'West', 910003: 'East', 910004: 'Central' },
  Apollyon: { 920001: 'NW', 920002: 'SW', 920003: 'NE', 920004: 'SE' }
};

function isoNow() {
  return new Date().toISOString();
}

function validCharacter(character, config) {
  return typeof character === 'string'
    && Object.prototype.hasOwnProperty.call(config.characters || {}, character);
}

function finiteInteger(value) {
  return Number.isFinite(Number(value)) ? Math.trunc(Number(value)) : null;
}

function withTransaction(db, operation) {
  db.exec('BEGIN IMMEDIATE');
  try {
    const result = operation();
    db.exec('COMMIT');
    return result;
  } catch (error) {
    db.exec('ROLLBACK');
    throw error;
  }
}

function ingestTelemetry(db, payload, config) {
  if (!payload || !validCharacter(payload.character, config)) {
    throw new Error('Unknown or missing character.');
  }
  const character = payload.character;
  const observedAt = isoNow();

  return withTransaction(db, () => {
    const gil = finiteInteger(payload.gil);
    if (gil !== null && gil >= 0) {
      db.prepare(`INSERT INTO character_state(character,gil,observed_at)
        VALUES(?,?,?) ON CONFLICT(character) DO UPDATE SET
        gil=excluded.gil,observed_at=excluded.observed_at`).run(character, gil, observedAt);
    } else {
      db.prepare(`INSERT INTO character_state(character,observed_at)
        VALUES(?,?) ON CONFLICT(character) DO UPDATE SET
        observed_at=excluded.observed_at`).run(character, observedAt);
    }

    if (Array.isArray(payload.key_items)) {
      const remove = db.prepare('DELETE FROM key_items WHERE character=?');
      const insert = db.prepare(`INSERT INTO key_items(character,item_id,name,observed_at)
        VALUES(?,?,?,?)`);
      remove.run(character);
      for (const item of payload.key_items.slice(0, 4096)) {
        const id = finiteInteger(item?.id);
        const name = typeof item?.name === 'string' ? item.name.trim().slice(0, 160) : '';
        if (id !== null && id > 0 && name) insert.run(character, id, name, observedAt);
      }
    }

    if (payload.currencies && typeof payload.currencies === 'object') {
      const remove = db.prepare('DELETE FROM currencies WHERE character=? AND page=?');
      const insert = db.prepare(`INSERT INTO currencies(character,page,name,amount,observed_at)
        VALUES(?,?,?,?,?)`);
      for (const [pageName, values] of Object.entries(payload.currencies)) {
        const page = pageName === '2' || pageName === 'Currencies 2' ? 2 : 1;
        if (!values || typeof values !== 'object') continue;
        remove.run(character, page);
        for (const [rawName, rawAmount] of Object.entries(values).slice(0, 512)) {
          const amount = finiteInteger(rawAmount);
          const name = String(rawName).trim().slice(0, 160);
          if (amount !== null && name && !name.startsWith('_')) {
            insert.run(character, page, name, amount, observedAt);
          }
        }
      }
    }

    if (payload.equipment && typeof payload.equipment === 'object') {
      const upsert = db.prepare(`INSERT INTO equipment
        (character,slot,item_id,name,bag,bag_index,observed_at)
        VALUES(?,?,?,?,?,?,?) ON CONFLICT(character,slot) DO UPDATE SET
        item_id=excluded.item_id,name=excluded.name,bag=excluded.bag,
        bag_index=excluded.bag_index,observed_at=excluded.observed_at`);
      for (const slot of ['main']) {
        const equipped = payload.equipment[slot];
        if (!equipped || typeof equipped !== 'object') continue;
        const itemId = finiteInteger(equipped.id);
        const rawName = typeof equipped.name === 'string' ? equipped.name.trim().slice(0, 160) : '';
        const name = itemId === 0 ? 'Unequipped' : rawName;
        const bag = equipped.bag === null || equipped.bag === undefined
          ? null : finiteInteger(equipped.bag);
        const bagIndex = equipped.index === null || equipped.index === undefined
          ? null : finiteInteger(equipped.index);
        if (itemId !== null && itemId >= 0 && name) {
          upsert.run(character, slot, itemId, name, bag, bagIndex, observedAt);
        }
      }
    }

    db.prepare(`INSERT INTO source_status(source,ok,updated_at,details)
      VALUES(?,1,?,?) ON CONFLICT(source) DO UPDATE SET
      ok=1,updated_at=excluded.updated_at,details=excluded.details`)
      .run(`Telemetry:${character}`, observedAt, 'LootAdvisor character telemetry');
    return { character, observed_at: observedAt };
  });
}

function recordLimbusChest(db, payload, config) {
  if (!payload || !validCharacter(payload.character, config)) {
    throw new Error('Unknown or missing character.');
  }
  const character = payload.character;
  const area = payload.area === 'Temenos' || payload.area === 'Apollyon'
    ? payload.area : null;
  const targetId = finiteInteger(payload.target_id);
  const units = finiteInteger(payload.units);
  const signature = typeof payload.signature === 'string'
    ? payload.signature.slice(0, 240) : '';
  // Store the actual coffer award. Storage caps can clip a bonus between
  // 3,000 and 5,000; do not discard the opening or round away its evidence.
  if (!area || targetId === null || targetId <= 0 || units === null
      || units < 3000 || units > 5000 || Number(payload.units) !== units || !signature) {
    throw new Error('Invalid Limbus chest event.');
  }
  const finalChest = LIMBUS_FINAL_TARGETS[area]?.[targetId] || null;
  const manualChest = signature.endsWith(':manual')
    ? LIMBUS_MANUAL_TARGETS[area]?.[targetId] || null : null;
  const chest = finalChest || manualChest;
  if (!chest) {
    throw new Error('Unrecognized Limbus rotation chest target.');
  }

  const openedAt = isoNow();
  return withTransaction(db, () => {
    db.prepare(`INSERT INTO limbus_chest_targets(area,target_id,chest,learned_at)
      VALUES(?,?,?,?) ON CONFLICT(area,target_id) DO UPDATE SET
      chest=excluded.chest,learned_at=excluded.learned_at`)
      .run(area, targetId, chest, openedAt);

    db.prepare(`INSERT OR IGNORE INTO limbus_chest_events
      (character,area,chest,target_id,units,opened_at,signature)
      VALUES(?,?,?,?,?,?,?)`).run(character, area, chest, targetId, units, openedAt, signature);
    return { character, area, chest, target_id: targetId, units, opened_at: openedAt };
  });
}

function computeRotation(events, sectors) {
  const recent = events.slice(0, 5);
  const lastOpened = new Map();
  for (const event of events) {
    if (event.chest && !lastOpened.has(event.chest)) {
      lastOpened.set(event.chest, event.opened_at);
    }
  }
  const complete = sectors.every((sector) => lastOpened.has(sector));
  let next = null;
  if (complete) {
    next = sectors.reduce((oldest, sector) =>
      lastOpened.get(sector) < lastOpened.get(oldest) ? sector : oldest, sectors[0]);
  }
  const lastBonus = events.find((event) => event.units > 3000) || null;
  return { next, learned: lastOpened.size, total: sectors.length, last_bonus: lastBonus, recent };
}

function dashboard(db, config) {
  const characters = Object.keys(config.characters || {});
  const states = new Map(db.prepare('SELECT * FROM character_state').all()
    .map((row) => [row.character, row]));
  const output = characters.map((character) => {
    const areas = {};
    for (const [area, sectors] of Object.entries(LIMBUS_SECTORS)) {
      const events = db.prepare(`SELECT character,area,chest,target_id,units,opened_at
        FROM limbus_chest_events WHERE character=? AND area=?
        ORDER BY opened_at DESC,id DESC`).all(character, area);
      areas[area] = computeRotation(events, sectors);
    }
    return { character, gil: states.get(character)?.gil ?? null,
      observed_at: states.get(character)?.observed_at ?? null, areas };
  });
  return { generated_at: isoNow(), characters: output };
}

function keyItemView(db, config) {
  return {
    characters: Object.keys(config.characters || {}),
    rows: db.prepare(`SELECT item_id id,name,character,observed_at
      FROM key_items ORDER BY name,character`).all()
  };
}

function currencyView(db, config) {
  return {
    characters: Object.keys(config.characters || {}),
    rows: db.prepare(`SELECT page,name,character,amount,observed_at
      FROM currencies ORDER BY page,name,character`).all()
  };
}

function equipmentView(db, config) {
  return {
    characters: Object.keys(config.characters || {}),
    rows: db.prepare(`SELECT character,slot,item_id id,name,bag,bag_index,observed_at
      FROM equipment ORDER BY slot,character`).all()
  };
}

module.exports = {
  LIMBUS_SECTORS,
  LIMBUS_FINAL_TARGETS,
  ingestTelemetry,
  recordLimbusChest,
  computeRotation,
  dashboard,
  keyItemView,
  currencyView,
  equipmentView
};
