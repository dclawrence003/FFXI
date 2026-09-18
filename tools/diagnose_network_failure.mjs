import { explicitRoot } from "./partyops-paths.mjs";
import { readFile, readdir } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

const stateRoot = explicitRoot(process.env.PARTYOPS_STATE_ROOT, "PARTYOPS_STATE_ROOT");
const sourceRoot = explicitRoot(process.env.PARTYOPS_SOURCE_ROOT, "PARTYOPS_SOURCE_ROOT");
const journal = await import(pathToFileURL(path.join(
  sourceRoot, "packages/journal/dist/index.js",
)).href);
const status = JSON.parse(await readFile(
  path.join(stateRoot, "run", "p4-attribution-status.json"), "utf8",
));
const continuityStart = Date.parse(process.argv[2] ?? "2026-09-16T12:07:00Z");
const continuityEnd = Date.parse(process.argv[3] ?? "2026-09-16T12:12:00Z");

const results = [];
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
  );
  const packets = records.filter((record) => {
    const payload = record.payload ?? {};
    return typeof payload.direction === "string"
      && typeof payload.packet_id === "number";
  });
  const incoming = packets.filter((record) => record.payload.direction === "incoming");
  const outgoing = packets.filter((record) => record.payload.direction === "outgoing");
  const last = (items) => items.length === 0 ? null : {
    at: items.at(-1).client_wall_time,
    packet_id_hex: items.at(-1).payload.packet_id_hex,
    source_class: items.at(-1).source_class,
  };
  let lastIncomingBeforeCurrentSegment = null;
  if (incoming.length === 0) {
    const closedNames = (await readdir(directory))
      .filter((name) => name.startsWith(agent.agent_session_id)
        && name.endsWith(".poj.gz"))
      .sort()
      .reverse();
    for (const closedName of closedNames) {
      const stem = closedName.slice(0, -".poj.gz".length);
      const manifestPath = path.join(directory, `${stem}.manifest.json`);
      const closed = {
        segmentPath: path.join(directory, closedName),
        manifestPath,
        manifest: JSON.parse(await readFile(manifestPath, "utf8")),
      };
      const closedParsed = await journal.verifyClosedSegment(closed);
      const closedRecords = closedParsed.frames.flatMap((frame) =>
        Array.isArray(frame.record?.payload?.records) ? frame.record.payload.records : []
      );
      const closedIncoming = closedRecords.filter((record) =>
        record.payload?.direction === "incoming"
          && typeof record.payload?.packet_id === "number"
      );
      if (closedIncoming.length > 0) {
        lastIncomingBeforeCurrentSegment = {
          segment: closedName,
          ...last(closedIncoming),
        };
        break;
      }
    }
  }
  const continuityRecords = [];
  const manifestNames = (await readdir(directory))
    .filter((name) => name.startsWith(agent.agent_session_id)
      && name.endsWith(".manifest.json"));
  for (const manifestName of manifestNames) {
    const manifestPath = path.join(directory, manifestName);
    const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
    if (Date.parse(manifest.client_time_last) < continuityStart
      || Date.parse(manifest.client_time_first) > continuityEnd) continue;
    const stem = manifestName.slice(0, -".manifest.json".length);
    const closedParsed = await journal.verifyClosedSegment({
      segmentPath: path.join(directory, `${stem}.poj.gz`),
      manifestPath,
      manifest,
    });
    continuityRecords.push(...closedParsed.frames.flatMap((frame) =>
      Array.isArray(frame.record?.payload?.records) ? frame.record.payload.records : []
    ));
  }
  const continuityIncomingTimes = continuityRecords
    .filter((record) => record.payload?.direction === "incoming"
      && typeof record.payload?.packet_id === "number")
    .map((record) => Date.parse(record.client_wall_time))
    .filter((time) => time >= continuityStart && time <= continuityEnd)
    .sort((a, b) => a - b);
  let maximumGapMs = continuityEnd - continuityStart;
  if (continuityIncomingTimes.length > 0) {
    const boundaries = [continuityStart, ...continuityIncomingTimes, continuityEnd];
    maximumGapMs = Math.max(...boundaries.slice(1).map((time, index) =>
      time - boundaries[index]));
  }
  results.push({
    character: agent.character,
    current_segment: names.at(-1),
    first_record_at: records[0]?.client_wall_time ?? null,
    last_record_at: records.at(-1)?.client_wall_time ?? null,
    packet_records: packets.length,
    last_incoming: last(incoming),
    last_incoming_before_current_segment: lastIncomingBeforeCurrentSegment,
    last_outgoing: last(outgoing),
    continuity_window: {
      start: new Date(continuityStart).toISOString(),
      end: new Date(continuityEnd).toISOString(),
      incoming_packets: continuityIncomingTimes.length,
      first_incoming_at: continuityIncomingTimes.length > 0
        ? new Date(continuityIncomingTimes[0]).toISOString() : null,
      last_incoming_at: continuityIncomingTimes.length > 0
        ? new Date(continuityIncomingTimes.at(-1)).toISOString() : null,
      maximum_gap_ms: maximumGapMs,
    },
  });
}

console.log(JSON.stringify({ observed_at: new Date().toISOString(), agents: results }, null, 2));
