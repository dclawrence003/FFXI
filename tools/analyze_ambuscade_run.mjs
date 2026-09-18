import { explicitRoot } from "./partyops-paths.mjs";
import { readFile, readdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

const defaultStateRoot = process.env.PARTYOPS_STATE_ROOT;
const defaultSourceRoot =
  process.env.PARTYOPS_SOURCE_ROOT;
const defaultWindowerRoot = process.env.WINDOWER_ROOT;

const startedAt = process.argv[2] ?? "2026-09-11T02:10:00.000Z";
const endedAt = process.argv[3] ?? "2026-09-11T02:22:00.000Z";
const outputPath = process.argv[4] === undefined
  ? null
  : path.resolve(process.argv[4]);
const stateRoot = explicitRoot(process.argv[5] ?? defaultStateRoot, "PARTYOPS_STATE_ROOT");
const sourceRoot = explicitRoot(process.argv[6] ?? defaultSourceRoot, "PARTYOPS_SOURCE_ROOT");
const windowerRoot = explicitRoot(process.argv[7] ?? defaultWindowerRoot, "WINDOWER_ROOT");
const startMilliseconds = Date.parse(startedAt);
const endMilliseconds = Date.parse(endedAt);
const preRollMilliseconds = startMilliseconds - 120_000;

if (
  !Number.isFinite(startMilliseconds)
  || !Number.isFinite(endMilliseconds)
  || endMilliseconds <= startMilliseconds
) {
  throw new Error(
    "Usage: analyze_ambuscade_run.mjs <start-iso> <end-iso> [output.json]"
  );
}

async function importBuilt(relativePath) {
  return import(pathToFileURL(path.join(sourceRoot, relativePath)).href);
}

const [{ inspectOpenSegment, verifyClosedSegment }, projectionModule, actionResourceModule,
  combatResourceModule, normalizerModule] = await Promise.all([
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
const projection = new FfxiBattleLabProjection();
const recordsByCharacter = new Map();

function phaseDirectory(agent) {
  return agent.expected_phase === "P11Q" ? "p11q" : "p4-attribution";
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

function outgoingActionRequests(name) {
  return (recordsByCharacter.get(name) ?? []).flatMap((record) => {
    if (
      record.source_class !== "combat"
      || record.payload.direction !== "outgoing"
      || record.payload.packet_id !== 0x01a
    ) {
      return [];
    }
    const bytes = packetBytes(record);
    if (bytes === null || bytes.length < 14) return [];
    return [{
      time: record.client_wall_time,
      target_id: bytes.readUInt32LE(4),
      target_index: bytes.readUInt16LE(8),
      category: bytes.readUInt16LE(10),
      param: bytes.readUInt16LE(12),
      injected: record.payload.injected === true,
      blocked: record.payload.blocked === true
    }];
  });
}

for (const agent of status.agents) {
  const directory = path.join(
    stateRoot,
    "journals",
    phaseDirectory(agent),
    agent.character
  );
  const segmentNames = await readdir(directory);
  const openName = segmentNames.find((name) =>
    name.startsWith(agent.agent_session_id) && name.endsWith(".poj.open")
  );
  if (openName === undefined) {
    // A disconnected capture client should reduce coverage, not prevent the
    // other active party journals from being analyzed.
    recordsByCharacter.set(agent.character, []);
    continue;
  }
  const parsedSegments = [];
  for (const manifestName of segmentNames.filter((name) =>
    name.startsWith(agent.agent_session_id) && name.endsWith(".manifest.json")
  ).sort()) {
    const manifestPath = path.join(directory, manifestName);
    const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
    const firstMilliseconds = Date.parse(manifest.client_time_first);
    const lastMilliseconds = Date.parse(manifest.client_time_last);
    if (
      Number.isFinite(firstMilliseconds)
      && Number.isFinite(lastMilliseconds)
      && lastMilliseconds >= preRollMilliseconds
      && firstMilliseconds <= endMilliseconds
    ) {
      parsedSegments.push(await verifyClosedSegment({
        segmentPath: path.join(
          directory,
          manifestName.replace(/\.manifest\.json$/, ".poj.gz")
        ),
        manifestPath,
        manifest
      }));
    }
  }
  parsedSegments.push(
    await inspectOpenSegment(path.join(directory, openName), true)
  );
  const selectedRecords = [];
  let currentZoneId = null;
  for (const frame of parsedSegments.flatMap((parsed) => parsed.frames)) {
    const sourceRecords = frame.record?.payload?.records;
    if (!Array.isArray(sourceRecords)) continue;
    for (const record of sourceRecords) {
      const effectiveMilliseconds = Date.parse(record.client_wall_time);
      if (record.source_class === "snapshot") {
        const observedZone = Number.isSafeInteger(record.payload.zone_id)
          ? record.payload.zone_id
          : Number.isSafeInteger(record.payload.zone)
            ? record.payload.zone
            : null;
        if (observedZone !== null) currentZoneId = observedZone;
        projection.observeSnapshotIdentity(record.payload.player, currentZoneId);
      }
      if (
        record.source_class === "zone"
        && record.payload.state === "zone_change"
        && Number.isSafeInteger(record.payload.new_zone_id)
      ) {
        currentZoneId = record.payload.new_zone_id;
      }
      if (
        effectiveMilliseconds >= preRollMilliseconds
        && effectiveMilliseconds <= endMilliseconds
      ) {
        projection.observeZoneTransition(record, {
          observer_character: agent.character,
          observer_party_position: agent.party_position,
          zone_id: currentZoneId,
          zone_epoch: record.zone_epoch
        });
        const bytes = packetBytes(record);
        if (bytes !== null) {
          projection.observePacket(record, bytes, {
            observer_character: agent.character,
            observer_party_position: agent.party_position,
            zone_id: currentZoneId,
            zone_epoch: record.zone_epoch
          });
        }
      }
      if (
        effectiveMilliseconds >= startMilliseconds
        && effectiveMilliseconds <= endMilliseconds
      ) {
        selectedRecords.push(record);
      }
    }
  }
  recordsByCharacter.set(agent.character, selectedRecords);
}

const resourceActionKinds = new Set([
  "weaponskill",
  "spell",
  "job_ability",
  "monster_ability",
  "item"
]);
const actionReferences = projection.actionReferences();
const invalidActionReferences = actionReferences.filter((reference) =>
  !resourceActionKinds.has(reference.action_kind)
  || !Number.isSafeInteger(reference.action_id)
  || reference.action_id <= 0
);
const actionCatalog = await resolveBattleLabResourceNames(
  windowerRoot,
  actionReferences.filter((reference) =>
    resourceActionKinds.has(reference.action_kind)
    && Number.isSafeInteger(reference.action_id)
    && reference.action_id > 0
  )
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
const combatEvents = projection.combatEvents(
  actionCatalog.names,
  combatResources
).events.filter((event) => {
  const effectiveMilliseconds = Date.parse(event.effective_time);
  return effectiveMilliseconds >= startMilliseconds
    && effectiveMilliseconds <= endMilliseconds;
});
const analytics = buildBattleLabCombatAnalytics(
  combatEvents,
  combatResources.sources
);

const partyNames = status.agents.map((agent) => agent.character);
const partyNameSet = new Set(partyNames);

function increment(map, key, amount = 1) {
  map.set(key, (map.get(key) ?? 0) + amount);
}

function sourceClassCounts(records) {
  const counts = new Map();
  for (const record of records) increment(counts, record.source_class);
  return Object.fromEntries([...counts].sort());
}

function observedZones(records) {
  const zones = new Map();
  for (const record of records) {
    if (record.source_class !== "snapshot") continue;
    const zoneId = Number.isSafeInteger(record.payload.zone_id)
      ? record.payload.zone_id
      : Number.isSafeInteger(record.payload.zone)
        ? record.payload.zone
        : null;
    if (zoneId !== null) increment(zones, String(zoneId));
  }
  return Object.fromEntries([...zones].sort((a, b) => Number(a[0]) - Number(b[0])));
}

function fieldChanges(character, fieldName) {
  const result = [];
  let previous = null;
  for (const record of recordsByCharacter.get(character) ?? []) {
    if (record.source_class !== "snapshot") continue;
    const value = record.payload.fields?.[fieldName];
    if (value === undefined) continue;
    const serialized = JSON.stringify(value);
    if (serialized !== previous) {
      result.push({ time: record.client_wall_time, value });
      previous = serialized;
    }
  }
  return result;
}

function hpSummary(character) {
  const changes = fieldChanges(character, "hp");
  const values = changes.map((entry) => entry.value)
    .filter((value) => Number.isFinite(Number(value?.current)));
  return {
    samples_with_changes: changes.length,
    start: values[0] ?? null,
    end: values.at(-1) ?? null,
    minimum_hp: values.length === 0
      ? null
      : Math.min(...values.map((value) => Number(value.current))),
    reached_zero_at: changes
      .filter((entry) => Number(entry.value?.current) === 0)
      .map((entry) => entry.time),
    timeline: changes
  };
}

function adapterDecisionGroups(character) {
  const groups = new Map();
  for (const record of recordsByCharacter.get(character) ?? []) {
    if (record.source_class !== "adapter_decision") continue;
    const payload = record.payload;
    const key = [
      payload.component,
      payload.event,
      payload.domain,
      payload.action_kind,
      payload.action_id,
      payload.reason
    ].map((value) => String(value ?? "null")).join("|");
    let group = groups.get(key);
    if (group === undefined) {
      group = {
        component: payload.component ?? null,
        event: payload.event ?? null,
        domain: payload.domain ?? null,
        action_kind: payload.action_kind ?? null,
        action_id: payload.action_id ?? null,
        reason: payload.reason ?? null,
        count: 0,
        first_at: record.client_wall_time,
        last_at: record.client_wall_time
      };
      groups.set(key, group);
    }
    group.count += 1;
    group.last_at = record.client_wall_time;
  }
  return [...groups.values()].sort((left, right) =>
    left.first_at.localeCompare(right.first_at)
  );
}

function actionGroups(actorName) {
  const groups = new Map();
  for (const event of combatEvents) {
    if (event.actor_name !== actorName) continue;
    const key = [event.action_kind, event.action_id, event.action_name]
      .join("|");
    let group = groups.get(key);
    if (group === undefined) {
      group = {
        kind: event.action_kind,
        id: event.action_id,
        name: event.action_display_name ?? event.action_name,
        phases: {},
        first_at: event.effective_time,
        last_at: event.effective_time,
        targets: {},
        damage: 0,
        healing: 0,
        status_applications: 0,
        status_removals: 0
      };
      groups.set(key, group);
    }
    increment(new Map(), "unused");
    group.phases[event.phase] = (group.phases[event.phase] ?? 0) + 1;
    group.last_at = event.effective_time;
    for (const targetName of event.target_names) {
      const name = targetName ?? "unknown";
      group.targets[name] = (group.targets[name] ?? 0) + 1;
    }
    for (const result of event.results ?? []) {
      if (result.source_name === actorName && result.amount !== null) {
        if (result.outcome_kind === "damage") group.damage += result.amount;
        if (result.outcome_kind === "healing") group.healing += result.amount;
      }
      if (result.outcome_kind === "status_application") {
        group.status_applications += 1;
      }
      if (result.outcome_kind === "status_removal") {
        group.status_removals += 1;
      }
    }
  }
  return [...groups.values()].sort((left, right) =>
    left.first_at.localeCompare(right.first_at)
  );
}

function hostileActionGroups() {
  const names = [...new Set(combatEvents
    .map((event) => event.actor_name)
    .filter((name) => name !== null && !partyNameSet.has(name)))].sort();
  return Object.fromEntries(names.map((name) => [name, actionGroups(name)]));
}

function partyPressure() {
  const pressure = Object.fromEntries(partyNames.map((name) => [name, {
    hostile_actions_targeted: 0,
    hostile_damage_events: 0,
    hostile_damage_taken: 0,
    hostile_actors: {}
  }]));
  for (const event of combatEvents) {
    if (event.actor_name === null || partyNameSet.has(event.actor_name)) continue;
    for (const targetName of new Set(event.target_names)) {
      if (targetName === null || !partyNameSet.has(targetName)) continue;
      pressure[targetName].hostile_actions_targeted += 1;
      pressure[targetName].hostile_actors[event.actor_name] =
        (pressure[targetName].hostile_actors[event.actor_name] ?? 0) + 1;
    }
    for (const result of event.results ?? []) {
      if (
        result.outcome_kind === "damage"
        && result.affected_name !== null
        && partyNameSet.has(result.affected_name)
      ) {
        pressure[result.affected_name].hostile_damage_events += 1;
        pressure[result.affected_name].hostile_damage_taken += result.amount ?? 0;
      }
    }
  }
  return pressure;
}

function combatTimeline() {
  return combatEvents.filter((event) =>
    event.action_kind === "monster_ability"
    || event.action_kind === "weaponskill"
    || event.action_kind === "spell"
    || event.action_kind === "job_ability"
    || (event.results ?? []).some((result) =>
      ["defeat", "status_application", "status_removal"]
        .includes(result.outcome_kind)
    )
  ).map((event) => ({
    time: event.effective_time,
    actor_id: event.actor_id,
    actor: event.actor_name,
    action_kind: event.action_kind,
    action_id: event.action_id,
    action: event.action_display_name ?? event.action_name,
    phase: event.phase,
    target_ids: event.target_ids,
    targets: event.target_names,
    results: (event.results ?? []).map((result) => ({
      kind: result.outcome_kind,
      source_id: result.source_id,
      source: result.source_name,
      affected_id: result.affected_id,
      affected: result.affected_name,
      amount: result.amount,
      unit: result.amount_unit,
      status: result.status_name,
      message_id: result.message_id
    }))
  }));
}

// Preserve entity IDs for repeated-name enemies and include ordinary melee
// swings. This makes post-fight target-convergence analysis possible without
// guessing which Bozzetto Tormentor produced a name-only aggregate.
function hostileDirectTargetTimeline() {
  return combatEvents.filter((event) => {
    if (event.actor_name === null || partyNameSet.has(event.actor_name)) {
      return false;
    }
    const partyTargets = [...new Set(event.target_names
      .filter((name) => name !== null && partyNameSet.has(name)))];
    return partyTargets.length === 1 && event.target_names.length === 1;
  }).map((event) => ({
    time: event.effective_time,
    actor_id: event.actor_id,
    actor: event.actor_name,
    action_kind: event.action_kind,
    action_id: event.action_id,
    action: event.action_display_name ?? event.action_name,
    phase: event.phase,
    target_id: event.target_ids[0] ?? null,
    target: event.target_names[0] ?? null
  }));
}

// Preserve exact enemy IDs for each party member's direct physical offense.
// The selected cursor target is not necessarily the battle target, especially
// during PartyCombat handoffs. A completed melee/ranged/WS event is positive
// evidence of which enemy the client actually acted on at that instant.
function partyDirectTargetTimeline() {
  const physicalKinds = new Set([
    "melee_attack",
    "ranged_attack",
    "weaponskill"
  ]);
  return combatEvents.filter((event) => {
    if (!partyNameSet.has(event.actor_name)
      || !physicalKinds.has(event.action_kind)) {
      return false;
    }
    return event.target_ids.length === 1
      && event.target_names.length === 1
      && !partyNameSet.has(event.target_names[0]);
  }).map((event) => ({
    time: event.effective_time,
    actor_id: event.actor_id,
    actor: event.actor_name,
    action_kind: event.action_kind,
    action_id: event.action_id,
    action: event.action_display_name ?? event.action_name,
    phase: event.phase,
    target_id: event.target_ids[0] ?? null,
    target: event.target_names[0] ?? null
  }));
}

function deathContexts() {
  const result = {};
  for (const character of partyNames) {
    const zeroTimes = hpSummary(character).reached_zero_at;
    result[character] = zeroTimes.map((zeroTime) => {
      const zeroMilliseconds = Date.parse(zeroTime);
      return {
        zero_at: zeroTime,
        events: combatEvents.filter((event) => {
          const delta = Date.parse(event.effective_time) - zeroMilliseconds;
          return delta >= -5_000 && delta <= 2_000;
        }).map((event) => ({
          time: event.effective_time,
          actor: event.actor_name,
          kind: event.action_kind,
          action_id: event.action_id,
          action: event.action_display_name ?? event.action_name,
          phase: event.phase,
          targets: event.target_names,
          message_ids: event.message_ids,
          results: event.results ?? []
        }))
      };
    });
  }
  return result;
}

const actorAnalyticsByName = new Map(
  analytics.actors.map((actor) => [actor.entity_name, actor])
);
const entityTracks = projection.entityTracks();
const report = {
  schema_version: 1,
  source: "live PartyOps journal snapshot; read only; open suffix tolerated",
  window: {
    started_at: startedAt,
    ended_at: endedAt,
    seconds: Math.round((endMilliseconds - startMilliseconds) / 1000),
    characters: Object.fromEntries(status.agents.map((agent) => [
      agent.character,
      {
        records: (recordsByCharacter.get(agent.character) ?? []).length,
        source_classes: sourceClassCounts(
          recordsByCharacter.get(agent.character) ?? []
        ),
        zones: observedZones(recordsByCharacter.get(agent.character) ?? [])
      }
    ]))
  },
  party: Object.fromEntries(partyNames.map((name) => [name, {
    analytics: actorAnalyticsByName.get(name) ?? null,
    hp: hpSummary(name),
    mp: fieldChanges(name, "mp"),
    tp: fieldChanges(name, "tp"),
    statuses: fieldChanges(name, "statuses"),
    targets: fieldChanges(name, "targets"),
    positions: fieldChanges(name, "positions"),
    adapter_decisions: adapterDecisionGroups(name),
    actions: actionGroups(name),
    outgoing_action_requests: outgoingActionRequests(name)
  }])),
  diagnostic_combat_samples: Object.fromEntries(partyNames.map((name) => [
    name,
    (recordsByCharacter.get(name) ?? [])
      .filter((record) => record.source_class === "combat")
      .slice(0, 20)
      .map((record) => ({
        time: record.client_wall_time,
        payload: record.payload
      }))
  ])),
  diagnostic_fastfollow_samples: Object.fromEntries(partyNames.map((name) => [
    name,
    (recordsByCharacter.get(name) ?? [])
      .filter((record) => record.source_class === "adapter_decision"
        && record.payload.component === "fastfollow")
      .map((record) => ({
        time: record.client_wall_time,
        payload: record.payload
      }))
  ])),
  pressure_by_party_member: partyPressure(),
  death_contexts: deathContexts(),
  hostile_actions: hostileActionGroups(),
  battlefield_records: Object.fromEntries(partyNames.map((name) => [
    name,
    (recordsByCharacter.get(name) ?? [])
      .filter((record) => record.source_class === "battlefield")
      .map((record) => ({
        time: record.client_wall_time,
        payload: record.payload
      }))
  ])),
  entities: entityTracks.map((track) => ({
    entity_id: track.entity_id,
    entity_index: track.entity_index,
    entity_kind: track.entity_kind,
    canonical_name: track.canonical_name,
    observer_character: track.observer_character,
    zone_id: track.zone_id,
    zone_epoch: track.zone_epoch,
    first_at: track.keyframes[0]?.effective_time ?? null,
    last_at: track.keyframes.at(-1)?.effective_time ?? null,
    keyframes: track.canonical_name?.startsWith("Bozzetto")
      ? track.keyframes
      : undefined
  })),
  hostile_direct_targets: hostileDirectTargetTimeline(),
  party_direct_targets: partyDirectTargetTimeline(),
  timeline: combatTimeline(),
  decoder: {
    entity_packets: projection.decoded_entity_packets,
    combat_packets: projection.decoded_combat_packets,
    combat_events: combatEvents.length,
    normalized_fragments: analytics.coverage.normalized_fragments,
    other_fragments: analytics.coverage.other_fragments,
    unresolved_message_ids: unresolvedMessageIds,
    invalid_action_references: invalidActionReferences
  }
};

const serialized = `${JSON.stringify(report, null, 2)}\n`;
if (outputPath === null) {
  process.stdout.write(serialized);
} else {
  await writeFile(outputPath, serialized, "utf8");
  process.stdout.write(`${JSON.stringify({
    result: "PASS",
    output_path: outputPath,
    combat_events: combatEvents.length,
    timeline_events: report.timeline.length
  }, null, 2)}\n`);
}
