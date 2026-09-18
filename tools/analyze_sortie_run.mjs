import { explicitRoot } from "./partyops-paths.mjs";
import { readFile, readdir } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

const defaultStateRoot = process.env.PARTYOPS_STATE_ROOT;
const defaultSourceRoot =
  process.env.PARTYOPS_SOURCE_ROOT;
const defaultWindowerRoot = process.env.WINDOWER_ROOT;

const stateRoot = explicitRoot(process.argv[2] ?? defaultStateRoot, "PARTYOPS_STATE_ROOT");
const sourceRoot = explicitRoot(process.argv[3] ?? defaultSourceRoot, "PARTYOPS_SOURCE_ROOT");
const windowerRoot = explicitRoot(process.argv[4] ?? defaultWindowerRoot, "WINDOWER_ROOT");

async function importBuilt(relativePath) {
  return import(pathToFileURL(path.join(sourceRoot, relativePath)).href);
}

const [{ inspectOpenSegment, verifyClosedSegment }, projectionModule,
  actionResourceModule, combatResourceModule, normalizerModule] =
  await Promise.all([
    importBuilt("packages/journal/dist/index.js"),
    importBuilt("apps/hub/dist/battlelab/ffxi-battlelab-projection.js"),
    importBuilt("apps/hub/dist/battlelab/windower-action-resources.js"),
    importBuilt("apps/hub/dist/battlelab/windower-combat-resources.js"),
    importBuilt("apps/hub/dist/battlelab/ffxi-combat-normalizer.js")
  ]);

const { FfxiBattleLabProjection } = projectionModule;
const { resolveBattleLabResourceNames } = actionResourceModule;
const { resolveBattleLabCombatResources } = combatResourceModule;
const { buildBattleLabCombatAnalytics } = normalizerModule;

const status = JSON.parse(await readFile(
  path.join(stateRoot, "run", "p4-attribution-status.json"),
  "utf8"
));

function phaseDirectory(agent) {
  return agent.expected_phase === "P11Q" ? "p11q" : "p4-attribution";
}

async function loadCurrentSession(agent) {
  const directory = path.join(
    stateRoot,
    "journals",
    phaseDirectory(agent),
    agent.character
  );
  const names = (await readdir(directory))
    .filter((name) => name.startsWith(agent.agent_session_id))
    .sort();
  const records = [];
  for (const name of names) {
    let parsed;
    if (name.endsWith(".manifest.json")) {
      const manifestPath = path.join(directory, name);
      const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
      const segmentPath =
        `${manifestPath.slice(0, -".manifest.json".length)}.poj.gz`;
      parsed = await verifyClosedSegment({
        manifestPath,
        segmentPath,
        manifest
      });
    } else if (name.endsWith(".poj.open")) {
      parsed = await inspectOpenSegment(path.join(directory, name), true);
    } else {
      continue;
    }
    for (const frame of parsed.frames) {
      const sourceRecords = frame.record?.payload?.records;
      if (!Array.isArray(sourceRecords)) {
        continue;
      }
      for (const record of sourceRecords) {
        records.push(record);
      }
    }
  }
  records.sort((left, right) =>
    Date.parse(left.client_wall_time) - Date.parse(right.client_wall_time)
      || left.source_sequence - right.source_sequence
  );
  return { agent, records };
}

const captures = await Promise.all(status.agents.map(loadCurrentSession));
const captureByCharacter = new Map(
  captures.map((capture) => [capture.agent.character, capture])
);

function completedZoneVisit(records, zoneId) {
  const epochs = new Map();
  for (const record of records) {
    if (
      record.source_class === "snapshot"
      && record.payload.zone_id === zoneId
    ) {
      const existing = epochs.get(record.zone_epoch);
      const time = record.client_wall_time;
      if (existing === undefined) {
        epochs.set(record.zone_epoch, { start: time, last: time });
      } else {
        existing.last = time;
      }
    }
  }
  const visits = [...epochs]
    .map(([epoch, times]) => {
      const exit = records.find((record) =>
        record.source_class === "zone"
        && record.payload.state === "zone_change"
        && record.payload.old_zone_id === zoneId
        && Date.parse(record.client_wall_time) >= Date.parse(times.start)
      );
      return {
        epoch,
        started_at: times.start,
        ended_at: exit?.client_wall_time ?? times.last,
        complete: exit !== undefined
      };
    })
    .filter((visit) => visit.complete)
    .sort((left, right) =>
      Date.parse(right.ended_at) - Date.parse(left.ended_at)
    );
  if (visits.length === 0) {
    throw new Error(`No completed zone ${zoneId} visit was captured.`);
  }
  const requestedIndex = Number.parseInt(
    process.env.SORTIE_VISIT_INDEX ?? "0",
    10
  );
  const visitIndex = Number.isSafeInteger(requestedIndex)
    && requestedIndex >= 0 ? requestedIndex : 0;
  if (visits[visitIndex] === undefined) {
    throw new Error(
      `Completed zone ${zoneId} visit index ${visitIndex} is unavailable; `
      + `${visits.length} visit(s) were captured.`
    );
  }
  return visits[visitIndex];
}

