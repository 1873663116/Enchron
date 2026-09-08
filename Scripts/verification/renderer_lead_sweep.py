"""Sweep the renderer lead budget on the device and read what the receiver made of it.

The DEBUG verb ``setRendererLeadFrames`` pins the lead ``RendererLeadBudget``
hands the delivery loop; without ``frames`` it returns to the ramp. For each
budget the tool holds playback, seeks a few times, and reduces the settlement
lines the probe journal wrote in that window to one cell: the displayed-frame
rate the renderer reported, the smallest enqueue lead, the widest delivery gap,
the process footprint and the flush cost of every seek. The cells are the
evidence behind the ceilings recorded in docs/PLAYBACK_ENGINE_CONSTRAINTS.md.
"""
from __future__ import annotations

import argparse
import json
import statistics
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import playback_mode_matrix as matrix
from harness import InstrumentFault

DEFAULT_ITEM = "MediaLibrary-grid-video-sdr-bframe-multiaudio-subtitles-30s.mkv"
DEFAULT_FRAMES = "auto,8,16,32,48"
DEFAULT_SEEK_POSITIONS = (0.5, 0.3, 0.6)
SETTLEMENT_PREFIX = "windowSettlement "
RATE_FIELDS = ("synchronizerRate", "synchronizerTime", "displayedFrameObservationCount")
SEEK_FIELDS = ("seekFlushMs", "seekTotalMs", "seekFramesInFlight")
MINIMUM_RATE_INTERVAL_SECONDS = 1.0


def parse_frames(text: str) -> list[int | None]:
    frames: list[int | None] = []
    for token in text.split(","):
        token = token.strip()
        if not token:
            continue
        frames.append(None if token == "auto" else int(token))
    if not frames:
        raise ValueError("at least one budget is required")
    return frames


def frames_label(frames: int | None) -> str:
    return "auto" if frames is None else str(frames)


def parse_settlement(line: str) -> dict[str, str] | None:
    index = line.find(SETTLEMENT_PREFIX)
    if index < 0:
        return None
    fields: dict[str, str] = {"time": line[:20]}
    for part in line[index + len(SETTLEMENT_PREFIX):].split(","):
        key, separator, value = part.partition("=")
        if separator:
            fields[key.strip()] = value.strip()
    return fields


def _number(text: str | None) -> float | None:
    if text is None:
        return None
    try:
        value = float(text)
    except ValueError:
        return None
    return value if value == value else None


def displayed_rates(samples: list[dict[str, str]]) -> list[float]:
    rates: list[float] = []
    previous: tuple[float, float] | None = None
    for sample in samples:
        rate = _number(sample.get("synchronizerRate"))
        time = _number(sample.get("synchronizerTime"))
        displayed = _number(sample.get("displayedFrameObservationCount"))
        if rate != 1.0 or time is None or displayed is None:
            previous = None
            continue
        if previous is not None:
            elapsed = time - previous[0]
            if elapsed >= MINIMUM_RATE_INTERVAL_SECONDS and displayed >= previous[1]:
                rates.append((displayed - previous[1]) / elapsed)
        previous = (time, displayed)
    return rates


def seek_costs(samples: list[dict[str, str]]) -> list[dict[str, float | None]]:
    costs: list[dict[str, float | None]] = []
    last: tuple[str | None, ...] | None = None
    for sample in samples:
        key = tuple(sample.get(field) for field in SEEK_FIELDS)
        if key == last or all(value in (None, "none") for value in key):
            continue
        last = key
        costs.append({"flushMs": _number(key[0]), "totalMs": _number(key[1]), "framesInFlight": _number(key[2])})
    return costs


def _extreme(samples: list[dict[str, str]], field: str, pick) -> float | None:
    values = [value for sample in samples if (value := _number(sample.get(field))) is not None]
    return pick(values) if values else None


def cell_summary(label: str, samples: list[dict[str, str]]) -> dict[str, object]:
    rates = displayed_rates(samples)
    return {
        "budget": label,
        "samples": len(samples),
        "budgetFramesSeen": sorted({sample["leadFramesBudget"] for sample in samples if "leadFramesBudget" in sample}, key=lambda text: (_number(text) is None, _number(text) or 0.0)),
        "displayedPerSecondMedian": round(statistics.median(rates), 1) if rates else None,
        "displayedPerSecondMin": round(min(rates), 1) if rates else None,
        "enqueueLeadMinSeconds": _extreme(samples, "enqueueLeadMin", min),
        "enqueueGapMaxSeconds": _extreme(samples, "enqueueGapMax", max),
        "lateEnqueuesMax": _extreme(samples, "lateEnqueues", max),
        "footprintMBMax": _extreme(samples, "footprintMB", max),
        "availableMBMin": _extreme(samples, "availableMB", min),
        "seeks": seek_costs(samples),
    }


