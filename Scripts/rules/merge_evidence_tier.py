#!/usr/bin/env python3

from __future__ import annotations

import argparse
from dataclasses import dataclass
import json
from pathlib import Path
import subprocess
import sys

if str(Path(__file__).parent) not in sys.path:
    sys.path.insert(0, str(Path(__file__).parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "verification"))

import journey_units

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
STANDARD_DOCUMENT = "docs/MERGE_EVIDENCE.md"
DEFAULT_RANGE = "@{upstream}..HEAD"

W0 = "W0"
W1 = "W1"
W2 = "W2"
W3 = "W3"
TIERS = (W0, W1, W2, W3)
FREE_MERGE_ENABLED_TIERS = (W0, W1)

VERIFICATION_GREEN = "verification-green"
SIMULATOR_E2E = "simulator-e2e"
DEVICE_HUB_INPUT = "device-hub-input"
PROBE_CONTRACT_SHAPE = "spatialTap entity=<entity> ... accepted=true"

TIER_EVIDENCE = {
    W0: (VERIFICATION_GREEN,),
    W1: (VERIFICATION_GREEN,),
    W2: (VERIFICATION_GREEN, SIMULATOR_E2E),
    W3: (VERIFICATION_GREEN, SIMULATOR_E2E, DEVICE_HUB_INPUT),
}

PATH_RULES = (
    ("docs/", W0),
    (".agents/skills/", W0),
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

FREE_MERGE_PHRASE = "免读合并合格"
REVIEW_PHRASE = "非免读，需证据清单"


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
    free_merge: bool
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
            True,
            "empty range: no committed changes to judge",
        )
    tier = TIERS[max(tier_rank(entry.tier) for entry in classifications)]
    return Verdict(
        range_expression,
        classifications,
        tier,
        tier in FREE_MERGE_ENABLED_TIERS,
        "",
    )


def unresolved_verdict(range_expression: str, detail: str) -> Verdict:
    return Verdict(
        range_expression,
        (),
        UNCLASSIFIED_TIER,
        False,
        f"range unresolved ({detail}); up-leveled to {UNCLASSIFIED_TIER}",
    )


def changed_paths(repository: Path, range_expression: str) -> list[str]:
    completed = subprocess.run(
        ["git", "-C", str(repository), "diff", "--name-only", "-z", range_expression],
        capture_output=True,
        text=True,
        check=True,
    )
    return [path for path in completed.stdout.split("\0") if path]


def required_evidence_lines(tier: str) -> list[str]:
    lines = []
    for kind in TIER_EVIDENCE[tier]:
        if kind == DEVICE_HUB_INPUT:
            lines.append(f"  - {kind}: {PROBE_CONTRACT_SHAPE}")
        else:
            lines.append(f"  - {kind}")
    if tier == W3:
        lines.append(
            "  - real-device evidence stands in only for decode-capability changes"
        )
    return lines


def render(verdict: Verdict) -> list[str]:
    lines = [f"merge evidence tier: {verdict.range_expression}"]
    for entry in verdict.classifications:
        lines.append(f"  {entry.tier} {entry.path} [{entry.rule}]")
    if verdict.reason:
        lines.append(verdict.reason)
    if verdict.tier is None:
        lines.append(f"verdict: {FREE_MERGE_PHRASE}")
    else:
        lines.append(f"tier: {verdict.tier}")
        lines.append(
            f"verdict: {FREE_MERGE_PHRASE}"
            if verdict.free_merge
            else f"verdict: {REVIEW_PHRASE}"
        )
        lines.append("required evidence:")
        lines.extend(required_evidence_lines(verdict.tier))
    lines.append(f"standard: {STANDARD_DOCUMENT}")
    return lines