const doloCapture = captureByCharacter.get("Dolomedes");
if (doloCapture === undefined) {
  throw new Error("Dolomedes capture is required to bound the Sortie run.");
}
const run = completedZoneVisit(doloCapture.records, 133);
const runStart = Date.parse(run.started_at);
const runEnd = Date.parse(run.ended_at);

function inRun(record) {
  const time = Date.parse(record.client_wall_time);
  return time >= runStart && time <= runEnd;
}

// The current PartyOps sessions contain several gigabytes of unrelated prior
// zones.  All requested analytics are scoped to this completed Sortie visit,
// so release those records before constructing the combat projection.  This
// changes memory use, not the run boundary or retained evidence.
for (const capture of captures) {
  capture.records = capture.records.filter(inRun);
}

function packetBytes(record) {
  const encoded = record.payload.original_base64;
  const declared = record.payload.original_length;
  if (
    typeof encoded !== "string"
    || !Number.isSafeInteger(declared)
    || declared < 0
  ) {
    return null;
  }
  const bytes = Buffer.from(encoded, "base64");
  return bytes.length === declared ? bytes : null;
}

const projection = new FfxiBattleLabProjection();
for (const capture of captures) {
  let currentZoneId = null;
  for (const record of capture.records) {
    if (record.source_class === "snapshot") {
      const observedZone = Number.isSafeInteger(record.payload.zone_id)
        ? record.payload.zone_id
        : Number.isSafeInteger(record.payload.zone)
          ? record.payload.zone
          : null;
      if (observedZone !== null) {
        currentZoneId = observedZone;
      }
      projection.observeSnapshotIdentity(record.payload.player, currentZoneId);
    }
    projection.observeZoneTransition(record, {
      observer_character: capture.agent.character,
      observer_party_position: capture.agent.party_position,
      zone_id: currentZoneId,
      zone_epoch: record.zone_epoch
    });
    if (
      record.source_class === "zone"
      && record.payload.state === "zone_change"
      && Number.isSafeInteger(record.payload.new_zone_id)
    ) {
      currentZoneId = record.payload.new_zone_id;
    }
    const bytes = packetBytes(record);
    if (bytes !== null) {
      projection.observePacket(record, bytes, {
        observer_character: capture.agent.character,
        observer_party_position: capture.agent.party_position,
        zone_id: currentZoneId,
        zone_epoch: record.zone_epoch
      });
    }
  }
}

