#!/usr/bin/env python3
"""Reclaim merged worktrees and their local branches after a PR merges.

The default is a dry run that prints the plan. --apply performs the work.
A worktree with local changes is skipped unless --force is given; --force
archives its tracked patches under --archive before removing it. --pr resolves
the head branch of a merged pull request with gh and reclaims exactly that
branch, which also covers squash merges that ancestry cannot see.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


def git(*arguments: str, cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", *arguments],
        cwd=cwd,
        capture_output=True,
        text=True,
        check=False,
    )


def git_text(*arguments: str, cwd: Path) -> str:
    return git(*arguments, cwd=cwd).stdout.strip()


def parse_worktrees(repository: Path) -> list[dict[str, str]]:
    entries: list[dict[str, str]] = []
    current: dict[str, str] = {}
    for line in git("worktree", "list", "--porcelain", cwd=repository).stdout.splitlines():
        if not line:
            if current:
                entries.append(current)
                current = {}
            continue
        key, _, value = line.partition(" ")
        current[key.lower()] = value
    if current:
        entries.append(current)
    return entries


def existing_refs(repository: Path, requested: list[str]) -> list[str]:
    refs = []
    for ref in requested:
        if git("rev-parse", "--verify", "--quiet", f"{ref}^{{commit}}", cwd=repository).returncode == 0:
            refs.append(ref)
    return refs


def is_ancestor(repository: Path, commit: str, integration: str) -> bool:
    return git("merge-base", "--is-ancestor", commit, integration, cwd=repository).returncode == 0


def status_lines(path: Path) -> list[str]:
    return [line for line in git("status", "--porcelain", cwd=path).stdout.splitlines() if line]


def tracked_status_lines(path: Path) -> list[str]:
    return [line for line in status_lines(path) if not line.startswith("??")]


def archive_worktree(archive_root: Path, path: Path) -> Path:
    target = archive_root / "worktrees" / (path.name or "worktree")
    target.mkdir(parents=True, exist_ok=True)
    (target / "status.txt").write_text(git("status", "--porcelain", cwd=path).stdout)
    (target / "head.txt").write_text(git("log", "-1", "--format=fuller", cwd=path).stdout)
    (target / "unstaged.patch").write_text(git("diff", "--binary", cwd=path).stdout)
    (target / "staged.patch").write_text(git("diff", "--cached", "--binary", cwd=path).stdout)
    return target


def local_branches(repository: Path) -> list[str]:
    return [
        line
        for line in git_text(
            "for-each-ref", "--format=%(refname:short)", "refs/heads/", cwd=repository
        ).splitlines()
        if line
    ]


def resolve_pr(repository: Path, number: int) -> dict[str, str]:
    finished = subprocess.run(
        ["gh", "pr", "view", str(number), "--json", "state,headRefName,headRefOid,mergedAt"],
        cwd=repository,
        capture_output=True,
        text=True,
        check=False,
    )
    if finished.returncode != 0:
        raise SystemExit(f"gh pr view {number} failed: {finished.stderr.strip()}")
    data = json.loads(finished.stdout)
    if data.get("state") != "MERGED":
        raise SystemExit(f"PR #{number} is {data.get('state')}, not MERGED")
    return data


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", default=".", type=Path)
    parser.add_argument("--pr", type=int, help="reclaim the head branch of a merged PR")
    parser.add_argument(
        "--integration",
        action="append",
        default=None,
        help="integration ref; repeatable; defaults to main and origin/main",
    )
    parser.add_argument("--apply", action="store_true", help="perform the plan")
    parser.add_argument(
        "--force",
        action="store_true",
        help="reclaim worktrees with local changes after archiving their patches",
    )
    parser.add_argument(
        "--archive",
        default=None,
        type=Path,
        help="archive directory; defaults to .scratch/git-cleanup/<UTC stamp>",
    )
    parser.add_argument(
        "--repair-origin-head",
        action="store_true",
        help="point origin/HEAD at the remote default branch",
    )
    arguments = parser.parse_args()

    repository = Path(git_text("rev-parse", "--show-toplevel", cwd=arguments.repository.resolve()))
    requested = arguments.integration or ["main", "origin/main"]
    integrations = existing_refs(repository, requested)
    if not integrations:
        raise SystemExit(f"none of the integration refs exist: {', '.join(requested)}")

    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    archive_root = arguments.archive or repository / ".scratch" / "git-cleanup" / stamp

    pr = resolve_pr(repository, arguments.pr) if arguments.pr else None
    pr_branch = pr["headRefName"] if pr else None
    pr_head = pr["headRefOid"] if pr else None

    worktrees = parse_worktrees(repository)
    primary = Path(worktrees[0]["worktree"]).resolve()
    checked_out: set[str] = set()
    worktree_plan: list[dict[str, object]] = []
    skipped: list[str] = []

    for entry in worktrees:
        path = Path(entry["worktree"])
        branch = entry.get("branch", "").removeprefix("refs/heads/")
        head = entry["head"]
        if path.resolve() == primary:
            if branch:
                checked_out.add(branch)
            continue
        if branch:
            checked_out.add(branch)

        merged_into = [ref for ref in integrations if is_ancestor(repository, head, ref)]
        merged = bool(merged_into) or (pr_branch is not None and branch == pr_branch)
        if not merged:
            skipped.append(f"unmerged {branch or '(detached)'} {path}")
            continue

        changes = status_lines(path)
        if changes and not arguments.force:
            skipped.append(f"local changes in {branch or '(detached)'} {path}")
            continue

        reason = (
            f"head of merged PR #{arguments.pr}"
            if pr_branch is not None and branch == pr_branch
            else f"merged into {merged_into[0]}"
            if merged_into
            else "merged"
        )
        worktree_plan.append(
            {
                "path": path,
                "branch": branch,
                "head": head,
                "reason": reason,
                "dirty": bool(changes),
                "archive": bool(changes) and arguments.force,
            }
        )

    branch_plan: list[dict[str, str]] = []
    remaining_checked_out = {entry["branch"] for entry in worktree_plan if entry["branch"]}
    for branch in local_branches(repository):
        if branch in checked_out and branch not in remaining_checked_out:
            continue
        tip = git_text("rev-parse", branch, cwd=repository)
        merged_into = [ref for ref in integrations if is_ancestor(repository, tip, ref)]
        if pr_branch is not None and branch == pr_branch:
            behind_pr_head = pr_head is not None and is_ancestor(repository, tip, pr_head)
            if pr_head is not None and tip != pr_head and behind_pr_head is False and arguments.force is False:
                skipped.append(f"branch {branch} is not at the merged PR head {pr_head}")
                continue
            branch_plan.append({"branch": branch, "head": tip, "force": True, "reason": "merged PR"})
            continue
        if merged_into:
            branch_plan.append(
                {"branch": branch, "head": tip, "force": False, "reason": f"merged into {merged_into[0]}"}
            )

    print(f"repository: {repository}")
    print(f"integrations: {', '.join(integrations)}")
    if arguments.apply is False:
        print("mode: dry run (pass --apply to execute)")
    else:
        print(f"mode: apply; archive: {archive_root}")

    for item in worktree_plan:
        action = "remove worktree"
        if item["dirty"]:
            action += " and discard local changes"
            if item["archive"]:
                action += f" after archiving {archive_root}"
        print(f"PLAN {action}: {item['path']} [{item['branch'] or '(detached)'}] ({item['reason']})")
    for item in branch_plan:
        deletion = "-D" if item["force"] else "-d"
        print(f"PLAN delete branch {deletion}: {item['branch']} ({item['reason']})")
    for line in skipped:
        print(f"SKIP {line}")
    if not worktree_plan and not branch_plan:
        print("nothing to reclaim")

    if arguments.apply is False:
        return 0

    for item in worktree_plan:
        path: Path = item["path"]
        if item["archive"]:
            archive_root.mkdir(parents=True, exist_ok=True)
            archived = archive_worktree(archive_root, path)
            print(f"archived {path} -> {archived}")
        removed = git("worktree", "remove", "--force", str(path), cwd=repository)
        if removed.returncode != 0:
            raise SystemExit(f"git worktree remove {path} failed: {removed.stderr.strip()}")
        print(f"removed worktree {path}")

    for item in branch_plan:
        deletion = "-D" if item["force"] else "-d"
        removed = git("branch", deletion, item["branch"], cwd=repository)
        if removed.returncode != 0:
            raise SystemExit(f"git branch {deletion} {item['branch']} failed: {removed.stderr.strip()}")
        print(f"deleted branch {item['branch']}")

    prune = git("worktree", "prune", cwd=repository)
    if prune.returncode != 0:
        raise SystemExit(f"git worktree prune failed: {prune.stderr.strip()}")
    if arguments.repair_origin_head:
        repaired = git("remote", "set-head", "origin", "-a", cwd=repository)
        if repaired.returncode != 0:
            raise SystemExit(f"git remote set-head failed: {repaired.stderr.strip()}")
        print("repaired origin/HEAD")

    remaining = [entry for entry in parse_worktrees(repository) if Path(entry["worktree"]).resolve() != primary]
    print(f"remaining linked worktrees: {len(remaining)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
