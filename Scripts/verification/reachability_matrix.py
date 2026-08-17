#!/usr/bin/env python3
"""Drive Enchron's physical-device reachability matrix and preserve raw evidence.

The inventory defines the axes. This runner never promotes XCTest's action return
value to delivery evidence: delivery requires an application probe, diagnostic
state transition, or an app-command response produced after the product handler.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import subprocess
import sys
import time
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
CONTROLLER = ROOT / "Scripts/verification/interactive_visionpro_ui.py"
INVENTORY = ROOT / "Config/reachability_operation_inventory.json"
BASELINE = ROOT / "Config/reachability_matrix_baseline.json"
DEFAULT_EVIDENCE = Path(
    "/Volumes/Cortisol/DevSpace/Xcode/Enchron/TestEvidence/reachability-round2-20260818"
)
DEFAULT_DERIVED_DATA = Path(
    "/Volumes/Cortisol/DevSpace/Xcode/Enchron/DerivedDataReachabilityRound2-20260818"
)
DEVICE = "00008142-001871A11491401C"
CORE_DEVICE = "59E3D57A-0288-53DC-9A7D-B657B6939558"
DEVELOPER_DIR = "/Volumes/Cortisol/Applications/Xcode-beta5.app/Contents/Developer"
APP_BUNDLE = "com.xiongzhipeng.XrPlayer"
PRESENTATIONS = ("window", "portal", "panorama", "docked")
PROBE_REMOTE_PATH = "Documents/surface-tap-probe.log"
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
        self.sequence = 0
        self.probe_offset = 0
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
        return document

    def app_command(self, verb: str, **arguments: str) -> dict[str, Any]:
        extra = ["--verb", verb, "--no-screenshot"]
        for key, value in arguments.items():
            extra.extend(("--arg", f"{key}={value}"))
        return self.controller("app-command", *extra)

    def copy_probe(self, label: str, *, timeout: float = 150) -> list[str]:
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
        if cell["applicationReceived"] is True:
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
        self.mark_observation(
            presentation,
            operation_id,
            exists=True if has_accessibility_target else None,
            hittable=True if has_accessibility_target else None,
            received=True,
            evidence=evidence,
            reason=reason,
        )

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
        return ready.get("success") is True

    def show_controls(self) -> dict[str, Any]:
        result = self.app_command("toggleControls", visible="true")
        if result.get("success") is not True and "file node" in str(
            result.get("error", "")
        ):
            time.sleep(0.5)
            result = self.app_command("toggleControls", visible="true")
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
            "MediaLibrary-grid-folder-DynamicRange",
            operation_id="accessibility:MediaLibrary-grid-folder-{folder.name}",
        )
        if folder.get("success") is not True:
            folder = self.tap(
                presentation,
                "FileBrowsing-grid-folder-DynamicRange",
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

    def open_source_connection(
        self, source: str
    ) -> tuple[dict[str, Any], list[str]]:
        presentation = "window"
        before = self.copy_probe(f"source-connection-{source}-open-before")
        offset = len(before)
        opened = self.controller(
            "tapSequence",
            "--identifiers",
            "FileBrowsing-SourcesSidebar-sourceMore",
            "plus",
            f"FileBrowsing-SourcesSidebar-add{source}",
            "--no-screenshot",
            "--timeout-seconds",
            "90",
            timeout=120,
        )
        probe = self.copy_probe(f"source-connection-{source}-opened")
        recent = probe[offset:]
        if opened.get("success") is True and any(
            "reachability files delivered action=sourceSidebar.sourceMore" in line
            for line in recent
        ):
            self.delivered(
                presentation,
                "accessibility:FileBrowsing-SourcesSidebar-sourceMore",
                self.events[-1]["evidence"],
                "Opening the source menu constructed its product-owned actions and appended a probe.",
            )
        source_value = "smb" if source == "SMB" else "webDAV"
        if opened.get("success") is True and any(
            f"reachability files delivered action=sidebar.add.{source_value}" in line
            for line in recent
        ):
            self.delivered(
                presentation,
                f"accessibility:FileBrowsing-SourcesSidebar-add{source}",
                self.events[-1]["evidence"],
                "The source-type action reached FilesScreen and presented its connection form.",
            )
        return opened, probe

    def type_source_connection_field(
        self, source: str, field: str, value: str, probe: list[str]
    ) -> list[str]:
        presentation = "window"
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
        for identifier, expected_action, nested in (
            ("addFiles", "sidebar.add.local", True),
            ("addFolder", "sidebar.addFolder", True),
            ("addPhotos", "sidebar.add.photoLibrary", True),
            ("refresh", "sidebar.refresh", False),
        ):
            self.relaunch()
            self.tap(presentation, "Navigation-Ornament-tab-files")
            before = self.copy_probe(f"source-sidebar-{identifier}-before")
            offset = len(before)
            sequence = ["FileBrowsing-SourcesSidebar-sourceMore"]
            if nested:
                sequence.append("plus")
            sequence.append(f"FileBrowsing-SourcesSidebar-{identifier}")
            response = self.controller(
                "tapSequence",
                "--identifiers",
                *sequence,
                "--no-screenshot",
                "--timeout-seconds",
                "90",
                timeout=120,
            )
            probe = self.copy_probe(f"source-sidebar-{identifier}")
            if response.get("success") is True and any(
                f"reachability files delivered action={expected_action}" in line
                for line in probe[offset:]
            ):
                self.delivered(
                    presentation,
                    f"accessibility:FileBrowsing-SourcesSidebar-{identifier}",
                    self.events[-1]["evidence"],
                    "The source-sidebar action reached its FilesScreen handler and appended an action probe.",
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

    def browser_condition_scenario(self) -> None:
        presentation = "window"
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

        self.tap(presentation, "FileBrowsing-FilesScreen-sort")
        before = self.copy_probe("browser-sort-before")
        offset = len(before)
        sort = self.controller("tap", "--label", "Size", "--no-screenshot")
        probe = self.copy_probe("browser-sort-selected")
        if sort.get("success") is True and any(
            "reachability files delivered action=files.sort" in line
            for line in probe[offset:]
        ):
            self.delivered(
                presentation, "accessibility:FileBrowsing-FilesScreen-sort",
                self.events[-1]["evidence"],
                "The sort Picker changed its product sort criteria and appended a probe.",
            )

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
        opened = self.controller(
            "tapSequence", "--identifiers",
            "FileBrowsing-Manage-button", "MediaLibrary-Manage-newFolder",
            "--no-screenshot", "--timeout-seconds", "90", timeout=120,
        )
        probe = self.copy_probe("browser-new-folder-open")
        recent = probe[offset:]
        if opened.get("success") is True:
            for operation_id, fact in (
                ("accessibility:FileBrowsing-Manage-button", "manage.open"),
                ("accessibility:MediaLibrary-Manage-newFolder", "manage.newFolder"),
            ):
                if any(
                    f"reachability files delivered action={fact}" in line
                    for line in recent
                ):
                    self.delivered(
                        presentation, operation_id, self.events[-1]["evidence"],
                        "The Manage menu path appended its action-specific product probe.",
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
            # multi-selection controls.
            self.tap(presentation, "MediaLibrary-Breadcrumb-current")
            self.controller("tap", "--label", "Media Library", "--no-screenshot")

        before = self.copy_probe("browser-multiselect-before")
        offset = len(before)
        selection = self.controller(
            "tapSequence", "--identifiers",
            "FileBrowsing-Manage-button", "MediaLibrary-Manage-selectMultiple",
            "--no-screenshot", "--timeout-seconds", "90", timeout=120,
        )
        probe = self.copy_probe("browser-multiselect-open")
        if selection.get("success") is True and any(
            "reachability files delivered action=manage.selectMultiple" in line
            for line in probe[offset:]
        ):
            self.delivered(
                presentation, "accessibility:MediaLibrary-Manage-selectMultiple",
                self.events[-1]["evidence"],
                "The Manage action entered Media Library multi-selection mode.",
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
        probe = self.copy_probe("open-media-selected")
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

        def open_editor() -> bool:
            self.show_controls()
            opened = self.tap(presentation, open_identifier)
            visible = self.wait_for_identifier(
                f"{identifier_prefix}-cancel", timeout=10
            )
            return opened.get("success") is True and isinstance(
                visible.get("matchedElement"), dict
            )

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

            offset = len(probe)
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

        if open_editor():
            before = self.copy_probe(
                f"{identifier_prefix}-custom-angle-before"
            )
            offset = len(before)
            picker = self.tap(
                presentation, f"{identifier_prefix}-CustomAngle"
            )
            selected = (
                self.controller(
                    "tap", "--label", "180°", "--no-screenshot", timeout=90
                )
                if picker.get("success") is True
                else {"success": False}
            )
            probe = self.wait_for_probe(
                f"{identifier_prefix}-custom-angle",
                offset,
                f"{probe_prefix}videoFormat.customAngle",
            )
            if selected.get("success") is True and any(
                f"{probe_prefix}videoFormat.customAngle" in line
                for line in probe[offset:]
            ):
                self.delivered(
                    presentation,
                    f"accessibility:{identifier_prefix}-CustomAngle",
                    self.events[-1]["evidence"],
                    "The custom-angle Picker changed its editor binding and appended a probe.",
                )
            self.tap(presentation, f"{identifier_prefix}-cancel")

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
            self.tap(presentation, f"{identifier_prefix}-cancel")

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
        self.transport_scenario(presentation)
        self.seek_scenario(presentation, "0.35")
        self.top_menu_scenario(presentation)
        self.resume_decision_scenario()

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
        self.show_controls()
        before = self.copy_probe(f"{presentation}-top-menu-before")
        offset = len(before)
        opened = self.tap(presentation, "PlayerUI-TopAction-more")
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

        # Complete a real selection so the first system-owned Menu closes before
        # opening another path. Reusing the open Menu leaves the top action hidden.
        speed = self.controller(
            "tap", "--label", "Playback Speed", "--no-screenshot", timeout=90,
        )
        if speed.get("success") is True:
            self.controller(
                "tap", "--label", "1.25×", "--no-screenshot", timeout=90,
            )

        # Selection is the delivery boundary for the system-owned submenu. Merely
        # seeing its label or constructing its content is not enough.
        self.show_controls()
        before = self.copy_probe(f"{presentation}-top-subtitles-before")
        offset = len(before)
        submenu = self.controller(
            "tapSequence", "--identifiers",
            "PlayerUI-TopAction-more", "PlayerUI-menu-subtitles",
            "--no-screenshot", "--timeout-seconds", "90", timeout=120,
        )
        selected = self.controller(
            "tap", "--label", "Off", "--no-screenshot", timeout=90,
        ) if submenu.get("success") is True else {"success": False}
        probe = self.copy_probe(f"{presentation}-top-subtitles-selected")
        if selected.get("success") is True and any(
            "reachability top actions delivered action=menu.item.off" in line
            for line in probe[offset:]
        ):
            self.delivered(
                presentation, "accessibility:PlayerUI-menu-subtitles",
                self.events[-1]["evidence"],
                "A subtitle choice ran the product selection binding and appended an item probe.",
            )

    def stop_playback(self, presentation: str) -> bool:
        self.show_controls()
        before = self.copy_probe(f"{presentation}-back-before")
        offset = len(before)
        stopped = self.tap(presentation, "PlayerUI-InfoBar-button-back")
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
        self.show_controls()
        before = self.copy_probe(f"{presentation}-panel-menu-before")
        offset = len(before)
        self.controller(
            "tapSequence", "--identifiers",
            "PlayerPanel-menu-more", "PlayerPanel-menu-speed",
            "--no-screenshot", "--timeout-seconds", "90", timeout=120,
        )
        probe = self.copy_probe(f"{presentation}-panel-menu-open")
        recent = probe[offset:]
        for operation_id, fact in (
            ("accessibility:PlayerPanel-menu-more", "menu.more"),
            ("accessibility:PlayerPanel-menu-speed", "menu.speed"),
            ("accessibility:PlayerPanel-menu-subtitles", "menu.subtitle"),
            ("accessibility:PlayerPanel-menu-audio", "menu.audio"),
            ("accessibility:PlayerPanel-menu-episodes", "menu.episode"),
        ):
            if any(
                f"reachability playerPanel delivered action={fact}" in line
                for line in recent
            ):
                self.delivered(
                    presentation,
                    operation_id,
                    self.events[-1]["evidence"],
                    "The PlayerPanel menu content appended its action-specific product probe.",
                )

        item_offset = len(probe)
        speed = self.controller(
            "tap", "--label", "1.25×", "--no-screenshot", timeout=90,
        )
        probe = self.copy_probe(f"{presentation}-panel-speed-selected")
        if speed.get("success") is True and any(
            "reachability playerPanel delivered action=menu.item." in line
            for line in probe[item_offset:]
        ):
            self.delivered(
                presentation,
                "accessibility:PlayerPanel-menu-{category}-{item.id}",
                self.events[-1]["evidence"],
                "The selected menu item appended its product item probe.",
            )

        for category in ("subtitles",):
            self.show_controls()
            before = self.copy_probe(f"{presentation}-panel-{category}-before")
            offset = len(before)
            self.controller(
                "tapSequence", "--identifiers",
                "PlayerPanel-menu-more", f"PlayerPanel-menu-{category}",
                "--no-screenshot", "--timeout-seconds", "90", timeout=120,
            )
            probe = self.copy_probe(f"{presentation}-panel-{category}-open")
            singular = category.removesuffix("s")
            submenu_delivered = any(
                f"reachability playerPanel delivered action=menu.{singular}" in line
                for line in probe[offset:]
            )
            if submenu_delivered:
                self.delivered(
                    presentation, f"accessibility:PlayerPanel-menu-{category}",
                    self.events[-1]["evidence"],
                    "The product submenu entered its active content state and appended a probe.",
                )
            if category == "subtitles" and submenu_delivered:
                before = probe
                offset = len(before)
                selected = self.controller(
                    "tap", "--label", "Off", "--no-screenshot", timeout=90,
                )
                probe = self.copy_probe(
                    f"{presentation}-panel-{category}-selected"
                )
                if selected.get("success") is True and any(
                    "reachability playerPanel delivered action=menu.item.off" in line
                    for line in probe[offset:]
                ):
                    self.delivered(
                        presentation,
                        "accessibility:PlayerPanel-menu-{category}-{item.id}",
                        self.events[-1]["evidence"],
                        "The subtitle menu ran an explicit product item action and appended its selection probe.",
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
        if toggle.get("success") is True and no_named_node and no_new_identifier:
            self.delivered(
                presentation, "negative:immersive-resident-window",
                self.events[-1]["evidence"],
                "Opening the mechanism added no named or identifier-addressable Accessibility target.",
                has_accessibility_target=False,
            )
        else:
            cell = self.cells[(presentation, "negative:immersive-resident-window")]
            cell["evidence"].append(self.events[-1]["evidence"])
            cell["reason"] = (
                "The mechanism exposed a named or identifier-addressable Accessibility target "
                f"(newIdentifiers={sorted(after_identifiers - before_identifiers)}, "
                f"named={not no_named_node})."
            )
        self.app_command("toggleBlackoutProbeWindow")

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

    def run(self) -> int:
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
                reset = self.app_command("resetState")
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
            baseline = {
                "schemaVersion": 1,
                "acceptedFrom": str(results_path),
                "acceptedAt": utc_now(),
                "cells": [
                    {
                        "presentation": cell["presentation"],
                        "operation": cell["operation"],
                        "verdict": cell["verdict"],
                    }
                    for cell in ordered_cells
                ],
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
    parser.add_argument(
        "--presentations", nargs="+", choices=PRESENTATIONS,
        default=list(PRESENTATIONS),
    )
    return parser.parse_args()


if __name__ == "__main__":
    raise SystemExit(ReachabilityRun(parse_arguments()).run())
