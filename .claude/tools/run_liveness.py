#!/usr/bin/env python3

"""Watch a long run's output and say when it stopped being normal.

A background task pushes a notification when it exits, and that covers success
and failure. It says nothing while the task is still running, so a run that
hangs or crawls is invisible until somebody looks. Both happened in the session
this was written for: a matrix stalled at step 148 and was found three samples
later by hand, and another crawled to step 59 in the time an earlier run of the
same segment reached 288, which no elapsed-time rule would have caught because
it was still writing files the whole way.

The two anomalies need different questions, and neither is a timeout:

    stalled   The output digest has not changed across STALE_OBSERVATIONS
              samples. Sample count, not seconds, for the same reason the
              dispatch watch uses it: how long a step ought to take is not
              knowable in advance, but "it produced nothing three times running"
              is a fact about the run.

    crawling  Progress continues below a fraction of the rate this same run
              established earlier. The baseline is the run's own fastest
              observed window, so it moves with the machine and the segment
              instead of being a number someone picked. The fraction is a
              chosen constant and the only one here.

Neither verdict is a failure. A stall may be a device that needs a nudge, a
crawl may be a segment that is genuinely heavier. The watcher reports what it
measured and leaves the decision where it belongs.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))

import coordinator_state as ledger  # noqa: E402

SLOW_FRACTION = 0.25
"""A window under a quarter of the run's own best rate counts as crawling."""

MINIMUM_WINDOWS = 4
"""Windows needed before a baseline rate means anything."""


def observe(directory: Path) -> tuple[str, int]:
    """A digest of what the run has written, and how many files that is."""
    names = sorted(str(path.relative_to(directory)) for path in directory.rglob("*") if path.is_file())
    digest = hashlib.sha256("\n".join(names).encode("utf-8")).hexdigest()[:16]
    return digest, len(names)


def verdict(samples: list[dict]) -> tuple[str, dict] | None:
    if len(samples) >= ledger.STALE_OBSERVATIONS:
        tail = samples[-ledger.STALE_OBSERVATIONS:]
        if len({sample["digest"] for sample in tail}) == 1:
            return "stalled", {
                "samples": len(tail),
                "files": tail[-1]["files"],
                "since": tail[0]["at"],
            }
    rates = [
        (later["files"] - earlier["files"]) / max(later["at"] - earlier["at"], 1e-6)
        for earlier, later in zip(samples, samples[1:])
    ]
    if len(rates) >= MINIMUM_WINDOWS:
        best = max(rates)
        current = rates[-1]
        if best > 0 and current < best * SLOW_FRACTION:
            return "crawling", {
                "filesPerSecond": round(current, 3),
                "bestFilesPerSecond": round(best, 3),
                "fraction": round(current / best, 3),
            }
    return None


def tail_of(path: Path, lines: int = 6) -> list[str]:
    try:
        return path.read_text(encoding="utf-8", errors="replace").splitlines()[-lines:]
    except OSError:
        return []


def watch(directory: Path, interval: float, log: Path | None, wake: str | None,
          once: bool = False) -> int:
    samples: list[dict] = []
    reported: set[str] = set()
    while True:
        if not directory.is_dir():
            time.sleep(interval)
            if once:
                return 0
            continue
        digest, files = observe(directory)
        samples.append({"at": time.time(), "digest": digest, "files": files})
        found = verdict(samples)
        if found is not None and found[0] not in reported:
            name, detail = found
            reported.add(name)
            report = {
                "watching": str(directory),
                "verdict": name,
                "detail": detail,
                "logTail": tail_of(log) if log else [],
            }
            print(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True), flush=True)
            if wake:
                subprocess.run(wake, shell=True, capture_output=True, text=True)
        if once:
            return 0
        time.sleep(interval)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--interval", type=float, default=30.0)
    parser.add_argument("--log", type=Path)
    parser.add_argument("--wake")
    parser.add_argument("--once", action="store_true")
    arguments = parser.parse_args(argv)
    return watch(arguments.directory, arguments.interval, arguments.log,
                 arguments.wake, arguments.once)


if __name__ == "__main__":
    raise SystemExit(main())