const actionCatalog = await resolveBattleLabResourceNames(
  windowerRoot,
  projection.actionReferences(),
  // Current live resources can observe a newly introduced weapon-skill ID
  // before Windower's generated resource catalog receives its English name.
  // The projection can still normalize every packet and retain the unknown
  // action as a generic weapon skill, so do not discard an otherwise complete
  // Sortie run solely because that optional display name is absent.
  new Set([
    "weaponskill:328",
    // Captured by the current clients before Windower's generated English
    // resource table learned their display names.  Keep the actions in the
    // projection as typed, unknown-name weapon skills instead of rejecting
    // the otherwise complete run.
    "weaponskill:3202",
    "weaponskill:3502"
  ])
);
const actionMessageText = await readFile(
  path.join(windowerRoot, "res", "action_messages.lua"),
  "utf8"
);
const availableMessageIds = new Set(
  [...actionMessageText.matchAll(/^\s*\[(\d+)\]\s*=\s*\{/gm)]
    .map((match) => Number(match[1]))
);
const messageReferences = projection.messageReferences();
const unresolvedMessageIds = [...new Set(messageReferences
  .map((reference) => reference.message_id)
  .filter((messageId) => messageId > 0 && !availableMessageIds.has(messageId))
)].sort((left, right) => left - right);
const combatResources = await resolveBattleLabCombatResources(
  windowerRoot,
  messageReferences.filter((reference) =>
    reference.message_id <= 0 || availableMessageIds.has(reference.message_id)
  )
);
const allCombatEvents = projection.combatEvents(
  actionCatalog.names,
  combatResources
).events;
const combatEvents = allCombatEvents.filter((event) =>
  event.zone_id === 133
  && Date.parse(event.effective_time) >= runStart
  && Date.parse(event.effective_time) <= runEnd
);
const analytics = buildBattleLabCombatAnalytics(
  combatEvents,
  combatResources.sources
);

const partyNames = status.agents.map((agent) => agent.character);
const partyNameSet = new Set(partyNames);

function includesDemisang(value) {
  return typeof value === "string" && value.toLowerCase().includes("demisang");
}

const demisangEvents = combatEvents.filter((event) =>
  includesDemisang(event.actor_name)
  || event.target_names.some(includesDemisang)
  || (event.results ?? []).some((result) =>
    includesDemisang(result.source_name)
    || includesDemisang(result.affected_name)
  )
);
const demisangBoundary = demisangEvents.length === 0
  ? null
  : {
      started_at: demisangEvents[0].effective_time,
      ended_at: demisangEvents.at(-1).effective_time
    };

function liveFieldPoints(character, fieldId, runOnly = true) {
  const capture = captureByCharacter.get(character);
  if (capture === undefined) {
    return [];
  }
  return capture.records
    .filter((record) =>
      (!runOnly || inRun(record))
      && record.source_class === "snapshot"
      && record.payload.zone_id === 133
      && record.payload.fields?.[fieldId] !== undefined
    )
    .map((record) => ({
      time: record.client_wall_time,
      value: record.payload.fields[fieldId]
    }));
}

function simplifyPositionTrace(
  character,
  startedAt,
  endedAt,
  tolerance = 4,
  runOnly = true
) {
  const started = Date.parse(startedAt);
  const ended = Date.parse(endedAt);
  const squaredTolerance = tolerance * tolerance;
  const source = liveFieldPoints(character, "positions", runOnly)
    .filter((point) => {
      const time = Date.parse(point.time);
      return time >= started && time <= ended
        && Number.isFinite(Number(point.value?.x))
        && Number.isFinite(Number(point.value?.y));
    })
    .map((point) => ({
      time: point.time,
      x: Number(point.value.x),
      y: Number(point.value.y),
      z: Number.isFinite(Number(point.value.z)) ? Number(point.value.z) : null
    }));

  const points = source.filter((point, index) => index === 0
    || Math.hypot(
      point.x - source[index - 1].x,
      point.y - source[index - 1].y,
      (point.z ?? 0) - (source[index - 1].z ?? 0)
    ) >= 0.5);

  function segmentDistanceSquared(point, first, last) {
    let x = first.x;
    let y = first.y;
    let z = first.z ?? 0;
    let dx = last.x - x;
    let dy = last.y - y;
    let dz = (last.z ?? 0) - z;
    if (dx !== 0 || dy !== 0 || dz !== 0) {
      const ratio = Math.max(0, Math.min(1,
        ((point.x - x) * dx
          + (point.y - y) * dy
          + ((point.z ?? 0) - z) * dz)
        / (dx * dx + dy * dy + dz * dz)
      ));
      x += dx * ratio;
      y += dy * ratio;
      z += dz * ratio;
    }
    dx = point.x - x;
    dy = point.y - y;
    dz = (point.z ?? 0) - z;
    return dx * dx + dy * dy + dz * dz;
  }

  function simplify(firstIndex, lastIndex, keep) {
    let maximum = squaredTolerance;
    let splitIndex = null;
    for (let index = firstIndex + 1; index < lastIndex; index += 1) {
      const distance = segmentDistanceSquared(
        points[index], points[firstIndex], points[lastIndex]
      );
      if (distance > maximum) {
        splitIndex = index;
        maximum = distance;
      }
    }
    if (splitIndex !== null) {
      if (splitIndex - firstIndex > 1) simplify(firstIndex, splitIndex, keep);
      keep.add(splitIndex);
      if (lastIndex - splitIndex > 1) simplify(splitIndex, lastIndex, keep);
    }
  }

  if (points.length <= 2) return points;
  const keep = new Set([0, points.length - 1]);
  simplify(0, points.length - 1, keep);
  return [...keep].sort((left, right) => left - right)
    .map((index) => points[index]);
}

function fieldWindow(points, startedAt, endedAt, fieldName) {
  const start = Date.parse(startedAt);
  const end = Date.parse(endedAt);
  const inWindow = points.filter((point) => {
    const time = Date.parse(point.time);
    return time >= start && time <= end;
  });
  if (inWindow.length === 0) {
    return null;
  }
  const samples = inWindow.map((point) => Number(point.value[fieldName]));
  const percentages = inWindow.map((point) => Number(point.value.percent));
  const thresholdSeconds = {};
  const longestThresholdSeconds = {};
  for (const threshold of [10, 20, 25, 50]) {
    let total = 0;
    let streak = 0;
    let longest = 0;
    for (let index = 0; index < inWindow.length; index += 1) {
      const point = inWindow[index];
      const pointTime = Date.parse(point.time);
      const nextTime = index + 1 < inWindow.length
        ? Math.min(Date.parse(inWindow[index + 1].time), end)
        : end;
      const duration = Math.max(0, nextTime - pointTime);
      if (Number(point.value.percent) <= threshold) {
        total += duration;
        streak += duration;
        longest = Math.max(longest, streak);
      } else {
        streak = 0;
      }
    }
    thresholdSeconds[`${threshold}_percent_or_less`] =
      Math.round(total / 1000);
    longestThresholdSeconds[`${threshold}_percent_or_less`] =
      Math.round(longest / 1000);
  }
  const changes = [];
  for (let index = 1; index < inWindow.length; index += 1) {
    const previous = inWindow[index - 1];
    const current = inWindow[index];
    const delta = Number(current.value[fieldName])
      - Number(previous.value[fieldName]);
    if (delta !== 0) {
      changes.push({ time: current.time, delta });
    }
  }
  return {
    started_at: startedAt,
    ended_at: endedAt,
    samples: inWindow.length,
    maximum_resource: Math.max(
      ...inWindow.map((point) => Number(point.value.maximum))
    ),
    start: samples[0],
    end: samples.at(-1),
    minimum: Math.min(...samples),
    maximum: Math.max(...samples),
    minimum_percent: Math.min(...percentages),
    maximum_percent: Math.max(...percentages),
    threshold_seconds: thresholdSeconds,
    longest_threshold_seconds: longestThresholdSeconds,
    total_positive_change: changes
      .filter((change) => change.delta > 0)
      .reduce((total, change) => total + change.delta, 0),
    total_negative_change: -changes
      .filter((change) => change.delta < 0)
      .reduce((total, change) => total + change.delta, 0),
    large_gains: changes
      .filter((change) => change.delta >= 400)
      .sort((left, right) => right.delta - left.delta)
      .slice(0, 20)
  };
}

const smallsMpPoints = liveFieldPoints("Smalls", "mp");
const smallsMp = {
  full_run: fieldWindow(smallsMpPoints, run.started_at, run.ended_at, "current"),
  demisang: demisangBoundary === null
    ? null
    : fieldWindow(
        smallsMpPoints,
        demisangBoundary.started_at,
        demisangBoundary.ended_at,
        "current"
      )
};

function valueAtOrAfter(points, time, maximumDelayMs = 5_000) {
  const target = Date.parse(time);
  return points.find((point) => {
    const delta = Date.parse(point.time) - target;
    return delta >= 0 && delta <= maximumDelayMs;
  }) ?? null;
}

function smallsConvertCycles() {
  const conversions = combatEvents.filter((event) =>
    event.actor_name === "Smalls"
    && event.action_kind === "job_ability"
    && event.action_name === "Convert"
    && ["finish", "instant"].includes(event.phase)
  );
  return conversions.map((event) => {
    const after = valueAtOrAfter(smallsMpPoints, event.effective_time);
    const afterTime = after === null ? null : Date.parse(after.time);
    const low = afterTime === null ? null : smallsMpPoints.find((point) =>
      Date.parse(point.time) >= afterTime
      && Number(point.value.percent) <= 20
    ) ?? null;
    return {
      converted_at: event.effective_time,
      observed_after: after,
      back_to_20_percent_at: low?.time ?? null,
      seconds_to_20_percent: low === null
        ? null
        : Math.round((Date.parse(low.time) - Date.parse(event.effective_time)) / 1000)
    };
  });
}

const spellRows = new Map();
for (const match of (await readFile(
  path.join(windowerRoot, "res", "spells.lua"),
  "utf8"
)).matchAll(
  /^\s*\[(\d+)\]\s*=\s*\{id=\d+,en="((?:\\.|[^"\\])*)".*?mp_cost=(\d+)/gm
)) {
  spellRows.set(Number(match[1]), {
    name: JSON.parse(`"${match[2]}"`),
    mp_cost: Number(match[3])
  });
}

