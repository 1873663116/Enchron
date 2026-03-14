#!/usr/bin/env python3
"""Bidirectional sync for project docs and Obsidian project notes.

The script is intentionally conservative:
- default mode is dry-run
- identical files are skipped
- missing files are copied to the other side
- conflicting edits are resolved by deterministic heuristics first
- unresolved conflicts can optionally be delegated to a headless model

Examples:
  python3 scripts/sync_workspace_agents.py
  python3 scripts/sync_workspace_agents.py --apply
  python3 scripts/sync_workspace_agents.py --apply --resolver gemini
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT_DEFAULT = SCRIPT_DIR.parent
OBSIDIAN_PROJECTS_BASE = Path(
    "/Users/xiongzhipeng/Library/Mobile Documents/iCloud~md~obsidian/Documents/"
    "my_obsidian_vault/项目"
)

WORKSPACE_AGENTS_DIRNAME = "workspace-agents"
ROOT_DOCS = {
    "AGENTS.md",
    "ARCHITECTURE.md",
    "PLANS.md",
    "TESTING.md",
    "QUALITY_SCORE.md",
    "REGRESSION.md",
}

IGNORE_DIR_NAMES = {
    ".git",
    ".gitignore",
    ".DS_Store",
    ".obsidian",
    ".trash",
    "__pycache__",
}

MTIME_MARGIN_SECONDS = 5


@dataclass(frozen=True)
class FileInfo:
    rel_path: str
    abs_path: Path
    size: int
    mtime_ns: int
    sha256: str


@dataclass(frozen=True)
class GitFacts:
    repo_root: Path | None
    tracked: bool
    dirty: bool
    last_commit_ts: int | None


@dataclass(frozen=True)
class SideFacts:
    name: str
    file: FileInfo | None
    git: GitFacts


@dataclass(frozen=True)
class Action:
    kind: str
    rel_path: str
    source: str | None
    destination: str | None
    reason: str
    details: dict[str, object]


class GitInspector:
    def __init__(self, root: Path) -> None:
        self.root = root
        self.repo_root = self._repo_root(root)
        self.root_repo_relative = (
            os.path.relpath(root, self.repo_root) if self.repo_root is not None else None
        )
        self._tracked_cache: set[str] | None = None
        self._dirty_cache: dict[str, str] | None = None
        self._commit_cache: dict[str, int | None] = {}

    def facts_for(self, rel_path: str) -> GitFacts:
        if self.repo_root is None or self.root_repo_relative is None:
            return GitFacts(repo_root=None, tracked=False, dirty=False, last_commit_ts=None)

        repo_path = self._repo_relative(rel_path)
        tracked = repo_path in self._tracked_files()
        dirty = repo_path in self._dirty_statuses()
        last_commit_ts = self._last_commit_ts(repo_path) if tracked else None
        return GitFacts(
            repo_root=self.repo_root,
            tracked=tracked,
            dirty=dirty,
            last_commit_ts=last_commit_ts,
        )

    def _repo_relative(self, rel_path: str) -> str:
        if self.root_repo_relative in (".", ""):
            return rel_path
        return str(Path(self.root_repo_relative) / rel_path)

    @staticmethod
    def _repo_root(root: Path) -> Path | None:
        result = subprocess.run(
            ["git", "-C", str(root), "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            return None
        stdout = result.stdout.strip()
        return Path(stdout) if stdout else None

    def _tracked_files(self) -> set[str]:
        if self._tracked_cache is not None:
            return self._tracked_cache

        result = subprocess.run(
            ["git", "-C", str(self.root), "ls-files", "-z", "--", "."],
            capture_output=True,
            check=False,
        )
        tracked = set()
        if result.returncode == 0 and result.stdout:
            for item in result.stdout.decode("utf-8", errors="ignore").split("\0"):
                if item:
                    tracked.add(item)
        self._tracked_cache = tracked
        return tracked

    def _dirty_statuses(self) -> dict[str, str]:
        if self._dirty_cache is not None:
            return self._dirty_cache

        result = subprocess.run(
            [
                "git",
                "-C",
                str(self.root),
                "status",
                "--porcelain=v1",
                "-z",
                "--untracked-files=all",
                "--",
                ".",
            ],
            capture_output=True,
            check=False,
        )
        statuses: dict[str, str] = {}
        if result.returncode == 0 and result.stdout:
            payload = result.stdout.decode("utf-8", errors="ignore")
            for entry in payload.split("\0"):
                if not entry:
                    continue
                status = entry[:2]
                path = entry[3:]
                if path:
                    statuses[path] = status
        self._dirty_cache = statuses
        return statuses

    def _last_commit_ts(self, repo_relative_path: str) -> int | None:
        if repo_relative_path in self._commit_cache:
            return self._commit_cache[repo_relative_path]

        result = subprocess.run(
            [
                "git",
                "-C",
                str(self.root),
                "log",
                "-1",
                "--format=%ct",
                "--",
                repo_relative_path,
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        value: int | None = None
        if result.returncode == 0:
            stdout = result.stdout.strip()
            if stdout:
                value = int(stdout)
        self._commit_cache[repo_relative_path] = value
        return value


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Sync a project's docs with its Obsidian mirror."
    )
    parser.add_argument(
        "--project-root",
        type=Path,
        default=PROJECT_ROOT_DEFAULT,
        help="Local project root containing workspace-agents and root markdown docs.",
    )
    parser.add_argument(
        "--project-name",
        default=PROJECT_ROOT_DEFAULT.name,
        help="Project folder name under the Obsidian 项目 directory.",
    )
    parser.add_argument(
        "--remote-base",
        type=Path,
        default=OBSIDIAN_PROJECTS_BASE,
        help="Obsidian 项目 base directory. The script appends --project-name.",
    )
    parser.add_argument(
        "--remote-root",
        type=Path,
        default=None,
        help="Explicit remote root. Overrides --remote-base and --project-name.",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Apply planned copies. Without this flag the script only prints a plan.",
    )
    parser.add_argument(
        "--resolver",
        choices=["none", "codex", "gemini"],
        default="gemini",
        help="Resolver used for ambiguous conflicts.",
    )
    parser.add_argument(
        "--resolver-model",
        default="gemini-3-flash",
        help="Model name passed to the selected headless resolver.",
    )
    parser.add_argument(
        "--codex-bin",
        default="codex",
        help="Codex CLI binary for --resolver codex.",
    )
    parser.add_argument(
        "--gemini-bin",
        default="gemini",
        help="Gemini CLI binary for --resolver gemini.",
    )
    parser.add_argument(
        "--mtime-margin-seconds",
        type=int,
        default=MTIME_MARGIN_SECONDS,
        help="Minimum mtime gap required before time alone decides a conflict.",
    )
    parser.add_argument(
        "--output-format",
        choices=["text", "json"],
        default="text",
        help="Output format for the final plan/result.",
    )
    return parser.parse_args()


def resolve_remote_root(args: argparse.Namespace) -> Path:
    if args.remote_root is not None:
        return args.remote_root.expanduser().resolve()
    return (args.remote_base.expanduser().resolve() / args.project_name).resolve()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def build_file_info(rel_path: str, abs_path: Path) -> FileInfo:
    stat = abs_path.stat()
    return FileInfo(
        rel_path=rel_path,
        abs_path=abs_path,
        size=stat.st_size,
        mtime_ns=stat.st_mtime_ns,
        sha256=sha256_file(abs_path),
    )


def collect_workspace_agents_files(project_root: Path) -> dict[str, FileInfo]:
    workspace_root = project_root / WORKSPACE_AGENTS_DIRNAME
    if not workspace_root.exists():
        return {}

    files: dict[str, FileInfo] = {}
    for current_root, dir_names, file_names in os.walk(workspace_root):
        dir_names[:] = sorted(d for d in dir_names if d not in IGNORE_DIR_NAMES)
        for file_name in sorted(file_names):
            if file_name in IGNORE_DIR_NAMES:
                continue
            abs_path = Path(current_root) / file_name
            rel_path = abs_path.relative_to(workspace_root).as_posix()
            files[rel_path] = build_file_info(rel_path, abs_path)
    return files


def collect_root_docs(project_root: Path) -> dict[str, FileInfo]:
    files: dict[str, FileInfo] = {}
    for doc_name in sorted(ROOT_DOCS):
        abs_path = project_root / doc_name
        if not abs_path.exists() or not abs_path.is_file():
            continue
        files[doc_name] = build_file_info(doc_name, abs_path)
    return files


def collect_local_files(project_root: Path) -> dict[str, FileInfo]:
    files = collect_workspace_agents_files(project_root)
    files.update(collect_root_docs(project_root))
    return files


def collect_remote_files(remote_root: Path) -> dict[str, FileInfo]:
    if not remote_root.exists():
        return {}

    files: dict[str, FileInfo] = {}
    for current_root, dir_names, file_names in os.walk(remote_root):
        dir_names[:] = sorted(d for d in dir_names if d not in IGNORE_DIR_NAMES)
        for file_name in sorted(file_names):
            if file_name in IGNORE_DIR_NAMES:
                continue
            abs_path = Path(current_root) / file_name
            rel_path = abs_path.relative_to(remote_root).as_posix()
            files[rel_path] = build_file_info(rel_path, abs_path)
    return files


def ns_to_seconds(value: int | None) -> float | None:
    if value is None:
        return None
    return value / 1_000_000_000


def summarize_side(side: SideFacts) -> dict[str, object]:
    file_info = side.file
    return {
        "exists": file_info is not None,
        "path": str(file_info.abs_path) if file_info else None,
        "size": file_info.size if file_info else None,
        "mtime_ns": file_info.mtime_ns if file_info else None,
        "mtime_seconds": ns_to_seconds(file_info.mtime_ns) if file_info else None,
        "sha256": file_info.sha256 if file_info else None,
        "git_tracked": side.git.tracked,
        "git_dirty": side.git.dirty,
        "git_last_commit_ts": side.git.last_commit_ts,
    }


def compare_file(
    rel_path: str,
    local: SideFacts,
    remote: SideFacts,
    mtime_margin_seconds: int,
) -> Action:
    if local.file is None and remote.file is None:
        raise ValueError(f"Expected at least one side for {rel_path}")

    if local.file is None:
        return Action(
            kind="copy",
            rel_path=rel_path,
            source="remote",
            destination="local",
            reason="missing on local side",
            details={"local": summarize_side(local), "remote": summarize_side(remote)},
        )

    if remote.file is None:
        return Action(
            kind="copy",
            rel_path=rel_path,
            source="local",
            destination="remote",
            reason="missing on remote side",
            details={"local": summarize_side(local), "remote": summarize_side(remote)},
        )

    if local.file.sha256 == remote.file.sha256:
        return Action(
            kind="noop",
            rel_path=rel_path,
            source=None,
            destination=None,
            reason="identical content",
            details={"local": summarize_side(local), "remote": summarize_side(remote)},
        )

    mtime_margin_ns = mtime_margin_seconds * 1_000_000_000
    local_mtime = local.file.mtime_ns
    remote_mtime = remote.file.mtime_ns
    mtime_gap = abs(local_mtime - remote_mtime)

    if local.git.dirty and not remote.git.dirty:
        return Action(
            kind="copy",
            rel_path=rel_path,
            source="local",
            destination="remote",
            reason="local has uncommitted changes",
            details={"local": summarize_side(local), "remote": summarize_side(remote)},
        )

    if remote.git.dirty and not local.git.dirty:
        return Action(
            kind="copy",
            rel_path=rel_path,
            source="remote",
            destination="local",
            reason="remote has uncommitted changes",
            details={"local": summarize_side(local), "remote": summarize_side(remote)},
        )

    if local.git.last_commit_ts and remote.git.last_commit_ts:
        if local.git.last_commit_ts != remote.git.last_commit_ts:
            if local.git.last_commit_ts > remote.git.last_commit_ts and local_mtime >= remote_mtime:
                return Action(
                    kind="copy",
                    rel_path=rel_path,
                    source="local",
                    destination="remote",
                    reason="local has newer git commit evidence",
                    details={"local": summarize_side(local), "remote": summarize_side(remote)},
                )
            if remote.git.last_commit_ts > local.git.last_commit_ts and remote_mtime >= local_mtime:
                return Action(
                    kind="copy",
                    rel_path=rel_path,
                    source="remote",
                    destination="local",
                    reason="remote has newer git commit evidence",
                    details={"local": summarize_side(local), "remote": summarize_side(remote)},
                )

    if mtime_gap >= mtime_margin_ns:
        newer_side = "local" if local_mtime > remote_mtime else "remote"
        older_side = "remote" if newer_side == "local" else "local"
        return Action(
            kind="copy",
            rel_path=rel_path,
            source=newer_side,
            destination=older_side,
            reason=f"{newer_side} mtime is newer by at least {mtime_margin_seconds}s",
            details={"local": summarize_side(local), "remote": summarize_side(remote)},
        )

    return Action(
        kind="conflict",
        rel_path=rel_path,
        source=None,
        destination=None,
        reason="evidence is mixed or too close to call",
        details={"local": summarize_side(local), "remote": summarize_side(remote)},
    )


def build_prompt(rel_path: str, action: Action) -> str:
    local = action.details["local"]
    remote = action.details["remote"]
    return f"""Resolve a bidirectional file sync conflict.

