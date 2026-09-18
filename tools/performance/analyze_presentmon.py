"""Summarize FFXI PresentMon captures by mapped character and over time."""

from __future__ import annotations

import argparse
import csv
from collections import Counter, defaultdict
from pathlib import Path
import statistics


NUMERIC_FIELDS = (
    "CPUStartTime",
    "FrameTime",
    "CPUBusy",
    "CPUWait",
    "GPULatency",
    "GPUTime",
    "GPUBusy",
    "GPUWait",
    "DisplayLatency",
    "DisplayedTime",
)


def number(value: str | None) -> float | None:
    try:
        result = float(value or "")
    except ValueError:
        return None
    return result


def percentile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    if not ordered:
        return float("nan")
    location = (len(ordered) - 1) * fraction
    lower = int(location)
    upper = min(lower + 1, len(ordered) - 1)
    weight = location - lower
    return ordered[lower] * (1 - weight) + ordered[upper] * weight


def process_map_path(capture: Path) -> Path:
    name = capture.name.replace("ffxi-presentmon-", "ffxi-process-map-", 1)
    return capture.with_name(name)


def load_process_map(capture: Path) -> dict[int, str]:
    path = process_map_path(capture)
    if not path.exists():
        return {}
    with path.open(newline="", encoding="utf-8-sig") as stream:
        return {
            int(row["Id"]): row.get("MainWindowTitle") or f"PID {row['Id']}"
            for row in csv.DictReader(stream)
        }


def load_capture(path: Path) -> dict[int, list[dict[str, object]]]:
    grouped: dict[int, list[dict[str, object]]] = defaultdict(list)
    with path.open(newline="", encoding="utf-8-sig") as stream:
        for source in csv.DictReader(stream):
            try:
                pid = int(source["ProcessID"])
            except (KeyError, TypeError, ValueError):
                continue
            row: dict[str, object] = dict(source)
            for field in NUMERIC_FIELDS:
                row[field] = number(source.get(field))
            grouped[pid].append(row)
    return grouped


def window_values(
    rows: list[dict[str, object]], start: float, end: float
) -> list[float]:
    return [
        float(row["FrameTime"])
        for row in rows
        if row["CPUStartTime"] is not None
        and row["FrameTime"] is not None
        and start <= float(row["CPUStartTime"]) <= end
    ]


def summarize(rows: list[dict[str, object]]) -> dict[str, object]:
    frames = [float(row["FrameTime"]) for row in rows if row["FrameTime"]]
    starts = [float(row["CPUStartTime"]) for row in rows if row["CPUStartTime"] is not None]
    if not frames or not starts:
        raise ValueError("capture has no usable frame records")
    first = min(starts)
    last = max(starts)
    # PresentMon's CSV time columns are milliseconds from trace start.
    span = max(last - first, 0.001)
    window = min(5000.0, span / 3)
    early = window_values(rows, first, first + window)
    late = window_values(rows, last - window, last)

    def average(field: str) -> float:
        values = [float(row[field]) for row in rows if row[field] is not None]
        return statistics.fmean(values) if values else float("nan")

    mean_frame = statistics.fmean(frames)
    early_mean = statistics.fmean(early) if early else float("nan")
    late_mean = statistics.fmean(late) if late else float("nan")
    modes = Counter(str(row.get("PresentMode") or "unknown") for row in rows)
    return {
        "frames": len(frames),
        "seconds": span / 1000.0,
        "fps": 1000.0 / mean_frame,
        "mean": mean_frame,
        "p95": percentile(frames, 0.95),
        "p99": percentile(frames, 0.99),
        "max": max(frames),
        "over_33": 100 * sum(value > 33.333 for value in frames) / len(frames),
        "over_50": 100 * sum(value > 50 for value in frames) / len(frames),
        "over_100": 100 * sum(value > 100 for value in frames) / len(frames),
        "cpu_busy": average("CPUBusy"),
        "gpu_busy": average("GPUBusy"),
        "gpu_wait": average("GPUWait"),
        "early": early_mean,
        "late": late_mean,
        "trend": 100 * (late_mean / early_mean - 1) if early_mean else float("nan"),
        "modes": modes,
    }


def print_capture(path: Path) -> None:
    names = load_process_map(path)
    grouped = load_capture(path)
    print(f"\n{path.name}")
    print(
        "Character       FPS   avg    p95    p99    max  >33ms  >50ms "
        " CPUms  GPUms  waitms  late-v-early"
    )
    print("-" * 103)
    summaries = []
    for pid, rows in grouped.items():
        summary = summarize(rows)
        summaries.append(summary)
        name = names.get(pid, f"PID {pid}")[:15]
        print(
            f"{name:<15} {summary['fps']:5.1f} {summary['mean']:6.1f}"
            f" {summary['p95']:6.1f} {summary['p99']:6.1f}"
            f" {summary['max']:6.1f} {summary['over_33']:6.1f}%"
            f" {summary['over_50']:6.1f}% {summary['cpu_busy']:6.1f}"
            f" {summary['gpu_busy']:6.1f} {summary['gpu_wait']:7.1f}"
            f" {summary['trend']:+11.1f}%"
        )
        mode_text = ", ".join(
            f"{mode}={count}" for mode, count in summary["modes"].most_common()
        )
        print(f"  PID {pid}; present modes: {mode_text}")
    if summaries:
        print(
            f"Aggregate per-client throughput: "
            f"{sum(float(item['fps']) for item in summaries):.1f} FPS"
        )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("captures", nargs="+", type=Path)
    args = parser.parse_args()
    for capture in args.captures:
        print_capture(capture.resolve())


if __name__ == "__main__":
    main()
