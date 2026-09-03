#!/usr/bin/env python3
from __future__ import annotations
import argparse
import datetime
import json
import sys
from collections.abc import Callable, Sequence
from pathlib import Path

if str(Path(__file__).parent) not in sys.path:
    sys.path.insert(0, str(Path(__file__).parent))
from harness.budgets import LANES, SAMPLE_LIMIT, TIMING_SAMPLES_FILENAME


def _sample_files(inputs: Sequence[Path]) -> list[Path]:
    files: list[Path] = []
    for raw in inputs:
        path = Path(raw)
        if not path.exists():
            raise ValueError(f"fold input {path} does not exist")
        if path.is_dir():
            candidate = path / TIMING_SAMPLES_FILENAME
            if candidate.is_file():
                files.append(candidate)
        elif path.is_file():
            files.append(path)
        else:
            raise ValueError(f"fold input {path} is neither a file nor a directory")
    return files


def _parse_sample(origin: Path, index: int, line: str) -> dict[str, object]:
    try:
        record = json.loads(line)
    except json.JSONDecodeError as error:
        raise ValueError(f"{origin}:{index}: {error}") from error
    if not isinstance(record, dict):
        raise ValueError(f"{origin}:{index}: a TimingSample must be a JSON object")
    verb = record.get("verb")
    lane = record.get("lane")
    seconds = record.get("seconds")
    censored = record.get("censored")
    at = record.get("at")
    if not isinstance(verb, str) or not verb:
        raise ValueError(f"{origin}:{index}: a TimingSample needs a verb string")
    if lane not in LANES:
        raise ValueError(
            f"{origin}:{index}: unknown lane {lane!r}; "
            f"samples fold per lane into controller_timings.<lane>.json "
            f"for lanes {LANES}"
        )
    try:
        seconds_value = float(seconds)  # type: ignore[arg-type]
    except (TypeError, ValueError):
        raise ValueError(
            f"{origin}:{index}: a TimingSample needs numeric seconds"
        ) from None
    if not isinstance(censored, bool):
        raise ValueError(f"{origin}:{index}: a TimingSample needs a censored boolean")
    if not isinstance(at, str) or not at:
        raise ValueError(f"{origin}:{index}: a TimingSample needs an at timestamp")
    try:
        datetime.datetime.fromisoformat(at)
    except ValueError:
        raise ValueError(
            f"{origin}:{index}: a TimingSample needs an ISO-8601 at timestamp"
        ) from None
    return {
        "verb": verb,
        "lane": lane,
        "seconds": round(seconds_value, 3),
        "censored": censored,
        "at": at,
    }


def _load_document(path: Path) -> dict[str, object]:
    if not path.exists():
        return {"verbs": {}, "updatedAt": None}
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise ValueError(f"{path}: {error}") from error
    if not isinstance(document, dict) or not isinstance(
        document.get("verbs", {}), dict
    ):
        raise ValueError(
            f"{path}: a controller timings document holds a verbs object"
        )
    return document


def _fold_lane(
    path: Path,
    incoming: dict[str, list[dict[str, object]]],
    now: Callable[[], datetime.datetime],
) -> int:
    document = _load_document(path)
    verbs = document["verbs"]
    assert isinstance(verbs, dict)
    added = 0
    for verb, samples in incoming.items():
        entry = verbs.get(verb)
        if not isinstance(entry, dict):
            entry = {"samples": []}
            verbs[verb] = entry
        stored = entry.get("samples")
        if not isinstance(stored, list):
            raise ValueError(
                f"{path}: verb {verb!r} does not hold a samples list"
            )
        seen = {
            (verb, item["at"])
            for item in stored
            if isinstance(item, dict) and isinstance(item.get("at"), str)
        }
        for parsed in samples:
            key = (verb, parsed["at"])
            if key in seen:
                continue
            seen.add(key)
            stored.append({
                "seconds": parsed["seconds"],
                "censored": parsed["censored"],
                "at": parsed["at"],
            })
            added += 1
        entry["samples"] = stored[-SAMPLE_LIMIT:]
    if added:
        document["updatedAt"] = now().isoformat()
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            json.dumps(document, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
    return added


def fold_samples(
    inputs: Sequence[Path],
    timings_directory: Path,
    now: Callable[[], datetime.datetime] = lambda: datetime.datetime.now(
        datetime.timezone.utc
    ),
) -> dict[str, dict[str, int]]:
    grouped: dict[str, dict[str, list[dict[str, object]]]] = {
        lane: {} for lane in LANES
    }
    for path in _sample_files(inputs):
        for index, line in enumerate(
            path.read_text(encoding="utf-8").splitlines(), start=1
        ):
            if not line.strip():
                continue
            parsed = _parse_sample(path, index, line)
            lane = str(parsed["lane"])
            grouped[lane].setdefault(str(parsed["verb"]), []).append(parsed)
    directory = Path(timings_directory)
    summary: dict[str, dict[str, int]] = {}
    for lane in LANES:
        added = 0
        if grouped[lane]:
            added = _fold_lane(
                directory / f"controller_timings.{lane}.json",
                grouped[lane],
                now,
            )
        summary[lane] = {"added": added, "verbs": len(grouped[lane])}
    return summary


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Fold frozen-run timing samples back into the per-lane "
            "controller timings; rerunning over the same inputs changes nothing."
        )
    )
    parser.add_argument(
        "inputs",
        nargs="+",
        help="results directories or timing-samples.jsonl files",
    )
    parser.add_argument(
        "--timings-directory",
        default=str(Path(__file__).resolve().parent),
        help="directory holding controller_timings.<lane>.json",
    )
    arguments = parser.parse_args(argv)
    try:
        summary = fold_samples(
            [Path(item) for item in arguments.inputs],
            Path(arguments.timings_directory),
        )
    except ValueError as error:
        print(f"fold_timing_samples: {error}", file=sys.stderr)
        return 1
    print(json.dumps(summary, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
