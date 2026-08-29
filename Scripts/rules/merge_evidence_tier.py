#!/usr/bin/env python3

from __future__ import annotations

import argparse
from dataclasses import dataclass
import json
from pathlib import Path
import subprocess
import sys

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
STANDARD_DOCUMENT = "docs/MERGE_EVIDENCE.md"
DEFAULT_RANGE = "@{upstream}..HEAD"

W0 = "W0"
W1 = "W1"
W2 = "W2"
W3 = "W3"
TIERS = (W0, W1, W2, W3)

VERIFICATION_GREEN = "verification-green"
SIMULATOR_E2E = "simulator-e2e"
DEVICE_HUB_INPUT = "device-hub-input"
REAL_DEVICE_DECODE = "real-device-decode"

TIER_EVIDENCE = {
    W0: (VERIFICATION_GREEN,),
    W1: (VERIFICATION_GREEN,),
    W2: (VERIFICATION_GREEN, SIMULATOR_E2E),
    W3: (VERIFICATION_GREEN, SIMULATOR_E2E, DEVICE_HUB_INPUT),
}

PATH_RULES = (
    ("docs/", W0),
    (".agents/skills/", W0),
    ("Regression/", W1),
    ("Scripts/", W1),
    ("Config/", W1),
    ("Tests/", W1),
    ("Packages/PlaybackCore/Tests/", W1),
    ("Modules/DesignSystem/", W2),
    ("Modules/Emby/", W2),
    ("Modules/MediaLibrary/", W2),
    ("Modules/MediaSource/", W2),
    ("Packages/PlaybackCore/", W3),
    ("Apps/Enchron/", W3),
    ("Modules/Playback/", W3),
    ("Packages/RealityKitContent/", W3),
)
UNCLASSIFIED_RULE = "unclassified"
UNCLASSIFIED_TIER = W3


def tier_rank(tier: str) -> int:
    return TIERS.index(tier)


@dataclass(frozen=True)
class Classification:
    path: str
    tier: str
    rule: str


@dataclass(frozen=True)
class Verdict:
    range_expression: str
    classifications: tuple[Classification, ...]
    tier: str | None
    reason: str


def classify_path(path: str) -> Classification:
    matches = [
        (prefix, tier) for prefix, tier in PATH_RULES if path.startswith(prefix)
    ]
    if not matches:
        return Classification(path, UNCLASSIFIED_TIER, UNCLASSIFIED_RULE)
    prefix, tier = max(matches, key=lambda match: len(match[0]))
    return Classification(path, tier, prefix)


def build_verdict(range_expression: str, paths: list[str]) -> Verdict:
    classifications = tuple(classify_path(path) for path in sorted(set(paths)))
    if not classifications:
        return Verdict(
            range_expression,
            (),
            None,
            "empty range: no committed changes to classify",
        )
    tier = TIERS[max(tier_rank(entry.tier) for entry in classifications)]
    return Verdict(range_expression, classifications, tier, "")


def unresolved_verdict(range_expression: str, detail: str) -> Verdict:
    return Verdict(
        range_expression,
        (),
        UNCLASSIFIED_TIER,
        f"range unresolved ({detail}); evidence strength raised to {UNCLASSIFIED_TIER}",
    )


def changed_paths(repository: Path, range_expression: str) -> list[str]:
    completed = subprocess.run(
        ["git", "-C", str(repository), "diff", "--name-only", "-z", range_expression],
        capture_output=True,
        text=True,
        check=True,
    )
    return [path for path in completed.stdout.split("\0") if path]


def render(verdict: Verdict) -> list[str]:
    lines = [f"merge evidence tier: {verdict.range_expression}"]
    for entry in verdict.classifications:
        lines.append(f"  {entry.tier} {entry.path} [{entry.rule}]")
    if verdict.reason:
        lines.append(verdict.reason)
    if verdict.tier is not None:
        lines.append(f"tier: {verdict.tier}")
        lines.append("required evidence:")
        lines.extend(f"  - {kind}" for kind in TIER_EVIDENCE[verdict.tier])
        if verdict.tier == W3:
            lines.append(
                f"  - {REAL_DEVICE_DECODE} may replace simulator and device-hub "
                "evidence only for decode-capability changes"
            )
    lines.append("merge authority: not decided by evidence Tier")
    lines.append(f"standard: {STANDARD_DOCUMENT}")
    return lines


def verdict_payload(verdict: Verdict) -> dict[str, object]:
    return {
        "schema": "enchron.merge-evidence-classification/v2",
        "range": verdict.range_expression,
        "tier": verdict.tier,
        "requiredEvidence": (
            list(TIER_EVIDENCE[verdict.tier]) if verdict.tier else []
        ),
        "reason": verdict.reason,
        "paths": [
            {"path": entry.path, "tier": entry.tier, "rule": entry.rule}
            for entry in verdict.classifications
        ],
        "standard": STANDARD_DOCUMENT,
    }


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Classify a commit range by required evidence strength. Tier does not "
            "grant merge authority; see Scripts/rules/merge_authority.py."
        )
    )
    parser.add_argument("range", nargs="?", default=None)
    parser.add_argument("--repository", type=Path, default=REPOSITORY_ROOT)
    parser.add_argument("--json", action="store_true")
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    repository = arguments.repository.resolve()
    explicit = arguments.range is not None
    range_expression = arguments.range if explicit else DEFAULT_RANGE
    try:
        verdict = build_verdict(
            range_expression, changed_paths(repository, range_expression)
        )
    except (OSError, subprocess.SubprocessError) as error:
        detail = "git diff failed"
        if isinstance(error, subprocess.CalledProcessError) and error.stderr:
            detail = error.stderr.strip().splitlines()[-1]
        if explicit:
            print(
                f"could not read the range {range_expression}: {detail}",
                file=sys.stderr,
            )
            return 2
        verdict = unresolved_verdict(range_expression, detail)
    if arguments.json:
        print(
            json.dumps(verdict_payload(verdict), indent=2, ensure_ascii=False) + "\n",
            end="",
        )
    else:
        for line in render(verdict):
            print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
