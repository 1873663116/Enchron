#!/usr/bin/env python3

"""Checks that what an agent is told to read or run actually exists.

Documents split into two populations. Instructions carry paths an agent is
expected to follow, so a path that no longer resolves sends the reader
somewhere empty; those failures are errors, including a path the retired
registry can name a replacement for, because an instruction is maintained now
and has no reason to keep the old name. History records what was true when it
was written, so its dead paths are reported and not enforced.
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
    "docs/BROWSING_AND_SOURCES_CONSTRAINTS.md",
    "docs/DESIGN_SYSTEM_CONSTRAINTS.md",
    "docs/PLAYBACK_ENGINE_CONSTRAINTS.md",
    "docs/PLAYBACK_PRESENTATION_CONSTRAINTS.md",
    "docs/UI_TEST_HARNESS_CONSTRAINTS.md",
    ".agents/skills",
    ".cursor/rules",
    ".github",
    "Config",
    "Regression",
    "Scripts",
)

HISTORY_ROOTS = ("docs/archive",)

DIGEST_BOUND_EVIDENCE_ROOTS = ("Regression/reviews",)

SELF = ("Scripts/rules/verify_documentation_references.py",
        "Scripts/rules/tests/test_verify_documentation_references.py")

GENERATOR_OUTPUT_ROOT = ".scratch"
RETIRED_ARTIFACT_ROOT = "/Volumes/Cortisol/DevSpace/Xcode/Enchron"
RETIRED_DOCUMENTS_PATH = REPOSITORY_ROOT / "Config/retired_documents.json"
CATALOG_SOURCE_ROOT = "Config/regression/catalog-root"
CATALOG_MATERIALIZED_ROOT = "Regression"

TOP_LEVEL_SEGMENTS = frozenset(
    entry.name
    for entry in REPOSITORY_ROOT.iterdir()
    if entry.name not in {".git", ".scratch", "DerivedData"}
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
        [
            "git",
            "-C",
            str(REPOSITORY_ROOT),
            "ls-files",
            "--cached",
            "--others",
            "--exclude-standard",
            "-z",
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    suffixes = {".md", ".mdc", ".json", ".py", ".sh", ".zsh", ".yml", ".yaml", ".swift", ".toml"}
    excluded_directories = {".git", ".scratch", "DerivedData"}
    repository_paths = (Path(name) for name in listing.stdout.split("\0") if name)
    files = (
        REPOSITORY_ROOT / path
        for path in repository_paths
        if path.suffix in suffixes and not excluded_directories.intersection(path.parts)
    )
    return sorted(path for path in files if path.is_file())


def quotes_dead_paths_as_examples(relative: str) -> bool:
    return relative in SELF


def population(path: Path) -> str | None:
    relative = path.relative_to(REPOSITORY_ROOT).as_posix()
    if quotes_dead_paths_as_examples(relative):
        return None
    if any(
        relative == root or relative.startswith(root + "/")
        for root in DIGEST_BOUND_EVIDENCE_ROOTS
    ):
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


def materialized_document(document: Path) -> Path:
    """Return where a source-catalog document's links are consumed."""
    source_root = REPOSITORY_ROOT / CATALOG_SOURCE_ROOT
    try:
        relative = document.relative_to(source_root)
    except ValueError:
        return document
    return REPOSITORY_ROOT / CATALOG_MATERIALIZED_ROOT / relative


def repository_candidates(text: str, document: Path) -> set[str]:
    found: set[str] = set()

    def add(candidate: str, implicit_relative: bool) -> None:
        candidate = strip_locator(candidate)
        if not candidate or candidate.startswith(("http", "mailto:", "/")):
            return
        if "*" in candidate or "<" in candidate or "{" in candidate:
            return
        if candidate.split("/", 1)[0] in TOP_LEVEL_SEGMENTS and "/" in candidate:
            found.add(candidate)
            return
        if not implicit_relative and not candidate.startswith(("./", "../")):
            return
        resolved = (document.parent / candidate).resolve()
        if REPOSITORY_ROOT in resolved.parents:
            found.add(resolved.relative_to(REPOSITORY_ROOT).as_posix())

    markdown_document = document.suffix.lower() in {".md", ".mdc"}
    for match in MARKDOWN_LINK.finditer(text):
        add(match.group(1), implicit_relative=markdown_document)
    for match in BACKTICKED.finditer(text):
        add(match.group(1), implicit_relative=False)
    return found


def absolute_candidates(text: str) -> set[str]:
    return {
        strip_locator(match.group(0))
        for match in ABSOLUTE_VOLUME_PATH.finditer(text)
        if not any(character in match.group(0) for character in "*<[\\")
    }


def is_generated_build_output(candidate: str) -> bool:
    try:
        Path(candidate).relative_to(REPOSITORY_ROOT / ".build")
    except ValueError:
        return False
    return True


def retired_replacement(candidate: str, retired: dict[str, str]) -> str | None:
    for retired_path in sorted(retired, key=len, reverse=True):
        if candidate == retired_path.rstrip("/"):
            return retired[retired_path]
        if retired_path.endswith("/") and candidate.startswith(retired_path):
            return retired[retired_path]
    return None


def is_unrun_generator_output(candidate: str) -> bool:
    return candidate == GENERATOR_OUTPUT_ROOT or candidate.startswith(
        GENERATOR_OUTPUT_ROOT + "/"
    )


def is_provisioned_per_machine(candidate: str) -> bool:
    completed = subprocess.run(
        ["git", "-C", str(REPOSITORY_ROOT), "check-ignore", "--quiet", "--", candidate],
        capture_output=True,
    )
    return completed.returncode == 0


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
        resolution_document = materialized_document(document)
        for candidate in sorted(repository_candidates(text, resolution_document)):
            if (REPOSITORY_ROOT / candidate).exists():
                continue
            if is_unrun_generator_output(candidate):
                continue
            if is_provisioned_per_machine(candidate):
                continue
            replacement = retired_replacement(candidate, retired)
            if replacement is None:
                sink.append(f"{relative}: {candidate} does not exist")
            else:
                sink.append(f"{relative}: {candidate} retired, now {replacement}")
        for candidate in sorted(absolute_candidates(text)):
            if candidate.startswith(RETIRED_ARTIFACT_ROOT):
                sink.append(f"{relative}: {candidate} is the retired artifact root")
            elif is_generated_build_output(candidate):
                continue
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
