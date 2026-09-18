import { execFileSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";

const SIGNET_BUFF_ID = 253;
const DEFAULT_WINDOW_MINUTES = 15;
const DEFAULT_REWARD_WARNING_SECONDS = 180;
const DEFAULT_TELEMETRY_WARNING_SECONDS = 15;

function parseArguments(argv) {
  const options = {
    json: false,
    minutes: DEFAULT_WINDOW_MINUTES,
    stateRoot: process.env.PARTYOPS_STATE_ROOT || path.join(
      process.env.LOCALAPPDATA || path.join(os.homedir(), "AppData", "Local"),
      "PartyOps"
    ),
    sourceRoot: process.env.PARTYOPS_SOURCE_ROOT || path.join(
      os.homedir(),
      "Documents",
      "Tesseract",
      "FFXI",
      "projects",
      "FFXI-Private"
    ),
    inventoryUrl: process.env.INVENTORYCORE_URL || "http://127.0.0.1:8787",
  };

  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--json") {
      options.json = true;
    } else if (argument === "--minutes") {
      options.minutes = Number(argv[index + 1]);
      index += 1;
    } else if (argument === "--state-root") {
      options.stateRoot = argv[index + 1];
      index += 1;
    } else if (argument === "--source-root") {
      options.sourceRoot = argv[index + 1];
      index += 1;
    } else if (argument === "--inventory-url") {
      options.inventoryUrl = argv[index + 1];
      index += 1;
    } else {
      throw new Error(`Unknown argument: ${argument}`);
    }
  }

  if (!Number.isFinite(options.minutes) || options.minutes < 1 || options.minutes > 120) {
    throw new Error("--minutes must be between 1 and 120.");
  }
  return options;
}

function asArray(value) {
  if (value === null || value === undefined || value === "") return [];
  return Array.isArray(value) ? value : [value];
}

function ageSeconds(isoTime, referenceMs) {
  const parsed = Date.parse(isoTime || "");
  return Number.isFinite(parsed)
    ? Math.max(0, Math.round((referenceMs - parsed) / 1000))
    : null;
}

