import { explicitRoot } from "./partyops-paths.mjs";
import { readFile, readdir } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

const stateRoot = explicitRoot(process.env.PARTYOPS_STATE_ROOT, "PARTYOPS_STATE_ROOT");
const sourceRoot = explicitRoot(process.env.PARTYOPS_SOURCE_ROOT, "PARTYOPS_SOURCE_ROOT");
const minutes = Number(process.argv[2] ?? 15);
const characterFilter = (process.argv[3] ?? "").toLowerCase();

const journal = await import(pathToFileURL(path.join(
  sourceRoot, "packages/journal/dist/index.js"
)).href);
const status = JSON.parse(await readFile(
  path.join(stateRoot, "run", "p4-attribution-status.json"), "utf8"
));

const cutoff = Date.now() - Math.max(1, minutes) * 60_000;
for (const agent of status.agents) {
  if (characterFilter && agent.character.toLowerCase() !== characterFilter) {
    continue;
  }
  const phase = agent.expected_phase === "P11Q" ? "p11q" : "p4-attribution";
  const directory = path.join(stateRoot, "journals", phase, agent.character);
  const names = (await readdir(directory))
    .filter((name) => name.startsWith(agent.agent_session_id)
      && name.endsWith(".poj.open"))
    .sort();
  if (names.length === 0) continue;
  const parsed = await journal.inspectOpenSegment(
    path.join(directory, names.at(-1)), true
  );
  const records = parsed.frames.flatMap((frame) =>
    Array.isArray(frame.record?.payload?.records)
      ? frame.record.payload.records
      : []
  ).filter((record) => Date.parse(record.client_wall_time) >= cutoff);

  const counts = {};
  for (const record of records) {
    counts[record.source_class] = (counts[record.source_class] ?? 0) + 1;
  }
  console.log(`\n## ${agent.character}`);
  console.log(JSON.stringify(counts));
  for (const record of records) {
    const payload = JSON.stringify(record.payload);
    if (record.source_class !== "adapter_decision"
      && !/(ExpeditionGuide|PartyTactics|sortie-|Cachaemic|C BURST|TANK PULL|lua i|pt |pc |ptgs|genmei|weapon.?skill|Savage Blade|Evisceration|Last Stand|Thunder Shot)/i.test(payload)) {
      continue;
    }
    console.log(`${record.client_wall_time} ${record.source_class} ${payload.slice(0, 1200)}`);
  }
}