function groupCompletedActions(character, startedAt, endedAt) {
  const start = Date.parse(startedAt);
  const end = Date.parse(endedAt);
  const groups = new Map();
  for (const event of combatEvents) {
    const time = Date.parse(event.effective_time);
    if (
      event.actor_name !== character
      || time < start
      || time > end
      || !["finish", "instant"].includes(event.phase)
      || !["spell", "job_ability", "weaponskill"].includes(event.action_kind)
    ) {
      continue;
    }
    const key = `${event.action_kind}:${event.action_id ?? 0}:${event.action_name}`;
    let group = groups.get(key);
    if (group === undefined) {
      const spell = event.action_kind === "spell" && event.action_id !== null
        ? spellRows.get(event.action_id)
        : undefined;
      group = {
        kind: event.action_kind,
        id: event.action_id,
        name: event.action_display_name ?? event.action_name,
        count: 0,
        mp_cost_each: spell?.mp_cost ?? 0,
        nominal_mp_cost: 0,
        damage: 0,
        healing: 0,
        targets: {}
      };
      groups.set(key, group);
    }
    group.count += 1;
    group.nominal_mp_cost += group.mp_cost_each;
    for (const target of event.target_names) {
      const name = target ?? "unknown";
      group.targets[name] = (group.targets[name] ?? 0) + 1;
    }
    for (const result of event.results ?? []) {
      if (result.source_name !== character || result.amount === null) {
        continue;
      }
      if (result.outcome_kind === "damage") {
        group.damage += result.amount;
      } else if (
        result.outcome_kind === "healing"
        && result.amount_unit === "hp"
      ) {
        group.healing += result.amount;
      }
    }
  }
  return [...groups.values()].sort((left, right) =>
    right.nominal_mp_cost - left.nominal_mp_cost
      || right.damage - left.damage
      || right.healing - left.healing
      || right.count - left.count
      || left.name.localeCompare(right.name)
  );
}