function formatAge(seconds) {
  if (seconds === null || seconds === undefined) return "unknown";
  if (seconds < 60) return `${seconds}s`;
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ${seconds % 60}s`;
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  return `${hours}h ${minutes}m`;
}

function formatTime(isoTime) {
  if (!isoTime) return "unknown";
  const date = new Date(isoTime);
  if (!Number.isFinite(date.getTime())) return "unknown";
  return new Intl.DateTimeFormat("en-US", {
    timeZone: "America/New_York",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "numeric",
    minute: "2-digit",
    second: "2-digit",
    timeZoneName: "short",
  }).format(date);
}

function formatNumber(value) {
  return Number.isFinite(value) ? Math.round(value).toLocaleString("en-US") : "—";
}

function playerState(status) {
  if (status === 0) return "Idle";
  if (status === 1) return "Engaged";
  if (status === 2) return "Dead";
  return Number.isInteger(status) ? `State ${status}` : "Unknown";
}

function readPolProcesses() {
  const command = [
    "$ErrorActionPreference = 'SilentlyContinue'",
    "Get-Process pol | Select-Object Id,Responding,MainWindowTitle | ConvertTo-Json -Compress",
  ].join("\n");
  try {
    const output = execFileSync(
      "powershell.exe",
      ["-NoProfile", "-Command", command],
      { encoding: "utf8", timeout: 5000, windowsHide: true }
    ).trim();
    return asArray(output ? JSON.parse(output) : []).map((entry) => ({
      id: entry.Id,
      responding: entry.Responding === true,
      title: String(entry.MainWindowTitle || "").trim(),
    }));
  } catch (error) {
    return { error: `Process query failed: ${error.message}` };
  }
}

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

// PartyOps replaces its status file atomically many times per second. Windows
// readers must explicitly share delete access or they can briefly prevent the
// hub's rename. Use a tiny .NET reader with FileShare.Delete rather than a
// conventional readFile call against this hot path.
function readJsonWithDeleteSharing(filePath) {
  const encodedPath = Buffer.from(filePath, "utf8").toString("base64");
  const command = [
    `$encodedPath = '${encodedPath}'`,
    "$filePath = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encodedPath))",
    "$share = [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete",
    "$stream = [IO.File]::Open($filePath, [IO.FileMode]::Open, [IO.FileAccess]::Read, $share)",
    "$reader = [IO.StreamReader]::new($stream)",
    "try { [Console]::Out.Write($reader.ReadToEnd()) } finally { $reader.Dispose() }",
  ].join("\n");
  const output = execFileSync(
    "powershell.exe",
    ["-NoProfile", "-Command", command],
    { encoding: "utf8", timeout: 5000, windowsHide: true, maxBuffer: 5 * 1024 * 1024 }
  );
  return JSON.parse(output);
}

async function readHubStatus(statusPath) {
  let lastError = null;
  for (let attempt = 0; attempt < 5; attempt += 1) {
    try {
      return readJsonWithDeleteSharing(statusPath);
    } catch (error) {
      lastError = error;
      await sleep(100);
    }
  }
  throw lastError;
}

async function waitForHubConnections(statusPath, initialStatus) {
  let status = initialStatus;
  if (status.connected_agents >= status.expected_agents) return status;

  const startAge = ageSeconds(status.started_at, Date.now());
  const maximumWaitMs = startAge !== null && startAge < 60 ? 20_000 : 4_000;
  const deadline = Date.now() + maximumWaitMs;
  while (Date.now() < deadline) {
    await sleep(1000);
    status = await readHubStatus(statusPath);
    if (status.connected_agents >= status.expected_agents) return status;
  }
  return status;
}

function hubSessionFingerprint(status) {
  return asArray(status.agents).map((agent) => [
    agent.character,
    agent.connected === true,
    agent.agent_session_id || null,
  ]);
}

async function loadZoneNames() {
  const programFilesX86 = process.env["ProgramFiles(x86)"] || "C:/Program Files (x86)";
  const zonePath = path.join(programFilesX86, "Windower", "res", "zones.lua");
  try {
    const text = await readFile(zonePath, "utf8");
    const names = new Map();
    const expression = /\[(\d+)\]\s*=\s*\{[^\r\n]*?\ben="((?:\\.|[^"])*)"/g;
    for (const match of text.matchAll(expression)) {
      names.set(Number(match[1]), match[2].replaceAll('\\"', '"'));
    }
    return names;
  } catch {
    return new Map();
  }
}

async function loadInventory(inventoryUrl) {
  const baseUrl = inventoryUrl.replace(/\/$/, "");
  const fetchJson = async (endpoint) => {
    const response = await fetch(`${baseUrl}${endpoint}`, {
      signal: AbortSignal.timeout(4000),
    });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    return response.json();
  };

  const [currencyResult, equipmentResult] = await Promise.allSettled([
    fetchJson("/api/currencies"),
    fetchJson("/api/equipment"),
  ]);
  const currencyPayload = currencyResult.status === "fulfilled" ? currencyResult.value : null;
  const equipmentPayload = equipmentResult.status === "fulfilled" ? equipmentResult.value : null;
  const conquestRows = asArray(currencyPayload?.rows).filter((row) =>
    typeof row.name === "string" && row.name.startsWith("Conquest Points (")
  );
  const sandyRows = conquestRows.filter((row) => row.name === "Conquest Points (San d'Oria)");
  const equipmentRows = asArray(equipmentPayload?.rows).filter((row) => row.slot === "main");

  return {
    available: currencyPayload !== null,
    error: currencyResult.status === "rejected"
      ? `InventoryCore currencies unavailable: ${currencyResult.reason.message}` : null,
    byCharacter: new Map(sandyRows.map((row) => [String(row.character), Number(row.amount)])),
    sandyTotal: currencyPayload === null
      ? null : sandyRows.reduce((sum, row) => sum + Number(row.amount || 0), 0),
    allNationsTotal: currencyPayload === null
      ? null : conquestRows.reduce((sum, row) => sum + Number(row.amount || 0), 0),
    observedAt: sandyRows.map((row) => row.observed_at).filter(Boolean).sort().at(0) || null,
    equipmentAvailable: equipmentPayload !== null,
    equipmentError: equipmentResult.status === "rejected"
      ? `InventoryCore equipment unavailable: ${equipmentResult.reason.message}` : null,
    equipmentByCharacter: new Map(equipmentRows.map((row) => [String(row.character), row])),
    equipmentObservedAt: equipmentRows
      .map((row) => row.observed_at).filter(Boolean).sort().at(0) || null,
  };
}

async function inspectAgent({
  agent,
  configuration,
  stateRoot,
  journal,
  decodeFfxiProgressReward,
  minimumClientTime,
  rewardCutoffMs,
  rateWindowMinutes,
  referenceMs,
}) {
  const profile = agent.expected_phase === "P11Q" ? "p11q" : "p4-attribution";
  const result = {
    character: agent.character,
    partyPosition: agent.party_position,
    connected: agent.connected === true,
    agentSessionId: agent.agent_session_id || null,
    telemetryAt: null,
    telemetryAgeSeconds: null,
    gameAt: null,
    loggedIn: null,
    zoneId: null,
    player: null,
    hp: null,
    targets: null,
    statusIds: [],
    statusesAt: null,
    signet: null,
    rewards: {},
    rewardRatesPerHour: {},
    lastExemplarAt: null,
    lastExemplarAgeSeconds: null,
    error: null,
  };

  if (!agent.agent_session_id) {
    result.error = "No active PartyOps session.";
    return result;
  }

  try {
    const snapshot = await journal.readJournalSessionSnapshot({
      directory: path.join(stateRoot, "journals", profile, agent.character),
      installation_id: configuration.installation_id,
      agent_id: agent.agent_id,
      session_id: agent.agent_session_id,
      minimum_client_time: minimumClientTime,
    });

    let game = null;
    let gameAt = null;
    const fields = {};
    const fieldTimes = {};
    const rewards = [];

    for (const frame of snapshot.frames) {
      const records = frame.record?.payload?.records;
      if (!Array.isArray(records)) continue;
      for (const record of records) {
        const payload = record.payload;
        if (record.source_class === "snapshot"
          && payload?.capture_api === "windower.ffxi.allowlisted_snapshot.v1") {
          game = payload;
          gameAt = record.client_wall_time;
        }
        if (record.source_class === "snapshot"
          && payload?.capture_api === "partyops.windower.passive-live-state.v1"
          && payload.fields) {
          for (const [field, value] of Object.entries(payload.fields)) {
            fields[field] = value;
            fieldTimes[field] = record.client_wall_time;
          }
        }
        if (record.source_class === "reward"
          && payload?.packet_id === 0x02d
          && typeof payload.original_base64 === "string"
          && Date.parse(record.client_wall_time) >= rewardCutoffMs) {
          try {
            rewards.push({
              at: record.client_wall_time,
              ...decodeFfxiProgressReward(Buffer.from(payload.original_base64, "base64")),
            });
          } catch {
            // A malformed reward packet should not hide all other health data.
          }
        }
      }
    }

    for (const reward of rewards) {
      result.rewards[reward.reward_kind] =
        (result.rewards[reward.reward_kind] || 0) + reward.amount;
      if (reward.reward_kind === "exemplar_points") {
        result.lastExemplarAt = reward.at;
      }
    }
    for (const [kind, amount] of Object.entries(result.rewards)) {
      result.rewardRatesPerHour[kind] = Math.round(amount * 60 / rateWindowMinutes);
    }

    result.gameAt = gameAt;
    result.telemetryAt = [gameAt, ...Object.values(fieldTimes)].filter(Boolean).sort().at(-1) || null;
    result.telemetryAgeSeconds = ageSeconds(result.telemetryAt, referenceMs);
    result.loggedIn = game?.logged_in ?? null;
    result.zoneId = game?.zone ?? null;
    result.player = game?.player ?? null;
    result.hp = fields.hp ?? null;
    result.targets = fields.targets ?? null;
    result.statusIds = Array.isArray(fields.statuses?.status_ids)
      ? fields.statuses.status_ids
      : [];
    result.statusesAt = fieldTimes.statuses ?? null;
    result.signet = result.statusIds.includes(SIGNET_BUFF_ID);
    result.lastExemplarAgeSeconds = ageSeconds(result.lastExemplarAt, referenceMs);
    return result;
  } catch (error) {
    result.error = error.message;
    return result;
  }
}

function buildReport({
  referenceMs,
  rateWindowMinutes,
  hubStatus,
  agents,
  processes,
  inventory,
  zoneNames,
  elapsedMs,
}) {
  const processList = Array.isArray(processes) ? processes : [];
  const processByTitle = new Map(processList.map((entry) => [entry.title.toLowerCase(), entry]));
  const warnings = [];
  const critical = [];

  for (const agent of agents) {
    const process = processByTitle.get(agent.character.toLowerCase());
    agent.process = process || null;
    agent.zoneName = zoneNames.get(agent.zoneId) || (agent.zoneId === null ? "Unknown" : `Zone ${agent.zoneId}`);
    agent.conquestPoints = inventory.byCharacter.get(agent.character) ?? null;
    const mainWeapon = inventory.equipmentByCharacter.get(agent.character) || null;
    agent.mainWeapon = mainWeapon?.name ?? null;
    agent.mainWeaponId = mainWeapon?.id ?? null;
    agent.equipmentAt = mainWeapon?.observed_at ?? null;
    agent.equipmentAgeSeconds = ageSeconds(agent.equipmentAt, referenceMs);

    if (!process) critical.push(`${agent.character}: game process not found`);
    else if (!process.responding) critical.push(`${agent.character}: game process is not responding`);
    if (!agent.connected) critical.push(`${agent.character}: PartyOps disconnected`);
    if (agent.loggedIn !== true) critical.push(`${agent.character}: not confirmed logged in`);
    if (agent.error) critical.push(`${agent.character}: ${agent.error}`);
    if (agent.telemetryAgeSeconds === null
      || agent.telemetryAgeSeconds > DEFAULT_TELEMETRY_WARNING_SECONDS) {
      warnings.push(`${agent.character}: telemetry age ${formatAge(agent.telemetryAgeSeconds)}`);
    }
    if (agent.signet !== true) warnings.push(`${agent.character}: Signet not present`);
    if (inventory.equipmentAvailable && !mainWeapon) {
      warnings.push(`${agent.character}: main weapon not reported`);
    } else if (mainWeapon && (agent.equipmentAgeSeconds === null
      || agent.equipmentAgeSeconds > 600)) {
      warnings.push(`${agent.character}: weapon snapshot age ${formatAge(agent.equipmentAgeSeconds)}`);
    }
    if (agent.lastExemplarAgeSeconds === null
      || agent.lastExemplarAgeSeconds > DEFAULT_REWARD_WARNING_SECONDS) {
      warnings.push(`${agent.character}: last EP ${formatAge(agent.lastExemplarAgeSeconds)} ago`);
    }
  }

  if (!Array.isArray(processes)) critical.push(processes.error);
  if (!inventory.available) warnings.push(inventory.error);
  if (!inventory.equipmentAvailable) warnings.push(inventory.equipmentError);
  const inventoryAgeSeconds = ageSeconds(inventory.observedAt, referenceMs);
  if (inventory.available && (inventoryAgeSeconds === null || inventoryAgeSeconds > 600)) {
    warnings.push(`InventoryCore CP age ${formatAge(inventoryAgeSeconds)}`);
  }

  const zones = [...new Set(agents.map((agent) => agent.zoneName))];
  const respondingCount = agents.filter((agent) => agent.process?.responding).length;
  const connectedCount = agents.filter((agent) => agent.connected).length;
  const loggedInCount = agents.filter((agent) => agent.loggedIn === true).length;
  const signetCount = agents.filter((agent) => agent.signet === true).length;
  const weaponCount = agents.filter((agent) => agent.mainWeapon !== null).length;
  const freshCount = agents.filter((agent) =>
    agent.telemetryAgeSeconds !== null
      && agent.telemetryAgeSeconds <= DEFAULT_TELEMETRY_WARNING_SECONDS
  ).length;
  const exemplarRates = agents.map((agent) =>
    agent.rewardRatesPerHour.exemplar_points ?? 0
  );
  const exemplarTotals = agents.map((agent) => agent.rewards.exemplar_points ?? 0);
  const lastExemplarAge = agents.length > 0
    ? Math.max(...agents.map((agent) => agent.lastExemplarAgeSeconds ?? Number.POSITIVE_INFINITY))
    : null;
  const finiteLastExemplarAge = Number.isFinite(lastExemplarAge) ? lastExemplarAge : null;
  const overall = critical.length > 0 ? "CRITICAL" : warnings.length > 0 ? "WARNING" : "OK";

  return {
    checkedAt: new Date(referenceMs).toISOString(),
    checkedAtDisplay: formatTime(new Date(referenceMs).toISOString()),
    elapsedMs,
    overall,
    summary: {
      expectedCharacters: agents.length,
      respondingProcesses: respondingCount,
      connectedAgents: connectedCount,
      loggedInCharacters: loggedInCount,
      freshTelemetryCharacters: freshCount,
      signetCharacters: signetCount,
      weaponCharacters: weaponCount,
      zones,
      lastExemplarAgeSeconds: finiteLastExemplarAge,
      exemplarPointsWindowMinimum: exemplarTotals.length ? Math.min(...exemplarTotals) : 0,
      exemplarPointsWindowMaximum: exemplarTotals.length ? Math.max(...exemplarTotals) : 0,
      exemplarRateMinimum: exemplarRates.length ? Math.min(...exemplarRates) : 0,
      exemplarRateMaximum: exemplarRates.length ? Math.max(...exemplarRates) : 0,
      rateWindowMinutes,
      sandyConquestPointsTotal: inventory.sandyTotal,
      allNationsConquestPointsTotal: inventory.allNationsTotal,
      inventoryObservedAt: inventory.observedAt,
      inventoryAgeSeconds,
      equipmentObservedAt: inventory.equipmentObservedAt,
      equipmentAgeSeconds: ageSeconds(inventory.equipmentObservedAt, referenceMs),
      hubUpdatedAt: hubStatus.updated_at,
      hubAgeSeconds: ageSeconds(hubStatus.updated_at, referenceMs),
      hubReady: hubStatus.live_state_observation?.status === "ready_for_observation",
      hubGappedCharacters: hubStatus.live_state_observation?.currently_gapped_characters ?? null,
    },
    agents,
    warnings,
    critical,
  };
}

function renderMarkdown(report) {
  const { summary } = report;
  const lines = [
    `FFXI STATUS — ${report.checkedAtDisplay}`,
    `Overall: **${report.overall}**`,
    "",
    `- Processes: **${summary.respondingProcesses}/${summary.expectedCharacters} responding**`,
    `- PartyOps: **${summary.connectedAgents}/${summary.expectedCharacters} connected**, `
      + `${summary.freshTelemetryCharacters}/${summary.expectedCharacters} fresh, `
      + `${summary.hubGappedCharacters ?? "?"} current gaps`,
    `- Logged in: **${summary.loggedInCharacters}/${summary.expectedCharacters}**`,
    `- Zone: **${summary.zones.join(", ")}**`,
    `- Signet: **${summary.signetCharacters}/${summary.expectedCharacters}**`,
    `- Weapons: **${summary.weaponCharacters}/${summary.expectedCharacters} reported** `
      + `(oldest snapshot ${formatAge(summary.equipmentAgeSeconds)} old)`,
    `- EP: **${formatNumber(summary.exemplarRateMinimum)}`
      + (summary.exemplarRateMaximum !== summary.exemplarRateMinimum
        ? `–${formatNumber(summary.exemplarRateMaximum)}`
        : "")
      + `/hour** over ${summary.rateWindowMinutes}m; last EP ${formatAge(summary.lastExemplarAgeSeconds)} ago`,
    `- San d'Oria CP: **${formatNumber(summary.sandyConquestPointsTotal)} total** `
      + `(snapshot ${formatAge(summary.inventoryAgeSeconds)} old)`,
    "",
    "| Character | Process | Game | HP | Signet | Main weapon | EP/hour | San d'Oria CP |",
    "|---|---|---|---:|---|---|---:|---:|",
  ];

  for (const agent of report.agents) {
    const processState = agent.process?.responding ? "OK" : agent.process ? "Hung" : "Missing";
    const gameState = agent.loggedIn === true
      ? `${playerState(agent.player?.status)} · ${formatAge(agent.lastExemplarAgeSeconds)} EP`
      : "Offline/unknown";
    lines.push(
      `| ${agent.character} | ${processState} | ${gameState} | `
      + `${agent.hp?.percent ?? agent.player?.hpp ?? "—"}% | `
      + `${agent.signet === true ? "Yes" : "NO"} | `
      + `${String(agent.mainWeapon ?? "—").replaceAll("|", "\\|")} | `
      + `${formatNumber(agent.rewardRatesPerHour.exemplar_points ?? 0)} | `
      + `${formatNumber(agent.conquestPoints)} |`
    );
  }

  const issues = [...report.critical, ...report.warnings];
  if (issues.length > 0) {
    lines.push("", "Issues:");
    for (const issue of issues) lines.push(`- ${issue}`);
  }
  lines.push("", `Collected in ${(report.elapsedMs / 1000).toFixed(1)}s.`);
  return lines.join("\n");
}

