"""Read CombatRecorder files; never connect to or control a game client."""
from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import time

ROSTER = ("Dolomedes", "Tackleberry", "Kickpuncher", "Barneystinson", "Smalls", "Achoo")
DEFAULT_ROOT = Path(os.environ.get(
    "FFXI_COMBAT_ROOT", r"C:\Program Files (x86)\Windower\addons\CombatRecorder\data"))


def timestamp(value):
    return datetime.fromtimestamp(value, timezone.utc).astimezone().strftime("%Y-%m-%d %H:%M:%S %Z")


def read_records(path, warnings=None):
    try:
        with path.open("r", encoding="utf-8") as handle:
            for line_number, line in enumerate(handle, 1):
                try:
                    row = json.loads(line)
                    if isinstance(row, dict) and isinstance(row.get("time"), (int, float)):
                        yield row
                except (ValueError, UnicodeError):
                    if warnings is not None:
                        warnings.append(f"Skipped incomplete/invalid record: {path.name}:{line_number}")
    except OSError as exc:
        if warnings is not None:
            warnings.append(f"Cannot read {path}: {exc}")


def bounds(path):
    """Skip non-overlapping segments without reading gigabytes of routine history."""
    try:
        with path.open("rb") as handle:
            first = json.loads(handle.readline()).get("time")
            handle.seek(0, 2)
            size = handle.tell()
            handle.seek(max(0, size - 131072))
            tail = handle.read().splitlines()
        for line in reversed(tail):
            try:
                last = json.loads(line).get("time")
                if isinstance(first, (int, float)) and isinstance(last, (int, float)):
                    return first, last
            except (ValueError, UnicodeError, AttributeError):
                continue
    except (OSError, ValueError, UnicodeError, AttributeError):
        pass
    return None


def latest_anchor(root):
    anchors = []
    for directory in root.iterdir() if root.exists() else []:
        if not directory.is_dir():
            continue
        files = sorted(directory.glob("incident-*.jsonl"), key=lambda p: p.stat().st_mtime, reverse=True)
        for path in files:
            times = [r["time"] for r in read_records(path) if r.get("kind") == "incident"]
            if times:
                anchors.append(min(times))
                break
    return max(anchors) if anchors else None


def load_window(root, start, end):
    records, seen, warnings = [], set(), []
    paths = list(root.glob("*/incident-*.jsonl")) + list(root.glob("*/combat-*.jsonl"))
    for path in paths:
        interval = bounds(path)
        if interval and (interval[1] < start or interval[0] > end):
            continue
        for row in read_records(path, warnings):
            if not start <= row["time"] <= end:
                continue
            key = (row.get("character"), row.get("session"), row.get("seq"))
            if key in seen:
                continue
            seen.add(key)
            records.append(row)
    records.sort(key=lambda r: (r["time"], r.get("character", ""), r.get("session", ""), r.get("seq", 0)))
    return records, warnings


def status(root, now=None):
    now = time.time() if now is None else now
    lines = [f"CombatRecorder storage: {root}"]
    extras = {p.name for p in root.iterdir() if p.is_dir()} if root.exists() else set()
    for name in sorted(set(ROSTER) | extras):
        path = root / name / "health.json"
        try:
            health = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            lines.append(f"{name}: NO READABLE HEARTBEAT (not verified running)")
            continue
        heartbeat_age = max(0, int(now - health.get("heartbeat", 0)))
        last_write = health.get("last_data_write", 0)
        write_age = f"{max(0, int(now - last_write))}s" if last_write else "NEVER"
        state = health.get("state", {})
        healthy = (heartbeat_age <= 30 and last_write > 0 and now - last_write <= 30
                   and state.get("recording") and not health.get("last_error") and not state.get("callback_errors")
                   and state.get("action_parser_available", True))
        label = "RECORDING" if healthy else "NOT VERIFIED HEALTHY"
        lines.append(f"{name}: {label}; heartbeat {heartbeat_age}s; disk write {write_age}; "
                     f"queued {health.get('queued_bytes', 0)}B; dropped {health.get('dropped_records', 0)}; "
                     f"callback errors {state.get('callback_errors', 0)}")
        if health.get("last_error") or health.get("retention_error"):
            lines.append(f"  {health.get('last_error') or health.get('retention_error')}")
    return "\n".join(lines)


def describe_entity(entity):
    if not isinstance(entity, dict):
        return "unknown"
    return entity.get("name") or f"#{entity.get('id', '?')}"


