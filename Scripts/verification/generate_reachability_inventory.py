#!/usr/bin/env python3
"""Generate and verify Enchron's source-derived accessibility inventory."""

from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass
import json
from pathlib import Path
import re
import sys


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
OUTPUT = REPOSITORY_ROOT / "Config/reachability_operation_inventory.json"
MATRIX_BASELINE = REPOSITORY_ROOT / "Config/reachability_matrix_baseline.json"
PRESENTATIONS = ("window", "portal", "panorama", "docked")
SOURCE_ROOTS = (
    REPOSITORY_ROOT / "Apps/Enchron",
    REPOSITORY_ROOT / "Modules/DesignSystem",
    REPOSITORY_ROOT / "Modules/Emby",
    REPOSITORY_ROOT / "Modules/MediaLibrary",
    REPOSITORY_ROOT / "Modules/PlaybackPresentation",
)
IDENTIFIER_FAMILIES = (
    "AcousticCalibration-",
    "DesignPreview-",
    "DesignSystem-",
    "Emby-",
    "EnvironmentCard-",
    "FileBrowsing-",
    "MediaLibrary-",
    "Navigation-",
    "PlayerPanel-",
    "PlayerUI-",
    "SampleBufferAcousticCalibration-",
    "SenseZone-",
    "Settings-",
    "WindowPlayback-",
)


@dataclass(frozen=True, order=True)
class SourceLocation:
    path: str
    line: int


def matching_parenthesis(text: str, opening: int) -> int | None:
    depth = 1
    index = opening + 1
    while index < len(text):
        if text.startswith("//", index):
            end = text.find("\n", index + 2)
            index = len(text) if end < 0 else end + 1
            continue
        if text.startswith("/*", index):
            depth_comment = 1
            index += 2
            while index < len(text) and depth_comment:
                if text.startswith("/*", index):
                    depth_comment += 1
                    index += 2
                elif text.startswith("*/", index):
                    depth_comment -= 1
                    index += 2
                else:
                    index += 1
            continue
        if text[index] == '"':
            _, index = swift_string(text, index)
            continue
        if text[index] == "(":
            depth += 1
        elif text[index] == ")":
            depth -= 1
            if depth == 0:
                return index
        index += 1
    return None


def swift_string(text: str, opening: int) -> tuple[str, int]:
    """Return one ordinary Swift string as a symbolic template and its end."""
    parts: list[str] = []
    index = opening + 1
    while index < len(text):
        character = text[index]
        if character == '"':
            return "".join(parts), index + 1
        if character == "\\" and index + 1 < len(text):
            following = text[index + 1]
            if following == "(":
                closing = matching_parenthesis(text, index + 1)
                if closing is None:
                    return "".join(parts), len(text)
                expression = " ".join(text[index + 2 : closing].split())
                parts.append("{" + expression + "}")
                index = closing + 1
                continue
            escapes = {"n": "\\n", "r": "\\r", "t": "\\t"}
            parts.append(escapes.get(following, following))
            index += 2
            continue
        parts.append(character)
        index += 1
    return "".join(parts), len(text)


def source_strings(text: str) -> list[tuple[str, int]]:
    strings: list[tuple[str, int]] = []
    index = 0
    while index < len(text):
        if text.startswith("//", index):
            end = text.find("\n", index + 2)
            index = len(text) if end < 0 else end + 1
            continue
        if text.startswith("/*", index):
            depth = 1
            index += 2
            while index < len(text) and depth:
                if text.startswith("/*", index):
                    depth += 1
                    index += 2
                elif text.startswith("*/", index):
                    depth -= 1
                    index += 2
                else:
                    index += 1
            continue
        if text.startswith('"""', index):
            end = text.find('"""', index + 3)
            index = len(text) if end < 0 else end + 3
            continue
        if text[index] == '"':
            line = text.count("\n", 0, index) + 1
            value, index = swift_string(text, index)
            strings.append((value, line))
            continue
        index += 1
    return strings


def family(template: str) -> str | None:
    for prefix in IDENTIFIER_FAMILIES:
        if template.startswith(prefix):
            return prefix.removesuffix("-")
    return None


def identifier_role(template: str) -> tuple[str, str | None]:
    lowered = template.lower()
    if lowered in {
        "emby-search",
        "playerui-dockmenu",
        "playerui-videoformat",
    } or lowered.endswith((
        "-error",
        "-panel",
        "-state",
        "-time-bubble",
        "-thumb",
    )):
        return "observation", None
    if any(
        marker in lowered
        for marker in (
            "-address",
            "-username",
            "-password",
            "-name",
            "-search",
            "-field",
        )
    ) and not any(marker in lowered for marker in ("-error", "-state")):
        return "operation", "typeText"
    if any(
        marker in lowered
        for marker in ("slider", "progress", "timeline")
    ):
        return "operation", "adjust"
    if any(
        marker in lowered
        for marker in (
            "button",
            "-tab-",
            "-tab",
            "-menu-",
            "-topaction-",
            "-dockmenu-",
            "-effect-",
            "-source-",
            "-row-",
            "-grid-",
            "-card-",
            "card-",
            "-episode-",
            "-season-",
            "-connect",
            "-signout",
            "-sort",
            "-viewmode",
            "-sidebartoggle",
            "-back",
            "-forward",
            "-apply",
            "-cancel",
            "-confirm",
            "-dismiss",
            "-reset",
            "-automatic",
            "-customangle",
            "-hdrfallback",
            "-resume",
            "-primary",
            "-secondary",
            "playfrombeginning",
            "overview-expand",
            "-create",
            "-addfiles",
            "-addfolder",
            "-addphotos",
            "-newfolder",
            "-selectmultiple",
            "-move",
            "-delete",
            "-done",
            "-close",
            "-refresh",
        )
    ):
        return "operation", "activate"
    return "observation", None


