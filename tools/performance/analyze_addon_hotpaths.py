"""Summarize the latest bounded Windower addon hot-path profiler run."""

from __future__ import annotations

import argparse
import csv
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Iterable


DEFAULT_DIRECTORIES = (
    Path(r"C:\Program Files (x86)\Windower\addons\battlemod\data\performance"),
    Path(r"C:\Program Files (x86)\Windower\addons\HealBot\data\performance"),
    Path(r"C:\Program Files (x86)\Windower\addons\PartyTactics\data\performance"),
    Path(r"C:\Program Files (x86)\Windower\addons\React\data\performance"),
)

INTEGER_FIELDS = {
    "second",
    "calls",
    "over_1ms",
    "over_5ms",
    "over_10ms",
    "over_20ms",
}
FLOAT_FIELDS = {
    "started_epoch",
    "total_wall_ms",
    "average_wall_ms",
    "max_wall_ms",
    "total_cpu_ms",
    "average_cpu_ms",
    "max_cpu_ms",
}


@dataclass(frozen=True)
class Report:
    path: Path
    character: str
    addon: str
    started_epoch: float
    stopped_epoch: float
    duration_seconds: float
    seconds_truncated: bool
    slow_samples_dropped: int
    rows: tuple[dict[str, object], ...]


def _number(value: str, integer: bool = False) -> int | float:
    if value == "":
        return 0
    return int(float(value)) if integer else float(value)


def read_report(path: Path) -> Report:
    with path.open(newline="", encoding="utf-8") as handle:
        records = list(csv.reader(handle))
    if not records or records[0][:2] != ["format", "windower-hotpath-v1"]:
        raise ValueError(f"Not a Windower hot-path report: {path}")

    header_index = next(
        (index for index, row in enumerate(records) if row and row[0] == "record_type"),
        None,
    )
    if header_index is None:
        raise ValueError(f"Missing profiler record header: {path}")
    metadata = {
        row[0]: row[1]
        for row in records[1:header_index]
        if len(row) >= 2 and row[0]
    }
    headings = records[header_index]
    rows: list[dict[str, object]] = []
    for values in records[header_index + 1 :]:
        if not values:
            continue
        raw = dict(zip(headings, values, strict=False))
        parsed: dict[str, object] = dict(raw)
        for field in INTEGER_FIELDS:
            parsed[field] = _number(raw.get(field, ""), integer=True)
        for field in FLOAT_FIELDS:
            parsed[field] = _number(raw.get(field, ""))
        rows.append(parsed)

    return Report(
        path=path,
        character=metadata["character"],
        addon=metadata["addon"],
        started_epoch=float(metadata["started_epoch"]),
        stopped_epoch=float(metadata["stopped_epoch"]),
        duration_seconds=float(metadata["duration_seconds"]),
        seconds_truncated=metadata.get("seconds_truncated", "false").lower() == "true",
        slow_samples_dropped=int(metadata.get("slow_samples_dropped", "0")),
        rows=tuple(rows),
    )


def discover_reports(inputs: Iterable[Path]) -> list[Path]:
    paths: list[Path] = []
    for item in inputs:
        if item.is_dir():
            paths.extend(item.glob("*-perf-*.csv"))
        elif item.is_file():
            paths.append(item)
    return sorted(set(path.resolve() for path in paths))


def latest_report_set(paths: Iterable[Path], window_seconds: float) -> list[Report]:
    valid: list[Report] = []
    for path in paths:
        try:
            valid.append(read_report(path))
        except (OSError, ValueError, KeyError):
            continue
    if not valid:
        return []
    newest = max(report.stopped_epoch for report in valid)
    recent = [
        report for report in valid
        if newest - report.stopped_epoch <= window_seconds
    ]
    latest: dict[tuple[str, str], Report] = {}
    for report in sorted(recent, key=lambda value: value.stopped_epoch):
        latest[(report.addon.lower(), report.character.lower())] = report
    return sorted(latest.values(), key=lambda value: (value.addon, value.character))


def aggregate_summaries(reports: Iterable[Report]) -> list[dict[str, object]]:
    combined: dict[tuple[str, str], dict[str, object]] = {}
    for report in reports:
        for row in report.rows:
            if row["record_type"] != "summary":
                continue
            key = (report.addon, str(row["event"]))
            aggregate = combined.setdefault(
                key,
                {
                    "addon": report.addon,
                    "event": row["event"],
                    "calls": 0,
                    "total_wall_ms": 0.0,
                    "total_cpu_ms": 0.0,
                    "max_wall_ms": 0.0,
                    "over_5ms": 0,
                    "over_10ms": 0,
                    "over_20ms": 0,
                },
            )
            aggregate["calls"] += int(row["calls"])
            aggregate["total_wall_ms"] += float(row["total_wall_ms"])
            aggregate["total_cpu_ms"] += float(row["total_cpu_ms"])
            aggregate["max_wall_ms"] = max(
                float(aggregate["max_wall_ms"]), float(row["max_wall_ms"])
            )
            for field in ("over_5ms", "over_10ms", "over_20ms"):
                aggregate[field] += int(row[field])
    output = []
    for row in combined.values():
        calls = int(row["calls"])
        row["average_wall_ms"] = (
            float(row["total_wall_ms"]) / calls if calls else 0.0
        )
        output.append(row)
    return sorted(output, key=lambda row: float(row["total_wall_ms"]), reverse=True)


