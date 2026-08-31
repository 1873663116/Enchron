#!/usr/bin/env python3

"""Probes for the run liveness watcher.

Run against a mutated copy by setting ENCHRON_CLAUDE_DIR.
"""

from __future__ import annotations

import os
from pathlib import Path
import sys
import tempfile

CLAUDE = Path(os.environ.get("ENCHRON_CLAUDE_DIR") or Path(__file__).resolve().parents[1])
sys.path.insert(0, str(CLAUDE / "tools"))

import run_liveness as liveness  # noqa: E402

FAILURES: list[str] = []


def check(name: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"OK   {name}")
    else:
        FAILURES.append(name)
        print(f"FAIL {name}: {detail}")


def samples(*pairs: tuple[float, str, int]) -> list[dict]:
    return [{"at": at, "digest": digest, "files": files} for at, digest, files in pairs]


def probe_a_frozen_output_is_a_stall() -> None:
    stalled = samples((0, "aaa", 10), (30, "aaa", 10), (60, "aaa", 10))
    found = liveness.verdict(stalled)
    check("three-identical-samples-are-a-stall", found is not None and found[0] == "stalled",
          f"{found}")
    check("the-stall-reports-when-it-started",
          found is not None and found[1]["since"] == 0, f"{found}")


def probe_two_identical_samples_are_not() -> None:
    # The newest two match and the oldest does not, so a window narrower than
    # STALE_OBSERVATIONS would call this a stall and the full window does not.
    moving = samples((0, "aaa", 10), (30, "bbb", 11), (60, "bbb", 11))
    found = liveness.verdict(moving)
    check("two-identical-samples-are-not-a-stall",
          found is None or found[0] != "stalled", f"{found}")


def probe_a_slow_window_is_measured_against_the_run_itself() -> None:
    crawling = samples(
        (0, "a", 0), (10, "b", 100), (20, "c", 200), (30, "d", 300), (40, "e", 302),
    )
    found = liveness.verdict(crawling)
    check("a-window-far-under-the-run-s-own-best-is-crawling",
          found is not None and found[0] == "crawling", f"{found}")
    check("the-crawl-names-the-rate-it-compared",
          found is not None and found[1]["bestFilesPerSecond"] == 10.0, f"{found}")


def probe_a_steady_run_is_not_crawling() -> None:
    steady = samples(
        (0, "a", 0), (10, "b", 100), (20, "c", 200), (30, "d", 300), (40, "e", 400),
    )
    check("a-steady-run-raises-nothing", liveness.verdict(steady) is None,
          f"{liveness.verdict(steady)}")


def probe_a_slow_run_is_judged_against_its_own_pace() -> None:
    # One file every ten seconds throughout. Only a baseline taken from some
    # other run would read this as crawling; its own best rate is its rate.
    unhurried = samples(
        (0, "a", 0), (10, "b", 1), (20, "c", 2), (30, "d", 3), (40, "e", 4),
    )
    found = liveness.verdict(unhurried)
    check("a-uniformly-slow-run-is-not-crawling", found is None, f"{found}")


def probe_a_short_run_has_no_baseline() -> None:
    young = samples((0, "a", 0), (10, "b", 100), (20, "c", 101))
    found = liveness.verdict(young)
    check("too-few-windows-cannot-name-a-baseline",
          found is None or found[0] != "crawling", f"{found}")


def probe_a_missing_directory_is_not_a_verdict() -> None:
    with tempfile.TemporaryDirectory() as directory:
        absent = Path(directory) / "never-created"
        check("watching-a-directory-that-does-not-exist-yet-is-quiet",
              liveness.watch(absent, 0.0, None, None, once=True) == 0)


def probe_the_digest_follows_the_files() -> None:
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        (root / "one.json").write_text("{}", encoding="utf-8")
        first, count = liveness.observe(root)
        (root / "two.json").write_text("{}", encoding="utf-8")
        second, grown = liveness.observe(root)
        check("a-new-file-moves-the-digest", first != second, f"{first} == {second}")
        check("the-file-count-follows", (count, grown) == (1, 2), f"{count},{grown}")
        again, _ = liveness.observe(root)
        check("an-unchanged-directory-holds-its-digest", again == second)


def main() -> int:
    for probe in (
        probe_a_frozen_output_is_a_stall,
        probe_two_identical_samples_are_not,
        probe_a_slow_window_is_measured_against_the_run_itself,
        probe_a_steady_run_is_not_crawling,
        probe_a_slow_run_is_judged_against_its_own_pace,
        probe_a_short_run_has_no_baseline,
        probe_a_missing_directory_is_not_a_verdict,
        probe_the_digest_follows_the_files,
    ):
        probe()
    print(f"liveness probes: {len(FAILURES)} failed")
    return 1 if FAILURES else 0


if __name__ == "__main__":
    raise SystemExit(main())
