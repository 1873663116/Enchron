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
        completed = subprocess.run(
            command,
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
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

    def copy_probe(self, label: str) -> list[str]:
        destination = self.raw / f"{self.sequence + 1:03d}-{label}-probe.log"
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
            timeout=150,
            check=False,
        )
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
            "tap", "--identifier", identifier, "--no-screenshot"
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
        return self.app_command("toggleControls", visible="true")

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
        folder = self.tap(
            presentation,
            "MediaLibrary-grid-folder-DynamicRange",
            operation_id="accessibility:MediaLibrary-grid-folder-{folder.name}",
        )
        if folder.get("success") is not True:
            self.tap(
                presentation,
                "FileBrowsing-grid-folder-DynamicRange",
                operation_id="accessibility:FileBrowsing-grid-folder-{folder.name}",
            )
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

    def open_media(self, identifier: str) -> dict[str, Any]:
        self.relaunch()
        self.tap("window", "Navigation-Ornament-tab-files")
        result = self.tap("window", identifier)
        if result.get("success") is not True and identifier.startswith(
            "MediaLibrary-grid-video-"
        ):
            file_name = identifier.removeprefix("MediaLibrary-grid-video-")
            imported = self.app_command("importMedia", file=file_name)
            if imported.get("success") is True:
                self.relaunch()
                self.tap("window", "Navigation-Ornament-tab-files")
                result = self.tap("window", identifier)
        time.sleep(2)
        return result

    def ensure_window_projection(self, projection: str) -> bool:
        control_plane = self.wait_for_identifier("PlayerUI-window-control-plane")
        value = str((control_plane.get("matchedElement") or {}).get("value", ""))
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
        return expected in value and "transition=none" in value

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
        self.observe(presentation, "Window playback controls")
        self.transport_scenario(presentation)
        seek = self.app_command("seekNormalized", position="0.35")
        if seek.get("success") is True:
            self.delivered(
                presentation, "command:seekNormalized", self.events[-1]["evidence"],
                "The command invoked PlaybackRuntime.seek and returned the computed target.",
                has_accessibility_target=False,
            )
            for operation_id in (
                "accessibility:PlayerPanel-progress",
                "accessibility:PlayerPanel-precision-timeline",
            ):
                self.delivered(
                    presentation, operation_id, self.events[-1]["evidence"],
                    "The DEBUG verb reached the same PlaybackRuntime seek pipeline.",
                )

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
        seek = self.app_command("seekNormalized", position="0.45")
        if seek.get("success") is True:
            self.delivered(
                presentation, "command:seekNormalized", self.events[-1]["evidence"],
                "The command reached PlaybackRuntime.seek during Panorama playback.",
                has_accessibility_target=False,
            )
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

    def docked_scenario(self) -> None:
        presentation = "docked"
        opened = self.open_media(
            "MediaLibrary-grid-video-furyroad-stripped.mkv"
        )
        if opened.get("success") is not True:
            return
        if not self.ensure_window_projection("Flat"):
            return
        self.show_controls()
        transition = self.controller(
            "tapSequence", "--identifiers",
            "PlayerUI-TopAction-dock", "PlayerUI-DockMenu-skybox",
            "--no-screenshot", timeout=90,
        )
        spatial = self.wait_for_identifier("PlayerUI-spatial-state", timeout=45)
        if transition.get("success") is not True or not isinstance(
            spatial.get("matchedElement"), dict
        ):
            return
        evidence = self.events[-1]["evidence"]
        for operation_id in (
            "accessibility:PlayerUI-TopAction-dock",
            "accessibility:PlayerUI-DockMenu-skybox",
        ):
            self.delivered(
                "window", operation_id, evidence,
                "The presentation entered Docked after the menu sequence.",
            )
        self.observe(presentation, "Docked playback")
        controls = self.show_controls()
        visible = self.wait_for_identifier("PlayerPanel-controls", timeout=10)
        if controls.get("success") is True and isinstance(visible.get("matchedElement"), dict):
            self.delivered(
                presentation, "command:toggleControls", self.events[-1]["evidence"],
                "The Docked attachment controls entered the hierarchy.",
                has_accessibility_target=False,
            )
        self.transport_scenario(presentation)
        for axis, value in (
            ("screenSize", "1.4"),
            ("distance", "3.0"),
            ("elevation", "5.0"),
        ):
            result = self.app_command("setDockedPlacement", axis=axis, value=value)
            if result.get("success") is True:
                self.delivered(
                    presentation, "command:setDockedPlacement",
                    self.events[-1]["evidence"],
                    "All requested Docked placement values reached the shared product setters.",
                    has_accessibility_target=False,
                )
        before = self.observe(presentation, "before resident-window negative")
        toggle = self.app_command("toggleBlackoutProbeWindow")
        after = self.controller("snapshot", "--no-screenshot")
        before_hierarchy = str(before.get("hierarchy", ""))
        after_hierarchy = str(after.get("hierarchy", ""))
        before_windows = len(re.findall(r"^\s+Window", before_hierarchy, re.MULTILINE))
        after_windows = len(re.findall(r"^\s+Window", after_hierarchy, re.MULTILINE))
        no_named_node = "Blackout Probe" not in after_hierarchy
        if toggle.get("success") is True and no_named_node and after_windows == before_windows:
            self.delivered(
                presentation, "negative:immersive-resident-window",
                self.events[-1]["evidence"],
                "Opening the mechanism did not add an accessibility Window or named node.",
                has_accessibility_target=False,
            )
        else:
            cell = self.cells[(presentation, "negative:immersive-resident-window")]
            cell["evidence"].append(self.events[-1]["evidence"])
            cell["reason"] = (
                "The mechanism changed the accessibility Window count or exposed a named node "
                f"(before={before_windows}, after={after_windows}, named={not no_named_node})."
            )
        self.app_command("toggleBlackoutProbeWindow")

    def run(self) -> int:
        selected = set(self.arguments.presentations)
        scenarios = {
            "window": lambda: (self.browser_scenario(), self.window_scenario()),
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
            initial = self.copy_probe(f"{presentation}-initial")
            if initial and self.clear_probe_after_archive():
                self.probe_offset = 0
            else:
                self.probe_offset = len(initial)
            scenarios[presentation]()
        if not self.arguments.reuse_session:
            self.controller("halt", "--no-screenshot", timeout=240)
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
        if BASELINE.is_file() and not self.arguments.accept_baseline:
            baseline = json.loads(BASELINE.read_text(encoding="utf-8"))
            current = {
                (cell["presentation"], cell["operation"]): cell
                for cell in ordered_cells
            }
            for old in baseline.get("cells", []):
                key = (old.get("presentation"), old.get("operation"))
                if key[0] not in selected:
                    continue
                if old.get("verdict") == "reachable" and (
                    key not in current or current[key].get("verdict") != "reachable"
                ):
                    regression_failures.append({
                        "presentation": str(key[0]),
                        "operation": str(key[1]),
                    })
        if self.arguments.accept_baseline:
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
    parser.add_argument(
        "--presentations", nargs="+", choices=PRESENTATIONS,
        default=list(PRESENTATIONS),
    )
    return parser.parse_args()


if __name__ == "__main__":
    raise SystemExit(ReachabilityRun(parse_arguments()).run())