function partyActorRows(rows) {
  return partyNames.map((name) =>
    rows.find((row) => row.entity_name === name) ?? {
      entity_name: name,
      damage_done: 0,
      damage_taken: 0,
      healing_done: 0,
      healing_received: 0,
      hits: 0,
      critical_hits: 0,
      misses: 0,
      avoidances: 0,
      status_applications: 0,
      status_removals: 0,
      defeats: 0,
      deaths: 0
    }
  );
}

function enemyPressure() {
  const result = Object.fromEntries(partyNames.map((name) => [name, {
    melee_events_targeted: 0,
    single_target_hostile_events: 0,
    all_hostile_events_including_aoe: 0,
    damage_events: 0,
    damage_taken: 0
  }]));
  for (const event of combatEvents) {
    if (event.actor_name !== null && partyNameSet.has(event.actor_name)) {
      continue;
    }
    const targets = new Set(event.target_names.filter((name) =>
      name !== null && partyNameSet.has(name)
    ));
    for (const target of targets) {
      const row = result[target];
      row.all_hostile_events_including_aoe += 1;
      if (event.target_names.length === 1) {
        row.single_target_hostile_events += 1;
      }
      if (event.action_kind === "melee_attack") {
        row.melee_events_targeted += 1;
      }
    }
    for (const fragment of event.results ?? []) {
      if (
        fragment.outcome_kind === "damage"
        && fragment.affected_name !== null
        && partyNameSet.has(fragment.affected_name)
      ) {
        result[fragment.affected_name].damage_events += 1;
        result[fragment.affected_name].damage_taken += fragment.amount ?? 0;
      }
    }
  }
  return result;
}

function interactionRows() {
  const nameByEntity = new Map();
  for (const track of projection.entityTracks()) {
    if (track.zone_id === 133 && track.canonical_name !== null) {
      nameByEntity.set(
        `${track.zone_epoch}:${track.entity_id}:${track.entity_index}`,
        track.canonical_name
      );
    }
  }
  const positions = liveFieldPoints("Dolomedes", "positions");
  function positionAt(time) {
    const target = Date.parse(time);
    let best = null;
    for (const point of positions) {
      const delta = Math.abs(Date.parse(point.time) - target);
      if (best === null || delta < best.delta) {
        best = { delta, point };
      }
    }
    return best === null || best.delta > 3_000 ? null : best.point.value;
  }
  const rows = [];
  for (const record of doloCapture.records) {
    if (
      !inRun(record)
      || record.source_class !== "combat"
      || record.payload.direction !== "outgoing"
      || record.payload.packet_id !== 0x01a
      || record.payload.blocked === true
    ) {
      continue;
    }
    const bytes = packetBytes(record);
    if (bytes === null || bytes.length < 14 || bytes.readUInt16LE(10) !== 0) {
      continue;
    }
    const entityId = bytes.readUInt32LE(4);
    const entityIndex = bytes.readUInt16LE(8);
    rows.push({
      time: record.client_wall_time,
      name: nameByEntity.get(
        `${record.zone_epoch}:${entityId}:${entityIndex}`
      ) ?? "unknown",
      entity_id: entityId,
      entity_index: entityIndex,
      position: positionAt(record.client_wall_time)
    });
  }
  return rows;
}

function combatControlPackets() {
  const result = {};
  for (const capture of captures) {
    const rows = [];
    for (const record of capture.records) {
      if (
        record.source_class !== "combat"
        || record.payload.direction !== "outgoing"
        || record.payload.packet_id !== 0x01a
        || record.payload.blocked === true
      ) {
        continue;
      }
      const bytes = packetBytes(record);
      if (bytes === null || bytes.length < 12) continue;
      const category = bytes.readUInt16LE(10);
      if (![0x02, 0x04, 0x0f].includes(category)) continue;
      rows.push({
        time: record.client_wall_time,
        category,
        operation: category === 0x04 ? "disengage" : "engage",
        target_id: bytes.readUInt32LE(4),
        target_index: bytes.readUInt16LE(8),
        injected: record.payload.injected ?? null,
        modified: record.payload.modified_base64 !== undefined
          && record.payload.modified_base64 !== record.payload.original_base64
      });
    }
    result[capture.agent.character] = rows;
  }
  return result;
}

