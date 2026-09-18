"""Summarize the opt-in GearSwap profiler CSVs across FFXI clients."""

from __future__ import annotations

import argparse
import csv
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


DEFAULT_DIRECTORY = Path(
    r"C:\Program Files (x86)\Windower\addons\GearSwap\data\performance"
)


@dataclass(frozen=True)
class Report:
    path: Path
    character: str
    duration_seconds: float
    rows: tuple[dict[str, object], ...]


def read_report(path: Path) -> Report:
    with path.open(newline="", encoding="utf-8") as handle:
        records = list(csv.reader(handle))
    if len(records) < 3 or records[0][0] != "character":
        raise ValueError(f"Not a GearSwap profiler report: {path}")

    character = records[0][1]
    duration = float(records[1][1])
    headings = records[2]
    rows: list[dict[str, object]] = []
    for values in records[3:]:
        if not values:
            continue
        raw = dict(zip(headings, values, strict=False))
        rows.append(
            {
                "kind": raw["kind"],
                "event": raw["event"],
                "calls": int(raw["calls"]),
                "total_ms": float(raw["total_ms"]),
                "average_ms": float(raw["average_ms"]),
                "max_ms": float(raw["max_ms"]),
                "over_1ms": int(raw["over_1ms"]),
                "over_5ms": int(raw["over_5ms"]),
                "over_10ms": int(raw["over_10ms"]),
            }
        )
    return Report(path, character, duration, tuple(rows))


def latest_report_set(directory: Path, window_seconds: float = 10) -> list[Path]:
    candidates = list(directory.glob("gearswap-perf-*.csv"))
    if not candidates:
        return []
    newest = max(path.stat().st_mtime for path in candidates)
    recent = [
        path for path in candidates
        if newest - path.stat().st_mtime <= window_seconds
    ]
    latest_by_character: dict[str, Path] = {}
    for path in sorted(recent, key=lambda item: item.stat().st_mtime):
        try:
            character = read_report(path).character.lower()
        except (OSError, ValueError, KeyError):
            continue
        latest_by_character[character] = path
    return sorted(latest_by_character.values(), key=lambda item: item.name.lower())


def aggregate(reports: Iterable[Report]) -> list[dict[str, object]]:
    combined: dict[tuple[str, str], dict[str, object]] = {}
    for report in reports:
        for row in report.rows:
            key = (str(row["kind"]), str(row["event"]))
            current = combined.setdefault(
                key,
                {
                    "kind": key[0],
                    "event": key[1],
                    "calls": 0,
                    "total_ms": 0.0,
                    "max_ms": 0.0,
                    "over_1ms": 0,
                    "over_5ms": 0,
                    "over_10ms": 0,
                },
            )
            current["calls"] += int(row["calls"])
            current["total_ms"] += float(row["total_ms"])
            current["max_ms"] = max(
                float(current["max_ms"]), float(row["max_ms"])
            )
            for threshold in ("over_1ms", "over_5ms", "over_10ms"):
                current[threshold] += int(row[threshold])
    output = []
    for row in combined.values():
        calls = int(row["calls"])
        row["average_ms"] = float(row["total_ms"]) / calls if calls else 0.0
        output.append(row)
    return sorted(output, key=lambda row: float(row["total_ms"]), reverse=True)


def print_rows(rows: Iterable[dict[str, object]], limit: int) -> None:
    print(
        f"{'kind':<10} {'event':<34} {'calls':>8} {'total ms':>11} "
        f"{'avg ms':>9} {'max ms':>9} {'>5ms':>7} {'>10ms':>7}"
    )
    for row in list(rows)[:limit]:
        print(
            f"{str(row['kind']):<10} {str(row['event'])[:34]:<34} "
            f"{int(row['calls']):>8} {float(row['total_ms']):>11.2f} "
            f"{float(row['average_ms']):>9.3f} {float(row['max_ms']):>9.2f} "
            f"{int(row['over_5ms']):>7} {int(row['over_10ms']):>7}"
        )


def resolve_paths(inputs: list[Path], window_seconds: float) -> list[Path]:
    if not inputs:
        return latest_report_set(DEFAULT_DIRECTORY, window_seconds)
    paths: list[Path] = []
    for item in inputs:
        if item.is_dir():
            paths.extend(latest_report_set(item, window_seconds))
        elif item.is_file():
            paths.append(item)
        else:
            raise FileNotFoundError(item)
    return sorted(set(path.resolve() for path in paths))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "inputs",
        nargs="*",
        type=Path,
        help="CSV files or a report directory; defaults to the live GearSwap directory",
    )
    parser.add_argument("--window", type=float, default=10, help="latest-run grouping window in seconds")
    parser.add_argument("--top", type=int, default=20, help="rows to show per table")
    args = parser.parse_args()

    paths = resolve_paths(args.inputs, args.window)
    if not paths:
        print("No GearSwap profiler reports found.")
        return 1
    reports = [read_report(path) for path in paths]

    print(f"Reports: {len(reports)}")
    for report in reports:
        print(f"  {report.character}: {report.duration_seconds:.1f}s — {report.path}")

    print("\nSix-client aggregate (inclusive timings):")
    print_rows(aggregate(reports), args.top)

    for report in sorted(reports, key=lambda item: item.character.lower()):
        print(f"\n{report.character} ({report.duration_seconds:.1f}s):")
        print_rows(
            sorted(report.rows, key=lambda row: float(row["total_ms"]), reverse=True),
            min(args.top, 10),
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

