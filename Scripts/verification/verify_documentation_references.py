#!/usr/bin/env python3

"""Checks that what an agent is told to read or run actually exists.

Documents split into two populations. Instructions carry paths an agent is
expected to follow, so a path that no longer resolves sends the reader
somewhere empty; those failures are errors. History records what was true when
it was written, so its dead paths are reported and not enforced.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import subprocess
import sys

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]

INSTRUCTION_ROOTS = (
    "AGENTS.md",
    "ARCHITECTURE.md",
    "docs/CONTEXT.md",
    "docs/MERGE_EVIDENCE.md",
    ".agents/skills",
    ".cursor/rules",
    ".github",
    "Config",
    "Scripts",
)

HISTORY_ROOTS = ("docs/archive",)

# This check and its test quote dead paths as data. They define the rule
# rather than instructing anyone, so scanning them only finds the examples.
SELF = ("Scripts/verification/verify_documentation_references.py",
        "Scripts/verification/test_verify_documentation_references.py")

RETIRED_ARTIFACT_ROOT = "/Volumes/Cortisol/DevSpace/Xcode/Enchron"
RETIRED_DOCUMENTS_PATH = REPOSITORY_ROOT / "Config/retired_documents.json"

TOP_LEVEL_SEGMENTS = frozenset(
    entry.name for entry in REPOSITORY_ROOT.iterdir() if not entry.name.startswith(".git/")
) | {".agents", ".claude", ".github", ".githooks", ".audit", ".cursor"}

MARKDOWN_LINK = re.compile(r"\[[^\]]*\]\(([^)\s]+)\)")
BACKTICKED = re.compile(r"`([^`\s]+)`")
ABSOLUTE_VOLUME_PATH = re.compile(r"/Volumes/[^\s`\"'),;]+")
LINE_LOCATOR = re.compile(r":[\d,\-–、\s]*$")


def retired_documents() -> dict[str, str]:
    record = json.loads(RETIRED_DOCUMENTS_PATH.read_text(encoding="utf-8"))
    return {entry["path"]: entry["replacement"] for entry in record["retired"]}


def tracked_text_files() -> list[Path]:
    listing = subprocess.run(
        ["git", "-C", str(REPOSITORY_ROOT), "ls-files", "-z"],
        capture_output=True,
        text=True,
        check=True,
    )
    suffixes = {".md", ".mdc", ".json", ".py", ".sh", ".zsh", ".yml", ".yaml", ".swift", ".toml"}
    return [
        REPOSITORY_ROOT / name
        for name in listing.stdout.split("\0")
        if name and Path(name).suffix in suffixes
    ]


def population(path: Path) -> str | None:
    relative = path.relative_to(REPOSITORY_ROOT).as_posix()
    if relative in SELF:
        return None
    if any(relative == root or relative.startswith(root + "/") for root in HISTORY_ROOTS):
        return "history"
    if any(relative == root or relative.startswith(root + "/") for root in INSTRUCTION_ROOTS):
        return "instruction"
    return None


def strip_locator(candidate: str) -> str:
    without_anchor = candidate.split("#", 1)[0]
    without_lines = LINE_LOCATOR.sub("", without_anchor)
    return without_lines.rstrip(".,;、）)：:").strip()


def repository_candidates(text: str, document: Path) -> set[str]:
    found: set[str] = set()
    for match in list(MARKDOWN_LINK.finditer(text)) + list(BACKTICKED.finditer(text)):
        candidate = strip_locator(match.group(1))
        if not candidate or candidate.startswith(("http", "mailto:", "/")):
            continue
        if "*" in candidate or "<" in candidate or "{" in candidate:
            continue
        if candidate.startswith(("./", "../")):
            resolved = (document.parent / candidate).resolve()
            if REPOSITORY_ROOT in resolved.parents:
                found.add(resolved.relative_to(REPOSITORY_ROOT).as_posix())
        elif candidate.split("/", 1)[0] in TOP_LEVEL_SEGMENTS and "/" in candidate:
            found.add(candidate)
    return found


def absolute_candidates(text: str) -> set[str]:
    return {
        strip_locator(match.group(0))
        for match in ABSOLUTE_VOLUME_PATH.finditer(text)
        if not any(character in match.group(0) for character in "*<[\\")
    }


def unresolved_references() -> tuple[list[str], list[str]]:
    errors: list[str] = []
    notes: list[str] = []
    retired = retired_documents()
    for document in tracked_text_files():
        group = population(document)
        if group is None:
            continue
        text = document.read_text(encoding="utf-8", errors="ignore")
        relative = document.relative_to(REPOSITORY_ROOT).as_posix()
        sink = errors if group == "instruction" else notes
        for candidate in sorted(repository_candidates(text, document)):
            if (REPOSITORY_ROOT / candidate).exists():
                continue
            # .scratch holds what a check regenerates, so an absent path there
            # means nobody has run the generator yet, not that the doc is stale.
            if candidate == ".scratch" or candidate.startswith(".scratch/"):
                continue
            for retired_path in (candidate, candidate + "/"):
                if retired_path in retired:
                    notes.append(f"{relative}: {candidate} retired, now {retired[retired_path]}")
                    break
            else:
                sink.append(f"{relative}: {candidate} does not exist")
        for candidate in sorted(absolute_candidates(text)):
            if candidate.startswith(RETIRED_ARTIFACT_ROOT):
                sink.append(f"{relative}: {candidate} is the retired artifact root")
            elif not Path(candidate).exists():
                sink.append(f"{relative}: {candidate} does not exist")
    return errors, notes


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--show-history", action="store_true")
    arguments = parser.parse_args()

    errors, notes = unresolved_references()

    if arguments.show_history:
        for note in notes:
            print(f"history {note}")
    for failure in errors:
        print(f"FAIL {failure}")

    print(f"\n{len(errors)} failures, {len(notes)} unenforced history references")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