def settlement_samples(delta: list[str]) -> list[dict[str, str]]:
    return [sample for line in delta if (sample := parse_settlement(line)) is not None]


def run(*, item: str, frames: list[int | None], evidence_directory: Path, hold_seconds: float, seek_positions: tuple[float, ...], seek_hold_seconds: float) -> dict[str, object]:
    instruments = matrix._get_instruments()
    client = matrix._controller_client(instruments, evidence_directory)
    matrix._invoke_controller(instruments, client, "lead-sweep:ensure-session", "ensure-session", "--no-screenshot")
    opened = matrix._invoke_controller(instruments, client, "lead-sweep:open", "tap", "--identifier", item, "--no-screenshot")
    if opened.get("success") is not True:
        return {"passed": False, "stage": "open", "response": opened}
    matrix.hold(instruments, "lead-sweep:landing", hold_seconds)
    cells: list[dict[str, object]] = []
    try:
        for budget in frames:
            label = frames_label(budget)
            arguments = () if budget is None else ("frames=" + label,)
            pinned = matrix.app_command_harness(instruments, client, "setRendererLeadFrames", *arguments)
            if pinned.get("ok") is not True and pinned.get("success") is not True:
                return {"passed": False, "stage": "pin:" + label, "response": pinned, "cells": cells}
            before = matrix._copy_probe_lines_harness(instruments, evidence_directory, "lead-sweep:before:" + label)
            cursor = matrix.probe_cursor(before)
            matrix.hold(instruments, "lead-sweep:hold:" + label, hold_seconds)
            for position in seek_positions:
                matrix.app_command_harness(instruments, client, "seekNormalized", "position=" + str(position))
                matrix.hold(instruments, "lead-sweep:seek:" + label, seek_hold_seconds)
            after = matrix._copy_probe_lines_harness(instruments, evidence_directory, "lead-sweep:after:" + label)
            delta, _, cursor_error = matrix.probe_lines_since(after, cursor)
            (evidence_directory / ("lead-sweep-" + label + ".log")).write_text("\n".join(delta) + ("\n" if delta else ""), encoding="utf-8")
            cell = cell_summary(label, settlement_samples(delta))
            cell["cursorError"] = cursor_error
            cells.append(cell)
    finally:
        matrix.app_command_harness(instruments, client, "setRendererLeadFrames")
    passed = bool(cells) and all(cell["displayedPerSecondMedian"] is not None for cell in cells)
    return {"passed": passed, "stage": "verdict", "item": item, "cells": cells}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--item", default=DEFAULT_ITEM)
    parser.add_argument("--frames", default=DEFAULT_FRAMES, help="comma-separated budgets; 'auto' releases the pin")
    parser.add_argument("--evidence-dir", type=Path, default=None)
    parser.add_argument("--hold-seconds", type=float, default=20.0)
    parser.add_argument("--seek-hold-seconds", type=float, default=6.0)
    parser.add_argument("--seek-positions", default=",".join(str(position) for position in DEFAULT_SEEK_POSITIONS))
    arguments = parser.parse_args()
    evidence_directory = (arguments.evidence_dir or matrix.default_evidence_directory() / "lead-sweep").expanduser().resolve()
    evidence_directory.mkdir(parents=True, exist_ok=True)
    seek_positions = tuple(float(token) for token in arguments.seek_positions.split(",") if token.strip())
    try:
        result = run(item=arguments.item, frames=parse_frames(arguments.frames), evidence_directory=evidence_directory, hold_seconds=arguments.hold_seconds, seek_positions=seek_positions, seek_hold_seconds=arguments.seek_hold_seconds)
    except InstrumentFault as fault:
        result = {"passed": False, "stage": "instrument", "kind": fault.kind, "evidence": fault.evidence}
    (evidence_directory / "result.json").write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, sort_keys=True))
    return 0 if result.get("passed") else 1


if __name__ == "__main__":
    raise SystemExit(main())
