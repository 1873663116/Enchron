#!/usr/bin/env python3
"""Classify every git worktree by whether removing it would lose anything.

Removing a worktree whose branch is merged loses nothing, because the branch ref
survives and the commits are already on the integration branch. Removing one
that holds uncommitted edits loses them for good. So the audit reports those two
facts per worktree and refuses to decide anything else; which worktrees are in
use by a running agent is not visible from git and stays with the caller.

Paths come from `git worktree list --porcelain`, never from a glob, so a
worktree parked outside the sibling naming convention still gets audited.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path


def git(*arguments: str, cwd: Path | None = None) -> str:
    finished = subprocess.run(
        ["git", *arguments],
        cwd=cwd,
        capture_output=True,
        text=True,
        check=False,
    )
    return finished.stdout.strip()


def worktrees(repository: Path) -> list[dict[str, str]]:
    entries: list[dict[str, str]] = []
    current: dict[str, str] = {}
    for line in git("worktree", "list", "--porcelain", cwd=repository).splitlines():
        if not line:
            if current:
                entries.append(current)
                current = {}
            continue
        key, _, value = line.partition(" ")
        current[key] = value
    if current:
        entries.append(current)
    return entries


def directory_bytes(path: Path) -> int:
    finished = subprocess.run(
        ["du", "-sk", str(path)], capture_output=True, text=True, check=False
    )
    field = finished.stdout.split("\t", 1)[0]
    return int(field) * 1024 if field.isdigit() else 0


def is_merged(repository: Path, branch: str, integration: str) -> bool:
    # `git branch --merged` prefixes a branch checked out in another worktree
    # with "+" rather than "*", so parsing its output silently reports every
    # such branch as unmerged. Ask about ancestry directly instead.
    if not branch:
        return False
    finished = subprocess.run(
        ["git", "merge-base", "--is-ancestor", branch, integration],
        cwd=repository,
        capture_output=True,
        check=False,
    )
    return finished.returncode == 0


def audit(repository: Path, integration: str) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    for entry in worktrees(repository):
        path = Path(entry["worktree"])
        branch = entry.get("branch", "").removeprefix("refs/heads/")
        status = git("status", "--porcelain", cwd=path).splitlines()
        tracked = [l for l in status if not l.startswith("??")]
        untracked = [l for l in status if l.startswith("??")]
        rows.append(
            {
                "path": str(path),
                "branch": branch or "(detached)",
                "is_primary": path == repository,
                "merged": is_merged(repository, branch, integration),
                "tracked_edits": len(tracked),
                "untracked": len(untracked),
                "untracked_names": [l[3:] for l in untracked][:5],
                "bytes": directory_bytes(path),
                "head_subject": git("log", "-1", "--format=%s", cwd=path),
            }
        )
    return rows


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", default=".", type=Path)
    parser.add_argument("--integration", default="main")
    parser.add_argument("--json", action="store_true")
    arguments = parser.parse_args()

    repository = Path(
        git("rev-parse", "--show-toplevel", cwd=arguments.repository.resolve())
    )
    rows = audit(repository, arguments.integration)
    if arguments.json:
        print(json.dumps(rows, indent=2, ensure_ascii=False))
        return 0

    reclaimable = 0
    for row in sorted(rows, key=lambda r: (not r["merged"], -r["bytes"])):
        if row["is_primary"]:
            marker = "PRIMARY"
        elif row["tracked_edits"]:
            marker = f"WIP:{row['tracked_edits']}"
        elif row["merged"]:
            marker = "merged"
            reclaimable += row["bytes"]
        else:
            marker = "UNMERGED"
        print(
            f"{marker:<10} {row['bytes'] / 1e9:6.2f} GB  {row['branch']:<42}"
            f" {Path(row['path']).name}"
        )
        if row["untracked"]:
            print(f"{'':10} {'':9}  scratch:{row['untracked']} {row['untracked_names']}")
    # du reports logical size. On APFS a worktree shares blocks with its
    # siblings through copy-on-write, so removing them frees less than the sum
    # of their sizes. Measured 2026-08-15: du said 7.80 GB across 15 worktrees
    # and df gained 4 GB. Read this as an upper bound and trust df.
    print(f"\nlogical size of merged worktrees: {reclaimable / 1e9:.2f} GB")
    print("APFS clones share blocks, so df will gain less; measure with df")
    print("in-use by a running agent is not visible here; the caller owns that check")
    return 0


if __name__ == "__main__":
    sys.exit(main())
