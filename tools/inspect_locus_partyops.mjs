import { explicitRoot } from "./partyops-paths.mjs";
import { readFile, readdir } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

const stateRoot = explicitRoot(process.env.PARTYOPS_STATE_ROOT, "PARTYOPS_STATE_ROOT");
const sourceRoot = explicitRoot(process.env.PARTYOPS_SOURCE_ROOT, "PARTYOPS_SOURCE_ROOT");
const minutes = Number(process.argv[2] ?? 45);
const limit = Number(process.argv[3] ?? 300);

const journal = await import(pathToFileURL(path.join(
  sourceRoot, "packages/journal/dist/index.js"
)).href);
const status = JSON.parse(await readFile(
  path.join(stateRoot, "run", "p4-attribution-status.json"), "utf8"
));
const agent = status.agents.find((entry) => entry.character === "Tackleberry");
if (!agent) throw new Error("Tackleberry PartyOps agent is absent");

const phase = agent.expected_phase === "P11Q" ? "p11q" : "p4-attribution";
const directory = path.join(stateRoot, "journals", phase, agent.character);
const names = (await readdir(directory))
  .filter((name) => name.startsWith(agent.agent_session_id)
    && name.endsWith(".poj.open"))
  .sort();
if (names.length === 0) throw new Error("No open Tackleberry journal segment");

const parsed = await journal.inspectOpenSegment(
  path.join(directory, names.at(-1)), true
);
const cutoff = Date.now() - Math.max(1, minutes) * 60_000;
const records = parsed.frames.flatMap((frame) =>
  Array.isArray(frame.record?.payload?.records)
    ? frame.record.payload.records
    : []
).filter((record) => Date.parse(record.client_wall_time) >= cutoff)
 .filter((record) => [
   "combat", "adapter_decision", "state_delta", "snapshot", "position",
   "reward",
 ].includes(record.source_class));

for (const record of records.slice(-Math.max(1, limit))) {
  console.log(JSON.stringify({
    time: record.client_wall_time,
    source: record.source_class,
    payload: record.payload,
  }));
}