function decisionsNearDisengages(controlPackets, radiusMs = 750) {
  const result = {};
  for (const capture of captures) {
    const disengages = controlPackets[capture.agent.character]
      .filter((packet) => packet.operation === "disengage");
    const decisions = capture.records.filter((record) =>
      record.source_class === "adapter_decision"
    );
    result[capture.agent.character] = disengages.map((packet) => {
      const packetTime = Date.parse(packet.time);
      return {
        ...packet,
        nearby_decisions: decisions.filter((record) =>
          Math.abs(Date.parse(record.client_wall_time) - packetTime) <= radiusMs
        ).map((record) => ({
          time: record.client_wall_time,
          payload: record.payload
        }))
      };
    });
  }
  return result;
}

function combatMinuteBins() {
  const bins = new Map();
  for (const event of combatEvents) {
    const minute = new Date(
      Math.floor(Date.parse(event.effective_time) / 60_000) * 60_000
    ).toISOString();
    let bin = bins.get(minute);
    if (bin === undefined) {
      bin = { events: 0, party_damage: 0, enemy_damage: 0, enemy_melee: 0 };
      bins.set(minute, bin);
    }
    bin.events += 1;
    if (event.action_kind === "melee_attack" && !partyNameSet.has(event.actor_name)) {
      bin.enemy_melee += 1;
    }
    for (const result of event.results ?? []) {
      if (result.outcome_kind !== "damage" || result.amount === null) {
        continue;
      }
      if (result.source_name !== null && partyNameSet.has(result.source_name)) {
        bin.party_damage += result.amount;
      }
      if (result.affected_name !== null && partyNameSet.has(result.affected_name)) {
        bin.enemy_damage += result.amount;
      }
    }
  }
  return [...bins].map(([minute, values]) => ({ minute, ...values }));
}

function relevantEnemyName(value) {
  return typeof value === "string"
    && (/^Cachaemic(?: |[A-Z])/u.test(value)
      || /^Abject(?: |[A-Z])/u.test(value)
      || value === "Skomora"
      || value === "Ghatjot");
}

function completedPartyAction(event) {
  return partyNameSet.has(event.actor_name)
    && ["finish", "instant", "message"].includes(event.phase);
}

function compactResult(result) {
  return {
    message_id: result.message_id,
    source: result.source_name,
    affected: result.affected_name,
    outcome: result.outcome_kind,
    amount: result.amount,
    unit: result.amount_unit,
    status: result.status_name
  };
}

function compactEvent(event) {
  return {
    time: event.effective_time,
    actor: event.actor_name,
    kind: event.action_kind,
    action_id: event.action_id,
    action: event.action_display_name ?? event.action_name,
    phase: event.phase,
    target_ids: event.target_ids,
    targets: event.target_names,
    message_ids: event.message_ids,
    results: (event.results ?? []).map(compactResult)
  };
}

