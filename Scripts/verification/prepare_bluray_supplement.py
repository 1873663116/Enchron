#!/usr/bin/env python3
"""Materialize the current task's simulator-only Blu-ray Regression Catalog.

The output is separate from Regression/ and does not change HC-000's 65-Promise
baseline. The normal review and compiled Operation gateway still apply.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
from collections.abc import Mapping
from dataclasses import dataclass

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from Scripts.regression.core.catalog import load_catalog
from Scripts.regression.core.digest import canonical_digest
from Scripts.regression.core.frontmatter import load_frontmatter
from Scripts.verification.regression_operation_adapter import catalog_operation_shape


@dataclass(frozen=True)
class BluRayCase:
    slug: str
    source_kind: str
    fixture: str | None
    disc_name: str
    selected_playlist: int
    authored_playlist_count: int
    selected_duration: str
    selected_name: str
    corpus_release: str
    corpus_folder: str
    primary_count: int
    group_counts: tuple[tuple[str, int], ...] = ()
    selected_group: str | None = None
    companion_titles: tuple[tuple[int, str, str], ...] = ()

    @property
    def is_directory(self) -> bool:
        return not self.disc_name.endswith(".iso")

    @property
    def root_item_count(self) -> int:
        return self.primary_count + len(self.group_counts) + int(self.is_directory)


AVS_GROUPS = (("videos", 97), ("sequences", 2), ("stillImages", 11))
CASES = (
    BluRayCase(
        "avs-iso", "local", "bluray-avs-iso", "HDMV-2d.iso", 99, 110,
        "30 sec", "Sequences · 30s · H.264 1080p", "AVS-HD-709", "HDMV-2d", 0,
        AVS_GROUPS, "sequences",
        ((43, "25 min", "Sequences · 25m 00s · H.264 1080p"),),
    ),
    BluRayCase(
        "avs-directory", "local", "bluray-avs-directory", "HDMV-2d", 99, 110,
        "30 sec", "Sequences · 30s · H.264 1080p", "AVS-HD-709", "HDMV-2d", 0,
        AVS_GROUPS, "sequences",
        ((43, "25 min", "Sequences · 25m 00s · H.264 1080p"),),
    ),
    BluRayCase("fel-iso", "local", "bluray-fel-iso", "FEL_test_for_AVS.iso",
               0, 1, "2 min", "FEL_test_for_AVS", "DolbyVision-Profile7-FEL",
               "FEL_test_for_AVS", 1),
    BluRayCase("fel-directory", "local", "bluray-fel-directory", "FEL_test_for_AVS",
               0, 1, "2 min", "FEL_test_for_AVS", "DolbyVision-Profile7-FEL",
               "FEL_test_for_AVS", 1),
    BluRayCase("smb-fel-iso", "smb", None, "FEL_test_for_AVS.iso",
               0, 1, "2 min", "FEL_test_for_AVS", "DolbyVision-Profile7-FEL",
               "FEL_test_for_AVS", 1),
    BluRayCase("smb-fel-directory", "smb", None, "FEL_test_for_AVS",
               0, 1, "2 min", "FEL_test_for_AVS", "DolbyVision-Profile7-FEL",
               "FEL_test_for_AVS", 1),
    BluRayCase("webdav-fel-iso", "webdav", None, "FEL_test_for_AVS.iso",
               0, 1, "2 min", "FEL_test_for_AVS", "DolbyVision-Profile7-FEL",
               "FEL_test_for_AVS", 1),
    BluRayCase("webdav-fel-directory", "webdav", None, "FEL_test_for_AVS",
               0, 1, "2 min", "FEL_test_for_AVS", "DolbyVision-Profile7-FEL",
               "FEL_test_for_AVS", 1),
    BluRayCase(
        "sintel-iso", "local", "bluray-sintel-iso", "Sintel-Bluray.iso",
        0, 2, "14 min", "Sintel-Bluray", "Sintel", "Sintel-Bluray", 1,
        (("additional", 1),),
    ),
    BluRayCase(
        "sintel-directory", "local", "bluray-sintel-directory", "Sintel-Bluray",
        0, 2, "14 min", "Sintel-Bluray", "Sintel", "Sintel-Bluray", 1,
        (("additional", 1),),
    ),
    BluRayCase(
        "sintel-editions-iso", "local", "bluray-sintel-editions-iso",
        "Sintel-Editions.iso", 1, 3, "1 min", "1m 15s · Sintel – Edition tests",
        "Sintel-Editions", "Sintel-Editions", 2, (("additional", 1),), None,
        ((0, "1 min", "1m 00s · Sintel – Edition tests"),),
    ),
    BluRayCase(
        "sintel-editions-directory", "local", "bluray-sintel-editions-directory",
        "Sintel-Editions", 1, 3, "1 min", "1m 15s · Sintel – Edition tests",
        "Sintel-Editions", "Sintel-Editions", 2, (("additional", 1),), None,
        ((0, "1 min", "1m 00s · Sintel – Edition tests"),),
    ),
)

AX = ("accessibility.tree", "accessibility-tree@1", "oracle:agent-structured-accessibility-tree@1")
PLAYBACK = ("playback.probe", "playback-probe@1", "oracle:agent-structured-playback-probe@1")
FRAMES = ("visual.frames", "frame-sequence@2", "oracle:agent-visual@2")


def _write(root: Path, relative: str, metadata: dict, body: str) -> None:
    target = root / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(
        "---\n" + json.dumps(_plain(metadata), ensure_ascii=False, indent=2) +
        "\n---\n# " + metadata["title"] + "\n\n" + body.strip() + "\n",
        encoding="utf-8",
    )


def _plain(value):
    if isinstance(value, Mapping):
        return {key: _plain(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [_plain(item) for item in value]
    return value


def _call(slug: str, number: int, operation: str, arguments: dict) -> dict:
    return {
        "callId": f"call:bluray-disc:{slug}:{number:02d}",
        "operation": f"operation:{operation}",
        "arguments": arguments,
        "maxInvocations": 1,
    }


def _scenario(root: Path, case: BluRayCase) -> tuple[dict, set[str], set[str]]:
    slug = case.slug
    source_kind = case.source_kind
    fixture = case.fixture
    disc_name = case.disc_name
    calls: list[dict] = []
    operations: set[str] = set()
    oracles: set[str] = set()
    bindings: list[tuple[str, str, tuple[str, str, str], list[str], list[str]]] = []

    def add(operation: str, arguments: dict) -> str:
        call = _call(slug, len(calls) + 1, operation, arguments)
        calls.append(call)
        operations.add(call["operation"])
        return call["callId"]

    if fixture is not None:
        add("media.stage-fixture@2", {"fixtureID": fixture, "sourceRoot": "workspace://TestMedia"})
    add("app.relaunch@1", {})
    add("navigation.select-tab@1", {"tab": "files"})
    if source_kind == "local":
        path = ["TestMediaInbox"]
        add("accessibility.activate@2", {"context": "main-window-browser", "identifiers": ["FileBrowsing-grid-folder-TestMediaInbox"]})
    elif source_kind == "smb":
        path = ["TestMedia", "Samples", "DiscImages", "DolbyVision-Profile7-FEL"]
        add("accessibility.activate@2", {"context": "main-window-browser", "labels": ["Enchron Regression SMB"]})
        for component in path:
            add("accessibility.activate@2", {"context": "main-window-browser", "identifiers": [f"FileBrowsing-grid-folder-{component}"]})
    else:
        path = ["DiscImages", "DolbyVision-Profile7-FEL"]
        add("accessibility.activate@2", {"context": "main-window-browser", "labels": ["Enchron Regression WebDAV"]})
        for component in path:
            add("accessibility.activate@2", {"context": "main-window-browser", "identifiers": [f"FileBrowsing-grid-folder-{component}"]})
    entry_id = (
        f"FileBrowsing-grid-bluray-disc-{disc_name}"
        if disc_name.endswith(".iso") else f"FileBrowsing-grid-folder-{disc_name}"
    )
    add("accessibility.activate@2", {"context": "main-window-browser", "identifiers": [entry_id]})

    def inspect(identifier: str) -> str:
        return add("accessibility.inspect@2", {
            "context": "main-window-browser", "identifier": identifier,
            "requireMatchedElement": True, "deadlineSeconds": 90,
        })

    group_names = {
        "videos": "Videos",
        "sequences": "Sequences",
        "stillImages": "Still images",
        "additional": "Additional content",
    }

    def inspect_root(instance: int) -> None:
        count_call = inspect("FileBrowsing-FilesScreen-itemCount")
        bindings.append((
            f"root-count-{instance}", count_call, AX,
            [f"matchedElement label or value is exactly '{case.root_item_count} items'."],
            [
                "A default page showing 110 raw playlist cards violates content projection; "
                "a missing count element or a count from another folder is Indeterminate."
            ],
        ))
        for kind, count in case.group_counts:
            identifier = f"FileBrowsing-grid-bluray-group-{kind}"
            call = inspect(identifier)
            rubric_kind = "still-images" if kind == "stillImages" else kind
            bindings.append((
                f"root-{rubric_kind}-{instance}", call, AX,
                [
                    f"matchedElement identifier is {identifier}, its label contains "
                    f"'{group_names[kind]}', and its visible count is {count}."
                ],
                [
                    "A raw playlist card, a missing content group, or a group count derived "
                    "from the currently selected playlist violates root content projection."
                ],
            ))

    inspect_root(1)
    if case.is_directory:
        add("accessibility.activate@2", {
            "context": "main-window-browser", "identifiers": ["FileBrowsing-grid-bluray-browseFiles"],
        })
        add("accessibility.activate@2", {
            "context": "main-window-browser", "identifiers": ["FileBrowsing-grid-folder-BDMV"],
        })
        inspect_root(2)

    if case.selected_group:
        group_id = f"FileBrowsing-grid-bluray-group-{case.selected_group}"
        add("accessibility.activate@2", {
            "context": "main-window-browser", "identifiers": [group_id],
        })
        group_count = dict(case.group_counts)[case.selected_group]
        count_call = inspect("FileBrowsing-FilesScreen-itemCount")
        bindings.append((
            "group-count", count_call, AX,
            [f"matchedElement label or value is exactly '{group_count} items'."],
            ["The root count or raw authored-playlist count cannot prove the opened group."],
        ))

    title_contracts = [
        (case.selected_playlist, case.selected_duration, case.selected_name)
    ] + list(case.companion_titles)
    for playlist_id, duration, content_name in title_contracts:
        title_id = f"FileBrowsing-grid-bluray-content-{playlist_id}"
        title_call = inspect(title_id)
        bindings.append((
            f"content-{playlist_id}", title_call, AX,
            [
                f"matchedElement identifier is {title_id}, its label contains "
                f"'{content_name}' and 'Duration {duration}', and its label does not contain 'Playlist'."
            ],
            [
                "A visible Playlist ID, a grid-bluray-playlist identifier, an authored duration "
                "mismatch, or a card observed before opening its content group violates this claim."
            ],
        ))

    selected_title_id = f"FileBrowsing-grid-bluray-content-{case.selected_playlist}"
    add("media.open@2", {"identifier": selected_title_id,
                          "expectedLanding": "window", "deadlineSeconds": 90})
    add("playback.await-window-state@1", {
        "presentation": "window", "lifecycle": "playing", "controls": "either", "deadlineSeconds": 90,
    })
    playback_call = add("diagnostics.playback-state@1", {})
    frames_call = add("evidence.capture-frames@1", {
        "context": "window", "count": 3, "minimumIntervalMillis": 1000,
    })

    bindings.extend((
        ("selection", playback_call, PLAYBACK,
         [f"fields.bluRayPlaylistID is exactly {case.selected_playlist}, with an active media session and lifecycle Playing."],
         ["A generic file selection, absent identity, or a different playlist ID violates selection."]),
        ("picture", frames_call, FRAMES,
         ["Three captured PNGs are larger than 1x1, nonblack and belong to the selected media session."],
         ["A 1x1, corrupt, black, stale, or differently selected screenshot cannot prove decoded playback."]),
    ))
    obligations = []
    for index, (label, producer, pair, criteria, negative) in enumerate(bindings, 1):
        evidence_type, evidence_schema, oracle = pair
        oracles.add(oracle)
        obligation_id = f"obligation:bluray-disc:{slug}:o{index:02d}:default"
        rubric_id = f"rubric:bluray-disc.{slug}.{label}@1"
        obligations.append({
            "artifactClass": "coverage", "caseKey": "default",
            "evidenceType": evidence_type, "evidenceSchema": evidence_schema,
            "id": obligation_id, "oracle": oracle,
            "producedByCall": producer, "rubric": rubric_id,
        })
        _write(root, f"rubrics/{slug}-{label}.md", {
            "schema": "enchron.regression.rubric", "schemaVersion": 1,
            "id": rubric_id, "title": f"Blu-ray {slug} {label}",
            "criteria": criteria, "negativeControls": negative,
        }, "The bound same-attempt artifact decides this criterion. Setup receipts are not playback evidence.")
    scenario = {
        "schema": "enchron.regression.scenario", "schemaVersion": 1,
        "id": f"scenario:bluray-disc:{slug}", "title": f"Blu-ray {slug}",
        "journey": "journey:bluray-disc",
        "promiseRefs": [f"promise:bluray-disc:c{1 if source_kind == 'local' else 2:02d}"],
        "applicability": {"factEquals": {"fact": "fact:bluray-disc.current-task-authorized", "value": True}},
        "lane": "simulator", "estimatedCostMillis": 900000 if fixture else 240000,
        "staticCases": ["default"], "readiness": "ready", "blockers": [],
        "prerequisites": (
            [{"key": f"{source_kind}-test-source-ready", "schema": f"remote-source.{source_kind}-fixture@2"}]
            if source_kind != "local" else []
        ),
        "operations": calls, "obligations": obligations,
        "success": {"all": [{"observation": item["id"]} for item in obligations]},
        "mainGateFor": ["simulator"] if slug == "avs-iso" else [],
    }
    _write(root, f"journeys/bluray-disc/scenarios/{slug}.md", scenario,
           "All card activations use the product's real hit testing. Container staging is setup only and bypasses Files import.")
    return scenario, operations, oracles


def prepare(output_root: Path) -> dict:
    output_root = output_root.resolve()
    if not output_root.is_relative_to(ROOT) or output_root == ROOT / "Regression":
        raise ValueError("supplemental Catalog must be a separate path inside this repository")
    if output_root.exists() and any(output_root.iterdir()):
        raise ValueError("supplemental Catalog output must be empty; preserve reviewed outputs")
    output_root.mkdir(parents=True, exist_ok=True)
    _write(output_root, "promises/bluray-disc.md", {
        "schema": "enchron.regression.promises", "schemaVersion": 1,
        "feature": "bluray-disc", "title": "Blu-ray disc browsing and playback",
        "promises": [
            {"id": "promise:bluray-disc:c01", "title": "Local disc titles",
             "statement": "Local ISO and BDMV parent/self entries project authored playlists into honest films, versions and content groups; selected content plays with stable internal playlist identity.",
             "automation": {"scope": "included"}},
            {"id": "promise:bluray-disc:c02", "title": "Remote disc titles",
             "statement": "SMB and WebDAV ISO and BDMV entries expose the same content projection and selected supported content plays through its source adapter.",
             "automation": {"scope": "included"}},
        ],
    }, "This supplemental Promise set is limited to the user's current Blu-ray request; the baseline Catalog remains unchanged.")
    _write(output_root, "facts/bluray-task-authorized.md", {
        "schema": "enchron.regression.fact", "schemaVersion": 1,
        "id": "fact:bluray-disc.current-task-authorized", "title": "Current Blu-ray simulator task",
        "statement": "The user authorized Blu-ray implementation and simulator end-to-end verification in the current task.",
        "valueType": "boolean", "value": True,
        "provenance": {"kind": "decision", "decision": "current-user-request"},
    }, "The current user request limits this supplement to local, SMB and WebDAV sources and simulator evidence.")

    scenarios = []
    operations: set[str] = set()
    oracles: set[str] = set()
    for case in CASES:
        scenario, used_operations, used_oracles = _scenario(output_root, case)
        scenarios.append(scenario)
        operations.update(used_operations)
        oracles.update(used_oracles)
    for source_kind in ("smb", "webdav"):
        source = ROOT / f"Regression/preparations/{source_kind}-test-source.md"
        document = load_frontmatter(source)
        metadata = dict(document.metadata)
        metadata["lane"] = "simulator"
        _write(output_root, f"preparations/{source_kind}-test-source.md", metadata,
               document.body)
        operations.update(call["operation"] for call in metadata["operations"])
    for operation in sorted(operations):
        source = next(
            path for path in (ROOT / "Regression/operations").glob("*.md")
            if load_frontmatter(path).metadata["id"] == operation
        )
        document = load_frontmatter(source)
        metadata = dict(document.metadata)
        shape = catalog_operation_shape(operation)
        metadata["argumentSchema"] = {
            "fields": shape["argumentFields"], "rules": shape["argumentRules"],
            "additionalProperties": False,
        }
        metadata["lanes"] = shape["lanes"]
        metadata["evidenceSchemas"] = shape["evidenceSchemas"]
        metadata["implementation"] = shape["implementation"]
        _write(output_root, f"operations/{source.name}", metadata, document.body)
    for oracle in sorted(oracles):
        source = next(path for path in (ROOT / "Regression/oracles").glob("*.md")
                      if load_frontmatter(path).metadata["id"] == oracle)
        document = load_frontmatter(source)
        _write(output_root, f"oracles/{source.name}", dict(document.metadata), document.body)
    _write(output_root, "journeys/bluray-disc/journey.md", {
        "schema": "enchron.regression.journey", "schemaVersion": 1,
        "id": "journey:bluray-disc", "title": "Blu-ray simulator verification",
        "scenarioRefs": [item["id"] for item in scenarios],
        "ordering": [], "sharedState": [],
    }, "Each scenario verifies projected root content before selecting one internal playlist identity. The local AVS ISO case is the simulator gate, and its default page shows content groups instead of 110 raw playlist cards.")
    catalog = load_catalog(output_root)
    blueprint = {
        "schemaVersion": 2,
        "analysisFactValues": {"fact:bluray-disc.current-task-authorized": True},
    }
    blueprint["contentDigest"] = str(canonical_digest(blueprint))
    blueprint_path = output_root.parent / "bluray-supplement-blueprint.json"
    blueprint_path.write_text(json.dumps(blueprint, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return {"catalogRoot": str(output_root), "blueprint": str(blueprint_path),
            "catalogDigest": str(catalog.digest), "scenarios": len(scenarios)}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-root", required=True, type=Path)
    arguments = parser.parse_args()
    try:
        result = prepare(arguments.output_root)
    except (OSError, ValueError, StopIteration) as error:
        parser.exit(1, f"Blu-ray supplemental Catalog failed: {error}\n")
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
