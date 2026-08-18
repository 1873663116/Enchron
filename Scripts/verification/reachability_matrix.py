#!/usr/bin/env python3
"""Drive Enchron's physical-device reachability matrix and preserve raw evidence.

The inventory defines the axes. This runner never promotes XCTest's action return
value to delivery evidence: delivery requires an application probe, diagnostic
state transition, or an app-command response produced after the product handler.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import time
from typing import Any
import uuid


ROOT = Path(__file__).resolve().parents[2]
CONTROLLER = ROOT / "Scripts/verification/interactive_visionpro_ui.py"
INVENTORY = ROOT / "Config/reachability_operation_inventory.json"
BASELINE = ROOT / "Config/reachability_matrix_baseline.json"
DEFAULT_EVIDENCE = Path(
    "/Volumes/Cortisol/DevSpace/Xcode/Enchron/TestEvidence/reachability-round7-20260818"
)
DEFAULT_DERIVED_DATA = Path(
    "/Volumes/Cortisol/DevSpace/Xcode/Enchron/DerivedDataReach7-20260818"
)
DEVICE = "00008142-001871A11491401C"
CORE_DEVICE = "59E3D57A-0288-53DC-9A7D-B657B6939558"
DEVELOPER_DIR = "/Volumes/Cortisol/Applications/Xcode-beta5.app/Contents/Developer"
APP_BUNDLE = "com.xiongzhipeng.XrPlayer"
PRESENTATIONS = ("window", "portal", "panorama", "docked")
SEGMENT_SCENARIO_NAMES = {
    "browser-core",
    "breadcrumbs",
    "docked",
    "file-browser-errors",
    "library-conditions",
    "library-reference-move",
    "manage-add",
    "panorama",
    "playback-failures",
    "player-ui-candidates",
    "player-panel-portal-menus",
    "portal",
    "resume-decision",
    "settings-menus",
    "source-connection-smb",
    "source-connection-webdav",
    "source-sidebar",
    "window-playback",
}
PROBE_REMOTE_PATH = "Documents/surface-tap-probe.log"
CHANNEL_HEALTH_REMOTE_PATH = "Documents/reachability-channel-health.txt"
REACHABILITY_LIBRARY_FOLDER = "Reachability Fixture"
FIXTURE_SOURCE_ROOT = Path(
    "/Volumes/Cortisol/DevSpace/Xcode/Enchron/TestEvidence/"
    "reachability-round2-20260818/recovery/TestMediaInbox"
)


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def template_pattern(template: str) -> re.Pattern[str]:
    parts: list[str] = []
    cursor = 0
    depth = 0
    start = -1
    for index, character in enumerate(template):
        if character == "{" and depth == 0:
            parts.append(re.escape(template[cursor:index]))
            start = index
            depth = 1
        elif character == "{" and depth:
            depth += 1
        elif character == "}" and depth:
            depth -= 1
            if depth == 0:
                parts.append(".+?")
                cursor = index + 1
    if depth:
        return re.compile("^" + re.escape(template) + "$")
    parts.append(re.escape(template[cursor:]))
    return re.compile("^" + "".join(parts) + "$")


def product_presentations(operation: dict[str, Any]) -> tuple[str, ...]:
    explicit = operation.get("presentations")
    if isinstance(explicit, list):
        return tuple(str(value) for value in explicit)
    template = str(operation.get("identifierTemplate", ""))
    family = template.partition("-")[0]
    if family in {"Emby", "FileBrowsing", "MediaLibrary", "Navigation", "Settings"}:
        return ("window",)
    if family in {"EnvironmentCard", "SenseZone"}:
        return ("window", "docked")
    if family == "PlayerPanel":
        return PRESENTATIONS
    if family == "PlayerUI":
        if template.startswith("PlayerUI-window-"):
            return ("window", "portal")
        if template == "PlayerUI-spatial-state":
            return ("panorama", "docked")
        return PRESENTATIONS
    return ("window",)


def reachability_evidence_is_complete(cell: dict[str, Any]) -> bool:
    if cell.get("identifierTemplate") is None:
        return cell.get("applicationReceived") is True
    return all(
        cell.get(key) is True
        for key in (
            "existsInHierarchy",
            "reportsHittable",
            "applicationReceived",
        )
    )


def menu_selection_target(
    listing: dict[str, Any],
    *,
    preferred: tuple[str, ...] = (),
) -> str | None:
    payload = listing.get("payload")
    available = [str(value) for value in payload] if isinstance(payload, list) else []
    for target in preferred:
        if target in available:
            return target

    menu_items = listing.get("menuItems")
    if isinstance(menu_items, list):
        for item in menu_items:
            if (
                isinstance(item, dict)
                and item.get("isSelected") is False
                and str(item.get("id")) in available
            ):
                return str(item["id"])
    return available[0] if available else None


def video_format_open_was_delivered(
    probe: list[str], *, offset: int
) -> bool:
    return any(
        "reachability " in line
        and " delivered action=videoFormat.open" in line
        for line in probe[offset:]
    )


def merge_selected_cells_into_baseline(
    baseline_cells: list[dict[str, Any]],
    current_cells: list[dict[str, Any]],
    *,
    selected: set[str],
) -> list[dict[str, Any]]:
    baseline_by_key = {
        (cell.get("presentation"), cell.get("operation")): cell
        for cell in baseline_cells
    }
    merged: list[dict[str, Any]] = []
    for cell in current_cells:
        key = (cell["presentation"], cell["operation"])
        accepted = (
            cell
            if cell["presentation"] in selected
            else baseline_by_key.get(key, cell)
        )
        merged.append({
            "presentation": accepted["presentation"],
            "operation": accepted["operation"],
            "verdict": accepted["verdict"],
        })
    return merged


def merge_segment_delivery(
    baseline_cells: list[dict[str, Any]],
    segment_results: list[dict[str, Any]],
) -> dict[str, Any]:
    """Merge only cells driven by complete, channel-continuous segments."""
    candidate_by_key = {
        (str(cell["presentation"]), str(cell["operation"])): dict(cell)
        for cell in baseline_cells
    }
    accepted_segments: list[str] = []
    rejected_segments: list[str] = []
    driven_keys: set[tuple[str, str]] = set()

    for segment in segment_results:
        name = str(segment.get("segment", "unnamed"))
        session_id = segment.get("sessionID")
        health = segment.get("channelHealth")
        before = health.get("before", {}) if isinstance(health, dict) else {}
        after = health.get("after", {}) if isinstance(health, dict) else {}
        channel_continuous = (
            segment.get("status") == "complete"
            and isinstance(session_id, str)
            and bool(session_id)
            and before.get("passed") is True
            and after.get("passed") is True
            and before.get("sessionID") == session_id
            and after.get("sessionID") == session_id
            and (
                not isinstance(segment.get("channelContinuity"), dict)
                or segment["channelContinuity"].get("passed") is True
            )
        )
        if not channel_continuous:
            rejected_segments.append(name)
            continue

        accepted_segments.append(name)
        cells = {
            (str(cell.get("presentation")), str(cell.get("operation"))): cell
            for cell in segment.get("cells", [])
            if isinstance(cell, dict)
        }
        for driven in segment.get("drivenCells", []):
            if not isinstance(driven, dict):
                continue
            key = (
                str(driven.get("presentation")),
                str(driven.get("operation")),
            )
            if key not in candidate_by_key:
                continue
            driven_keys.add(key)
            observed = cells.get(key)
            candidate_by_key[key]["verdict"] = (
                str(observed.get("verdict"))
                if isinstance(observed, dict)
                else "known-defect"
            )

    failures: list[dict[str, str]] = []
    baseline_by_key = {
        (str(cell["presentation"]), str(cell["operation"])): cell
        for cell in baseline_cells
    }
    for key in sorted(driven_keys):
        if (
            baseline_by_key[key].get("verdict") == "reachable"
            and candidate_by_key[key].get("verdict") != "reachable"
        ):
            failures.append({
                "presentation": key[0],
                "operation": key[1],
                "reason": "driven-old-reachable-not-reproved",
            })

    return {
        "accepted": bool(accepted_segments) and not failures,
        "acceptedSegments": accepted_segments,
        "rejectedSegments": rejected_segments,
        "drivenCells": [
            {"presentation": presentation, "operation": operation}
            for presentation, operation in sorted(driven_keys)
        ],
        "failures": failures,
        "candidateCells": [
            candidate_by_key[(str(cell["presentation"]), str(cell["operation"]))]
            for cell in baseline_cells
        ],
    }


def validate_segment_plan(
    plan: dict[str, Any],
    *,
    operation_ids: set[str],
    scenario_names: set[str],
) -> list[str]:
    errors: list[str] = []
    seen: set[str] = set()
    segments = plan.get("segments")
    if not isinstance(segments, list) or not segments:
        return ["segment plan must contain a nonempty segments array"]
    for segment in segments:
        if not isinstance(segment, dict):
            errors.append("segment plan contains a non-object segment")
            continue
        name = str(segment.get("id", ""))
        if not name:
            errors.append("segment is missing id")
        elif name in seen:
            errors.append(f"segment {name} is duplicated")
        seen.add(name)
        presentation = str(segment.get("presentation", ""))
        if presentation not in PRESENTATIONS:
            errors.append(
                f"segment {name or '<missing>'} has unknown presentation {presentation}"
            )
        scenarios = segment.get("scenarios")
        if not isinstance(scenarios, list) or not scenarios:
            errors.append(f"segment {name or '<missing>'} has no scenarios")
        else:
            for scenario in scenarios:
                if str(scenario) not in scenario_names:
                    errors.append(
                        f"segment {name or '<missing>'} has unknown scenario {scenario}"
                    )
        operations = segment.get("operations")
        if not isinstance(operations, list) or not operations:
            errors.append(f"segment {name or '<missing>'} has no operations")
        else:
            for operation in operations:
                if str(operation) not in operation_ids:
                    errors.append(
                        f"segment {name or '<missing>'} has unknown operation {operation}"
                    )
    return errors


def immersive_resident_window_is_hidden(
    *,
    toggle: dict[str, Any],
    cleanup: dict[str, Any],
    no_named_node: bool,
    no_new_identifier: bool,
) -> bool:
    cleanup_proves_intermediate_state = (
        cleanup.get("success") is True
        and cleanup.get("ok") is True
        and cleanup.get("payload") == ["false"]
    )
    mechanism_was_open = (
        toggle.get("success") is True or cleanup_proves_intermediate_state
    )
    return mechanism_was_open and no_named_node and no_new_identifier


class ReachabilityRun:
    def __init__(self, arguments: argparse.Namespace) -> None:
        self.arguments = arguments
        self.output = arguments.output_directory.resolve()
        self.controller_output = self.output / "controller"
        self.raw = self.output / "raw"
        self.output.mkdir(parents=True, exist_ok=True)
        self.controller_output.mkdir(parents=True, exist_ok=True)
        self.raw.mkdir(parents=True, exist_ok=True)
        self.inventory = json.loads(INVENTORY.read_text(encoding="utf-8"))
        self.operations = {
            str(item["id"]): item for item in self.inventory["operations"]
        }
        self.cells: dict[tuple[str, str], dict[str, Any]] = {}
        self.events: list[dict[str, Any]] = []
        self.driven_cells: set[tuple[str, str]] = set()
        self.session_id: str | None = None
        self.channel_health: dict[str, dict[str, Any]] = {}
        self.channel_failures: list[dict[str, Any]] = []
        self.segment: dict[str, Any] | None = getattr(arguments, "segment_spec", None)
        self.sequence = 0
        self.probe_offset = 0
        plan_document = getattr(arguments, "segment_plan_document", None)
        if self.segment is not None and isinstance(plan_document, dict):
            (self.output / "segment-plan.json").write_text(
                json.dumps(
                    plan_document, ensure_ascii=False, indent=2, sort_keys=True
                ) + "\n",
                encoding="utf-8",
            )
        for presentation in PRESENTATIONS:
            for operation_id, operation in self.operations.items():
                applicable = presentation in product_presentations(operation)
                self.cells[(presentation, operation_id)] = {
                    "presentation": presentation,
                    "operation": operation_id,
                    "kind": operation["kind"],
                    "identifierTemplate": operation.get("identifierTemplate"),
                    "applicable": applicable,
                    "existsInHierarchy": None if not applicable else False,
                    "reportsHittable": None if not applicable else False,
                    "applicationReceived": None if not applicable else False,
                    "verdict": "not-applicable" if not applicable else "known-defect",
                    "reason": (
                        "The product semantic is not offered in this presentation."
                        if not applicable
                        else "The first-run fixture has not produced delivery evidence."
                    ),
                    "evidence": [],
                }

    def controller(self, action: str, *extra: str, timeout: float = 180.0) -> dict[str, Any]:
        if self.segment is not None and self.channel_failures and action != "halt":
            document = {
                "success": False,
                "error": "segment channel continuity already failed",
            }
            self.sequence += 1
            name = f"{self.sequence:03d}-{action}.json"
            (self.raw / name).write_text(
                json.dumps(document, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
                encoding="utf-8",
            )
            self.events.append({
                "at": utc_now(),
                "action": action,
                "arguments": list(extra),
                "success": False,
                "evidence": f"raw/{name}",
                "elapsedSeconds": 0.0,
            })
            return document
        command = [
            sys.executable,
            str(CONTROLLER),
            "--device",
            DEVICE,
            "--output-directory",
            str(self.controller_output),
            "--developer-dir",
            DEVELOPER_DIR,
            "--derived-data-path",
            str(self.arguments.derived_data_path),
            action,
            *extra,
        ]
        started = time.monotonic()
        try:
            completed = subprocess.run(
                command,
                cwd=ROOT,
                capture_output=True,
                text=True,
                timeout=timeout,
                check=False,
            )
        except subprocess.TimeoutExpired:
            document = {
                "success": False,
                "error": f"controller {action} exceeded {timeout:.1f} seconds",
            }
        else:
            try:
                document = json.loads(completed.stdout)
            except json.JSONDecodeError:
                document = {
                    "success": False,
                    "error": "controller returned non-JSON output",
                    "stdout": completed.stdout[-1000:],
                    "stderr": completed.stderr[-1000:],
                }
        self.sequence += 1
        name = f"{self.sequence:03d}-{action}.json"
        (self.raw / name).write_text(
            json.dumps(document, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        self.events.append(
            {
                "at": utc_now(),
                "action": action,
                "arguments": list(extra),
                "success": document.get("success"),
                "evidence": f"raw/{name}",
                "elapsedSeconds": round(time.monotonic() - started, 3),
            }
        )
        error = str(document.get("error", ""))
        if (
            self.segment is not None
            and (
                "exceeded" in error
                or "runner is not ready" in error
            )
        ):
            self.channel_failures.append({
                "at": utc_now(),
                "action": action,
                "error": error,
                "evidence": f"raw/{name}",
            })
        return document

    def app_command(self, verb: str, **arguments: str) -> dict[str, Any]:
        operation_id = f"command:{verb}"
        presentation = self.active_presentation
        if operation_id in self.operations and presentation is not None:
            self.driven_cells.add((presentation, operation_id))
        extra = ["--verb", verb, "--no-screenshot"]
        for key, value in arguments.items():
            extra.extend(("--arg", f"{key}={value}"))
        return self.controller("app-command", *extra)

    @property
    def active_presentation(self) -> str | None:
        if self.segment is not None:
            return str(self.segment["presentation"])
        selected = list(getattr(self.arguments, "presentations", []))
        return selected[0] if len(selected) == 1 else None

    def mark_driven(self, presentation: str, operation_id: str) -> None:
        if operation_id in self.operations:
            self.driven_cells.add((presentation, operation_id))

    def channel_health_probe(self, phase: str) -> dict[str, Any]:
        session_id = self.session_id
        payload = (
            f"reachability-channel-health phase={phase} session={session_id} "
            f"nonce={uuid.uuid4()}\n"
        ).encode("utf-8")
        source = self.raw / f"channel-health-{phase}-source.txt"
        returned = self.raw / f"channel-health-{phase}-returned.txt"
        empty = self.raw / "channel-health-empty.txt"
        source.write_bytes(payload)
        empty.write_bytes(b"")
        commands = (
            (
                "to",
                "--source", str(source),
                "--destination", CHANNEL_HEALTH_REMOTE_PATH,
            ),
            (
                "from",
                "--source", CHANNEL_HEALTH_REMOTE_PATH,
                "--destination", str(returned),
            ),
            (
                "to",
                "--source", str(empty),
                "--destination", CHANNEL_HEALTH_REMOTE_PATH,
            ),
        )
        transfers: list[dict[str, Any]] = []
        for direction, *copy_arguments in commands:
            started = time.monotonic()
            try:
                completed = subprocess.run(
                    [
                        "xcrun", "devicectl", "device", "copy", direction,
                        "--device", CORE_DEVICE,
                        "--domain-type", "appDataContainer",
                        "--domain-identifier", APP_BUNDLE,
                        *copy_arguments,
                    ],
                    cwd=ROOT,
                    env={"DEVELOPER_DIR": DEVELOPER_DIR, "PATH": "/usr/bin:/bin"},
                    capture_output=True,
                    text=True,
                    timeout=30,
                    check=False,
                )
                transfers.append({
                    "direction": direction,
                    "passed": completed.returncode == 0,
                    "elapsedSeconds": round(time.monotonic() - started, 3),
                    "detail": (completed.stderr or completed.stdout)[-1000:],
                })
            except subprocess.TimeoutExpired:
                transfers.append({
                    "direction": direction,
                    "passed": False,
                    "elapsedSeconds": round(time.monotonic() - started, 3),
                    "detail": "The 30-second channel-health transfer deadline expired.",
                })
                break
        returned_bytes = returned.read_bytes() if returned.is_file() else b""
        digest = hashlib.sha256(payload).hexdigest()
        returned_digest = hashlib.sha256(returned_bytes).hexdigest()
        passed = (
            len(transfers) == 3
            and all(transfer["passed"] for transfer in transfers)
            and returned_bytes == payload
            and isinstance(session_id, str)
            and bool(session_id)
        )
        result = {
            "phase": phase,
            "sessionID": session_id,
            "passed": passed,
            "byteCount": len(payload),
            "sha256": digest,
            "returnedSha256": returned_digest,
            "transfers": transfers,
            "source": f"raw/{source.name}",
            "returned": f"raw/{returned.name}",
        }
        health_path = self.raw / f"channel-health-{phase}.json"
        health_path.write_text(
            json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        self.events.append({
            "at": utc_now(),
            "action": "channelHealth",
            "phase": phase,
            "success": passed,
            "evidence": f"raw/{health_path.name}",
        })
        self.channel_health[phase] = result
        return result

    def copy_probe(self, label: str, *, timeout: float = 150) -> list[str]:
        if (
            self.segment is not None
            and self.channel_failures
            and label != "segment-after-surface"
        ):
            self.events.append({
                "at": utc_now(),
                "action": "copyProbe",
                "success": False,
                "detail": "Skipped after segment channel continuity failed.",
            })
            return []
        destination = self.raw / f"{self.sequence + 1:03d}-{label}-probe.log"
        try:
            completed = subprocess.run(
                [
                    "xcrun", "devicectl", "device", "copy", "from",
                    "--device", CORE_DEVICE,
                    "--domain-type", "appDataContainer",
                    "--domain-identifier", APP_BUNDLE,
                    "--source", PROBE_REMOTE_PATH,
                    "--destination", str(destination),
                ],
                cwd=ROOT,
                env={"DEVELOPER_DIR": DEVELOPER_DIR, "PATH": "/usr/bin:/bin"},
                capture_output=True,
                text=True,
                timeout=timeout,
                check=False,
            )
        except subprocess.TimeoutExpired:
            if self.segment is not None and timeout >= 120:
                self.channel_failures.append({
                    "at": utc_now(),
                    "action": "copyProbe",
                    "error": f"Device probe copy exceeded {timeout:.1f} seconds.",
                })
            self.events.append({
                "at": utc_now(), "action": "copyProbe", "success": False,
                "detail": f"Device probe copy exceeded {timeout:.1f} seconds.",
            })
            return []
        if completed.returncode != 0 or not destination.is_file():
            self.events.append({
                "at": utc_now(), "action": "copyProbe", "success": False,
                "detail": (completed.stderr or completed.stdout)[-1000:],
            })
            return []
        lines = destination.read_text(encoding="utf-8", errors="replace").splitlines()
        self.events.append({
            "at": utc_now(), "action": "copyProbe", "success": True,
            "evidence": f"raw/{destination.name}", "lineCount": len(lines),
        })
        return lines

    def wait_for_probe(
        self,
        label: str,
        offset: int,
        needle: str,
        *,
        timeout: float = 20.0,
    ) -> list[str]:
        deadline = time.monotonic() + timeout
        probe: list[str] = []
        attempt = 0
        while time.monotonic() < deadline:
            remaining = max(1.0, deadline - time.monotonic())
            probe = self.copy_probe(
                f"{label}-{attempt}",
                timeout=min(3.0, remaining),
            )
            if any(needle in line for line in probe[offset:]):
                return probe
            attempt += 1
            time.sleep(0.5)
        return probe

    def clear_probe_after_archive(self) -> bool:
        empty = self.raw / "probe-empty.log"
        empty.write_text("", encoding="utf-8")
        completed = subprocess.run(
            [
                "xcrun", "devicectl", "device", "copy", "to",
                "--device", CORE_DEVICE,
                "--domain-type", "appDataContainer",
                "--domain-identifier", APP_BUNDLE,
                "--source", str(empty),
                "--destination", PROBE_REMOTE_PATH,
            ],
            cwd=ROOT,
            env={"DEVELOPER_DIR": DEVELOPER_DIR, "PATH": "/usr/bin:/bin"},
            capture_output=True,
            text=True,
            timeout=150,
            check=False,
        )
        self.events.append({
            "at": utc_now(),
            "action": "clearProbeAfterArchive",
            "success": completed.returncode == 0,
            "detail": (completed.stderr or completed.stdout)[-1000:],
        })
        return completed.returncode == 0

    def stage_fixture(self, file_name: str) -> bool:
        source = FIXTURE_SOURCE_ROOT / file_name
        if not source.is_file():
            self.events.append({
                "at": utc_now(),
                "action": "stageFixture",
                "success": False,
                "detail": f"Fixture is missing: {source}",
            })
            return False
        existing = self.app_command("importMedia", file=file_name)
        if existing.get("success") is True:
            self.events.append({
                "at": utc_now(),
                "action": "stageFixture",
                "fixture": file_name,
                "success": True,
                "detail": (
                    "Reused the existing harness-owned TestMediaInbox file; "
                    "resetState will remove the temporary library reference."
                ),
                "evidence": self.events[-1]["evidence"],
            })
            return True
        missing_message = f"TestMediaInbox does not contain {file_name}."
        if missing_message not in json.dumps(existing, ensure_ascii=False):
            self.events.append({
                "at": utc_now(),
                "action": "stageFixture",
                "fixture": file_name,
                "success": False,
                "detail": (
                    "The staged-file check failed outside the product's "
                    "missing-file condition; the fixture was not recopied."
                ),
                "evidence": self.events[-1]["evidence"],
            })
            return False
        try:
            completed = subprocess.run(
                [
                    "xcrun", "devicectl", "device", "copy", "to",
                    "--device", CORE_DEVICE,
                    "--domain-type", "appDataContainer",
                    "--domain-identifier", APP_BUNDLE,
                    "--source", str(source),
                    "--destination", f"Documents/TestMediaInbox/{file_name}",
                ],
                cwd=ROOT,
                env={"DEVELOPER_DIR": DEVELOPER_DIR, "PATH": "/usr/bin:/bin"},
                capture_output=True,
                text=True,
                timeout=300,
                check=False,
            )
        except subprocess.TimeoutExpired:
            self.events.append({
                "at": utc_now(),
                "action": "stageFixture",
                "fixture": file_name,
                "success": False,
                "detail": "Fixture copy exceeded the 300-second transport deadline.",
            })
            return False
        self.events.append({
            "at": utc_now(),
            "action": "stageFixture",
            "fixture": file_name,
            "success": completed.returncode == 0,
            "detail": (completed.stderr or completed.stdout)[-1000:],
        })
        return completed.returncode == 0

    def mark_observation(
        self,
        presentation: str,
        operation_id: str,
        *,
        exists: bool | None = None,
        hittable: bool | None = None,
        received: bool | None = None,
        evidence: str,
        reason: str,
    ) -> None:
        cell = self.cells[(presentation, operation_id)]
        if not cell["applicable"]:
            return
        if exists is not None:
            cell["existsInHierarchy"] = bool(cell["existsInHierarchy"] or exists)
        if hittable is not None:
            cell["reportsHittable"] = bool(cell["reportsHittable"] or hittable)
        if received is not None:
            cell["applicationReceived"] = bool(cell["applicationReceived"] or received)
        cell["evidence"].append(evidence)
        cell["reason"] = reason
        if reachability_evidence_is_complete(cell):
            cell["verdict"] = "reachable"
        elif cell["existsInHierarchy"] is True and cell["reportsHittable"] is False:
            cell["verdict"] = "known-defect"

    @staticmethod
    def hierarchy_identifiers(document: dict[str, Any]) -> set[str]:
        hierarchy = document.get("hierarchy")
        if not isinstance(hierarchy, str):
            return set()
        return set(re.findall(r"identifier: '([^']+)'", hierarchy))

    def observe(self, presentation: str, label: str) -> dict[str, Any]:
        document = self.controller("snapshot", "--no-screenshot")
        hierarchy_identifiers = sorted(
            identifier for identifier in self.hierarchy_identifiers(document)
            if identifier.partition("-")[0] in self.inventory["identifierFamilies"]
        )
        evidence = self.events[-1]["evidence"]
        for operation_id, operation in self.operations.items():
            template = operation.get("identifierTemplate")
            if not isinstance(template, str):
                continue
            exists = any(
                template_pattern(template).match(identifier)
                for identifier in hierarchy_identifiers
            )
            if exists:
                self.mark_observation(
                    presentation,
                    operation_id,
                    exists=True,
                    evidence=evidence,
                    reason=(
                        f"Observed during {label}; hittability requires an actual action "
                        "response and delivery requires product evidence."
                    ),
                )
        return document

    def tap(
        self,
        presentation: str,
        identifier: str,
        *,
        operation_id: str | None = None,
    ) -> dict[str, Any]:
        operation_id = operation_id or f"accessibility:{identifier}"
        self.mark_driven(presentation, operation_id)
        document = self.controller(
            "tap", "--identifier", identifier,
            "--no-screenshot", "--timeout-seconds", "90", timeout=120,
        )
        matched = document.get("matchedElement")
        if operation_id in self.operations and isinstance(matched, dict):
            self.mark_observation(
                presentation,
                operation_id,
                exists=True,
                hittable=matched.get("isHittable") is True,
                evidence=self.events[-1]["evidence"],
                reason="XCTest located the target; product delivery is judged separately.",
            )
        return document

    def tap_label(
        self,
        presentation: str,
        label: str,
        *,
        operation_id: str | None = None,
    ) -> dict[str, Any]:
        if operation_id is not None:
            self.mark_driven(presentation, operation_id)
        document = self.controller(
            "tap", "--label", label,
            "--no-screenshot", "--timeout-seconds", "90", timeout=120,
        )
        matched = document.get("matchedElement")
        if operation_id in self.operations and isinstance(matched, dict):
            self.mark_observation(
                presentation,
                operation_id,
                exists=True,
                hittable=matched.get("isHittable") is True,
                evidence=self.events[-1]["evidence"],
                reason="XCTest located the target; product delivery is judged separately.",
            )
        return document

    def delivered(
        self,
        presentation: str,
        operation_id: str,
        evidence: str,
        reason: str,
        *,
        has_accessibility_target: bool = True,
    ) -> None:
        self.mark_driven(presentation, operation_id)
        self.mark_observation(
            presentation,
            operation_id,
            exists=True if has_accessibility_target else None,
            hittable=True if has_accessibility_target else None,
            received=True,
            evidence=evidence,
            reason=reason,
        )

    def delivered_by_debug_menu_selection(
        self,
        presentation: str,
        operation_id: str,
        parent_operation_id: str,
        evidence: str,
        reason: str,
    ) -> bool:
        parent = self.cells[(presentation, parent_operation_id)]
        if not (
            parent["existsInHierarchy"] is True
            and parent["reportsHittable"] is True
        ):
            return False
        self.mark_observation(
            presentation,
            operation_id,
            exists=True,
            hittable=True,
            received=True,
            evidence=evidence,
            reason=reason,
        )
        return True

    def select_debug_menu_item(
        self,
        *,
        presentation: str,
        host: str,
        family: str,
        preferred: tuple[str, ...] = (),
        driven_operations: tuple[str, ...] = (),
    ) -> tuple[str | None, dict[str, Any], dict[str, Any]]:
        for operation_id in driven_operations:
            self.mark_driven(presentation, operation_id)
        listing = self.app_command(
            "listMenuItems",
            host=host,
            family=family,
        )
        if listing.get("success") is not True and "file node" in str(
            listing.get("error", "")
        ):
            time.sleep(0.5)
            listing = self.app_command(
                "listMenuItems",
                host=host,
                family=family,
            )
        if listing.get("success") is not True:
            return None, listing, {"success": False}
        self.delivered(
            presentation,
            "command:listMenuItems",
            self.events[-1]["evidence"],
            "The visible product host enumerated its current menu items.",
            has_accessibility_target=False,
        )
        target = menu_selection_target(listing, preferred=preferred)
        if target is None:
            return None, listing, {"success": False}
        selected = self.app_command(
            "selectMenuItem",
            host=host,
            family=family,
            target=target,
        )
        if selected.get("success") is True:
            self.delivered(
                presentation,
                "command:selectMenuItem",
                self.events[-1]["evidence"],
                "The visible product host invoked its shared menu selection handler.",
                has_accessibility_target=False,
            )
        return target, listing, selected

    def wait_for_identifier(
        self, identifier: str, *, timeout: float = 40.0
    ) -> dict[str, Any]:
        deadline = time.monotonic() + timeout
        latest: dict[str, Any] = {}
        while time.monotonic() < deadline:
            latest = self.controller(
                "snapshot", "--identifier", identifier, "--no-screenshot"
            )
            if isinstance(latest.get("matchedElement"), dict):
                return latest
            time.sleep(1)
        return latest

    def wait_for_any_identifier(
        self, identifiers: tuple[str, ...], *, timeout: float = 40.0
    ) -> tuple[str | None, dict[str, Any]]:
        deadline = time.monotonic() + timeout
        latest: dict[str, Any] = {}
        while time.monotonic() < deadline:
            latest = self.controller("snapshot", "--no-screenshot")
            visible = self.hierarchy_identifiers(latest)
            for identifier in identifiers:
                if identifier in visible:
                    return identifier, latest
            time.sleep(1)
        return None, latest

    def relaunch(self) -> None:
        self.controller("relaunch", "--no-screenshot", timeout=180)
        time.sleep(1)

    def ensure_session(self) -> bool:
        ready = self.controller(
            "ensure-session",
            "--destination-id",
            DEVICE,
            "--no-screenshot",
            timeout=420,
        )
        session_id = ready.get("sessionID")
        if ready.get("success") is True and isinstance(session_id, str):
            self.session_id = session_id
            return True
        return False

    def show_controls(self) -> dict[str, Any]:
        result = self.app_command("toggleControls", visible="true")
        if result.get("success") is not True and "file node" in str(
            result.get("error", "")
        ):
            time.sleep(0.5)
            result = self.app_command("toggleControls", visible="true")
        presentation = self.active_presentation
        if result.get("success") is True and presentation is not None:
            self.delivered(
                presentation,
                "command:toggleControls",
                self.events[-1]["evidence"],
                "The DEBUG command reached the product control-visibility handler and returned success.",
                has_accessibility_target=False,
            )
        return result

    def tap_control(
        self,
        presentation: str,
        identifier: str,
        *,
        operation_id: str | None = None,
    ) -> dict[str, Any]:
        self.show_controls()
        return self.tap(presentation, identifier, operation_id=operation_id)

    def tap_with_fresh_controls(
        self,
        presentation: str,
        identifier: str,
        *,
        probe_label: str,
    ) -> tuple[dict[str, Any], list[str]]:
        before = self.copy_probe(probe_label)
        self.show_controls()
        return self.tap(presentation, identifier), before

    def reset_reachability_state(self) -> dict[str, Any]:
        return self.app_command(
            "resetState",
            libraryFolder=REACHABILITY_LIBRARY_FOLDER,
        )

    def browser_scenario(self) -> None:
        presentation = "window"
        self.relaunch()
        self.observe(presentation, "browser launch")
        before = self.copy_probe("browser-before")
        self.probe_offset = len(before)

        for identifier, tab in (
            ("Navigation-Ornament-tab-settings", "settings"),
            ("Navigation-Ornament-tab-files", "files"),
            ("Emby-Navigation-Tab", "emby"),
        ):
            response = self.tap(presentation, identifier)
            time.sleep(0.5)
            probe = self.copy_probe(f"navigation-{tab}")
            if response.get("success") is True and any(
                f"navigation tab delivered tab={tab}" in line
                for line in probe[self.probe_offset:]
            ):
                self.delivered(
                    presentation,
                    f"accessibility:{identifier}",
                    self.events[-1]["evidence"],
                    "The navigation handler appended its tab-specific application probe.",
                )
            self.probe_offset = len(probe)

            if tab == "settings":
                before = self.copy_probe("settings-category-before")
                offset = len(before)
                category = self.tap(
                    presentation, "Settings-category-storagePrivacy"
                )
                probe = self.copy_probe("settings-category-selected")
                if category.get("success") is True and any(
                    "reachability settings delivered action=category.storagePrivacy"
                    in line for line in probe[offset:]
                ):
                    self.delivered(
                        presentation,
                        "accessibility:Settings-category-{item.id}",
                        self.events[-1]["evidence"],
                        "The Settings category row changed the product selection and appended its category probe.",
                    )
                self.probe_offset = len(probe)

        self.observe(presentation, "Emby home")
        emby = self.app_command("scrollEmby", page="home", direction="forward")
        if emby.get("success") is True:
            self.delivered(
                presentation, "scroll:emby", self.events[-1]["evidence"],
                "The visible Emby page accepted the request and reported the handled page.",
                has_accessibility_target=False,
            )
        self.observe(presentation, "Emby after forward pagination")

        environment = self.tap(
            presentation, "Navigation-Ornament-tab-environment"
        )
        opened_probe = self.copy_probe("environment-open")
        if any(
            "navigation tab delivered tab=environment" in line
            for line in opened_probe[self.probe_offset:]
        ):
            self.delivered(
                presentation,
                "accessibility:Navigation-Ornament-tab-environment",
                self.events[-1]["evidence"],
                "The navigation handler appended the environment-tab application probe.",
            )
        self.probe_offset = len(opened_probe)
        volume = self.wait_for_identifier("SenseZone-VolumeRoot")
        effect_ids = sorted(
            identifier for identifier in self.hierarchy_identifiers(volume)
            if identifier.startswith("EnvironmentCard-effect-")
        )
        effect_delivered = False
        if effect_ids:
            self.tap(presentation, effect_ids[0], operation_id=(
                "accessibility:EnvironmentCard-effect-"
                "{environment.environment.rawValue}"
            ))
            time.sleep(0.5)
            probe = self.copy_probe("environment-effect")
            effect_delivered = any(
                "environmentCard effect delivered" in line
                for line in probe[self.probe_offset:]
            )
            self.probe_offset = len(probe)
            if effect_delivered:
                self.delivered(
                    presentation,
                    "accessibility:EnvironmentCard-effect-"
                    "{environment.environment.rawValue}",
                    self.events[-1]["evidence"],
                    "The Environment Card handler appended the selected effect probe.",
                )
        dismiss = self.app_command("dismissEnvironmentCard")
        closed = self.wait_for_identifier("SenseZone-VolumeRoot", timeout=8)
        if (
            environment.get("success") is True
            and isinstance(volume.get("matchedElement"), dict)
            and effect_delivered
            and dismiss.get("success") is True
            and not isinstance(closed.get("matchedElement"), dict)
        ):
            self.delivered(
                presentation,
                "environmentVolume:open-interact-close",
                self.events[-1]["evidence"],
                "Open, effect interaction, and application-driven close each produced device evidence.",
                has_accessibility_target=False,
            )
        probe = self.copy_probe("environment-close")
        self.probe_offset = len(probe)

        self.tap(presentation, "Navigation-Ornament-tab-files")
        before = self.copy_probe("browser-folder-before")
        offset = len(before)
        folder = self.tap(
            presentation,
            f"MediaLibrary-grid-folder-{REACHABILITY_LIBRARY_FOLDER}",
            operation_id="accessibility:MediaLibrary-grid-folder-{folder.name}",
        )
        if folder.get("success") is not True:
            folder = self.tap(
                presentation,
                f"FileBrowsing-grid-folder-{REACHABILITY_LIBRARY_FOLDER}",
                operation_id="accessibility:FileBrowsing-grid-folder-{folder.name}",
            )
        probe = self.copy_probe("browser-folder-open")
        if folder.get("success") is True:
            if any(
                "reachability files delivered action=library.folder" in line
                for line in probe[offset:]
            ):
                self.delivered(
                    presentation,
                    "accessibility:MediaLibrary-grid-folder-{folder.name}",
                    self.events[-1]["evidence"],
                    "The Media Library card ran its folder navigation handler.",
                )
            elif any(
                "reachability files delivered action=remote.folder" in line
                for line in probe[offset:]
            ):
                self.delivered(
                    presentation,
                    "accessibility:FileBrowsing-grid-folder-{folder.name}",
                    self.events[-1]["evidence"],
                    "The remote browser card ran its folder navigation handler.",
                )
        self.probe_offset = len(probe)
        self.observe(presentation, "file folder")
        scroll = self.controller(
            "swipeUp", "--identifier", "FileBrowsing-FilesScreen-list",
            "--no-screenshot", timeout=90,
        )
        time.sleep(0.5)
        probe = self.copy_probe("file-scroll")
        if scroll.get("success") is True and any(
            "reachability fileScroll" in line for line in probe[self.probe_offset:]
        ):
            self.delivered(
                presentation, "scroll:file-list", self.events[-1]["evidence"],
                "The Files scroll geometry callback appended an offset probe.",
                has_accessibility_target=False,
            )

    def prove_navigation_tab(self, tab: str) -> bool:
        presentation = "window"
        identifiers = {
            "files": "Navigation-Ornament-tab-files",
            "settings": "Navigation-Ornament-tab-settings",
        }
        identifier = identifiers[tab]
        self.relaunch()
        before = self.copy_probe(f"segment-navigation-{tab}-before")
        offset = len(before)
        response = self.tap(presentation, identifier)
        probe = self.copy_probe(f"segment-navigation-{tab}")
        delivered = response.get("success") is True and any(
            f"navigation tab delivered tab={tab}" in line
            for line in probe[offset:]
        )
        if delivered:
            self.delivered(
                presentation,
                f"accessibility:{identifier}",
                self.events[-1]["evidence"],
                "The segment prerequisite navigation reached its product handler and appended the tab probe.",
            )
        return delivered

    def open_source_connection(
        self, source: str
    ) -> tuple[dict[str, Any], list[str]]:
        presentation = "window"
        before = self.copy_probe(f"source-connection-{source}-open-before")
        offset = len(before)
        parent = self.tap(
            presentation, "FileBrowsing-SourcesSidebar-sourceMore"
        )
        source_value = "smb" if source == "SMB" else "webDAV"
        _, _, opened = self.select_debug_menu_item(
            presentation=presentation,
            host="files",
            family="sourceAdd",
            preferred=(source_value,),
            driven_operations=(
                f"accessibility:FileBrowsing-SourcesSidebar-add{source}",
            ),
        )
        probe = self.copy_probe(f"source-connection-{source}-opened")
        recent = probe[offset:]
        if parent.get("success") is True and opened.get("success") is True and any(
            "reachability files delivered action=sourceSidebar.sourceMore" in line
            for line in recent
        ):
            self.delivered(
                presentation,
                "accessibility:FileBrowsing-SourcesSidebar-sourceMore",
                self.events[-1]["evidence"],
                "Opening the source menu constructed its product-owned actions and appended a probe.",
            )
        if parent.get("success") is True and opened.get("success") is True and any(
            f"reachability files delivered action=sidebar.add.{source_value}" in line
            for line in recent
        ):
            self.delivered_by_debug_menu_selection(
                presentation,
                f"accessibility:FileBrowsing-SourcesSidebar-add{source}",
                "accessibility:FileBrowsing-SourcesSidebar-sourceMore",
                self.events[-1]["evidence"],
                "The named source menu was hittable; the DEBUG equivalent ran the "
                "source-type product action and presented its connection form.",
            )
        return opened, probe

    def type_source_connection_field(
        self, source: str, field: str, value: str, probe: list[str]
    ) -> list[str]:
        presentation = "window"
        self.mark_driven(
            presentation,
            f"accessibility:FileBrowsing-SourceConnection-{source}-{field}",
        )
        offset = len(probe)
        typed = self.controller(
            "typeText",
            "--identifier",
            f"FileBrowsing-SourceConnection-{source}-{field}",
            "--text",
            value,
            "--no-screenshot",
            timeout=90,
        )
        updated = self.wait_for_probe(
            f"source-connection-{source}-{field}",
            offset,
            f"reachability files delivered action=sourceConnection.{source}.{field}",
        )
        if typed.get("success") is True and any(
            f"reachability files delivered action=sourceConnection.{source}.{field}"
            in line for line in updated[offset:]
        ):
            self.delivered(
                presentation,
                f"accessibility:FileBrowsing-SourceConnection-{source}-{field}",
                self.events[-1]["evidence"],
                "Typing changed the source-specific form binding and appended its field probe.",
            )
        return updated

    def source_connection_scenario(self, source: str) -> None:
        presentation = "window"
        self.relaunch()
        self.tap(presentation, "Navigation-Ornament-tab-files")
        opened, probe = self.open_source_connection(
            "SMB" if source == "smb" else "WebDAV"
        )
        if opened.get("success") is not True:
            return
        if not isinstance(
            self.wait_for_identifier(
                f"FileBrowsing-SourceConnection-{source}-address", timeout=10
            ).get("matchedElement"),
            dict,
        ):
            return

        for field, value in (
            ("name", f"Reachability {source}"),
            ("address", "127.0.0.1"),
            ("username", "reachability"),
            ("password", "not-a-secret"),
        ):
            probe = self.type_source_connection_field(
                source, field, value, probe
            )

        if source == "smb":
            offset = len(probe)
            guest = self.tap(
                presentation, "FileBrowsing-SourceConnection-smb-guest"
            )
            probe = self.wait_for_probe(
                "source-connection-smb-guest",
                offset,
                "reachability files delivered action=sourceConnection.smb.guest",
            )
            if guest.get("success") is True and any(
                "reachability files delivered action=sourceConnection.smb.guest"
                in line for line in probe[offset:]
            ):
                self.delivered(
                    presentation,
                    "accessibility:FileBrowsing-SourceConnection-smb-guest",
                    self.events[-1]["evidence"],
                    "The guest toggle changed the SMB form binding and appended its probe.",
                )

        offset = len(probe)
        connected = self.tap(
            presentation,
            f"FileBrowsing-SourceConnection-{source}-connect",
        )
        probe = self.wait_for_probe(
            f"source-connection-{source}-connect",
            offset,
            f"reachability files delivered action=sourceConnection.{source}.connect",
        )
        if connected.get("success") is True and any(
            f"reachability files delivered action=sourceConnection.{source}.connect"
            in line for line in probe[offset:]
        ):
            self.delivered(
                presentation,
                f"accessibility:FileBrowsing-SourceConnection-{source}-connect",
                self.events[-1]["evidence"],
                "Connect delivered the source-specific request to FilesScreen before network resolution.",
            )

        self.relaunch()
        self.tap(presentation, "Navigation-Ornament-tab-files")
        opened, probe = self.open_source_connection(
            "SMB" if source == "smb" else "WebDAV"
        )
        if opened.get("success") is not True:
            return
        offset = len(probe)
        cancelled = self.tap(
            presentation,
            f"FileBrowsing-SourceConnection-{source}-cancel",
        )
        probe = self.wait_for_probe(
            f"source-connection-{source}-cancel",
            offset,
            f"reachability files delivered action=sourceConnection.{source}.cancel",
        )
        if cancelled.get("success") is True and any(
            f"reachability files delivered action=sourceConnection.{source}.cancel"
            in line for line in probe[offset:]
        ):
            self.delivered(
                presentation,
                f"accessibility:FileBrowsing-SourceConnection-{source}-cancel",
                self.events[-1]["evidence"],
                "Cancel ran the source-specific dismissal closure and appended its probe.",
            )

    def source_sidebar_scenario(self) -> None:
        presentation = "window"
        for identifier, family, target, expected_action in (
            ("addFiles", "sourceAdd", "local", "sidebar.add.local"),
            ("addFolder", "sourceAdd", "folder", "sidebar.addFolder"),
            ("addPhotos", "sourceAdd", "photoLibrary", "sidebar.add.photoLibrary"),
            ("refresh", "sourceAction", "refresh", "sidebar.refresh"),
        ):
            self.relaunch()
            self.tap(presentation, "Navigation-Ornament-tab-files")
            before = self.copy_probe(f"source-sidebar-{identifier}-before")
            offset = len(before)
            parent = self.tap(
                presentation, "FileBrowsing-SourcesSidebar-sourceMore"
            )
            _, _, response = self.select_debug_menu_item(
                presentation=presentation,
                host="files",
                family=family,
                preferred=(target,),
                driven_operations=(
                    f"accessibility:FileBrowsing-SourcesSidebar-{identifier}",
                ),
            )
            probe = self.copy_probe(f"source-sidebar-{identifier}")
            if parent.get("success") is True and response.get("success") is True and any(
                f"reachability files delivered action={expected_action}" in line
                for line in probe[offset:]
            ):
                self.delivered_by_debug_menu_selection(
                    presentation,
                    f"accessibility:FileBrowsing-SourcesSidebar-{identifier}",
                    "accessibility:FileBrowsing-SourcesSidebar-sourceMore",
                    self.events[-1]["evidence"],
                    "The named source menu was hittable; the DEBUG equivalent reached "
                    "the FilesScreen handler and appended its product action probe.",
                )

        self.relaunch()
        self.tap(presentation, "Navigation-Ornament-tab-files")
        before = self.copy_probe("source-sidebar-row-before")
        offset = len(before)
        selected = self.tap(
            presentation,
            "FileBrowsing-SourcesSidebar-source-media-library",
            operation_id=(
                "accessibility:FileBrowsing-SourcesSidebar-source-{item.id}"
            ),
        )
        probe = self.copy_probe("source-sidebar-row-selected")
        if selected.get("success") is True and any(
            "reachability files delivered action=sidebar.select.media-library" in line
            for line in probe[offset:]
        ):
            self.delivered(
                presentation,
                "accessibility:FileBrowsing-SourcesSidebar-source-{item.id}",
                self.events[-1]["evidence"],
                "The source row ran the product source-selection handler and appended its item probe.",
            )

    def file_browser_error_scenario(self) -> None:
        presentation = "window"
        self.relaunch()
        self.tap(presentation, "Navigation-Ornament-tab-files")

        for action in ("primary", "secondary"):
            before = self.copy_probe(f"file-browser-error-{action}-before")
            offset = len(before)
            shown = self.app_command(
                "showFileBrowserError",
                message=f"Reachability verification error: {action}",
            )
            if shown.get("success") is not True:
                return
            identifier = f"FileBrowsing-error-{action}"
            visible = self.wait_for_identifier(identifier, timeout=10)
            if not isinstance(visible.get("matchedElement"), dict):
                return
            tapped = self.tap(presentation, identifier)
            probe = self.wait_for_probe(
                f"file-browser-error-{action}",
                offset,
                f"reachability files delivered action=fileBrowserError.{action}",
            )
            if tapped.get("success") is True and any(
                f"reachability files delivered action=fileBrowserError.{action}"
                in line for line in probe[offset:]
            ):
                self.delivered(
                    presentation,
                    f"accessibility:{identifier}",
                    self.events[-1]["evidence"],
                    "The error-dialog action reached its FilesScreen handler and appended an action probe.",
                )

    def browser_condition_scenario(
        self, *, include_source_scenarios: bool = True
    ) -> None:
        presentation = "window"
        if include_source_scenarios:
            self.source_connection_scenario("smb")
            self.source_connection_scenario("webDAV")
            self.source_sidebar_scenario()
            self.file_browser_error_scenario()
        self.relaunch()
        self.tap(presentation, "Navigation-Ornament-tab-files")
        reference = self.wait_for_identifier(
            "MediaLibrary-grid-video-furyroad-stripped.mkv", timeout=5
        )
        if not isinstance(reference.get("matchedElement"), dict):
            self.app_command("importMedia", file="furyroad-stripped.mkv")
            self.relaunch()
            self.tap(presentation, "Navigation-Ornament-tab-files")

        before = self.copy_probe("browser-conditions-before")
        offset = len(before)
        sidebar = self.tap(presentation, "FileBrowsing-FilesScreen-sidebarToggle")
        probe = self.copy_probe("browser-sidebar-toggle")
        if sidebar.get("success") is True and any(
            "reachability files delivered action=files.sidebarToggle" in line
            for line in probe[offset:]
        ):
            self.delivered(
                presentation, "accessibility:FileBrowsing-FilesScreen-sidebarToggle",
                self.events[-1]["evidence"],
                "The sidebar binding changed and appended its application probe.",
            )
        self.tap(presentation, "FileBrowsing-FilesScreen-sidebarToggle")

        before = self.copy_probe("browser-view-mode-before")
        offset = len(before)
        view_mode = self.tap(presentation, "FileBrowsing-FilesScreen-viewMode")
        probe = self.copy_probe("browser-view-mode")
        if view_mode.get("success") is True and any(
            "reachability files delivered action=files.viewMode" in line
            for line in probe[offset:]
        ):
            self.delivered(
                presentation, "accessibility:FileBrowsing-FilesScreen-viewMode",
                self.events[-1]["evidence"],
                "The view-mode gesture changed the screen-local product binding.",
            )

        before = self.copy_probe("browser-sort-before")
        offset = len(before)
        parent = self.tap(presentation, "FileBrowsing-FilesScreen-sort")
        target, _, sort = self.select_debug_menu_item(
            presentation=presentation,
            host="files",
            family="sortKey",
            preferred=("size", "modifiedDate", "name"),
        )
        probe = self.copy_probe("browser-sort-selected")
        if parent.get("success") is True and sort.get("success") is True and any(
            "reachability files delivered action=files.sort" in line
            for line in probe[offset:]
        ):
            self.delivered_by_debug_menu_selection(
                presentation,
                "accessibility:FileBrowsing-FilesScreen-sort",
                "accessibility:FileBrowsing-FilesScreen-sort",
                self.events[-1]["evidence"],
                "The named sort parent was hittable; the DEBUG equivalent selected "
                f"target={target} through the Picker binding and its product onChange probe.",
            )
        if target is not None:
            self.controller("tap", "--label", "Size", "--no-screenshot")

        before = self.copy_probe("browser-search-before")
        offset = len(before)
        search = self.controller(
            "typeText", "--identifier", "FileBrowsing-FilesScreen-search",
            "--text", "fury", "--no-screenshot", timeout=90,
        )
        probe = self.copy_probe("browser-search-typed")
        if search.get("success") is True and any(
            "reachability files delivered action=files.search" in line
            for line in probe[offset:]
        ):
            self.delivered(
                presentation, "accessibility:FileBrowsing-FilesScreen-search",
                self.events[-1]["evidence"],
                "Typing changed the browser search binding and appended a probe.",
            )

        self.relaunch()
        self.tap(presentation, "Navigation-Ornament-tab-files")
        before = self.copy_probe("browser-new-folder-before")
        offset = len(before)
        parent = self.tap(presentation, "FileBrowsing-Manage-button")
        _, _, opened = self.select_debug_menu_item(
            presentation=presentation,
            host="files",
            family="manage",
            preferred=("newFolder",),
            driven_operations=(
                "accessibility:MediaLibrary-Manage-newFolder",
            ),
        )
        probe = self.copy_probe("browser-new-folder-open")
        recent = probe[offset:]
        if parent.get("success") is True and any(
            "reachability files delivered action=manage.open" in line
            for line in recent
        ):
            self.delivered(
                presentation,
                "accessibility:FileBrowsing-Manage-button",
                self.events[-1]["evidence"],
                "The named Manage menu was hittable and constructed its product actions.",
            )
        if opened.get("success") is True and any(
            "reachability files delivered action=manage.newFolder" in line
            for line in recent
        ):
            self.delivered_by_debug_menu_selection(
                presentation,
                "accessibility:MediaLibrary-Manage-newFolder",
                "accessibility:FileBrowsing-Manage-button",
                self.events[-1]["evidence"],
                "The named Manage parent was hittable; the DEBUG equivalent entered "
                "the product new-folder action and its probe confirmed delivery.",
            )
        before = probe
        offset = len(before)
        typed = self.controller(
            "typeText", "--identifier", "MediaLibrary-NewFolder-name",
            "--text", "Reachability Round 2", "--no-screenshot", timeout=90,
        )
        probe = self.copy_probe("browser-new-folder-name")
        if typed.get("success") is True and any(
            "reachability files delivered action=newFolder.name" in line
            for line in probe[offset:]
        ):
            self.delivered(
                presentation, "accessibility:MediaLibrary-NewFolder-name",
                self.events[-1]["evidence"],
                "Typing changed the new-folder name binding and appended a probe.",
            )
        before = probe
        offset = len(before)
        created = self.tap(presentation, "MediaLibrary-NewFolder-create")
        probe = self.copy_probe("browser-new-folder-created")
        if created.get("success") is True and any(
            "reachability files delivered action=newFolder.create" in line
            for line in probe[offset:]
        ):
            self.delivered(
                presentation, "accessibility:MediaLibrary-NewFolder-create",
                self.events[-1]["evidence"],
                "The confirmation invoked MediaLibrary.createFolder and appended a probe.",
            )

        error = self.wait_for_identifier("MediaLibrary-error-dismiss", timeout=5)
        if isinstance(error.get("matchedElement"), dict):
            before = self.copy_probe("browser-error-before")
            offset = len(before)
            dismissed = self.tap(presentation, "MediaLibrary-error-dismiss")
            probe = self.copy_probe("browser-error-dismissed")
            if dismissed.get("success") is True and any(
                "reachability files delivered action=mediaLibraryError.dismiss" in line
                for line in probe[offset:]
            ):
                self.delivered(
                    presentation, "accessibility:MediaLibrary-error-dismiss",
                    self.events[-1]["evidence"],
                    "The failed folder creation exposed the product error panel, whose dismiss closure appended a probe.",
                )
        else:
            before = probe
            offset = len(before)
            folder = self.tap(
                presentation, "MediaLibrary-grid-folder-Reachability Round 2",
                operation_id="accessibility:MediaLibrary-grid-folder-{folder.name}",
            )
            probe = self.copy_probe("browser-library-folder-open")
            if folder.get("success") is True and any(
                "reachability files delivered action=library.folder" in line
                for line in probe[offset:]
            ):
                self.delivered(
                    presentation, "accessibility:MediaLibrary-grid-folder-{folder.name}",
                    self.events[-1]["evidence"],
                    "Opening the created folder ran the Media Library navigation handler.",
                )

            for direction in ("back", "forward"):
                before = probe
                offset = len(before)
                navigation = self.tap(
                    presentation,
                    f"FileBrowsing-FilesScreen-navBackForward-{direction}",
                )
                probe = self.copy_probe(f"browser-navigation-{direction}")
                if navigation.get("success") is True and any(
                    f"reachability files delivered action=files.nav.{direction}"
                    in line for line in probe[offset:]
                ):
                    self.delivered(
                        presentation,
                        "accessibility:FileBrowsing-FilesScreen-"
                        f"navBackForward-{direction}",
                        self.events[-1]["evidence"],
                        "The navigation button reached the corresponding browser history handler.",
                    )

            # Return through the product breadcrumb before exercising root-only
            # multi-selection controls. The named parent supplies structural
            # evidence; the equivalent selection enters the same callback as the
            # system Picker item.
            before = probe
            offset = len(before)
            parent = self.tap(
                presentation, "MediaLibrary-Breadcrumb-current"
            )
            _, _, selected = self.select_debug_menu_item(
                presentation=presentation,
                host="mediaLibrary",
                family="breadcrumb",
                preferred=("0",),
                driven_operations=(
                    "accessibility:MediaLibrary-Breadcrumb-current",
                ),
            )
            probe = self.copy_probe("browser-library-breadcrumb-root")
            if (
                parent.get("success") is True
                and selected.get("success") is True
                and any(
                    "reachability files delivered "
                    "action=breadcrumb.mediaLibrary" in line
                    for line in probe[offset:]
                )
            ):
                self.delivered_by_debug_menu_selection(
                    presentation,
                    "accessibility:MediaLibrary-Breadcrumb-current",
                    "accessibility:MediaLibrary-Breadcrumb-current",
                    self.events[-1]["evidence"],
                    "The named breadcrumb was hittable; the DEBUG equivalent "
                    "entered its product navigation callback and the callback "
                    "probe confirmed delivery.",
                )
            self.controller(
                "tap", "--label", "Media Library", "--no-screenshot",
                timeout=90,
            )

        before = self.copy_probe("browser-multiselect-before")
        offset = len(before)
        parent = self.tap(presentation, "FileBrowsing-Manage-button")
        _, _, selection = self.select_debug_menu_item(
            presentation=presentation,
            host="files",
            family="manage",
            preferred=("selectMultiple",),
            driven_operations=(
                "accessibility:MediaLibrary-Manage-selectMultiple",
            ),
        )
        probe = self.copy_probe("browser-multiselect-open")
        if parent.get("success") is True and selection.get("success") is True and any(
            "reachability files delivered action=manage.selectMultiple" in line
            for line in probe[offset:]
        ):
            self.delivered_by_debug_menu_selection(
                presentation,
                "accessibility:MediaLibrary-Manage-selectMultiple",
                "accessibility:FileBrowsing-Manage-button",
                self.events[-1]["evidence"],
                "The named Manage parent was hittable; the DEBUG equivalent entered "
                "the product multi-selection action and its probe confirmed delivery.",
            )
        before = probe
        offset = len(before)
        reference = self.tap(
            presentation, "MediaLibrary-grid-video-furyroad-stripped.mkv",
            operation_id="accessibility:MediaLibrary-grid-video-{reference.name}",
        )
        probe = self.copy_probe("browser-reference-selected")
        if reference.get("success") is True and any(
            "reachability files delivered action=library.video" in line
            for line in probe[offset:]
        ):
            self.delivered(
                presentation, "accessibility:MediaLibrary-grid-video-{reference.name}",
                self.events[-1]["evidence"],
                "The library card ran its selection-aware activation handler.",
            )
        before = probe
        offset = len(before)
        done = self.tap(presentation, "MediaLibrary-MultiSelect-done")
        probe = self.copy_probe("browser-multiselect-done")
        if done.get("success") is True and any(
            "reachability files delivered action=multiSelect.done" in line
            for line in probe[offset:]
        ):
            self.delivered(
                presentation, "accessibility:MediaLibrary-MultiSelect-done",
                self.events[-1]["evidence"],
                "Done exited the product multi-selection state and appended a probe.",
            )

        # Re-enter selection so the system-owned Move To menu can keep its own
        # three-tier evidence without sacrificing the Done regression cell.
        self.tap(presentation, "FileBrowsing-Manage-button")
        self.select_debug_menu_item(
            presentation=presentation,
            host="files",
            family="manage",
            preferred=("selectMultiple",),
            driven_operations=(
                "accessibility:MediaLibrary-Manage-selectMultiple",
            ),
        )
        self.tap(
            presentation,
            "MediaLibrary-grid-video-furyroad-stripped.mkv",
            operation_id="accessibility:MediaLibrary-grid-video-{reference.name}",
        )
        before = self.copy_probe("browser-move-selection-before")
        offset = len(before)
        move_parent = self.tap(
            presentation, "MediaLibrary-MultiSelect-move"
        )
        _, _, moved = self.select_debug_menu_item(
            presentation=presentation,
            host="mediaLibrary",
            family="moveDestination",
            preferred=("root",),
        )
        probe = self.copy_probe("browser-move-selection")
        if (
            move_parent.get("success") is True
            and moved.get("success") is True
            and any(
                "reachability files delivered action=multiSelect.move" in line
                for line in probe[offset:]
            )
        ):
            self.delivered_by_debug_menu_selection(
                presentation,
                "accessibility:MediaLibrary-MultiSelect-move",
                "accessibility:MediaLibrary-MultiSelect-move",
                self.events[-1]["evidence"],
                "The named Move To parent was hittable; the DEBUG equivalent "
                "entered the shared move handler and its product probe confirmed "
                "delivery.",
            )

    def manage_add_scenario(self) -> None:
        presentation = "window"
        for target, expected_action in (
            ("addFiles", "manage.addFiles"),
            ("addFolder", "manage.addFolder"),
            ("addPhotos", "manage.addPhotos"),
        ):
            self.relaunch()
            self.tap(presentation, "Navigation-Ornament-tab-files")
            before = self.copy_probe(f"manage-{target}-before")
            offset = len(before)
            parent = self.tap(presentation, "FileBrowsing-Manage-button")
            self.mark_driven(
                presentation, f"accessibility:MediaLibrary-Manage-{target}"
            )
            _, _, selected = self.select_debug_menu_item(
                presentation=presentation,
                host="files",
                family="manage",
                preferred=(target,),
            )
            probe = self.copy_probe(f"manage-{target}-selected")
            if parent.get("success") is True and any(
                "reachability files delivered action=manage.open" in line
                for line in probe[offset:]
            ):
                self.delivered(
                    presentation,
                    "accessibility:FileBrowsing-Manage-button",
                    self.events[-1]["evidence"],
                    "The named Manage button constructed its product menu and appended the open probe.",
                )
            if (
                parent.get("success") is True
                and selected.get("success") is True
                and any(
                    f"reachability files delivered action={expected_action}" in line
                    for line in probe[offset:]
                )
            ):
                self.delivered_by_debug_menu_selection(
                    presentation,
                    f"accessibility:MediaLibrary-Manage-{target}",
                    "accessibility:FileBrowsing-Manage-button",
                    self.events[-1]["evidence"],
                    "The named Manage parent was hittable; the DEBUG equivalent "
                    f"entered the {target} product handler and its probe confirmed delivery.",
                )

    def settings_menu_scenario(self) -> None:
        presentation = "window"
        self.relaunch()
        self.tap(presentation, "Navigation-Ornament-tab-settings")
        self.tap(presentation, "Settings-category-playback", operation_id=(
            "accessibility:Settings-category-{item.id}"
        ))
        for family in (
            "resume-strategy",
            "end-behavior",
            "default-scenic-environment",
            "default-speed",
            "controls-auto-hide",
        ):
            operation_id = f"menu:settings:{family}"
            before = self.copy_probe(f"settings-{family}-before")
            offset = len(before)
            target, _, selected = self.select_debug_menu_item(
                presentation=presentation,
                host="settings",
                family=family,
                driven_operations=(operation_id,),
            )
            probe = self.copy_probe(f"settings-{family}-selected")
            if selected.get("success") is True and target is not None and any(
                f"reachability settings delivered action=menu.{family}" in line
                for line in probe[offset:]
            ):
                self.delivered(
                    presentation,
                    operation_id,
                    self.events[-1]["evidence"],
                    "The visible Settings host invoked its shared menu binding and appended the family probe.",
                    has_accessibility_target=False,
                )

    def library_reference_move_scenario(self) -> None:
        presentation = "window"
        self.relaunch()
        self.tap(presentation, "Navigation-Ornament-tab-files")
        imported = self.app_command("importMedia", file="furyroad-stripped.mkv")
        if imported.get("success") is True:
            self.relaunch()
            self.tap(presentation, "Navigation-Ornament-tab-files")
        before = self.copy_probe("library-reference-move-before")
        offset = len(before)
        target, _, moved = self.select_debug_menu_item(
            presentation=presentation,
            host="mediaLibrary",
            family="referenceMoveDestination",
        )
        probe = self.copy_probe("library-reference-move-selected")
        if moved.get("success") is True and target is not None and any(
            "reachability files delivered action=libraryReference.move" in line
            for line in probe[offset:]
        ):
            self.delivered(
                presentation,
                "command:selectMenuItem",
                self.events[-1]["evidence"],
                "The visible library reference host invoked the shared move handler and appended its product probe.",
                has_accessibility_target=False,
            )

    def breadcrumb_scenario(self) -> None:
        presentation = "window"
        self.relaunch()
        self.tap(presentation, "Navigation-Ornament-tab-files")
        folder = self.tap(
            presentation,
            f"MediaLibrary-grid-folder-{REACHABILITY_LIBRARY_FOLDER}",
            operation_id="accessibility:MediaLibrary-grid-folder-{folder.name}",
        )
        if folder.get("success") is True:
            before = self.copy_probe("media-library-breadcrumb-before")
            offset = len(before)
            parent = self.tap(presentation, "MediaLibrary-Breadcrumb-current")
            self.mark_driven(
                presentation, "accessibility:MediaLibrary-Breadcrumb-current"
            )
            _, _, selected = self.select_debug_menu_item(
                presentation=presentation,
                host="mediaLibrary",
                family="breadcrumb",
                preferred=("0",),
            )
            probe = self.copy_probe("media-library-breadcrumb-selected")
            if (
                parent.get("success") is True
                and selected.get("success") is True
                and any(
                    "reachability files delivered action=breadcrumb.mediaLibrary"
                    in line for line in probe[offset:]
                )
            ):
                self.delivered_by_debug_menu_selection(
                    presentation,
                    "accessibility:MediaLibrary-Breadcrumb-current",
                    "accessibility:MediaLibrary-Breadcrumb-current",
                    self.events[-1]["evidence"],
                    "The named Media Library breadcrumb was hittable; the DEBUG equivalent entered its navigation callback.",
                )

        self.relaunch()
        self.tap(presentation, "Navigation-Ornament-tab-files")
        sources = self.controller("snapshot", "--no-screenshot")
        source_identifiers = sorted(
            identifier
            for identifier in self.hierarchy_identifiers(sources)
            if identifier.startswith("FileBrowsing-SourcesSidebar-source-")
            and identifier != "FileBrowsing-SourcesSidebar-source-media-library"
        )
        if not source_identifiers:
            return
        before = self.copy_probe("files-source-before")
        offset = len(before)
        source = self.tap(
            presentation,
            source_identifiers[0],
            operation_id=(
                "accessibility:FileBrowsing-SourcesSidebar-source-{item.id}"
            ),
        )
        probe = self.wait_for_probe(
            "files-source-selected",
            offset,
            "reachability files delivered action=sidebar.select.",
        )
        if source.get("success") is True and any(
            "reachability files delivered action=sidebar.select." in line
            for line in probe[offset:]
        ):
            self.delivered(
                presentation,
                "accessibility:FileBrowsing-SourcesSidebar-source-{item.id}",
                self.events[-1]["evidence"],
                "The existing remote-source row ran the product selection handler and appended its item probe.",
            )
        visible = self.wait_for_identifier(
            "FileBrowsing-Breadcrumb-current", timeout=10
        )
        if not isinstance(visible.get("matchedElement"), dict):
            return
        before = self.copy_probe("files-breadcrumb-before")
        offset = len(before)
        parent = self.tap(presentation, "FileBrowsing-Breadcrumb-current")
        self.mark_driven(
            presentation, "accessibility:FileBrowsing-Breadcrumb-current"
        )
        _, _, selected = self.select_debug_menu_item(
            presentation=presentation,
            host="files",
            family="breadcrumb",
            preferred=("0",),
        )
        probe = self.copy_probe("files-breadcrumb-selected")
        if (
            parent.get("success") is True
            and selected.get("success") is True
            and any(
                "reachability files delivered action=breadcrumb.files" in line
                for line in probe[offset:]
            )
        ):
            self.delivered_by_debug_menu_selection(
                presentation,
                "accessibility:FileBrowsing-Breadcrumb-current",
                "accessibility:FileBrowsing-Breadcrumb-current",
                self.events[-1]["evidence"],
                "The named Files breadcrumb was hittable; the DEBUG equivalent entered its navigation callback.",
            )

    def player_panel_portal_menu_scenario(self) -> None:
        opened = self.open_media("MediaLibrary-grid-video-furyroad-stripped.mkv")
        if opened.get("success") is not True:
            return
        if not self.ensure_window_projection("180°"):
            return
        portal = self.wait_for_identifier(
            "PlayerUI-window-control-plane", timeout=45
        )
        value = str((portal.get("matchedElement") or {}).get("value", ""))
        if "presentation=portal" not in value:
            return
        self.player_panel_menu_scenario("portal")

    def open_media(self, identifier: str) -> dict[str, Any]:
        self.relaunch()
        self.tap("window", "Navigation-Ornament-tab-files")
        before = self.copy_probe("open-media-before")
        offset = len(before)
        self.controller("activate", "--no-screenshot")
        file_name = identifier.removeprefix("MediaLibrary-grid-video-")
        media_label = f"{Path(file_name).stem}, video"
        operation_id = "accessibility:MediaLibrary-grid-video-{reference.name}"
        result = self.tap_label(
            "window", media_label, operation_id=operation_id
        )
        if result.get("success") is not True and identifier.startswith(
            "MediaLibrary-grid-video-"
        ):
            imported = self.app_command("importMedia", file=file_name)
            if imported.get("success") is True:
                self.relaunch()
                self.tap("window", "Navigation-Ornament-tab-files")
                self.controller("activate", "--no-screenshot")
                result = self.tap_label(
                    "window", media_label, operation_id=operation_id
                )
        probe = self.wait_for_probe(
            "open-media-selected",
            offset,
            "reachability files delivered action=library.video",
            timeout=15,
        )
        if result.get("success") is True and any(
            "reachability files delivered action=library.video" in line
            for line in probe[offset:]
        ):
            self.delivered(
                "window", "accessibility:MediaLibrary-grid-video-{reference.name}",
                self.events[-1]["evidence"],
                "The Media Library video card ran its playback activation handler.",
            )
        time.sleep(2)
        return result

    def video_format_editor_scenario(
        self,
        presentation: str,
        identifier_prefix: str,
        probe_prefix: str,
    ) -> None:
        open_identifier = (
            "PlayerUI-TopAction-videoFormat"
            if identifier_prefix == "PlayerUI-VideoFormat"
            else "PlayerPanel-button-settings"
        )

        def cancel_editor() -> None:
            before = self.copy_probe(f"{identifier_prefix}-cancel-before")
            offset = len(before)
            cancelled = self.tap(
                presentation, f"{identifier_prefix}-cancel"
            )
            probe = self.wait_for_probe(
                f"{identifier_prefix}-cancel",
                offset,
                f"{probe_prefix}videoFormat.cancel",
            )
            if cancelled.get("success") is True and any(
                f"{probe_prefix}videoFormat.cancel" in line
                for line in probe[offset:]
            ):
                self.delivered(
                    presentation,
                    f"accessibility:{identifier_prefix}-cancel",
                    self.events[-1]["evidence"],
                    "Cancel ran the format editor's discard handler and appended its probe.",
                )

        def open_editor() -> bool:
            if self.channel_failures:
                return False
            opened, before = self.tap_with_fresh_controls(
                presentation,
                open_identifier,
                probe_label=f"{identifier_prefix}-open-before",
            )
            if self.channel_failures:
                return False
            offset = len(before)
            visible = self.wait_for_identifier(
                f"{identifier_prefix}-cancel", timeout=10
            )
            probe = self.copy_probe(f"{identifier_prefix}-opened")
            delivered = opened.get("success") is True and isinstance(
                visible.get("matchedElement"), dict
            ) and video_format_open_was_delivered(probe, offset=offset)
            if delivered:
                self.delivered(
                    presentation,
                    f"accessibility:{open_identifier}",
                    self.events[-1]["evidence"],
                    "The visible format host ran its open handler and appended the product open probe.",
                )
            return delivered

        if open_editor():
            before = self.copy_probe(
                f"{identifier_prefix}-option-before"
            )
            offset = len(before)
            option = self.tap(
                presentation,
                f"{identifier_prefix}-Stereo Layout-Side-by-Side",
                operation_id=(
                    f"accessibility:{identifier_prefix}-"
                    "{title}-{label(option)}"
                ),
            )
            probe = self.wait_for_probe(
                f"{identifier_prefix}-option",
                offset,
                f"{probe_prefix}videoFormat.option.Stereo Layout.Side-by-Side",
            )
            if option.get("success") is True and any(
                f"{probe_prefix}videoFormat.option.Stereo Layout.Side-by-Side"
                in line for line in probe[offset:]
            ):
                self.delivered(
                    presentation,
                    f"accessibility:{identifier_prefix}-"
                    "{title}-{label(option)}",
                    self.events[-1]["evidence"],
                    "The format option changed the editor selection and appended its option probe.",
                )

            cancel_editor()

        if open_editor():
            before = self.copy_probe(
                f"{identifier_prefix}-custom-angle-before"
            )
            offset = len(before)
            picker = self.tap(
                presentation, f"{identifier_prefix}-CustomAngle"
            )
            host = (
                "playerUI"
                if identifier_prefix == "PlayerUI-VideoFormat"
                else "playerPanel"
            )
            _, _, selected = self.select_debug_menu_item(
                presentation=presentation,
                host=host,
                family="customAngle",
                preferred=("180",),
            )
            probe = self.wait_for_probe(
                f"{identifier_prefix}-custom-angle",
                offset,
                f"{probe_prefix}videoFormat.customAngle",
            )
            if (
                picker.get("success") is True
                and selected.get("success") is True
                and any(
                    f"{probe_prefix}videoFormat.customAngle" in line
                    for line in probe[offset:]
                )
            ):
                self.delivered_by_debug_menu_selection(
                    presentation,
                    f"accessibility:{identifier_prefix}-CustomAngle",
                    f"accessibility:{identifier_prefix}-CustomAngle",
                    self.events[-1]["evidence"],
                    "The named custom-angle Picker was hittable; the DEBUG "
                    "equivalent changed the same editor binding and its existing "
                    "product probe confirmed delivery.",
                )
            self.controller(
                "tap", "--label", "180°", "--no-screenshot", timeout=90
            )
            cancel_editor()

        if open_editor():
            fallback = self.wait_for_identifier(
                f"{identifier_prefix}-HDRFallback", timeout=3
            )
            if isinstance(fallback.get("matchedElement"), dict):
                before = self.copy_probe(
                    f"{identifier_prefix}-hdr-fallback-before"
                )
                offset = len(before)
                toggled = self.tap(
                    presentation, f"{identifier_prefix}-HDRFallback"
                )
                probe = self.wait_for_probe(
                    f"{identifier_prefix}-hdr-fallback",
                    offset,
                    f"{probe_prefix}videoFormat.hdrFallback",
                )
                if toggled.get("success") is True and any(
                    f"{probe_prefix}videoFormat.hdrFallback" in line
                    for line in probe[offset:]
                ):
                    self.delivered(
                        presentation,
                        f"accessibility:{identifier_prefix}-HDRFallback",
                        self.events[-1]["evidence"],
                        "The HDR fallback toggle changed its editor binding and appended a probe.",
                    )
            cancel_editor()

        if open_editor():
            self.tap(presentation, f"{identifier_prefix}-Projection-Flat")
            before = self.copy_probe(f"{identifier_prefix}-apply-before")
            offset = len(before)
            applied = self.tap(
                presentation, f"{identifier_prefix}-apply"
            )
            probe = self.wait_for_probe(
                f"{identifier_prefix}-apply",
                offset,
                f"{probe_prefix}videoFormat.apply",
            )
            if applied.get("success") is True and any(
                f"{probe_prefix}videoFormat.apply" in line
                for line in probe[offset:]
            ):
                self.delivered(
                    presentation,
                    f"accessibility:{identifier_prefix}-apply",
                    self.events[-1]["evidence"],
                    "Apply ran the format editor's commit handler and appended its probe.",
                )

        if open_editor():
            before = self.copy_probe(f"{identifier_prefix}-automatic-before")
            offset = len(before)
            automatic = self.tap(
                presentation, f"{identifier_prefix}-automatic"
            )
            probe = self.wait_for_probe(
                f"{identifier_prefix}-automatic",
                offset,
                f"{probe_prefix}videoFormat.automatic",
            )
            if automatic.get("success") is True and any(
                f"{probe_prefix}videoFormat.automatic" in line
                for line in probe[offset:]
            ):
                self.delivered(
                    presentation,
                    f"accessibility:{identifier_prefix}-automatic",
                    self.events[-1]["evidence"],
                    "Automatic ran the format restoration handler and appended its probe.",
                )

    def ensure_window_projection(self, projection: str) -> bool:
        control_plane = self.wait_for_identifier("PlayerUI-window-control-plane")
        value = str((control_plane.get("matchedElement") or {}).get("value", ""))
        source_presentation = next(
            (
                candidate for candidate in PRESENTATIONS
                if f"presentation={candidate}" in value
            ),
            "window",
        )
        expected = {
            "Flat": "presentation=window",
            "180°": "presentation=portal",
        }[projection]
        if expected in value:
            return True
        self.show_controls()
        conversion = self.controller(
            "tapSequence",
            "--identifiers",
            "PlayerUI-TopAction-videoFormat",
            f"PlayerUI-VideoFormat-Projection-{projection}",
            "PlayerUI-VideoFormat-apply",
            "--no-screenshot",
            "--timeout-seconds",
            "90",
            timeout=120,
        )
        if conversion.get("success") is not True:
            return False
        settled = self.wait_for_identifier("PlayerUI-window-control-plane", timeout=30)
        value = str((settled.get("matchedElement") or {}).get("value", ""))
        delivered = expected in value and "transition=none" in value
        if delivered:
            self.delivered(
                source_presentation,
                "accessibility:PlayerUI-TopAction-videoFormat",
                self.events[-1]["evidence"],
                "The projection menu completed its product transition and the diagnostic control plane reported the settled presentation.",
            )
        return delivered

    def window_scenario(self) -> None:
        presentation = "window"
        opened = self.open_media(
            "MediaLibrary-grid-video-furyroad-stripped.mkv"
        )
        if opened.get("success") is not True:
            return
        if not self.ensure_window_projection("Flat"):
            return
        controls = self.show_controls()
        visible = self.wait_for_identifier("PlayerPanel-controls", timeout=10)
        if controls.get("success") is True and isinstance(visible.get("matchedElement"), dict):
            self.delivered(
                presentation, "command:toggleControls", self.events[-1]["evidence"],
                "The command changed product control visibility and the controls entered the hierarchy.",
                has_accessibility_target=False,
            )
        self.video_format_editor_scenario(
            presentation,
            "PlayerUI-VideoFormat",
            "reachability top actions delivered action=",
        )
        self.video_format_editor_scenario(
            presentation,
            "PlayerPanel-VideoFormat",
            "reachability playerPanel delivered action=",
        )
        self.observe(presentation, "Window playback controls")
        self.seek_scenario(presentation, "0.35")
        self.transport_scenario(presentation)
        self.top_menu_scenario(presentation)
        self.resume_decision_scenario()

    def player_ui_candidate_scenario(self) -> None:
        presentation = "window"
        opened = self.open_media(
            "MediaLibrary-grid-video-furyroad-stripped.mkv"
        )
        if opened.get("success") is not True:
            return
        if not self.ensure_window_projection("Flat"):
            return
        controls = self.show_controls()
        visible = self.wait_for_identifier("PlayerPanel-controls", timeout=10)
        if controls.get("success") is True and isinstance(
            visible.get("matchedElement"), dict
        ):
            self.delivered(
                presentation,
                "command:toggleControls",
                self.events[-1]["evidence"],
                "The command changed product control visibility and the controls entered the hierarchy.",
                has_accessibility_target=False,
            )
        self.video_format_editor_scenario(
            presentation,
            "PlayerUI-VideoFormat",
            "reachability top actions delivered action=",
        )
        if self.channel_failures:
            return
        self.seek_scenario(presentation, "0.35")
        before = self.copy_probe("window-forward-before")
        offset = len(before)
        forwarded = self.tap_control(
            presentation, "PlayerPanel-button-forward"
        )
        probe = self.wait_for_probe(
            "window-forward",
            offset,
            "playback control delivered action=forward",
        )
        if forwarded.get("success") is True and any(
            "playback control delivered action=forward" in line
            for line in probe[offset:]
        ):
            self.delivered(
                presentation,
                "accessibility:PlayerPanel-button-forward",
                self.events[-1]["evidence"],
                "The forward control closure appended its action-specific application probe after the deterministic pre-seek.",
            )
        self.top_menu_scenario(presentation)

    def transport_scenario(self, presentation: str) -> None:
        before = self.copy_probe(f"{presentation}-transport-before")
        offset = len(before)
        for identifier, fact in (
            ("PlayerPanel-button-rewind", "rewind"),
            ("PlayerPanel-button-forward", "forward"),
            ("PlayerPanel-button-play", "playPause"),
        ):
            response = self.tap_control(presentation, identifier)
            probe = self.copy_probe(f"{presentation}-{fact}")
            if response.get("success") is True and any(
                f"playback control delivered action={fact}" in line
                for line in probe[offset:]
            ):
                self.delivered(
                    presentation, f"accessibility:{identifier}",
                    self.events[-1]["evidence"],
                    "The control closure appended its action-specific application probe.",
                )
            offset = len(probe)

    def seek_scenario(self, presentation: str, position: str) -> None:
        seek = self.app_command("seekNormalized", position=position)
        if seek.get("success") is not True:
            return
        evidence = self.events[-1]["evidence"]
        self.delivered(
            presentation, "command:seekNormalized", evidence,
            "The DEBUG verb reached PlaybackRuntime.seek and returned the computed target.",
            has_accessibility_target=False,
        )
        for operation_id in (
            "accessibility:PlayerPanel-progress",
            "accessibility:PlayerPanel-precision-timeline",
        ):
            self.delivered(
                presentation, operation_id, evidence,
                "The DEBUG verb reached the same PlaybackRuntime seek pipeline.",
            )

    def top_menu_scenario(self, presentation: str) -> None:
        opened, before = self.tap_with_fresh_controls(
            presentation,
            "PlayerUI-TopAction-more",
            probe_label=f"{presentation}-top-menu-before",
        )
        offset = len(before)
        probe = self.copy_probe(f"{presentation}-top-menu-open")
        if opened.get("success") is True and any(
            "reachability top actions delivered action=menu.more" in line
            for line in probe[offset:]
        ):
            self.delivered(
                presentation, "accessibility:PlayerUI-TopAction-more",
                self.events[-1]["evidence"],
                "Opening the system Menu caused its product-owned content to append a probe.",
            )

        # System Menu removes item identifiers. The named top-level parent still
        # supplies the hierarchy and hittability evidence; the DEBUG verb invokes
        # the same Picker binding setter and its existing product probe proves
        # delivery beyond XCTest.
        item_offset = len(probe)
        target, _, selected = self.select_debug_menu_item(
            presentation=presentation,
            host="playerUI",
            family="subtitles",
            preferred=("off",),
            driven_operations=("accessibility:PlayerUI-menu-subtitles",),
        )
        probe = self.copy_probe(f"{presentation}-top-subtitles-selected")
        if selected.get("success") is True and target is not None and any(
            "reachability top actions delivered action=menu.item."
            + target in line
            for line in probe[item_offset:]
        ):
            self.delivered_by_debug_menu_selection(
                presentation,
                "accessibility:PlayerUI-menu-subtitles",
                "accessibility:PlayerUI-TopAction-more",
                self.events[-1]["evidence"],
                "The named More parent supplied hierarchy and hittability evidence; "
                "the DEBUG equivalent entered the subtitle Picker binding and its "
                "menu.item product probe confirmed delivery.",
            )

        # The equivalent action does not dismiss the system-owned menu. A label
        # action is cleanup only and never contributes delivery evidence.
        speed = self.controller(
            "tap", "--label", "Playback Speed", "--no-screenshot", timeout=90,
        )
        if speed.get("success") is True:
            self.controller(
                "tap", "--label", "1.25×", "--no-screenshot", timeout=90,
            )

    def stop_playback(self, presentation: str) -> bool:
        stopped, before = self.tap_with_fresh_controls(
            presentation,
            "PlayerUI-InfoBar-button-back",
            probe_label=f"{presentation}-back-before",
        )
        offset = len(before)
        probe = self.copy_probe(f"{presentation}-back")
        delivered = stopped.get("success") is True and any(
            "reachability top actions delivered action=back" in line
            for line in probe[offset:]
        )
        if delivered:
            self.delivered(
                presentation, "accessibility:PlayerUI-InfoBar-button-back",
                self.events[-1]["evidence"],
                "The Back control stopped playback through PlaybackLaunchCoordinator and appended its product probe.",
            )
        return delivered

    def resume_decision_scenario(self) -> None:
        presentation = "window"
        active = self.wait_for_identifier(
            "PlayerUI-window-control-plane", timeout=3
        )
        if isinstance(active.get("matchedElement"), dict):
            if not self.stop_playback(presentation):
                return
            self.wait_for_identifier("FileBrowsing-FilesScreen-list", timeout=15)

        self.tap(presentation, "Navigation-Ornament-tab-settings")
        settings = self.controller("snapshot", "--no-screenshot")
        hierarchy = str(settings.get("hierarchy", ""))
        current_policy = next(
            (
                title for title in (
                    "Ask Every Time",
                    "Always Resume",
                    "Always Start Over",
                )
                if f"label: '{title}'" in hierarchy
            ),
            None,
        )
        if current_policy is None:
            return
        if current_policy == "Ask Every Time":
            selected = {"success": True}
        else:
            opened = self.controller(
                "tap", "--label", current_policy, "--no-screenshot", timeout=90,
            )
            if opened.get("success") is not True:
                return
            selected = self.controller(
                "tap", "--label", "Ask Every Time", "--no-screenshot", timeout=90,
            )
        if selected.get("success") is not True:
            return

        self.tap(presentation, "Navigation-Ornament-tab-files")
        resume_media = "MediaLibrary-grid-video-reachability-resume-16m.mp4"
        available = self.wait_for_identifier(resume_media, timeout=5)
        if not isinstance(available.get("matchedElement"), dict):
            imported = self.app_command(
                "importMedia", file="reachability-resume-16m.mp4"
            )
            if imported.get("success") is not True:
                return
            self.relaunch()
            self.tap(presentation, "Navigation-Ornament-tab-files")
        started = self.tap(
            presentation, resume_media,
            operation_id="accessibility:MediaLibrary-grid-video-{reference.name}",
        )
        if started.get("success") is not True:
            return
        if not isinstance(
            self.wait_for_identifier(
                "PlayerUI-window-control-plane", timeout=20
            ).get("matchedElement"),
            dict,
        ):
            return
        time.sleep(16)
        self.seek_scenario(presentation, "0.25")
        if not self.stop_playback(presentation):
            return
        self.wait_for_identifier("FileBrowsing-FilesScreen-list", timeout=15)

        for identifier, fact in (
            ("PlayerUI-resumeDecision-primary", "resume"),
            ("PlayerUI-resumeDecision-secondary", "startOver"),
        ):
            opened = self.tap(
                presentation, resume_media,
                operation_id="accessibility:MediaLibrary-grid-video-{reference.name}",
            )
            if opened.get("success") is not True:
                return
            decision = self.wait_for_identifier(identifier, timeout=15)
            if not isinstance(decision.get("matchedElement"), dict):
                return
            before = self.copy_probe(f"resume-{fact}-before")
            offset = len(before)
            chosen = self.tap(presentation, identifier)
            probe = self.wait_for_probe(
                f"resume-{fact}",
                offset,
                f"reachability resume decision delivered action={fact}",
            )
            if chosen.get("success") is True and any(
                f"reachability resume decision delivered action={fact}" in line
                for line in probe[offset:]
            ):
                self.delivered(
                    presentation, f"accessibility:{identifier}",
                    self.events[-1]["evidence"],
                    "The visible resume decision ran its product-owned playback choice and appended an action probe.",
                )
            self.wait_for_identifier("PlayerUI-window-control-plane", timeout=15)
            if not self.stop_playback(presentation):
                return
            self.wait_for_identifier("FileBrowsing-FilesScreen-list", timeout=15)

    def playback_failure_scenario(self) -> None:
        presentation = "window"
        opened = self.open_media(
            "MediaLibrary-grid-video-broken-clip.mp4"
        )
        if opened.get("success") is not True:
            return

        primary, _ = self.wait_for_any_identifier(
            (
                "PlayerUI-loadFailure-primary",
                "PlayerUI-playbackIssue-primary",
            ),
            timeout=20,
        )
        if primary is not None:
            before = self.copy_probe("playback-failure-primary-before")
            offset = len(before)
            retried = self.tap(presentation, primary)
            probe = self.copy_probe("playback-failure-primary")
            if retried.get("success") is True and any(
                "reachability playback issue delivered" in line
                and "action=retry" in line
                for line in probe[offset:]
            ):
                self.delivered(
                    presentation, f"accessibility:{primary}",
                    self.events[-1]["evidence"],
                    "The negative media exposed the product failure alert and Retry ran its application handler.",
                )

        secondary, _ = self.wait_for_any_identifier(
            (
                "PlayerUI-loadFailure-secondary",
                "PlayerUI-playbackIssue-secondary",
                "PlayerUI-playbackIssue-confirm",
            ),
            timeout=20,
        )
        if secondary is None:
            return
        before = self.copy_probe("playback-failure-secondary-before")
        offset = len(before)
        closed = self.tap(presentation, secondary)
        probe = self.copy_probe("playback-failure-secondary")
        expected_action = "confirm" if secondary.endswith("confirm") else "close"
        if closed.get("success") is True and any(
            "reachability playback issue delivered" in line
            and f"action={expected_action}" in line
            for line in probe[offset:]
        ):
            self.delivered(
                presentation, f"accessibility:{secondary}",
                self.events[-1]["evidence"],
                "The visible product failure alert ran its terminal action and appended a probe.",
            )

    def player_panel_menu_scenario(self, presentation: str) -> None:
        opened, before = self.tap_with_fresh_controls(
            presentation,
            "PlayerPanel-menu-more",
            probe_label=f"{presentation}-panel-menu-before",
        )
        offset = len(before)
        probe = self.copy_probe(f"{presentation}-panel-menu-open")
        if opened.get("success") is True and any(
            "reachability playerPanel delivered action=menu.more" in line
            for line in probe[offset:]
        ):
            self.delivered(
                presentation,
                "accessibility:PlayerPanel-menu-more",
                self.events[-1]["evidence"],
                "The named PlayerPanel More menu was hittable and constructed its product content.",
            )

        family_operations = (
            ("speed", "accessibility:PlayerPanel-menu-speed", ("1.25",)),
            ("subtitles", "accessibility:PlayerPanel-menu-subtitles", ("off",)),
            ("audio", "accessibility:PlayerPanel-menu-audio", ()),
            ("episodes", "accessibility:PlayerPanel-menu-episodes", ()),
        )
        for family, operation_id, preferred in family_operations:
            item_offset = len(probe)
            target, _, selected = self.select_debug_menu_item(
                presentation=presentation,
                host="playerPanel",
                family=family,
                preferred=preferred,
                driven_operations=(
                    operation_id,
                    "accessibility:PlayerPanel-menu-{category}-{item.id}",
                ),
            )
            probe = self.copy_probe(
                f"{presentation}-panel-{family}-selected"
            )
            if selected.get("success") is True and target is not None and any(
                "reachability playerPanel delivered action=menu.item."
                + target in line
                for line in probe[item_offset:]
            ):
                self.delivered_by_debug_menu_selection(
                    presentation,
                    operation_id,
                    "accessibility:PlayerPanel-menu-more",
                    self.events[-1]["evidence"],
                    "The named More parent supplied hierarchy and hittability evidence; "
                    f"the DEBUG equivalent entered the {family} item handler and its "
                    "menu.item product probe confirmed delivery.",
                )
                self.delivered_by_debug_menu_selection(
                    presentation,
                    "accessibility:PlayerPanel-menu-{category}-{item.id}",
                    "accessibility:PlayerPanel-menu-more",
                    self.events[-1]["evidence"],
                    "The named More parent supplied hierarchy and hittability evidence; "
                    "the DEBUG equivalent entered the exact item action and its product "
                    "probe confirmed delivery.",
                )

        # The equivalent action does not dismiss the system-owned menu. These
        # label actions are cleanup only and never contribute delivery evidence.
        self.controller(
            "tap", "--label", "Playback Speed", "--no-screenshot", timeout=90,
        )
        self.controller(
            "tap", "--label", "1×", "--no-screenshot", timeout=90,
        )

    def docked_settings_scenario(self) -> None:
        presentation = "docked"
        self.show_controls()
        before = self.copy_probe("docked-settings-before")
        offset = len(before)
        opened = self.tap(presentation, "PlayerPanel-button-settings")
        probe = self.copy_probe("docked-settings-open")
        if opened.get("success") is True and any(
            "reachability playerPanel delivered action=settings.open" in line
            for line in probe[offset:]
        ):
            self.delivered(
                presentation, "accessibility:PlayerPanel-button-settings",
                self.events[-1]["evidence"],
                "The settings button expanded the Docked placement controls and appended a probe.",
            )
        before = probe
        offset = len(before)
        reset = self.tap(presentation, "PlayerPanel-DockedPlacement-reset")
        probe = self.copy_probe("docked-placement-reset")
        if reset.get("success") is True and any(
            "reachability playerPanel delivered action=dockedPlacement.reset" in line
            for line in probe[offset:]
        ):
            self.delivered(
                presentation, "accessibility:PlayerPanel-DockedPlacement-reset",
                self.events[-1]["evidence"],
                "Restore Defaults reached the shared Docked placement reset handler.",
            )


    def panorama_scenario(self) -> bool:
        presentation = "panorama"
        opened = self.open_media("MediaLibrary-grid-video-furyroad-stripped.mkv")
        if opened.get("success") is not True:
            return False
        if not self.ensure_window_projection("180°"):
            return False
        self.show_controls()
        entered = self.controller(
            "tapSequence",
            "--identifiers",
            "PlayerUI-TopAction-resumePanorama",
            "--no-screenshot",
            "--timeout-seconds",
            "90",
            timeout=120,
        )
        if entered.get("success") is not True:
            return False
        spatial = self.wait_for_identifier("PlayerUI-spatial-state", timeout=45)
        if not isinstance(spatial.get("matchedElement"), dict):
            return False
        self.observe(presentation, "Panorama playback")
        controls = self.show_controls()
        visible = self.wait_for_identifier("PlayerPanel-controls", timeout=10)
        if controls.get("success") is True and isinstance(visible.get("matchedElement"), dict):
            self.delivered(
                presentation, "command:toggleControls", self.events[-1]["evidence"],
                "The immersive attachment controls entered the hierarchy after the product command.",
                has_accessibility_target=False,
            )
        self.transport_scenario(presentation)
        self.seek_scenario(presentation, "0.45")
        self.player_panel_menu_scenario(presentation)
        return True

    def portal_scenario(self) -> None:
        presentation = "portal"
        opened = self.open_media("MediaLibrary-grid-video-furyroad-stripped.mkv")
        if opened.get("success") is not True:
            return
        if not self.ensure_window_projection("180°"):
            return
        portal = self.wait_for_identifier("PlayerUI-window-control-plane", timeout=45)
        value = str((portal.get("matchedElement") or {}).get("value", ""))
        if "presentation=portal" not in value:
            return
        self.observe(presentation, "Portal playback")
        size = self.app_command("setWindowSize", width="1180", height="720")
        time.sleep(1)
        probe = self.copy_probe("portal-window-size")
        if size.get("success") is True and any(
            "setWindowSize observed=" in line for line in probe
        ):
            self.delivered(
                presentation, "command:setWindowSize", self.events[-1]["evidence"],
                "The geometry request pipeline recorded the observed applied size.",
                has_accessibility_target=False,
            )
        controls = self.show_controls()
        visible = self.wait_for_identifier("PlayerPanel-controls", timeout=10)
        if controls.get("success") is True and isinstance(visible.get("matchedElement"), dict):
            self.delivered(
                presentation, "command:toggleControls", self.events[-1]["evidence"],
                "The Portal controls entered the hierarchy after the product command.",
                has_accessibility_target=False,
            )
        self.transport_scenario(presentation)
        self.seek_scenario(presentation, "0.4")
        self.top_menu_scenario(presentation)

    def enter_docked_playback(
        self,
        *,
        dock_choice: str = "skybox",
        record_route: bool = False,
    ) -> bool:
        presentation = "docked"
        opened = self.open_media(
            "MediaLibrary-grid-video-furyroad-stripped.mkv"
        )
        if opened.get("success") is not True:
            return False
        if not self.ensure_window_projection("Flat"):
            return False

        if record_route:
            self.show_controls()
            before = self.copy_probe("docked-video-format-before")
            offset = len(before)
            changed = self.controller(
                "tapSequence",
                "--identifiers",
                "PlayerUI-TopAction-videoFormat",
                "PlayerUI-VideoFormat-Projection-Flat",
                "PlayerUI-VideoFormat-apply",
                "--no-screenshot",
                "--timeout-seconds",
                "90",
                timeout=120,
            )
            probe = self.copy_probe("docked-video-format-applied")
            if changed.get("success") is True and all(
                any(f"action={action}" in line for line in probe[offset:])
                for action in ("videoFormat.open", "videoFormat.apply")
            ):
                self.delivered(
                    presentation,
                    "accessibility:PlayerUI-TopAction-videoFormat",
                    self.events[-1]["evidence"],
                    "The Docked route opened and applied the product Video Format editor, with both DEBUG probes present.",
                )

        self.show_controls()
        before = self.copy_probe(f"docked-{dock_choice}-transition-before")
        offset = len(before)
        transition = self.controller(
            "tapSequence",
            "--identifiers",
            "PlayerUI-TopAction-dock",
            f"PlayerUI-DockMenu-{dock_choice}",
            "--no-screenshot",
            "--timeout-seconds",
            "90",
            timeout=120,
        )
        spatial = self.wait_for_identifier("PlayerUI-spatial-state", timeout=45)
        value = str((spatial.get("matchedElement") or {}).get("value", ""))
        probe = self.copy_probe(f"docked-{dock_choice}-settled")
        settled = all(
            fact in value
            for fact in (
                "presentation=docked",
                "transition=none",
                "surfacePreparation=surfaceAttached",
                "lifecycle=Playing",
                "attached=docked",
                "rendererConsumer=docked",
                "displayedPixel=true",
                "surfaceRenderingReady=true",
                "surfaceSettled=true",
            )
        )
        delivered_probe = any(
            "reachability topActions delivered action=dock.open" in line
            for line in probe[offset:]
        ) and any(
            "reachability topActions delivered action=dock.select" in line
            and f"effect={'none' if dock_choice == 'skybox' else dock_choice}" in line
            for line in probe[offset:]
        ) and any(
            "worldLoad event=completed anchor=PlaybackSurfaceAnchor" in line
            for line in probe[offset:]
        )
        if transition.get("success") is not True or not settled or not delivered_probe:
            return False

        route_operations = ["accessibility:PlayerUI-TopAction-dock"]
        if dock_choice == "skybox":
            route_operations.append("accessibility:PlayerUI-DockMenu-skybox")
        else:
            route_operations.append("accessibility:PlayerUI-DockMenu-{$0.rawValue}")
        for operation_id in route_operations:
            self.mark_observation(
                presentation,
                operation_id,
                exists=True,
                hittable=True,
                evidence=self.events[-3]["evidence"],
                reason="XCTest completed the Docked menu route.",
            )
            self.mark_observation(
                presentation,
                operation_id,
                evidence=self.events[-2]["evidence"],
                reason="The spatial diagnostic reached settled Docked playback with displayed pixels.",
            )
            self.mark_observation(
                presentation,
                operation_id,
                received=True,
                evidence=self.events[-1]["evidence"],
                reason="The top-action probe, Dock target probe, world anchor probe, and settled diagnostic all agree.",
            )
        for operation_id in (
            "accessibility:PlayerUI-TopAction-dock",
            "accessibility:PlayerUI-DockMenu-skybox",
        ):
            if operation_id in route_operations:
                self.delivered(
                    "window",
                    operation_id,
                    self.events[-1]["evidence"],
                    "The presentation entered settled Docked playback after the menu sequence.",
                )
        return True

    def docked_environment_card_scenario(self) -> None:
        presentation = "docked"
        before = self.copy_probe("docked-environment-card-before")
        offset = len(before)
        opened = self.app_command("openEnvironmentCard")
        volume = self.wait_for_identifier("SenseZone-VolumeRoot", timeout=15)
        identifiers = self.hierarchy_identifiers(volume)
        effect_identifier = next(
            (value for value in sorted(identifiers)
             if value.startswith("EnvironmentCard-effect-")),
            None,
        )
        environment_identifier = next(
            (value for value in sorted(identifiers)
             if value.startswith("EnvironmentCard-button-environment-")),
            None,
        )
        if opened.get("success") is not True or effect_identifier is None:
            return

        changed = self.tap(presentation, effect_identifier, operation_id=(
            "accessibility:EnvironmentCard-effect-"
            "{environment.environment.rawValue}"
        ))
        probe = self.copy_probe("docked-environment-card-effect")
        effect_delivered = changed.get("success") is True and any(
            "environmentCard effect delivered" in line
            for line in probe[offset:]
        )
        if effect_delivered:
            evidence = self.events[-1]["evidence"]
            for operation_id in (
                "accessibility:EnvironmentCard-effect-"
                "{environment.environment.rawValue}",
                "accessibility:EnvironmentCard-card",
                "accessibility:EnvironmentCard-carousel",
            ):
                self.mark_observation(
                    presentation,
                    operation_id,
                    exists=True,
                    hittable=True,
                    evidence=self.events[-2]["evidence"],
                    reason="The Environment volume exposed the product card structure.",
                )
                self.mark_observation(
                    presentation,
                    operation_id,
                    received=True,
                    evidence=evidence,
                    reason="The DEBUG open verb reached its terminal state and the card's effect handler appended a product probe.",
                )

        if environment_identifier is not None:
            toggle_offset = len(probe)
            toggled = self.tap(
                presentation,
                environment_identifier,
                operation_id=(
                    "accessibility:EnvironmentCard-button-environment-"
                    "{environment.environment.rawValue}"
                ),
            )
            probe = self.copy_probe("docked-environment-card-toggle")
            if toggled.get("success") is True and any(
                "environmentCard toggle delivered" in line
                for line in probe[toggle_offset:]
            ):
                self.delivered(
                    presentation,
                    "accessibility:EnvironmentCard-button-environment-"
                    "{environment.environment.rawValue}",
                    self.events[-1]["evidence"],
                    "The visible environment button reached the product toggle handler and appended its probe.",
                )

        dismissed = self.app_command("dismissEnvironmentCard")
        closed = self.wait_for_identifier("SenseZone-VolumeRoot", timeout=10)
        if (
            effect_delivered
            and dismissed.get("success") is True
            and not isinstance(closed.get("matchedElement"), dict)
        ):
            self.delivered(
                presentation,
                "environmentVolume:open-interact-close",
                self.events[-1]["evidence"],
                "The DEBUG open and dismiss verbs bracketed a probed product interaction and the volume disappeared.",
                has_accessibility_target=False,
            )

    def docked_media_information_scenario(self) -> None:
        presentation = "docked"
        self.show_controls()
        before = self.copy_probe("docked-media-information-before")
        offset = len(before)
        opened = self.tap(presentation, "PlayerPanel-media-information")
        close = self.wait_for_identifier(
            "PlayerPanel-media-information-close", timeout=10
        )
        if opened.get("success") is not True or not isinstance(
            close.get("matchedElement"), dict
        ):
            return
        closed = self.tap(
            presentation, "PlayerPanel-media-information-close"
        )
        probe = self.copy_probe("docked-media-information-close")
        if closed.get("success") is True and any(
            "reachability playerPanel delivered action=mediaInformation.close"
            in line for line in probe[offset:]
        ):
            self.delivered(
                presentation,
                "accessibility:PlayerPanel-media-information-close",
                self.events[-1]["evidence"],
                "The expanded media information close button reached its product handler and appended a probe.",
            )

    def exercise_playback_issue(
        self,
        presentation: str,
        *,
        category: str,
        identifier: str,
        action: str,
    ) -> bool:
        before = self.copy_probe(f"{presentation}-{identifier}-before")
        offset = len(before)
        shown = self.app_command("showPlaybackIssue", category=category)
        visible = self.wait_for_identifier(identifier, timeout=10)
        tapped = self.tap(presentation, identifier)
        probe = self.wait_for_probe(
            f"{presentation}-{identifier}",
            offset,
            f"reachability playback issue delivered",
            timeout=15,
        )
        delivered = (
            shown.get("success") is True
            and isinstance(visible.get("matchedElement"), dict)
            and any(
                "reachability playback issue delivered" in line
                and f"action={action}" in line
                for line in probe[offset:]
            )
        )
        if delivered:
            self.mark_observation(
                presentation,
                f"accessibility:{identifier}",
                exists=True,
                hittable=tapped.get("success") is True,
                evidence=self.events[-3]["evidence"],
                reason="The DEBUG issue verb exposed the expected product action.",
            )
            self.mark_observation(
                presentation,
                f"accessibility:{identifier}",
                received=True,
                evidence=self.events[-1]["evidence"],
                reason="The product alert action appended its location and action probe.",
            )
        return delivered

    def docked_issue_scenario(self) -> None:
        presentation = "docked"
        for category, identifier, action in (
            ("environmentLoadingFailed", "PlayerUI-spatialFailure-primary", "retry"),
            ("playbackControlFailed", "PlayerUI-playbackIssue-confirm", "confirm"),
            ("capabilityUnavailable", "PlayerUI-unmetCapability-dismiss", "confirm"),
        ):
            self.exercise_playback_issue(
                presentation,
                category=category,
                identifier=identifier,
                action=action,
            )

    def docked_main_window_issue_scenario(self) -> None:
        presentation = "docked"
        for identifier, action in (
            ("PlayerUI-loadFailure-primary", "retry"),
            ("PlayerUI-loadFailure-secondary", "close"),
        ):
            opened = self.open_media(
                "MediaLibrary-grid-video-furyroad-stripped.mkv"
            )
            if opened.get("success") is not True:
                return
            self.exercise_playback_issue(
                presentation,
                category="mediaOpeningFailed",
                identifier=identifier,
                action=action,
            )

    def docked_exit_scenario(self) -> None:
        presentation = "docked"
        self.show_controls()
        before = self.copy_probe("docked-exit-before")
        offset = len(before)
        exited = self.tap(presentation, "PlayerPanel-button-exit-spatial")
        settled = self.wait_for_identifier("PlayerUI-window-control-plane", timeout=45)
        value = str((settled.get("matchedElement") or {}).get("value", ""))
        probe = self.copy_probe("docked-exit-settled")
        if (
            exited.get("success") is True
            and "presentation=window" in value
            and "transition=none" in value
            and any(
                "reachability playerPanel delivered action=exitSpatial" in line
                for line in probe[offset:]
            )
        ):
            self.delivered(
                presentation,
                "accessibility:PlayerPanel-button-exit-spatial",
                self.events[-1]["evidence"],
                "The Docked exit button appended its product probe and the control plane settled in Window.",
            )

        self.show_controls()
        before = probe
        offset = len(before)
        stopped = self.tap(presentation, "PlayerUI-InfoBar-button-back")
        probe = self.copy_probe("docked-route-back")
        if stopped.get("success") is True and any(
            "reachability top actions delivered action=back" in line
            for line in probe[offset:]
        ):
            self.delivered(
                presentation,
                "accessibility:PlayerUI-InfoBar-button-back",
                self.events[-1]["evidence"],
                "The post-Docked Window route stopped playback through the product coordinator and appended its probe.",
            )

        self.exercise_playback_issue(
            presentation,
            category="presentationConversionFailed",
            identifier="PlayerUI-presentation-conversion-dismiss",
            action="confirm",
        )

    def docked_scenario(self) -> None:
        presentation = "docked"
        self.docked_main_window_issue_scenario()

        opened = self.open_media(
            "MediaLibrary-grid-video-furyroad-stripped.mkv"
        )
        if opened.get("success") is not True:
            return
        self.top_menu_scenario(presentation)

        if not self.enter_docked_playback(record_route=True):
            return
        for axis, value in (
            ("screenSize", "1.4"),
            ("distance", "3.0"),
            ("elevation", "5.0"),
        ):
            result = self.app_command(
                "setDockedPlacement", axis=axis, value=value
            )
            if result.get("success") is True:
                evidence = self.events[-1]["evidence"]
                self.delivered(
                    presentation,
                    "command:setDockedPlacement",
                    evidence,
                    "The requested Docked placement value reached the shared product setter immediately after the settled transition.",
                    has_accessibility_target=False,
                )
                self.delivered(
                    presentation,
                    "accessibility:PlayerPanel-{identifier}-slider",
                    evidence,
                    "The DEBUG verb reached the same setter used by the placement slider.",
                )
        controls = self.show_controls()
        visible = self.wait_for_identifier("PlayerPanel-controls", timeout=10)
        if controls.get("success") is True and isinstance(visible.get("matchedElement"), dict):
            self.delivered(
                presentation, "command:toggleControls", self.events[-1]["evidence"],
                "The Docked attachment controls entered the hierarchy.",
                has_accessibility_target=False,
            )
        self.docked_settings_scenario()
        self.docked_media_information_scenario()
        self.observe(presentation, "Docked playback")

        if not self.enter_docked_playback(dock_choice="dark"):
            return
        self.docked_environment_card_scenario()

        if not self.enter_docked_playback():
            return
        self.player_panel_menu_scenario(presentation)

        if not self.enter_docked_playback():
            return
        self.transport_scenario(presentation)
        self.seek_scenario(presentation, "0.3")
        self.docked_issue_scenario()

        before = self.observe(presentation, "before resident-window negative")
        toggle = self.app_command("toggleBlackoutProbeWindow")
        after = self.controller("snapshot", "--no-screenshot")
        before_hierarchy = str(before.get("hierarchy", ""))
        after_hierarchy = str(after.get("hierarchy", ""))
        before_identifiers = self.hierarchy_identifiers(before)
        after_identifiers = self.hierarchy_identifiers(after)
        no_named_node = "Blackout Probe" not in after_hierarchy
        no_new_identifier = after_identifiers <= before_identifiers
        hierarchy_evidence = self.events[-1]["evidence"]
        cleanup = self.app_command("toggleBlackoutProbeWindow")
        cleanup_evidence = self.events[-1]["evidence"]
        if immersive_resident_window_is_hidden(
            toggle=toggle,
            cleanup=cleanup,
            no_named_node=no_named_node,
            no_new_identifier=no_new_identifier,
        ):
            self.delivered(
                presentation, "negative:immersive-resident-window",
                hierarchy_evidence,
                "Opening the mechanism added no named or identifier-addressable Accessibility target.",
                has_accessibility_target=False,
            )
            if toggle.get("success") is not True:
                self.cells[
                    (presentation, "negative:immersive-resident-window")
                ]["evidence"].append(cleanup_evidence)
        else:
            cell = self.cells[(presentation, "negative:immersive-resident-window")]
            cell["evidence"].extend((hierarchy_evidence, cleanup_evidence))
            if no_named_node and no_new_identifier:
                cell["reason"] = (
                    "The Accessibility hierarchy remained hidden, but neither command "
                    "response proved that the mechanism window was open."
                )
            else:
                cell["reason"] = (
                    "The mechanism exposed a named or identifier-addressable Accessibility target "
                    f"(newIdentifiers={sorted(after_identifiers - before_identifiers)}, "
                    f"named={not no_named_node})."
                )

        if not self.enter_docked_playback():
            return
        self.docked_exit_scenario()

        if not self.enter_docked_playback():
            return
        self.exercise_playback_issue(
            presentation,
            category="environmentLoadingFailed",
            identifier="PlayerUI-spatialFailure-secondary",
            action="close",
        )

    def run_named_segment_scenario(self, name: str) -> None:
        scenarios = {
            "browser-core": self.browser_scenario,
            "breadcrumbs": self.breadcrumb_scenario,
            "docked": self.docked_scenario,
            "file-browser-errors": self.file_browser_error_scenario,
            "library-conditions": lambda: self.browser_condition_scenario(
                include_source_scenarios=False
            ),
            "library-reference-move": self.library_reference_move_scenario,
            "manage-add": self.manage_add_scenario,
            "panorama": self.panorama_scenario,
            "playback-failures": self.playback_failure_scenario,
            "player-ui-candidates": self.player_ui_candidate_scenario,
            "player-panel-portal-menus": self.player_panel_portal_menu_scenario,
            "portal": self.portal_scenario,
            "resume-decision": self.resume_decision_scenario,
            "settings-menus": self.settings_menu_scenario,
            "source-connection-smb": lambda: self.source_connection_scenario("smb"),
            "source-connection-webdav": lambda: self.source_connection_scenario("webDAV"),
            "source-sidebar": self.source_sidebar_scenario,
            "window-playback": self.window_scenario,
        }
        scenarios[name]()

    def record_segment_health_context(
        self,
        phase: str,
        *,
        surface_probe_copied: bool,
        surface_probe_cleared: bool,
    ) -> dict[str, Any]:
        health = self.channel_health_probe(phase)
        health["surfaceProbeCopied"] = surface_probe_copied
        health["surfaceProbeCleared"] = surface_probe_cleared
        health["passed"] = (
            health["passed"]
            and surface_probe_copied
            and surface_probe_cleared
        )
        health_path = self.raw / f"channel-health-{phase}.json"
        health_path.write_text(
            json.dumps(health, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        self.channel_health[phase] = health
        return health

    def run_segment(self) -> int:
        assert self.segment is not None
        if getattr(self.arguments, "reuse_session", False):
            raise ValueError("Segmented runs require an independent XCTest session.")
        if not self.ensure_session():
            self.controller("halt", "--no-screenshot", timeout=240)
            return self.finish_segment("session-failed")

        initial_probe = self.copy_probe("segment-before-surface")
        initial_copied = self.events[-1].get("success") is True
        initial_cleared = self.clear_probe_after_archive() if initial_copied else False
        before_health = self.record_segment_health_context(
            "before",
            surface_probe_copied=initial_copied,
            surface_probe_cleared=initial_cleared,
        )
        if before_health["passed"] is not True:
            self.controller("halt", "--no-screenshot", timeout=240)
            return self.finish_segment("channel-health-failed")
        self.probe_offset = 0

        fixture_scenarios = {
            "breadcrumbs",
            "docked",
            "library-conditions",
            "library-reference-move",
            "panorama",
            "playback-failures",
            "player-ui-candidates",
            "player-panel-portal-menus",
            "portal",
            "resume-decision",
            "window-playback",
        }
        planned_scenarios = {str(value) for value in self.segment["scenarios"]}
        if planned_scenarios & fixture_scenarios and not self.stage_fixture(
            "furyroad-stripped.mkv"
        ):
            self.controller("halt", "--no-screenshot", timeout=240)
            return self.finish_segment("drive-error")

        reset = self.reset_reachability_state()
        if reset.get("success") is not True:
            self.controller("halt", "--no-screenshot", timeout=240)
            return self.finish_segment("drive-error")
        self.relaunch()
        if planned_scenarios != {"settings-menus"}:
            self.prove_navigation_tab("files")
        if "settings-menus" in planned_scenarios:
            self.prove_navigation_tab("settings")
        for scenario in self.segment["scenarios"]:
            self.run_named_segment_scenario(str(scenario))
            if self.channel_failures:
                break

        self.copy_probe("segment-after-surface")
        final_copied = self.events[-1].get("success") is True
        final_cleared = self.clear_probe_after_archive() if final_copied else False
        after_health = self.record_segment_health_context(
            "after",
            surface_probe_copied=final_copied,
            surface_probe_cleared=final_cleared,
        )
        if self.channel_failures:
            self.controller("halt", "--no-screenshot", timeout=240)
            return self.finish_segment("channel-continuity-failed")
        if after_health["passed"] is not True:
            self.controller("halt", "--no-screenshot", timeout=240)
            return self.finish_segment("channel-health-failed")
        stopped = self.controller("stop", "--no-screenshot", timeout=240)
        if stopped.get("success") is not True:
            self.controller("halt", "--no-screenshot", timeout=240)
            return self.finish_segment("stop-failed")
        return self.finish_segment("complete")

    def finish_segment(self, status: str) -> int:
        assert self.segment is not None
        ordered_cells = [
            self.cells[(presentation, operation_id)]
            for presentation in PRESENTATIONS
            for operation_id in sorted(self.operations)
        ]
        planned = {str(value) for value in self.segment["operations"]}
        driven = [
            {"presentation": presentation, "operation": operation}
            for presentation, operation in sorted(self.driven_cells)
        ]
        result = {
            "schemaVersion": 2,
            "generatedAt": utc_now(),
            "status": status,
            "segment": str(self.segment["id"]),
            "segmentPlan": self.segment,
            "sessionID": self.session_id,
            "channelHealth": self.channel_health,
            "channelContinuity": {
                "passed": not self.channel_failures,
                "failures": self.channel_failures,
            },
            "device": DEVICE,
            "coreDevice": CORE_DEVICE,
            "inventory": str(INVENTORY.relative_to(ROOT)),
            "plannedOperations": sorted(planned),
            "drivenCells": driven,
            "unplannedDrivenCells": [
                cell for cell in driven if cell["operation"] not in planned
            ],
            "stepCount": len(self.events),
            "cells": ordered_cells,
            "events": self.events,
        }
        results_path = self.output / "results.json"
        results_path.write_text(
            json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        print(json.dumps({
            "results": str(results_path),
            "segment": result["segment"],
            "sessionID": self.session_id,
            "status": status,
            "stepCount": result["stepCount"],
            "drivenCellCount": len(driven),
        }, ensure_ascii=False, indent=2, sort_keys=True))
        return 0 if status == "complete" else 2

    def run(self) -> int:
        if self.segment is not None:
            return self.run_segment()
        selected = set(self.arguments.presentations)
        state_reset = False
        window_scenario = (
            self.resume_decision_scenario
            if self.arguments.window_resume_only
            else lambda: (
                self.browser_condition_scenario(),
                self.browser_scenario(),
                self.window_scenario(),
                self.playback_failure_scenario(),
            )
        )
        scenarios = {
            "window": window_scenario,
            "portal": self.portal_scenario,
            "panorama": self.panorama_scenario,
            "docked": self.docked_scenario,
        }
        for presentation in PRESENTATIONS:
            if presentation not in selected:
                continue
            if not self.arguments.reuse_session and not self.ensure_session():
                self.controller("halt", "--no-screenshot", timeout=240)
                self.finish("drive-error")
                return 2
            if presentation == "docked" and not self.stage_fixture(
                "furyroad-stripped.mkv"
            ):
                if not self.arguments.reuse_session:
                    self.controller("halt", "--no-screenshot", timeout=240)
                self.finish("drive-error")
                return 2
            if not state_reset:
                reset = self.reset_reachability_state()
                if reset.get("success") is not True:
                    if not self.arguments.reuse_session:
                        self.controller("halt", "--no-screenshot", timeout=240)
                    self.finish("drive-error")
                    return 2
                self.relaunch()
                state_reset = True
            initial = self.copy_probe(f"{presentation}-initial")
            if initial and self.clear_probe_after_archive():
                self.probe_offset = 0
            else:
                self.probe_offset = len(initial)
            scenarios[presentation]()
        if not self.arguments.reuse_session:
            self.controller("stop", "--no-screenshot", timeout=240)
        return self.finish("complete")

    def finish(self, status: str) -> int:
        ordered_cells = [
            self.cells[(presentation, operation_id)]
            for presentation in PRESENTATIONS
            for operation_id in sorted(self.operations)
        ]
        prior_events: list[dict[str, Any]] = []
        results_path = self.output / "results.json"
        selected = set(self.arguments.presentations)
        if selected != set(PRESENTATIONS) and results_path.is_file():
            prior = json.loads(results_path.read_text(encoding="utf-8"))
            prior_cells = {
                (cell["presentation"], cell["operation"]): cell
                for cell in prior.get("cells", [])
                if isinstance(cell, dict)
            }
            ordered_cells = [
                prior_cells.get((cell["presentation"], cell["operation"]), cell)
                if cell["presentation"] not in selected else cell
                for cell in ordered_cells
            ]
            prior_events = list(prior.get("events", []))
        summary = {
            verdict: sum(cell["verdict"] == verdict for cell in ordered_cells)
            for verdict in ("reachable", "known-defect", "not-applicable")
        }
        result = {
            "schemaVersion": 1,
            "generatedAt": utc_now(),
            "status": status,
            "device": DEVICE,
            "coreDevice": CORE_DEVICE,
            "inventory": str(INVENTORY.relative_to(ROOT)),
            "presentations": list(PRESENTATIONS),
            "summary": summary,
            "cells": ordered_cells,
            "events": prior_events + self.events,
        }
        results_path.write_text(
            json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        regression_failures: list[dict[str, str]] = []
        if BASELINE.is_file():
            baseline = json.loads(BASELINE.read_text(encoding="utf-8"))
            current = {
                (cell["presentation"], cell["operation"]): cell
                for cell in ordered_cells
            }
            for old in baseline.get("cells", []):
                key = (old.get("presentation"), old.get("operation"))
                if key[0] not in selected:
                    continue
                if (
                    key[0] == "window"
                    and key[1] in {
                        "accessibility:PlayerUI-TopAction-dock",
                        "accessibility:PlayerUI-DockMenu-skybox",
                    }
                    and "docked" not in selected
                ):
                    continue
                if (
                    self.arguments.window_resume_only
                    and key[0] == "window"
                    and key[1] not in {
                        "accessibility:PlayerPanel-precision-timeline",
                        "accessibility:PlayerPanel-progress",
                        "accessibility:PlayerUI-InfoBar-button-back",
                        "accessibility:PlayerUI-resumeDecision-primary",
                        "accessibility:PlayerUI-resumeDecision-secondary",
                        "command:seekNormalized",
                    }
                ):
                    continue
                if old.get("verdict") == "reachable" and (
                    key not in current or current[key].get("verdict") != "reachable"
                ):
                    regression_failures.append({
                        "presentation": str(key[0]),
                        "operation": str(key[1]),
                    })
        if (
            self.arguments.accept_baseline
            and status == "complete"
            and not regression_failures
        ):
            existing_baseline_cells: list[dict[str, Any]] = []
            if BASELINE.is_file():
                existing_baseline_cells = json.loads(
                    BASELINE.read_text(encoding="utf-8")
                ).get("cells", [])
            baseline = {
                "schemaVersion": 1,
                "acceptedFrom": str(results_path),
                "acceptedAt": utc_now(),
                "cells": merge_selected_cells_into_baseline(
                    existing_baseline_cells,
                    ordered_cells,
                    selected=selected,
                ),
            }
            BASELINE.write_text(
                json.dumps(baseline, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
                encoding="utf-8",
            )
        regression_path = self.output / "regression.json"
        regression_path.write_text(
            json.dumps(
                {"failures": regression_failures, "passed": not regression_failures},
                ensure_ascii=False,
                indent=2,
                sort_keys=True,
            ) + "\n",
            encoding="utf-8",
        )
        print(json.dumps({
            "results": str(results_path),
            "summary": summary,
            "regressionFailures": regression_failures,
        }, ensure_ascii=False, indent=2, sort_keys=True))
        if regression_failures:
            return 1
        if self.arguments.require_complete and summary["known-defect"]:
            return 1
        return 0


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-directory", type=Path, default=DEFAULT_EVIDENCE)
    parser.add_argument("--derived-data-path", type=Path, default=DEFAULT_DERIVED_DATA)
    parser.add_argument("--reuse-session", action="store_true")
    parser.add_argument("--accept-baseline", action="store_true")
    parser.add_argument("--require-complete", action="store_true")
    parser.add_argument("--window-resume-only", action="store_true")
    parser.add_argument("--segment-plan", type=Path)
    parser.add_argument("--segment")
    parser.add_argument(
        "--merge-segments", nargs="+", type=Path, metavar="RESULTS_JSON"
    )
    parser.add_argument(
        "--presentations", nargs="+", choices=PRESENTATIONS,
        default=list(PRESENTATIONS),
    )
    return parser.parse_args()


def merge_segment_result_files(arguments: argparse.Namespace) -> int:
    baseline = json.loads(BASELINE.read_text(encoding="utf-8"))
    segment_results = [
        json.loads(path.read_text(encoding="utf-8"))
        for path in arguments.merge_segments
    ]
    delivery = merge_segment_delivery(baseline.get("cells", []), segment_results)
    delivery.update({
        "schemaVersion": 1,
        "generatedAt": utc_now(),
        "baseline": str(BASELINE.relative_to(ROOT)),
        "segmentResults": [str(path.resolve()) for path in arguments.merge_segments],
    })
    delivery["summary"] = {
        verdict: sum(
            cell.get("verdict") == verdict
            for cell in delivery["candidateCells"]
        )
        for verdict in ("reachable", "known-defect", "not-applicable")
    }
    arguments.output_directory.mkdir(parents=True, exist_ok=True)
    delivery_path = arguments.output_directory / "delivery.json"
    delivery_path.write_text(
        json.dumps(delivery, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    if arguments.accept_baseline and delivery["accepted"]:
        accepted = {
            "schemaVersion": 1,
            "acceptedFrom": str(delivery_path.resolve()),
            "acceptedAt": utc_now(),
            "cells": [
                {
                    "presentation": cell["presentation"],
                    "operation": cell["operation"],
                    "verdict": cell["verdict"],
                }
                for cell in delivery["candidateCells"]
            ],
        }
        BASELINE.write_text(
            json.dumps(accepted, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    print(json.dumps({
        "accepted": delivery["accepted"],
        "acceptedSegments": delivery["acceptedSegments"],
        "rejectedSegments": delivery["rejectedSegments"],
        "failures": delivery["failures"],
        "summary": delivery["summary"],
        "delivery": str(delivery_path),
    }, ensure_ascii=False, indent=2, sort_keys=True))
    return 0 if delivery["accepted"] else 1


def configure_segment(arguments: argparse.Namespace) -> None:
    if arguments.segment_plan is None or arguments.segment is None:
        raise SystemExit("--segment-plan and --segment must be supplied together")
    plan = json.loads(arguments.segment_plan.read_text(encoding="utf-8"))
    inventory = json.loads(INVENTORY.read_text(encoding="utf-8"))
    errors = validate_segment_plan(
        plan,
        operation_ids={str(item["id"]) for item in inventory["operations"]},
        scenario_names=SEGMENT_SCENARIO_NAMES,
    )
    if errors:
        raise SystemExit("Invalid segment plan:\n" + "\n".join(errors))
    matching = [
        segment for segment in plan["segments"]
        if str(segment["id"]) == arguments.segment
    ]
    if not matching:
        raise SystemExit(f"Segment plan has no segment named {arguments.segment}")
    arguments.segment_spec = matching[0]
    arguments.segment_plan_document = plan
    arguments.presentations = [str(matching[0]["presentation"])]


def main() -> int:
    arguments = parse_arguments()
    if arguments.merge_segments:
        if arguments.segment_plan is not None or arguments.segment is not None:
            raise SystemExit("--merge-segments cannot be combined with --segment")
        return merge_segment_result_files(arguments)
    if arguments.segment_plan is not None or arguments.segment is not None:
        configure_segment(arguments)
    return ReachabilityRun(arguments).run()


if __name__ == "__main__":
    raise SystemExit(main())