def render_report(records, start, end, warnings=(), timeline=False):
    lines = ["CombatRecorder incident review", f"Window: {timestamp(start)} through {timestamp(end)}",
             "Times are local; ordering between different clients within one second is uncertain."]
    captured = {r.get("character") for r in records}
    missing = sorted(set(ROSTER) - captured)
    lines.append("Captured: " + (", ".join(sorted(captured)) if captured else "none"))
    if missing:
        lines.append("No records in this window: " + ", ".join(missing))
    deaths, seen_deaths = [], set()
    for row in records:
        if row.get("kind") != "death":
            continue
        data = row.get("data", {})
        victim = describe_entity(data.get("victim"))
        # Each observer may see a death on a slightly different second.
        if any(v == victim and abs(t - row["time"]) <= 3 for v, t in seen_deaths):
            continue
        seen_deaths.add((victim, row["time"]))
        deaths.append((row["time"], victim, data.get("source")))
    lines.append("\nObserved deaths:")
    lines.extend(f"  {timestamp(t)} — {victim} ({source})" for t, victim, source in deaths)
    if not deaths:
        lines.append("  None recorded. A manual mark, prior death, or missing capture is not evidence of a new death.")
    cutoff = min((t for t, _, _ in deaths), default=end)
    lines.append("\nLast recorded living state before the first observed death:")
    for character in ROSTER:
        snapshots = [r for r in records if r.get("character") == character and r.get("kind") == "snapshot"
                     and r["time"] <= cutoff and r.get("data", {}).get("vitals", {}).get("hp", 0) > 0]
        if not snapshots:
            lines.append(f"  {character}: no living snapshot available")
            continue
        row = snapshots[-1]
        data, vitals = row["data"], row["data"]["vitals"]
        target = data.get("battle_target") or data.get("target")
        sustain = [b.get("name") or str(b.get("id")) for b in data.get("buffs", [])
                   if any(s in (b.get("name") or "").lower() for s in ("refresh", "ballad", "majesty", "silence", "petrif", "stun", "sleep", "paral"))]
        lines.append(f"  {character} ({cutoff - row['time']:.0f}s before): HP {vitals.get('hp', '?')} "
                     f"({vitals.get('hpp', '?')}%), MP {vitals.get('mp', '?')} ({vitals.get('mpp', '?')}%), "
                     f"target {describe_entity(target)}; relevant buffs: {', '.join(sustain) or 'none recorded'}")
    lines.append("\nRecorded actions in the minute before the first death:")
    recent = [r for r in records if cutoff - 60 <= r["time"] <= cutoff]
    for character in ROSTER:
        own = [r for r in recent if r.get("character") == character]
        requests = [r for r in own if r.get("kind") == "action_request"]
        complete = [r["data"].get("name", "unknown spell") for r in own if r.get("kind") == "action"
                    and r["data"].get("category") == 4
                    and describe_entity(r["data"].get("actor")) == character]
        cures = Counter(name for name in complete if name.startswith(("Cure", "Cura")))
        lines.append(f"  {character}: {len(requests)} outgoing requests "
                     f"({sum(bool(r['data'].get('blocked')) for r in requests)} blocked); "
                     f"spell-result packets {len(complete)}; Cure/Curaga results "
                     + (", ".join(f"{name} x{count}" for name, count in cures.items()) or "none"))
    lines.append("\nRecent diagnostics and non-melee events (last 30 seconds before first death):")
    events, seen_events = [], set()
    for row in records:
        if not cutoff - 30 <= row["time"] <= cutoff + 3:
            continue
        kind, data = row.get("kind"), row.get("data", {})
        message = None
        if kind in {"diagnostic", "recorder_error"}:
            message = f"{row['character']}: {data.get('text') or data.get('error')}"
        elif kind == "action" and data.get("category") in {3, 4, 6, 7, 8, 11, 13, 14, 15}:
            outcomes = []
            for target in data.get("targets", []):
                result = ",".join(f"msg={a.get('message')} value={a.get('param')}" for a in target.get("actions", []))
                outcomes.append(f"{describe_entity(target.get('entity'))} [{result}]")
            message = (f"{describe_entity(data.get('actor'))}: {data.get('name') or ('action #' + str(data.get('param')))} "
                       f"(category {data.get('category')}) -> " + "; ".join(outcomes))
        elif kind == "action_message":
            message = (f"{describe_entity(data.get('actor'))} -> {describe_entity(data.get('target'))}: "
                       f"msg={data.get('message')} p1={data.get('param_1')} p2={data.get('param_2')} "
                       f"{data.get('message_text') or ''}")
        if message is not None:
            key = (row["time"], message)
            if key not in seen_events:
                seen_events.add(key)
                events.append(f"  {timestamp(row['time'])} {message}")
    lines.extend(events if timeline else events[-45:])
    if not timeline and len(events) > 45:
        lines.append(f"  {len(events) - 45} earlier lines omitted; use --timeline for all events in this interval.")
    if not events:
        lines.append("  None captured.")
    gaps = [r for r in records if r.get("kind") in {"recorder_error", "session_end"}
            or (r.get("kind") == "incident" and (r["data"].get("queue_dropped") or r["data"].get("prehistory_size_limited")))]
    if warnings or gaps:
        lines.append(f"\nCapture caveats: {len(gaps)} recorder/session/retention markers; {len(warnings)} read warnings.")
        lines.extend("  " + warning for warning in warnings[:10])
    lines.append("\nThis is recorded evidence, not an automatic cause-of-death verdict. A request is not proof a spell landed; "
                 "raw result/message IDs are retained for diagnosis. Missing records are not proof of inactivity.")
    return "\n".join(lines)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=DEFAULT_ROOT)
    parser.add_argument("--status", action="store_true", help="Verify all six disk heartbeats, without contacting the game")
    parser.add_argument("--at", help="Local ISO date/time, e.g. 2026-09-01T03:10:00; defaults to latest incident")
    parser.add_argument("--before", type=int, default=5, help="Minutes of preceding evidence")
    parser.add_argument("--after", type=int, default=2, help="Minutes of following evidence")
    parser.add_argument("--timeline", action="store_true", help="Do not truncate the recent event list")
    parser.add_argument("--output", type=Path, help="Optional plain-text report file")
    args = parser.parse_args(argv)
    if args.status:
        result = status(args.root)
    else:
        anchor = datetime.fromisoformat(args.at).timestamp() if args.at else latest_anchor(args.root)
        if anchor is None:
            result = "No preserved incident is recorded yet. Load CombatRecorder on each client.\n" + status(args.root)
        else:
            start, end = anchor - max(0, args.before) * 60, anchor + max(0, args.after) * 60
            records, warnings = load_window(args.root, start, end)
            result = render_report(records, start, end, warnings, args.timeline)
    if args.output:
        args.output.write_text(result + "\n", encoding="utf-8")
    else:
        print(result)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
