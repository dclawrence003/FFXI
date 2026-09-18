"""Private incident memory. Stores evidence-backed claims; never parses game journals.

Designed and directed by Don Lawrence, developed using OpenAI Codex.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import tempfile
from contextlib import contextmanager
from datetime import datetime, timezone

KINDS = {'operator_report', 'hypothesis', 'attempt', 'test_passed', 'test_failed',
         'deployed', 'loaded', 'live_passed', 'live_failed', 'limitation', 'lesson'}
LEVELS = {'reported', 'artifact', 'simulated', 'live'}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def read_json(path):
    path = Path(path)
    require(path.stat().st_size <= 8 * 1024 * 1024, 'JSON input exceeds 8 MiB.')
    return json.loads(path.read_text(encoding='utf-8-sig'))


def timestamp(value):
    result = datetime.fromisoformat(value.replace('Z', '+00:00'))
    require(result.tzinfo is not None, 'Timestamps must include a UTC offset.')
    return result


def safe_id(value):
    require(isinstance(value, str) and re.fullmatch(r'[a-z0-9][a-z0-9-]{0,99}', value), 'Invalid ID.')
    return value


def validate(event):
    require(event.get('version') == 1, 'Unsupported event version.')
    for key in ('incident_id', 'event_id'):
        safe_id(event.get(key))
    for key in ('title', 'summary', 'scope'):
        require(isinstance(event.get(key), str) and 0 < len(event[key]) <= 4000, f'Missing or oversized {key}.')
    timestamp(event['occurred_at'])
    require(event.get('kind') in KINDS, 'Unknown event kind.')
    require(event.get('evidence_level') in LEVELS, 'Unknown evidence level.')
    evidence = event.get('evidence')
    require(isinstance(evidence, list) and 0 < len(evidence) <= 30, 'Evidence references required.')
    for ref in evidence:
        require(isinstance(ref.get('locator'), str) and 0 < len(ref['locator']) <= 2000, 'Evidence locator required.')
        require(ref.get('type') in {'thread', 'file', 'test', 'observation', 'partyops'}, 'Unknown evidence type.')
        if 'sha256' in ref:
            require(re.fullmatch(r'[a-f0-9]{64}', ref['sha256']), 'Invalid evidence hash.')
    if event['kind'] in {'live_passed', 'live_failed'}:
        require(event['evidence_level'] == 'live', 'Live outcome requires live evidence.')
        require(any(r['type'] in {'observation', 'partyops'} for r in evidence), 'Live outcome needs observation evidence.')
    if event['kind'] in {'test_passed', 'test_failed'}:
        require(event['evidence_level'] in {'simulated', 'artifact'}, 'Test result requires test artifact evidence.')
        require(any(r['type'] == 'test' and 'sha256' in r for r in evidence), 'Test result needs hashed test evidence.')
    for key in ('supersedes', 'tags'):
        require(isinstance(event.get(key, []), list), f'{key} must be a list.')
        for value in event.get(key, []):
            safe_id(value)
    return event


def knowledge_root(value=None):
    root = Path(value or os.environ.get('FFXI_KNOWLEDGE_ROOT') or
                Path(__file__).resolve().parents[2].parent / 'Tesseract' / 'FFXI').resolve()
    require((root / 'operations/current-state.md').is_file(), 'Operator knowledge root unavailable; supply --knowledge-root.')
    return root


def load_events(root):
    result = []
    for path in sorted((root / 'operations/incidents/events').glob('*/*.json')):
        require(not path.is_symlink(), 'Linked event files are not supported.')
        event = validate(read_json(path))
        require(path.parent.name == event['incident_id'] and path.stem == event['event_id'], 'Event identity/path mismatch.')
        result.append(event)
    return sorted(result, key=lambda e: (timestamp(e['occurred_at']), e['event_id']))


def md(value):
    return str(value).replace('\r', ' ').replace('\n', ' ').replace('|', '\\|').replace('<', '&lt;').replace('>', '&gt;')


def render_incident(events):
    lines = [f"# {md(events[-1]['title'])}", '',
             'Generated from immutable event records. Newer entries do not erase earlier failures.',
             'Test success, deployment, loaded code and live results are separate claims.', '',
             '## Timeline', '']
    for e in events:
        lines += [f"### {e['occurred_at']} — {e['kind']} ({e['evidence_level']})", '',
                  md(e['summary']), '', f"Scope: {md(e['scope'])}", '', f"Event: `{e['event_id']}`", '']
        if e.get('supersedes'):
            lines += ['Explicitly supersedes: ' + ', '.join(e['supersedes']), '']
        for ref in e['evidence']:
            lines.append(f"- {ref['type']}: {md(ref['locator'])}" + (f"; SHA-256 `{ref['sha256']}`" if ref.get('sha256') else ''))
        lines.append('')
    lines += ['## Interpretation', '', 'There is no automatic resolved status. Evaluate the scope and evidence of each outcome.',
              'Thread reports remain reports unless independently checked. Missing telemetry is unknown.', '']
    return '\n'.join(lines)


def atomic_text(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=path.parent, delete=False) as handle:
        handle.write(text)
        temp = Path(handle.name)
    try:
        os.replace(temp, path)
    finally:
        temp.unlink(missing_ok=True)


def rebuild(root):
    events = load_events(root)
    grouped = {}
    for e in events:
        grouped.setdefault(e['incident_id'], []).append(e)
    lines = ['# Incident memory', '', 'Generated index. Search before changing a previously investigated component.', '',
             '| Incident | Latest entry | Recorded events |', '|---|---|---|']
    for incident, rows in sorted(grouped.items()):
        atomic_text(root / f'operations/incidents/{incident}.md', render_incident(rows))
        lines.append(f"| [{md(rows[-1]['title'])}]({incident}.md) | {rows[-1]['kind']} | {len(rows)} |")
    atomic_text(root / 'operations/incidents/index.md', '\n'.join(lines) + '\n')
    return events


@contextmanager
def writer(root):
    base = root / 'operations/incidents'
    base.mkdir(parents=True, exist_ok=True)
    lock = base / '.writer.lock'
    # Fail rather than racing a second writer. A crashed lock needs explicit inspection.
    with lock.open('x', encoding='utf-8') as handle:
        handle.write(str(os.getpid()))
    try:
        yield base
    finally:
        lock.unlink()


def record(root, event):
    event = dict(validate(event))
    with writer(root) as base:
        current = load_events(root)
        known = {e['event_id'] for e in current if e['incident_id'] == event['incident_id']}
        require(set(event.get('supersedes', [])) <= known, 'Superseded event does not exist in this incident.')
        path = base / 'events' / event['incident_id'] / (event['event_id'] + '.json')
        if path.exists():
            existing = read_json(path)
            comparable = dict(existing)
            comparable.pop('recorded_at', None)
            require(comparable == event, 'Event ID already exists with different content. Add a new correction event.')
        else:
            event['recorded_at'] = datetime.now(timezone.utc).isoformat()
            path.parent.mkdir(parents=True, exist_ok=True)
            with path.open('x', encoding='utf-8') as handle:
                json.dump(event, handle, ensure_ascii=False, indent=2)
                handle.write('\n')
        rebuild(root)
        return path


def attach_file(event, filename, kind='file'):
    path = Path(filename).resolve()
    require(path.is_file(), 'Evidence file is missing.')
    sha = hashlib.sha256()
    with path.open('rb') as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b''):
            sha.update(block)
    event.setdefault('evidence', []).append({'type': kind, 'locator': str(path), 'sha256': sha.hexdigest()})
    return event


def diagnostic_event(filename, incident, title):
    d = read_json(filename)
    require(d.get('kind') == 'partyops-historical-diagnostic' and d.get('version') == 1, 'Not a supported PartyOps diagnostic.')
    require(isinstance(d.get('observers'), list) and d['observers'], 'Diagnostic observers missing.')
    window = d['requested_window']
    require(timestamp(window['ended_at']) > timestamp(window['started_at']), 'Invalid diagnostic window.')
    summary = '; '.join(f"{o['character']}: {o['selected_records']} records ({o['result']})" for o in d['observers'])
    event = {'version': 1, 'incident_id': incident, 'event_id': 'diagnostic-' + digest(Path(filename).read_bytes())[:16],
             'title': title, 'occurred_at': window['ended_at'], 'kind': 'limitation', 'evidence_level': 'artifact',
             'summary': 'PartyOps diagnostic: ' + summary,
             'scope': f"{window['started_at']} through {window['ended_at']}; counts only. No continuous coverage, cause or encounter-success claim.",
             'tags': ['partyops', 'coverage'], 'evidence': []}
    return attach_file(event, filename, 'partyops')


def offline_event(filename, incident, title):
    path = Path(filename).resolve()
    report = read_json(path)
    require(report.get('format') == 'ffxi-offline-check-result-v1', 'Unsupported offline report.')
    require(report.get('live_commands') is False and report.get('installed_file_checks') is False,
            'Only source-only offline reports can be attached here.')
    suites = report.get('suites')
    require(isinstance(suites, list) and 0 < len(suites) <= 27, 'Invalid suite collection.')
    require(len({s['suite'] for s in suites}) == len(suites), 'Duplicate suite names.')
    def verify_local(value, expected=None):
        candidate = Path(value).resolve()
        require(candidate.parent == path.parent, 'Evidence must stay in the report directory.')
        require(candidate.is_file() and candidate.stat().st_size <= 32 * 1024 * 1024,
                'Missing or oversized report evidence.')
        actual = digest(candidate.read_bytes())
        require(expected is None or actual == expected, 'Report evidence hash mismatch.')
        return candidate, actual
    snapshot, before_hash = verify_local(report['source_snapshot'], report['source_snapshot_sha256'])
    _, after_hash = verify_local(path.parent / 'source-after.json')
    unchanged = before_hash == after_hash
    require(report.get('source_unchanged_during_run') is unchanged, 'Source stability claim mismatch.')
    source = read_json(snapshot)
    require(source.get('format') == 'ffxi-offline-source-snapshot-v1', 'Unsupported source snapshot.')
    require(re.fullmatch(r'[a-f0-9]{40}', source.get('commit', '')), 'Invalid source commit.')
    failures = []
    evidence = []
    for suite in suites:
        require(type(suite.get('exit_code')) is int, 'Suite exit code is missing.')
        log, sha = verify_local(suite['log'], suite['log_sha256'])
        evidence.append({'type': 'test', 'locator': str(log), 'sha256': sha})
        if suite['exit_code'] != 0:
            failures.append(suite['suite'])
    passed = unchanged and not failures
    event = {'version': 1, 'incident_id': incident,
             'event_id': 'offline-' + digest(path.read_bytes())[:16], 'title': title,
             'occurred_at': report['recorded_at'], 'kind': 'test_passed' if passed else 'test_failed',
             'evidence_level': 'simulated',
             'summary': f"Offline run: {len(suites)} suites; failed: {', '.join(failures) or 'none'}; source unchanged: {unchanged}.",
             'scope': f"Commit {source['commit']} plus hashed working files. Only configured cases, including their documented mocks. No deployment, loaded-client, historical-cause or gameplay-success claim.",
             'tags': ['offline', 'automated-checkpoint'], 'evidence': evidence}
    attach_file(event, path, 'test')
    attach_file(event, snapshot)
    return validate(event)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--knowledge-root')
    commands = parser.add_subparsers(dest='command', required=True)
    add = commands.add_parser('record')
    add.add_argument('event_json')
    add.add_argument('--evidence-file', action='append', default=[])
    search = commands.add_parser('search')
    search.add_argument('query')
    commands.add_parser('rebuild')
    diag = commands.add_parser('attach-diagnostic')
    diag.add_argument('diagnostic_json')
    diag.add_argument('--incident', required=True)
    diag.add_argument('--title', required=True)
    offline = commands.add_parser('attach-offline')
    offline.add_argument('result_json')
    offline.add_argument('--incident', required=True)
    offline.add_argument('--title', required=True)
    args = parser.parse_args()
    root = knowledge_root(args.knowledge_root)
    if args.command == 'record':
        event = read_json(args.event_json)
        for filename in args.evidence_file:
            attach_file(event, filename)
        print(record(root, event))
    elif args.command == 'attach-diagnostic':
        print(record(root, diagnostic_event(args.diagnostic_json, args.incident, args.title)))
    elif args.command == 'attach-offline':
        print(record(root, offline_event(args.result_json, args.incident, args.title)))
    elif args.command == 'search':
        query = args.query.casefold()
        matches = [e for e in load_events(root) if query in json.dumps(e, ensure_ascii=False).casefold()]
        print(json.dumps(matches, ensure_ascii=False, indent=2))
    else:
        with writer(root):
            print(f'Rebuilt {len(rebuild(root))} events.')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, KeyError, TypeError) as error:
        raise SystemExit(str(error))