function objectiveEncounterRows() {
  const namesById = new Map();
  for (const event of combatEvents) {
    if (relevantEnemyName(event.actor_name)) {
      namesById.set(event.actor_id, event.actor_name);
    }
    for (let index = 0; index < event.target_ids.length; index += 1) {
      const name = event.target_names[index];
      if (relevantEnemyName(name)) namesById.set(event.target_ids[index], name);
    }
    for (const result of event.results ?? []) {
      if (relevantEnemyName(result.source_name)) {
        namesById.set(result.source_id, result.source_name);
      }
      if (relevantEnemyName(result.affected_name)) {
        namesById.set(result.affected_id, result.affected_name);
      }
    }
  }

  const doloTracks = projection.entityTracks().filter((track) =>
    track.zone_id === 133
    && track.zone_epoch === run.epoch
    && track.observer_character === "Dolomedes"
  );
  const rows = [];
  for (const [entityId, name] of namesById) {
    const events = combatEvents.filter((event) =>
      event.actor_id === entityId
      || event.target_ids.includes(entityId)
      || (event.results ?? []).some((result) =>
        result.source_id === entityId || result.affected_id === entityId
      )
    );
    if (events.length === 0) continue;

    const damageByParty = Object.fromEntries(partyNames.map((partyName) =>
      [partyName, 0]
    ));
    const incomingDamageByParty = Object.fromEntries(partyNames.map((partyName) =>
      [partyName, 0]
    ));
    const hostileTargets = Object.fromEntries(partyNames.map((partyName) =>
      [partyName, 0]
    ));
    const partyActions = [];
    const partyActionSummary = new Map();
    const enemyActionSummary = new Map();
    let totalPartyDamage = 0;
    let firstPartyDamage = null;
    let lastPartyDamage = null;
    const deathResults = [];
    for (const event of events) {
      if (event.actor_id === entityId) {
        for (const targetName of new Set(event.target_names)) {
          if (partyNameSet.has(targetName)) hostileTargets[targetName] += 1;
        }
        if (["finish", "instant", "message"].includes(event.phase)) {
          const key = `${event.action_kind}:${event.action_id ?? 0}:${event.action_name}`;
          let summary = enemyActionSummary.get(key);
          if (summary === undefined) {
            summary = {
              kind: event.action_kind,
              action_id: event.action_id,
              action: event.action_display_name ?? event.action_name,
              count: 0
            };
            enemyActionSummary.set(key, summary);
          }
          summary.count += 1;
        }
      }
      let actionDamage = 0;
      for (const result of event.results ?? []) {
        if (result.affected_id === entityId
          && result.outcome_kind === "damage"
          && partyNameSet.has(result.source_name)) {
          const amount = result.amount ?? 0;
          totalPartyDamage += amount;
          actionDamage += amount;
          damageByParty[result.source_name] += amount;
          firstPartyDamage ??= {
            time: event.effective_time,
            actor: result.source_name,
            kind: event.action_kind,
            action_id: event.action_id,
            action: event.action_display_name ?? event.action_name,
            amount,
            message_id: result.message_id
          };
          lastPartyDamage = {
            time: event.effective_time,
            actor: result.source_name,
            kind: event.action_kind,
            action_id: event.action_id,
            action: event.action_display_name ?? event.action_name,
            amount,
            message_id: result.message_id
          };
        }
        if (result.source_id === entityId
          && result.outcome_kind === "damage"
          && partyNameSet.has(result.affected_name)) {
          incomingDamageByParty[result.affected_name] += result.amount ?? 0;
        }
        if (result.affected_id === entityId
          && ["death", "defeat"].includes(result.outcome_kind)) {
          deathResults.push({time: event.effective_time, ...compactResult(result)});
        }
      }
      if (completedPartyAction(event)
        && (event.target_ids.includes(entityId) || actionDamage > 0)) {
        const key = `${event.actor_name}:${event.action_kind}:${event.action_id ?? 0}:${event.action_name}`;
        let summary = partyActionSummary.get(key);
        if (summary === undefined) {
          summary = {
            actor: event.actor_name,
            kind: event.action_kind,
            action_id: event.action_id,
            action: event.action_display_name ?? event.action_name,
            count: 0,
            damage: 0
          };
          partyActionSummary.set(key, summary);
        }
        summary.count += 1;
        summary.damage += actionDamage;
        partyActions.push({
          time: event.effective_time,
          actor: event.actor_name,
          kind: event.action_kind,
          action_id: event.action_id,
          action: event.action_display_name ?? event.action_name,
          damage: actionDamage,
          message_ids: event.message_ids
        });
      }
    }

    const tracks = doloTracks.filter((track) => track.entity_id === entityId);
    const hpKeyframes = tracks.flatMap((track) => track.keyframes)
      .filter((frame) => {
        const time = Date.parse(frame.effective_time);
        return time >= runStart && time <= runEnd;
      })
      .sort((left, right) => Date.parse(left.effective_time)
        - Date.parse(right.effective_time));
    rows.push({
      entity_id: entityId,
      name,
      first_event: events[0].effective_time,
      last_event: events.at(-1).effective_time,
      duration_seconds: Math.round((Date.parse(events.at(-1).effective_time)
        - Date.parse(events[0].effective_time)) / 1000),
      party_damage: totalPartyDamage,
      damage_by_party: damageByParty,
      incoming_damage_by_party: incomingDamageByParty,
      hostile_targets: hostileTargets,
      first_party_damage: firstPartyDamage,
      last_party_damage: lastPartyDamage,
      death_results: deathResults,
      party_action_summary: [...partyActionSummary.values()].sort((left, right) =>
        right.damage - left.damage || right.count - left.count),
      enemy_action_summary: [...enemyActionSummary.values()].sort((left, right) =>
        right.count - left.count || left.action.localeCompare(right.action)),
      party_actions: partyActions,
      hp_keyframes: hpKeyframes.map((frame) => ({
        time: frame.effective_time,
        hp_percent: frame.hp_percent,
        status_id: frame.status_id,
        visible: frame.visible
      }))
    });
  }
  return rows.sort((left, right) => Date.parse(left.first_event)
    - Date.parse(right.first_event));
}

function selectedSmallsActionTimeline() {
  const selected = new Set([
    "Haste II", "Refresh III", "Phalanx II", "Protect V", "Shell V",
    "Dia III", "Thunder", "Fire V", "Black Halo", "Convert"
  ]);
  return combatEvents.filter((event) =>
    event.actor_name === "Smalls"
    && ["finish", "instant"].includes(event.phase)
    && selected.has(event.action_display_name ?? event.action_name)
  ).map(compactEvent);
}

function creditEvidenceTimeline() {
  return combatEvents.filter((event) =>
    event.message_ids.some((messageId) =>
      [252, 265, 291].includes(messageId)
    )
  ).map(compactEvent);
}

