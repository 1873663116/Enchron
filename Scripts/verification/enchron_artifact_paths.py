#!/usr/bin/env python3

"""Where this checkout puts build output, working directories and device evidence.

Everything derives from the checkout, so a worktree or a clone on another
volume carries its own artifacts instead of writing into a path that happened
to exist on one machine. `ENCHRON_ARTIFACT_ROOT` overrides the working root for
a run that has to put it elsewhere.

Two roots, and the difference is how long the contents are meant to live.
`.scratch` holds anything a check can regenerate, which is why
`Scripts/scratch-prune.zsh` is free to delete it by age. `TestEvidence` holds
what a device run recorded and nobody can regenerate without the headset.
"""

from __future__ import annotations

from pathlib import Path
import os

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]


def artifact_root() -> Path:
    """The working root: build output, probes, logs, anything regenerable."""
    override = os.environ.get("ENCHRON_ARTIFACT_ROOT")
    return Path(override) if override else REPOSITORY_ROOT / ".scratch"


def scratch_directory(name: str) -> Path:
    """A working directory for one check, created on demand."""
    path = artifact_root() / name
    path.mkdir(parents=True, exist_ok=True)
    return path


def derived_data(name: str) -> Path:
    """A DerivedData path for one xcodebuild invocation."""
    return artifact_root() / "DerivedData" / name


def evidence_root() -> Path:
    """Device evidence. Not regenerable without the headset, so not under .scratch."""
    return REPOSITORY_ROOT / "TestEvidence"