def source_scope(template: str) -> str:
    if template.startswith(("AcousticCalibration-", "SampleBufferAcousticCalibration-")):
        return "debug-calibration"
    if template.startswith("DesignPreview-"):
        return "component-default"
    if template == "PlayerUI-debug-evidence":
        return "debug-diagnostic"
    return "product"


def build_inventory() -> dict[str, object]:
    identifiers: dict[str, list[SourceLocation]] = {}
    for root in SOURCE_ROOTS:
        for path in sorted(root.rglob("*.swift")):
            text = path.read_text(encoding="utf-8")
            relative = path.relative_to(REPOSITORY_ROOT).as_posix()
            for template, line in source_strings(text):
                if family(template) is None:
                    continue
                identifiers.setdefault(template, []).append(
                    SourceLocation(relative, line)
                )

    records: list[dict[str, object]] = []
    operations: list[dict[str, object]] = []
    for template, locations in sorted(identifiers.items()):
        role, action = identifier_role(template)
        record = {
            "template": template,
            "family": family(template),
            "scope": source_scope(template),
            "role": role,
            "action": action,
            "sources": [asdict(location) for location in sorted(set(locations))],
        }
        records.append(record)
        if role == "operation" and record["scope"] == "product":
            operations.append(
                {
                    "id": "accessibility:" + template,
                    "kind": action,
                    "identifierTemplate": template,
                    "source": "accessibilityIdentifier",
                }
            )

    semantic_operations = [
        {
            "id": "command:toggleControls",
            "kind": "command",
            "presentations": ["window", "portal", "panorama", "docked"],
            "source": "Apps/Enchron/TestCommandChannel.swift",
        },
        {
            "id": "command:setWindowSize",
            "kind": "command",
            "presentations": ["portal"],
            "source": "Apps/Enchron/TestCommandChannel.swift",
        },
        {
            "id": "command:seekNormalized",
            "kind": "command",
            "presentations": ["window", "portal", "panorama", "docked"],
            "source": "Apps/Enchron/TestCommandChannel.swift",
        },
        {
            "id": "command:setDockedPlacement",
            "kind": "command",
            "presentations": ["docked"],
            "source": "Apps/Enchron/TestCommandChannel.swift",
        },
        {
            "id": "environmentVolume:open-interact-close",
            "kind": "compound",
            "presentations": ["window", "docked"],
            "source": "Apps/Enchron/MainView.swift",
        },
        {
            "id": "scroll:file-list",
            "kind": "scroll",
            "presentations": ["window"],
            "source": "Apps/Enchron/Screens/FilesScreen.swift",
        },
        {
            "id": "scroll:emby",
            "kind": "scroll",
            "presentations": ["window"],
            "source": "Modules/Emby/EmbyScreens.swift",
        },
        {
            "id": "negative:immersive-resident-window",
            "kind": "negative",
            "presentations": ["panorama", "docked"],
            "source": "Apps/Enchron/EnchronApp.swift",
        },
    ]
    return {
        "version": 1,
        "sourceRoots": [
            root.relative_to(REPOSITORY_ROOT).as_posix() for root in SOURCE_ROOTS
        ],
        "identifierFamilies": [prefix.removesuffix("-") for prefix in IDENTIFIER_FAMILIES],
        "identifiers": records,
        "operations": sorted(operations + semantic_operations, key=lambda item: item["id"]),
    }


def encoded_inventory() -> str:
    return json.dumps(build_inventory(), ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--write",
        action="store_true",
        help="Replace the version-controlled inventory with the current source result.",
    )
    arguments = parser.parse_args()
    generated = encoded_inventory()
    if arguments.write:
        OUTPUT.write_text(generated, encoding="utf-8")
        print(f"wrote {OUTPUT.relative_to(REPOSITORY_ROOT)}")
        return 0
    if not OUTPUT.is_file():
        print(f"missing {OUTPUT.relative_to(REPOSITORY_ROOT)}; rerun with --write", file=sys.stderr)
        return 1
    current = OUTPUT.read_text(encoding="utf-8")
    if current != generated:
        print(
            "reachability inventory drifted; run "
            "Scripts/verification/generate_reachability_inventory.py --write",
            file=sys.stderr,
        )
        return 1
    if MATRIX_BASELINE.is_file():
        baseline = json.loads(MATRIX_BASELINE.read_text(encoding="utf-8"))
        expected = {
            (presentation, str(operation["id"]))
            for presentation in PRESENTATIONS
            for operation in build_inventory()["operations"]
        }
        actual = {
            (str(cell.get("presentation")), str(cell.get("operation")))
            for cell in baseline.get("cells", [])
            if isinstance(cell, dict)
        }
        if actual != expected:
            print(
                "reachability matrix baseline does not cover the current inventory; "
                "run the physical matrix with --accept-baseline",
                file=sys.stderr,
            )
            return 1
    payload = json.loads(current)
    print(
        "reachability inventory: "
        f"{len(payload['identifiers'])} identifier templates, "
        f"{len(payload['operations'])} operations"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