Return strict JSON only with this shape:
{{
  "winner": "local" | "remote" | "manual",
  "reason": "short string"
}}

Rules:
- Prefer the side that is more likely to contain the newest intentional content.
- Consider git dirty state stronger than commit timestamps.
- Consider commit timestamps stronger than filesystem mtime.
- If evidence is still ambiguous, return "manual".
- Keep the reason under 20 words.

Relative path: {rel_path}

Local facts:
{json.dumps(local, ensure_ascii=False, indent=2)}

Remote facts:
{json.dumps(remote, ensure_ascii=False, indent=2)}
"""


def resolver_result_to_action(
    rel_path: str,
    action: Action,
    winner: str,
    reason: str,
    resolver_name: str,
) -> Action:
    if winner == "manual":
        return Action(
            kind="conflict",
            rel_path=rel_path,
            source=None,
            destination=None,
            reason=f"{resolver_name} requested manual review: {reason}",
            details=action.details,
        )

    return Action(
        kind="copy",
        rel_path=rel_path,
        source=winner,
        destination="remote" if winner == "local" else "local",
        reason=f"{resolver_name} chose {winner}: {reason}",
        details=action.details,
    )


def resolve_with_codex(
    rel_path: str,
    action: Action,
    args: argparse.Namespace,
    working_root: Path,
) -> Action:
    schema = {
        "type": "object",
        "additionalProperties": False,
        "required": ["winner", "reason"],
        "properties": {
            "winner": {"type": "string", "enum": ["local", "remote", "manual"]},
            "reason": {"type": "string"},
        },
    }
    prompt = build_prompt(rel_path, action)

    with tempfile.TemporaryDirectory(prefix="sync-workspace-agents-") as temp_dir:
        schema_path = Path(temp_dir) / "schema.json"
        output_path = Path(temp_dir) / "result.json"
        schema_path.write_text(json.dumps(schema), encoding="utf-8")

        command = [
            args.codex_bin,
            "exec",
            "-C",
            str(working_root),
            "-m",
            args.resolver_model,
            "-s",
            "read-only",
            "-a",
            "never",
            "--output-schema",
            str(schema_path),
            "-o",
            str(output_path),
            "-",
        ]
        result = subprocess.run(
            command,
            input=prompt,
            text=True,
            capture_output=True,
            check=False,
        )

        if result.returncode != 0:
            return Action(
                kind="conflict",
                rel_path=rel_path,
                source=None,
                destination=None,
                reason=f"codex resolver failed: {result.stderr.strip() or result.stdout.strip()}",
                details=action.details,
            )

        try:
            payload = json.loads(output_path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, FileNotFoundError) as exc:
            return Action(
                kind="conflict",
                rel_path=rel_path,
                source=None,
                destination=None,
                reason=f"codex resolver returned invalid JSON: {exc}",
                details=action.details,
            )

    return resolver_result_to_action(
        rel_path=rel_path,
        action=action,
        winner=payload["winner"],
        reason=payload["reason"],
        resolver_name="codex resolver",
    )


def strip_json_fences(text: str) -> str:
    stripped = text.strip()
    if stripped.startswith("```"):
        lines = stripped.splitlines()
        if len(lines) >= 3:
            stripped = "\n".join(lines[1:-1]).strip()
    return stripped


def parse_gemini_payload(stdout: str) -> dict[str, str]:
    envelope = json.loads(stdout)
    response_text = envelope["response"] if isinstance(envelope, dict) else envelope
    if not isinstance(response_text, str):
        raise json.JSONDecodeError("Gemini response is not a JSON string", stdout, 0)
    return json.loads(strip_json_fences(response_text))


def resolve_with_gemini(
    rel_path: str,
    action: Action,
    args: argparse.Namespace,
    working_root: Path,
) -> Action:
    prompt = build_prompt(rel_path, action)
    command = [
        args.gemini_bin,
        "-m",
        args.resolver_model,
        "-p",
        prompt,
        "--approval-mode",
        "plan",
        "--sandbox",
        "--output-format",
        "json",
        "--include-directories",
        str(working_root),
    ]
    result = subprocess.run(
        command,
        text=True,
        capture_output=True,
        check=False,
    )

    if result.returncode != 0:
        return Action(
            kind="conflict",
            rel_path=rel_path,
            source=None,
            destination=None,
            reason=f"gemini resolver failed: {result.stderr.strip() or result.stdout.strip()}",
            details=action.details,
        )

    try:
        payload = parse_gemini_payload(result.stdout)
    except (json.JSONDecodeError, KeyError) as exc:
        return Action(
            kind="conflict",
            rel_path=rel_path,
            source=None,
            destination=None,
            reason=f"gemini resolver returned invalid JSON: {exc}",
            details=action.details,
        )

    winner = payload.get("winner")
    reason = payload.get("reason")
    if winner not in {"local", "remote", "manual"} or not isinstance(reason, str):
        return Action(
            kind="conflict",
            rel_path=rel_path,
            source=None,
            destination=None,
            reason="gemini resolver returned an unexpected schema",
            details=action.details,
        )

    return resolver_result_to_action(
        rel_path=rel_path,
        action=action,
        winner=winner,
        reason=reason,
        resolver_name="gemini resolver",
    )


def maybe_resolve_conflicts(
    actions: list[Action], args: argparse.Namespace, working_root: Path
) -> list[Action]:
    if args.resolver == "none":
        return actions

    resolved: list[Action] = []
    for action in actions:
        if action.kind != "conflict":
            resolved.append(action)
            continue
        if args.resolver == "codex":
            resolved.append(resolve_with_codex(action.rel_path, action, args, working_root))
            continue
        if args.resolver == "gemini":
            resolved.append(resolve_with_gemini(action.rel_path, action, args, working_root))
            continue
        resolved.append(action)
    return resolved


def resolve_local_destination(project_root: Path, rel_path: str) -> Path:
    if rel_path in ROOT_DOCS:
        return project_root / rel_path
    return project_root / WORKSPACE_AGENTS_DIRNAME / rel_path


def apply_copy(action: Action, project_root: Path, remote_root: Path) -> None:
    if action.source == "local":
        src = resolve_local_destination(project_root, action.rel_path)
        dst = remote_root / action.rel_path
    elif action.source == "remote":
        src = remote_root / action.rel_path
        dst = resolve_local_destination(project_root, action.rel_path)
    else:
        raise ValueError(f"Action {action.rel_path} has no source")

    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)


def action_to_dict(action: Action) -> dict[str, object]:
    return {
        "kind": action.kind,
        "rel_path": action.rel_path,
        "source": action.source,
        "destination": action.destination,
        "reason": action.reason,
        "details": action.details,
    }


def build_result(
    actions: list[Action],
    applied: bool,
    project_root: Path,
    remote_root: Path,
) -> dict[str, object]:
    counts = {"copy": 0, "conflict": 0, "noop": 0}
    for action in actions:
        counts[action.kind] += 1
    return {
        "mode": "apply" if applied else "dry-run",
        "project_root": str(project_root),
        "remote_root": str(remote_root),
        "summary": counts,
        "actions": [action_to_dict(action) for action in actions],
    }


def print_plan(actions: Iterable[Action]) -> None:
    for action in actions:
        if action.kind == "noop":
            continue
        if action.kind == "copy":
            print(
                f"[COPY] {action.source:>6} -> {action.destination:<6} "
                f"{action.rel_path} :: {action.reason}"
            )
            continue
        print(f"[CONFLICT] {action.rel_path} :: {action.reason}")


def print_summary(result: dict[str, object]) -> None:
    summary = result["summary"]
    print("")
    print(f"Remote root: {result['remote_root']}")
    print(
        f"Summary ({result['mode']}): copy={summary['copy']} "
        f"conflict={summary['conflict']} noop={summary['noop']}"
    )


def main() -> int:
    args = parse_args()
    project_root = args.project_root.expanduser().resolve()
    remote_root = resolve_remote_root(args)

    if not project_root.exists():
        print(f"Project root does not exist: {project_root}", file=sys.stderr)
        return 2

    workspace_root = project_root / WORKSPACE_AGENTS_DIRNAME
    if not workspace_root.exists():
        print(f"Workspace docs root does not exist: {workspace_root}", file=sys.stderr)
        return 2

    remote_root.mkdir(parents=True, exist_ok=True)

    local_files = collect_local_files(project_root)
    remote_files = collect_remote_files(remote_root)
    local_git = GitInspector(project_root)
    remote_git = GitInspector(remote_root)

    actions: list[Action] = []
    for rel_path in sorted(set(local_files) | set(remote_files)):
        local_side = SideFacts("local", local_files.get(rel_path), local_git.facts_for(rel_path))
        remote_side = SideFacts("remote", remote_files.get(rel_path), remote_git.facts_for(rel_path))
        actions.append(compare_file(rel_path, local_side, remote_side, args.mtime_margin_seconds))

    actions = maybe_resolve_conflicts(actions, args, project_root)
    if args.apply:
        for action in actions:
            if action.kind == "copy":
                apply_copy(action, project_root, remote_root)

    result = build_result(actions, args.apply, project_root, remote_root)
    if args.output_format == "json":
        json.dump(result, sys.stdout, ensure_ascii=False, indent=2)
        print("")
    else:
        print_plan(actions)
        print_summary(result)

    if any(action.kind == "conflict" for action in actions):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