def synchronized_seconds(reports: Iterable[Report]) -> list[dict[str, object]]:
    grouped: dict[int, dict[str, object]] = {}
    for report in reports:
        for row in report.rows:
            if row["record_type"] != "second":
                continue
            epoch = int(float(row["started_epoch"]))
            bucket = grouped.setdefault(
                epoch,
                {
                    "epoch": epoch,
                    "inclusive_wall_ms": 0.0,
                    "max_callback_ms": 0.0,
                    "over_10ms": 0,
                    "contributors": defaultdict(float),
                },
            )
            wall = float(row["total_wall_ms"])
            bucket["inclusive_wall_ms"] += wall
            bucket["max_callback_ms"] = max(
                float(bucket["max_callback_ms"]), float(row["max_wall_ms"])
            )
            bucket["over_10ms"] += int(row["over_10ms"])
            label = f"{report.addon}/{row['event']}"
            bucket["contributors"][label] += wall
    return sorted(
        grouped.values(),
        key=lambda row: (float(row["max_callback_ms"]), float(row["inclusive_wall_ms"])),
        reverse=True,
    )


def slow_samples(reports: Iterable[Report]) -> list[dict[str, object]]:
    samples: list[dict[str, object]] = []
    for report in reports:
        for row in report.rows:
            if row["record_type"] == "slow":
                samples.append(
                    {
                        "addon": report.addon,
                        "character": report.character,
                        "event": row["event"],
                        "started_epoch": row["started_epoch"],
                        "wall_ms": row["max_wall_ms"],
                        "cpu_ms": row["max_cpu_ms"],
                    }
                )
    return sorted(samples, key=lambda row: float(row["wall_ms"]), reverse=True)


def _clock(epoch: float) -> str:
    return datetime.fromtimestamp(epoch).astimezone().strftime("%H:%M:%S")


def print_report(reports: list[Report], top: int) -> None:
    print(f"Reports: {len(reports)}")
    by_addon: dict[str, int] = defaultdict(int)
    for report in reports:
        by_addon[report.addon] += 1
    print("Clients per addon: " + ", ".join(
        f"{addon}={count}" for addon, count in sorted(by_addon.items())
    ))
    starts = [report.started_epoch for report in reports]
    stops = [report.stopped_epoch for report in reports]
    print(
        f"Run span: {_clock(min(starts))}–{_clock(max(stops))}; "
        f"individual durations {min(r.duration_seconds for r in reports):.1f}–"
        f"{max(r.duration_seconds for r in reports):.1f}s"
    )
    warnings = [
        report for report in reports
        if report.seconds_truncated or report.slow_samples_dropped
    ]
    if warnings:
        print(
            "Bound warnings: "
            + ", ".join(
                f"{report.addon}/{report.character} "
                f"(timeline_truncated={report.seconds_truncated}, "
                f"slow_rotated={report.slow_samples_dropped})"
                for report in warnings
            )
        )

    print("\nSix-client inclusive callback totals (nested rows are not additive):")
    print(
        f"{'addon':<14} {'event':<32} {'calls':>9} {'wall ms':>11} "
        f"{'avg ms':>9} {'max ms':>9} {'>10ms':>7} {'>20ms':>7}"
    )
    for row in aggregate_summaries(reports)[:top]:
        print(
            f"{str(row['addon'])[:14]:<14} {str(row['event'])[:32]:<32} "
            f"{int(row['calls']):>9} {float(row['total_wall_ms']):>11.2f} "
            f"{float(row['average_wall_ms']):>9.3f} "
            f"{float(row['max_wall_ms']):>9.2f} "
            f"{int(row['over_10ms']):>7} {int(row['over_20ms']):>7}"
        )

    print("\nLargest individual callback samples:")
    print(
        f"{'time':<8} {'character':<14} {'addon':<14} {'event':<31} "
        f"{'wall ms':>9} {'cpu ms':>9}"
    )
    for row in slow_samples(reports)[:top]:
        print(
            f"{_clock(float(row['started_epoch'])):<8} "
            f"{str(row['character'])[:14]:<14} {str(row['addon'])[:14]:<14} "
            f"{str(row['event'])[:31]:<31} {float(row['wall_ms']):>9.2f} "
            f"{float(row['cpu_ms']):>9.2f}"
        )

    print("\nSeconds with the largest callback spike (absolute clocks align clients):")
    print(f"{'time':<8} {'max ms':>9} {'inclusive ms':>13} {'>10ms':>7}  contributors")
    for row in synchronized_seconds(reports)[:top]:
        contributors = sorted(
            row["contributors"].items(), key=lambda item: item[1], reverse=True
        )[:3]
        contribution_text = ", ".join(
            f"{name}={value:.1f}" for name, value in contributors
        )
        print(
            f"{_clock(float(row['epoch'])):<8} "
            f"{float(row['max_callback_ms']):>9.2f} "
            f"{float(row['inclusive_wall_ms']):>13.2f} "
            f"{int(row['over_10ms']):>7}  {contribution_text}"
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "inputs",
        nargs="*",
        type=Path,
        help="Profiler CSV files or directories; defaults to the four live addon directories.",
    )
    parser.add_argument(
        "--window",
        type=float,
        default=20,
        help="Seconds around the newest stop time used to group the latest run.",
    )
    parser.add_argument("--top", type=int, default=20)
    args = parser.parse_args()

    inputs = args.inputs or list(DEFAULT_DIRECTORIES)
    reports = latest_report_set(discover_reports(inputs), args.window)
    if not reports:
        print("No Windower addon hot-path profiler reports found.")
        return 1
    print_report(reports, args.top)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
