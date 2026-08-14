#!/usr/bin/env python3

"""Resolves the volume that holds Enchron build and test artifacts, for scripts
that cannot source `enchron_artifact_paths.sh`. Both carry the same default and
the same refusal to write to the system disk when the volume is not mounted."""

from pathlib import Path
import os

DEFAULT_ARTIFACT_ROOT = Path("/Volumes/Cortisol/DevSpace/Xcode/Enchron")


def artifact_root() -> Path:
    root = Path(os.environ.get("ENCHRON_ARTIFACT_ROOT", str(DEFAULT_ARTIFACT_ROOT)))
    if root == Path("/Volumes/Cortisol") or Path("/Volumes/Cortisol") in root.parents:
        if not Path("/Volumes/Cortisol").is_mount():
            raise SystemExit(
                "Cortisol is not mounted; refusing to write Enchron build and test "
                "artifacts to the system disk."
            )
    return root


def scratch_directory(name: str) -> Path:
    """A working directory for one check. Lives beside the build artifacts rather
    than in the system temporary directory, which is on the internal disk."""
    path = artifact_root() / "Temporary" / name
    path.mkdir(parents=True, exist_ok=True)
    return path