const zoneEntityNames = [...Map.groupBy(
  projection.entityTracks().filter((track) =>
    track.zone_id === 133 && track.canonical_name !== null
  ),
  (track) => track.canonical_name
)].map(([name, tracks]) => ({
  name,
  tracks: tracks.length,
  entity_ids: [...new Set(tracks.map((track) => track.entity_id))]
})).sort((left, right) => left.name.localeCompare(right.name));

const demisangNames = [...new Set(demisangEvents.flatMap((event) => [
  event.actor_name,
  ...event.target_names,
  ...(event.results ?? []).flatMap((result) => [
    result.source_name,
    result.affected_name
  ])
]).filter(includesDemisang))].sort();

const controlPackets = combatControlPackets();

const report = {
  schema_version: 1,
  source: "live PartyOps journal snapshot; read only; open suffix tolerated",
  run: {
    zone_id: 133,
    zone_epoch: run.epoch,
    started_at: run.started_at,
    ended_at: run.ended_at,
    duration_seconds: Math.round((runEnd - runStart) / 1000),
    character_records: Object.fromEntries(captures.map((capture) => [
      capture.agent.character,
      capture.records.filter(inRun).length
    ]))
  },
  demisang: {
    boundary: demisangBoundary,
    named_entities: demisangNames,
    combat_events: demisangEvents.length
  },
  smalls_mp: smallsMp,
  smalls_convert_cycles: smallsConvertCycles(),
  smalls_actions: {
    full_run: groupCompletedActions("Smalls", run.started_at, run.ended_at),
    demisang: demisangBoundary === null
      ? []
      : groupCompletedActions(
          "Smalls",
          demisangBoundary.started_at,
          demisangBoundary.ended_at
        )
  },
  party_combat: partyActorRows(analytics.actors),
  party_actions: Object.fromEntries(partyNames.map((name) => [
    name,
    groupCompletedActions(name, run.started_at, run.ended_at)
  ])),
  enemy_pressure: enemyPressure(),
  combat_control_packets: controlPackets,
  adapter_decisions_near_disengages: decisionsNearDisengages(controlPackets),
  dolomedes_interactions: interactionRows(),
  dolomedes_full_route_trace: simplifyPositionTrace(
    "Dolomedes", run.started_at, run.ended_at, 3
  ),
  dolomedes_route_trace: {
    start_to_gate_b1: simplifyPositionTrace(
      "Dolomedes", "2026-09-11T00:43:08Z", "2026-09-11T00:49:50Z", 5
    ),
    gate_b1_to_b2: simplifyPositionTrace(
      "Dolomedes", "2026-09-11T00:49:46Z", "2026-09-11T00:50:16Z", 3
    ),
    gate_b2_to_b3: simplifyPositionTrace(
      "Dolomedes", "2026-09-11T00:50:12Z", "2026-09-11T00:51:07Z", 3
    ),
    gate_b3_to_b4: simplifyPositionTrace(
      "Dolomedes", "2026-09-11T00:51:03Z", "2026-09-11T00:51:56Z", 3
    ),
    gate_b4_to_b5: simplifyPositionTrace(
      "Dolomedes", "2026-09-11T00:51:52Z", "2026-09-11T00:52:19Z", 3
    ),
    gate_b5_to_b6: simplifyPositionTrace(
      "Dolomedes", "2026-09-11T00:52:15Z", "2026-09-11T00:53:03Z", 3
    ),
    gate_b6_to_device_b: simplifyPositionTrace(
      "Dolomedes", "2026-09-11T00:53:00Z", "2026-09-11T00:53:53Z", 3
    ),
    device_b_to_d_entry: simplifyPositionTrace(
      "Dolomedes", "2026-09-11T00:53:45Z", "2026-09-11T00:55:33Z", 4
    ),
    sector_d_sweep: simplifyPositionTrace(
      "Dolomedes", "2026-09-11T00:55:27Z", "2026-09-11T01:41:27Z", 7
    ),
    prior_gate_d1_to_device_d: simplifyPositionTrace(
      "Dolomedes", "2026-09-10T03:08:25Z", "2026-09-10T03:10:20Z", 3,
      false
    )
  },
  combat_minute_bins: combatMinuteBins(),
  objective_encounters: objectiveEncounterRows(),
  selected_smalls_action_timeline: selectedSmallsActionTimeline(),
  skillchain_and_burst_evidence: creditEvidenceTimeline(),
  zone_entity_names: zoneEntityNames,
  decoder: {
    entity_packets: projection.decoded_entity_packets,
    combat_packets: projection.decoded_combat_packets,
    normalized_events: combatEvents.length,
    normalized_fragments: analytics.coverage.normalized_fragments,
    other_fragments: analytics.coverage.other_fragments,
    unresolved_message_ids: unresolvedMessageIds
  }
};

process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
