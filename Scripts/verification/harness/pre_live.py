from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path
from typing import Callable

RULES_DIRECTORY = Path(__file__).resolve().parents[2] / "rules"

PRE_LIVE_CHECKS = (
    "test_controller_replay.py",
    "test_emby_hang_recovery.py",
    "test_reachability_matrix.py",
    "test_playback_failure_identifier_contract.py",
    "test_honest_menu_audio_episodes.py",
    "test_reachability_closure.py",
    "test_emby_signin_harness.py",
)

REQUIRED_CHECKS = frozenset(
    {"test_controller_replay.py", "test_emby_hang_recovery.py"}
)

CheckRunner = Callable[[Path], int]


def pre_live_disabled() -> bool:
    return bool(
        os.environ.get("ENCHRON_REPLAY") or os.environ.get("ENCHRON_SKIP_PRELIVE")
    )


def _subprocess_check(path: Path) -> int:
    environment = dict(os.environ)
    environment["ENCHRON_SKIP_PRELIVE"] = "1"
    completed = subprocess.run(
        [sys.executable, str(path)],
        capture_output=True,
        text=True,
        env=environment,
    )
    return completed.returncode


def failing_pre_live_checks(runner: CheckRunner | None = None) -> list[str]:
    execute = runner if runner is not None else _subprocess_check
    failed: list[str] = []
    for name in PRE_LIVE_CHECKS:
        if execute(RULES_DIRECTORY / name) != 0:
            failed.append(name)
    return failed


def refusal_reason(failed: list[str]) -> str:
    joined = ", ".join(failed)
    return (
        "offline harness verification failed before any live run; the changed "
        f"harness logic did not pass its offline checks: {joined}. Fix the logic "
        "and rerun the offline checks; a live segment run stays refused until the "
        "offline loop is green."
    )