async function main() {
  const startedAt = Date.now();
  const options = parseArguments(process.argv.slice(2));
  const referenceMs = Date.now();
  const rewardCutoffMs = referenceMs - options.minutes * 60_000;
  const minimumClientTime = new Date(
    rewardCutoffMs - 2 * 60_000
  ).toISOString();

  const journalUrl = pathToFileURL(path.join(
    options.sourceRoot,
    "packages",
    "journal",
    "dist",
    "index.js"
  )).href;
  const decoderUrl = pathToFileURL(path.join(
    options.sourceRoot,
    "apps",
    "hub",
    "dist",
    "battlelab",
    "ffxi-packet-decoder.js"
  )).href;

  const hubStatusPath = path.join(
    options.stateRoot,
    "run",
    "p4-attribution-status.json"
  );

  const [configuration, initialHubStatus, journal, decoder, processes, inventory, zoneNames] =
    await Promise.all([
      readFile(path.join(options.stateRoot, "config", "p4-attribution.json"), "utf8")
        .then(JSON.parse),
      readHubStatus(hubStatusPath),
      import(journalUrl),
      import(decoderUrl),
      Promise.resolve(readPolProcesses()),
      loadInventory(options.inventoryUrl),
      loadZoneNames(),
    ]);

  let hubStatus = await waitForHubConnections(hubStatusPath, initialHubStatus);
  const inspectAgents = (status) => Promise.all(status.agents.map((agent) => inspectAgent({
      agent,
      configuration,
      stateRoot: options.stateRoot,
      journal,
      decodeFfxiProgressReward: decoder.decodeFfxiProgressReward,
      minimumClientTime,
      rewardCutoffMs,
      rateWindowMinutes: options.minutes,
      referenceMs,
    })));
  let agents = await inspectAgents(hubStatus);

  // If the supervisor restarted the hub while the journal snapshot was being
  // assembled, wait for reconnection and repeat once against the new sessions.
  const finalHubStatus = await readHubStatus(hubStatusPath);
  if (finalHubStatus.started_at !== hubStatus.started_at
    || JSON.stringify(hubSessionFingerprint(finalHubStatus))
      !== JSON.stringify(hubSessionFingerprint(hubStatus))) {
    hubStatus = await waitForHubConnections(hubStatusPath, finalHubStatus);
    agents = await inspectAgents(hubStatus);
  } else {
    hubStatus = finalHubStatus;
  }

  const report = buildReport({
    referenceMs,
    rateWindowMinutes: options.minutes,
    hubStatus,
    agents,
    processes,
    inventory,
    zoneNames,
    elapsedMs: Date.now() - startedAt,
  });
  process.stdout.write(options.json
    ? `${JSON.stringify(report, null, 2)}\n`
    : `${renderMarkdown(report)}\n`);
}

main().catch((error) => {
  process.stderr.write(`FFXI status failed: ${error.stack || error.message}\n`);
  process.exitCode = 1;
});
