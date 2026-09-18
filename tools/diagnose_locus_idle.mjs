import { explicitRoot } from "./partyops-paths.mjs";
import { readFile, readdir } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

const stateRoot = explicitRoot(process.env.PARTYOPS_STATE_ROOT, "PARTYOPS_STATE_ROOT");
const sourceRoot = explicitRoot(process.env.PARTYOPS_SOURCE_ROOT, "PARTYOPS_SOURCE_ROOT");
const minutes = Math.max(1, Number(process.argv[2] ?? 30));
const targetId = Number(process.argv[3] ?? 0);

const journal = await import(pathToFileURL(path.join(
  sourceRoot, "packages/journal/dist/index.js",
)).href);
const packetDecoder = await import(pathToFileURL(path.join(
  sourceRoot, "apps/hub/dist/battlelab/ffxi-packet-decoder.js",
)).href);
const status = JSON.parse(await readFile(
  path.join(stateRoot, "run", "p4-attribution-status.json"), "utf8",
));

const cutoff = Date.now() - minutes * 60_000;
const round = (value) => typeof value === "number" ? Number(value.toFixed(3)) : value;
const distance = (a, b) => a && b
  ? Math.hypot(a.x - b.x, a.y - b.y, (a.z ?? 0) - (b.z ?? 0))
  : null;

const result = {
  observed_at: new Date().toISOString(),
  window_minutes: minutes,
  target_id: targetId || null,
  characters: [],
  target_combat_timeline: [],
};
const observedEntities = new Map();

