# Incident memory

Record what was tried and what the evidence actually supports. The command
stores private JSON events and generates a searchable Markdown index in the
existing operator vault. It does not read game packets, replace PartyOps,
run commands from transcripts, or change live clients.

Designed and directed by Don Lawrence, with code developed using OpenAI Codex.

## Use

Python 3.11 or later; no additional packages. Set FFXI_KNOWLEDGE_ROOT or pass
--knowledge-root. Otherwise the sibling Tesseract/FFXI vault is used.

```powershell
python tools/WorkspaceSetup/incident_memory.py search sortie
python tools/WorkspaceSetup/incident_memory.py record C:/private/event.json
python tools/WorkspaceSetup/incident_memory.py attach-diagnostic C:/private/report.json --incident sortie-stop --title 'Sortie repeated disengagement'
python tools/WorkspaceSetup/incident_memory.py attach-offline tools/OfflineTests/reports/<run>/result.json --incident sortie-stop --title 'Sortie offline checks'
```

The diagnostic must come from PartyOps' existing historical diagnostic command.
This attachment records counts, scope and a file hash. Counts never establish
continuous coverage or encounter success. The command does not export journals
or solve the current historical export size/continuity limits.

For a test run with automatic checkpoint recording, use
`./tools/OfflineTests/Invoke-Checks.ps1 -Suite PartyTactics -RecordIncident sortie-stop`.
The optional flag writes to the private vault through this existing tool after
the report is saved, including failed suites. No flag means no vault write,
which keeps standalone GitHub checks independent of private data. The attachment
requires the current report format, matching log/snapshot hashes and truthful
source stability. It rejects empty collections and evidence outside the report
folder. Retrying the same report is idempotent. It never declares an incident
resolved or promotes a test to live evidence. A crash before a complete report
still needs a separate failure record.

An event looks like this:

```json
{
  "version": 1,
  "incident_id": "sortie-stop",
  "event_id": "initial-report",
  "title": "Sortie repeated disengagement",
  "occurred_at": "2026-09-15T01:00:00Z",
  "kind": "operator_report",
  "evidence_level": "reported",
  "summary": "Operator reports weapons repeatedly lowering.",
  "scope": "One historical run. Cause unconfirmed.",
  "tags": ["sortie", "disengagement"],
  "evidence": [{"type": "thread", "locator": "thread ID, turn ID, message ID"}]
}
```

Kinds: operator_report, hypothesis, attempt, test_passed, test_failed, deployed,
loaded, live_passed, live_failed, limitation, lesson. Evidence levels: reported,
artifact, simulated, live. Historical assistant claims stay reported. Reserve
live results for directly checked observations and identify their scope.
Test results require a hashed test reference. `--evidence-file` adds a local
file reference and its current SHA-256 without copying the contents.

## Working loop

1. Search the affected profile, component and symptom before proposing a fix.
2. Record the failure with a source reference and its actual time. If only the
   conversation-turn time is known, say so in scope; do not invent packet times.
3. Add the hypothesis and attempt separately. Record source version, test
   command/log, deployed hash and loaded version when known. Unknown stays unknown.
4. Record the observed result, including partial success and a later recurrence.
5. Add a narrowly scoped lesson and the next regression criterion. Do not turn
   an explanation from an old assistant message into an established root cause.

Source of truth: operations/incidents/events/<incident>/<event>.json.
Generated views: operations/incidents/index.md and <incident>.md.
Reusing an identical event is harmless; changing it under the same ID fails.
Correct a record with a new event and an explicit `supersedes` list. Earlier
records remain available. There is no automatic resolved status.

Recording regenerates Markdown automatically. `rebuild` restores generated
views if needed. The writer lock rejects concurrent writers; inspect a stale
lock before removing it after a crash. This is a local documentation command,
not a background observer or automatic truth detector. Codex must invoke it at
meaningful checkpoints. Keep event files, thread extracts and reports private.