def verdict_payload(verdict: Verdict) -> dict[str, object]:
    return {
        "version": 1,
        "range": verdict.range_expression,
        "tier": verdict.tier,
        "freeMerge": verdict.free_merge,
        "freeMergeEnabledTiers": list(FREE_MERGE_ENABLED_TIERS),
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


def nonempty_string(value: object) -> bool:
    return isinstance(value, str) and bool(value.strip())


def string_list(value: object) -> bool:
    return (
        isinstance(value, list)
        and bool(value)
        and all(nonempty_string(item) for item in value)
    )


def registered_device_hub_units() -> set[str]:
    return {
        unit.id
        for unit in journey_units.UNITS
        if any(step.drive == journey_units.DEVICE_HUB for step in unit.steps)
    }


def verification_complaints(entry: object) -> list[str]:
    if not isinstance(entry, dict):
        return ["verification evidence must be an object"]
    complaints = []
    for key in ("runDirectory", "summary"):
        if not nonempty_string(entry.get(key)):
            complaints.append(f"verification.{key} must point at the run artifact")
    if entry.get("verdict") != "passed":
        complaints.append("verification.verdict must be 'passed'")
    return complaints


def simulator_complaints(items: object) -> list[str]:
    if not isinstance(items, list) or not items:
        return ["simulatorE2E must list at least one run"]
    complaints = []
    for index, item in enumerate(items):
        prefix = f"simulatorE2E[{index}]"
        if not isinstance(item, dict):
            complaints.append(f"{prefix} must be an object")
            continue
        if not nonempty_string(item.get("unit")):
            complaints.append(f"{prefix}.unit must name the operation unit")
        if not string_list(item.get("artifacts")):
            complaints.append(f"{prefix}.artifacts must list artifact paths")
    return complaints


def device_hub_complaints(items: object) -> list[str]:
    if not isinstance(items, list):
        return ["deviceHubInput must be a list"]
    complaints = []
    registered = registered_device_hub_units()
    for index, item in enumerate(items):
        prefix = f"deviceHubInput[{index}]"
        if not isinstance(item, dict):
            complaints.append(f"{prefix} must be an object")
            continue
        for key in ("unit", "target", "entity", "probeLog", "diagnostics"):
            if not nonempty_string(item.get(key)):
                complaints.append(f"{prefix}.{key} is missing")
        unit = item.get("unit")
        if nonempty_string(unit) and unit not in registered:
            complaints.append(
                f"{prefix}.unit must name a registered device-hub unit "
                f"from Scripts/verification/journey_units.py; "
                f"registered: {', '.join(sorted(registered))}"
            )
        entity = item.get("entity")
        probe = item.get("probe")
        if not (
            isinstance(entity, str)
            and isinstance(probe, str)
            and journey_units.probe_matches_contract(entity, probe)
        ):
            complaints.append(
                f"{prefix}.probe must be the app-side spatialTap line "
                f"({PROBE_CONTRACT_SHAPE})"
            )
    return complaints


def real_device_complaints(items: object) -> list[str]:
    if not isinstance(items, list):
        return ["realDeviceDecode must be a list"]
    complaints = []
    for index, item in enumerate(items):
        prefix = f"realDeviceDecode[{index}]"
        if not isinstance(item, dict):
            complaints.append(f"{prefix} must be an object")
            continue
        for key in ("capability", "reason"):
            if not nonempty_string(item.get(key)):
                complaints.append(f"{prefix}.{key} is missing")
        if not string_list(item.get("evidence")):
            complaints.append(f"{prefix}.evidence must list artifact paths")
    return complaints


def manifest_complaints(
    payload: object, computed_tier: str | None
) -> list[str]:
    if not isinstance(payload, dict):
        return ["manifest must be a JSON object"]
    complaints = []
    if payload.get("version") != 1:
        complaints.append("manifest version must be 1")
    declared = payload.get("declaredTier")
    if declared not in TIERS:
        complaints.append(f"declaredTier must be one of {', '.join(TIERS)}")
        complaints.extend(verification_complaints(payload.get("verification")))
        return complaints
    effective = declared
    if computed_tier is not None and tier_rank(declared) < tier_rank(computed_tier):
        complaints.append(
            f"declaredTier {declared} is below the computed {computed_tier} "
            "for the range; a manifest may only declare upward"
        )
        effective = computed_tier
    complaints.extend(verification_complaints(payload.get("verification")))
    if tier_rank(effective) < tier_rank(W2):
        return complaints
    needs_simulator = True
    if effective == W3:
        hub = payload.get("deviceHubInput")
        decode = payload.get("realDeviceDecode")
        hub_present = isinstance(hub, list) and bool(hub)
        decode_present = isinstance(decode, list) and bool(decode)
        if not hub_present and not decode_present:
            complaints.append(
                "W3 needs deviceHubInput evidence, or a realDeviceDecode "
                "entry for a decode-capability exception"
            )
        if hub is not None:
            complaints.extend(device_hub_complaints(hub))
        if decode is not None:
            complaints.extend(real_device_complaints(decode))
        needs_simulator = hub_present or not decode_present
    if needs_simulator:
        complaints.extend(simulator_complaints(payload.get("simulatorE2E")))
    return complaints


def judge_manifest(
    manifest_path: Path, verdict: Verdict, as_json: bool
) -> int:
    try:
        payload = json.loads(manifest_path.read_text(encoding="utf-8"))
    except OSError as error:
        print(f"could not read the manifest: {error}", file=sys.stderr)
        return 2
    except json.JSONDecodeError as error:
        print(f"manifest is not valid JSON: {error}", file=sys.stderr)
        return 1
    complaints = manifest_complaints(payload, verdict.tier)
    if as_json:
        report = {
            "version": 1,
            "manifest": str(manifest_path),
            "computed": verdict_payload(verdict),
            "complaints": complaints,
            "sufficient": not complaints,
        }
        print(json.dumps(report, indent=2, ensure_ascii=False))
    else:
        for line in render(verdict):
            print(line)
        if complaints:
            for complaint in complaints:
                print(f"FAIL {complaint}")
        else:
            print(f"manifest: sufficient for {payload.get('declaredTier')}")
    return 1 if complaints else 0


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Classify a commit range into the merge evidence tiers and "
            "judge evidence manifests against them; the standard is "
            "docs/MERGE_EVIDENCE.md."
        )
    )
    parser.add_argument("range", nargs="?", default=None)
    parser.add_argument("--repository", type=Path, default=REPOSITORY_ROOT)
    parser.add_argument("--manifest", type=Path, default=None)
    parser.add_argument("--json", action="store_true")
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    repository = arguments.repository.resolve()
    explicit = arguments.range is not None
    range_expression = arguments.range if explicit else DEFAULT_RANGE
    try:
        paths = changed_paths(repository, range_expression)
        verdict = build_verdict(range_expression, paths)
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
    if arguments.manifest is not None:
        return judge_manifest(arguments.manifest, verdict, arguments.json)
    if arguments.json:
        print(json.dumps(verdict_payload(verdict), indent=2, ensure_ascii=False))
    else:
        for line in render(verdict):
            print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