for (const agent of status.agents) {
  const phase = agent.expected_phase === "P11Q" ? "p11q" : "p4-attribution";
  const directory = path.join(stateRoot, "journals", phase, agent.character);
  const names = (await readdir(directory))
    .filter((name) => name.startsWith(agent.agent_session_id)
      && name.endsWith(".poj.open"))
    .sort();
  if (names.length === 0) continue;

  const parsed = await journal.inspectOpenSegment(path.join(directory, names.at(-1)), true);
  const records = parsed.frames.flatMap((frame) =>
    Array.isArray(frame.record?.payload?.records) ? frame.record.payload.records : []
  ).filter((record) => Date.parse(record.client_wall_time) >= cutoff);

  let latestPosition = null;
  let latestTarget = null;
  let latestPlayer = null;
  let firstPosition = null;
  let previousPosition = null;
  let pathDistance = 0;
  let latestPositionAt = null;
  const targetEntitySamples = [];
  const outboundTargetActions = [];

  for (const record of records) {
    const at = record.client_wall_time;
    const payload = record.payload ?? {};
    if (record.source_class === "entity" && payload.packet_id === 0x00E
      && typeof payload.original_base64 === "string") {
      try {
        const bytes = Buffer.from(payload.original_base64, "base64");
        const decoded = packetDecoder.decodeFfxiEntityUpdate(0x00E, bytes);
        const prior = observedEntities.get(decoded.entity_id) ?? {};
        observedEntities.set(decoded.entity_id, {
          ...prior,
          entity_id: decoded.entity_id,
          entity_index: decoded.entity_index,
          name: decoded.canonical_name ?? prior.name ?? null,
          position: decoded.position ?? prior.position ?? null,
          hp_percent: decoded.hp_percent ?? prior.hp_percent ?? null,
          status_id: decoded.status_id ?? prior.status_id ?? null,
          despawn: decoded.despawn,
          claim_id: bytes.length >= 0x30 && (decoded.update_mask & 0x02) !== 0
            ? bytes.readUInt32LE(0x2C) : prior.claim_id ?? null,
          observed_at: at,
        });
      } catch {
        // Ignore malformed entity evidence and retain the rest of the report.
      }
    }
    if (record.source_class === "snapshot"
      && payload.capture_api === "partyops.windower.passive-live-state.v1") {
      if (payload.fields?.positions) {
        const p = payload.fields.positions;
        const current = { x: p.x, y: p.y, z: p.z };
        if (!firstPosition) firstPosition = { ...current, at };
        if (previousPosition) pathDistance += distance(current, previousPosition) ?? 0;
        previousPosition = current;
        latestPosition = current;
        latestPositionAt = at;
      }
      if (payload.fields?.targets) {
        latestTarget = { ...payload.fields.targets, at };
      }
    }
    if (record.source_class === "snapshot"
      && payload.capture_api === "windower.ffxi.allowlisted_snapshot.v1") {
      latestPlayer = { ...payload.player, at };
    }
    if (targetId && record.source_class === "entity"
      && (payload.packet_id === 0x00D || payload.packet_id === 0x00E)) {
      const encoded = payload.original_base64;
      if (typeof encoded === "string") {
        const bytes = Buffer.from(encoded, "base64");
        if (bytes.length >= 8 && bytes.readUInt32LE(4) === targetId) {
          let decoded = null;
          try {
            decoded = packetDecoder.decodeFfxiEntityUpdate(payload.packet_id, bytes);
          } catch (error) {
            decoded = { decode_error: error.message };
          }
          targetEntitySamples.push({ at, ...decoded });
        }
      }
    }
    if (targetId && record.source_class === "combat"
      && payload.packet_id === 0x01A
      && typeof payload.original_base64 === "string") {
      const bytes = Buffer.from(payload.original_base64, "base64");
      if (bytes.length >= 16 && bytes.readUInt32LE(4) === targetId) {
        outboundTargetActions.push({
          at,
          category: bytes.readUInt16LE(10),
          param: bytes.readUInt16LE(12),
          injected: payload.injected === true,
          blocked: payload.blocked === true,
        });
      }
    }
    if (agent.character === "Dolomedes" && targetId
      && record.source_class === "combat"
      && typeof payload.original_base64 === "string"
      && (payload.packet_id === 0x028 || payload.packet_id === 0x029)) {
      const bytes = Buffer.from(payload.original_base64, "base64");
      try {
        const decoded = payload.packet_id === 0x028
          ? packetDecoder.decodeFfxiAction(bytes)
          : packetDecoder.decodeFfxiActionMessage(bytes);
        const touchesTarget = decoded.actor_id === targetId
          || decoded.target_id === targetId
          || decoded.targets?.some((target) => target.entity_id === targetId);
        if (touchesTarget) result.target_combat_timeline.push({ at, ...decoded });
      } catch {
        // Ignore malformed combat evidence and retain the rest of the report.
      }
    }
  }

  result.characters.push({
    name: agent.character,
    status: latestPlayer?.status ?? null,
    hp_percent: latestPlayer?.hpp ?? null,
    position: latestPosition && Object.fromEntries(
      Object.entries(latestPosition).map(([key, value]) => [key, round(value)]),
    ),
    position_at: latestPositionAt,
    displacement_from_window_start: firstPosition && latestPosition
      ? round(distance(firstPosition, latestPosition)) : null,
    sampled_path_distance: round(pathDistance),
    target: latestTarget,
    player_snapshot_at: latestPlayer?.at ?? null,
    target_entity_samples: targetEntitySamples.slice(-3),
    outbound_target_actions: outboundTargetActions.slice(-20),
  });
}

const leader = result.characters.find((entry) => entry.name === "Dolomedes");
for (const character of result.characters) {
  character.distance_from_dolomedes = round(distance(character.position, leader?.position));
}

result.nearby_entities = [...observedEntities.values()]
  .map((entity) => ({
    ...entity,
    distance_from_dolomedes: round(distance(entity.position, leader?.position)),
  }))
  .filter((entity) => entity.distance_from_dolomedes !== null
    && entity.distance_from_dolomedes <= 30)
  .sort((left, right) => left.distance_from_dolomedes - right.distance_from_dolomedes);

console.log(JSON.stringify(result, null, 2));
