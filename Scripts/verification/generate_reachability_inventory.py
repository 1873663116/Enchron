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
SETTINGS_MENU_FAMILIES = (
    "resume-strategy",
    "end-behavior",
    "default-scenic-environment",
    "default-speed",
    "controls-auto-hide",
)
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

DEBUG_MENU_EQUIVALENTS: dict[str, dict[str, object]] = {
    "accessibility:FileBrowsing-FilesScreen-sort": {
        "host": "files",
        "families": ["sortKey", "sortOrder"],
        "parentOperation": "accessibility:FileBrowsing-FilesScreen-sort",
    },
    "accessibility:FileBrowsing-Breadcrumb-current": {
        "host": "files",
        "families": ["breadcrumb"],
        "parentOperation": "accessibility:FileBrowsing-Breadcrumb-current",
    },
    "accessibility:MediaLibrary-Breadcrumb-current": {
        "host": "mediaLibrary",
        "families": ["breadcrumb"],
        "parentOperation": "accessibility:MediaLibrary-Breadcrumb-current",
    },
    "accessibility:MediaLibrary-MultiSelect-move": {
        "host": "mediaLibrary",
        "families": ["moveDestination"],
        "parentOperation": "accessibility:MediaLibrary-MultiSelect-move",
    },
    "accessibility:Emby-Detail-Version": {
        "host": "emby",
        "families": ["version"],
        "parentOperation": "accessibility:Emby-Detail-Version",
    },
    "accessibility:Emby-Season-Picker": {
        "host": "emby",
        "families": ["season"],
        "parentOperation": "accessibility:Emby-Season-Picker",
    },
    "accessibility:Emby-Season-{season.metadata.id.rawValue}": {
        "host": "emby",
        "families": ["season"],
        "parentOperation": "accessibility:Emby-Season-Picker",
    },
    "accessibility:PlayerUI-menu-subtitles": {
        "host": "playerUI",
        "families": ["subtitles"],
        "parentOperation": "accessibility:PlayerUI-TopAction-more",
    },
    "accessibility:PlayerUI-VideoFormat-CustomAngle": {
        "host": "playerUI",
        "families": ["customAngle"],
        "parentOperation": "accessibility:PlayerUI-VideoFormat-CustomAngle",
    },
    "accessibility:PlayerPanel-VideoFormat-CustomAngle": {
        "host": "playerPanel",
        "families": ["customAngle"],
        "parentOperation": "accessibility:PlayerPanel-VideoFormat-CustomAngle",
    },
    "accessibility:PlayerPanel-menu-speed": {
        "host": "playerPanel",
        "families": ["speed"],
        "parentOperation": "accessibility:PlayerPanel-menu-more",
    },
    "accessibility:PlayerPanel-menu-subtitles": {
        "host": "playerPanel",
        "families": ["subtitles"],
        "parentOperation": "accessibility:PlayerPanel-menu-more",
    },
    "accessibility:PlayerPanel-menu-audio": {
        "host": "playerPanel",
        "families": ["audio"],
        "parentOperation": "accessibility:PlayerPanel-menu-more",
    },
    "accessibility:PlayerPanel-menu-episodes": {
        "host": "playerPanel",
        "families": ["episodes"],
        "parentOperation": "accessibility:PlayerPanel-menu-more",
    },
    "accessibility:PlayerPanel-menu-{category}-{item.id}": {
        "host": "playerPanel",
        "families": ["subtitles", "audio", "speed", "episodes"],
        "parentOperation": "accessibility:PlayerPanel-menu-more",
    },
}

for identifier, family, target in (
    ("MediaLibrary-Manage-addFiles", "manage", "addFiles"),
    ("MediaLibrary-Manage-addFolder", "manage", "addFolder"),
    ("MediaLibrary-Manage-addPhotos", "manage", "addPhotos"),
    ("MediaLibrary-Manage-newFolder", "manage", "newFolder"),
    ("MediaLibrary-Manage-selectMultiple", "manage", "selectMultiple"),
    ("FileBrowsing-SourcesSidebar-addFiles", "sourceAdd", "local"),
    ("FileBrowsing-SourcesSidebar-addFolder", "sourceAdd", "folder"),
    ("FileBrowsing-SourcesSidebar-addPhotos", "sourceAdd", "photoLibrary"),
    ("FileBrowsing-SourcesSidebar-addWebDAV", "sourceAdd", "webDAV"),
    ("FileBrowsing-SourcesSidebar-addSMB", "sourceAdd", "smb"),
    ("FileBrowsing-SourcesSidebar-refresh", "sourceAction", "refresh"),
    ("FileBrowsing-SourcesSidebar-delete", "sourceAction", "delete"),
):
    DEBUG_MENU_EQUIVALENTS[f"accessibility:{identifier}"] = {
        "host": "files",
        "families": [family],
        "target": target,
        "parentOperation": (
            "accessibility:FileBrowsing-Manage-button"
            if family == "manage"
            else "accessibility:FileBrowsing-SourcesSidebar-sourceMore"
        ),
    }


@dataclass(frozen=True, order=True)
class SourceLocation:
    path: str
    line: int


class RuntimeIdentifierResolutionError(ValueError):
    """A component-built accessibility identifier cannot be enumerated."""


@dataclass(frozen=True)
class SwiftStruct:
    name: str
    path: str
    body: str
    body_offset: int


@dataclass(frozen=True)
class SwiftFunction:
    name: str
    path: str
    parameters: str
    body: str
    body_offset: int


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


def matching_brace(text: str, opening: int) -> int | None:
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
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
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


def swift_structs(documents: dict[str, str]) -> list[SwiftStruct]:
    structs: list[SwiftStruct] = []
    declaration = re.compile(r"\bstruct\s+([A-Za-z_][A-Za-z0-9_]*)[^\{]*\{")
    for path, text in documents.items():
        for match in declaration.finditer(text):
            opening = text.find("{", match.start())
            closing = matching_brace(text, opening)
            if closing is None:
                continue
            structs.append(
                SwiftStruct(
                    name=match.group(1),
                    path=path,
                    body=text[opening + 1 : closing],
                    body_offset=opening + 1,
                )
            )
    return structs


def swift_functions(documents: dict[str, str]) -> list[SwiftFunction]:
    functions: list[SwiftFunction] = []
    declaration = re.compile(r"\bfunc\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(")
    for path, text in documents.items():
        for match in declaration.finditer(text):
            parameters_opening = text.find("(", match.start())
            parameters_closing = matching_parenthesis(text, parameters_opening)
            if parameters_closing is None:
                continue
            body_opening = text.find("{", parameters_closing + 1)
            if body_opening < 0:
                continue
            body_closing = matching_brace(text, body_opening)
            if body_closing is None:
                continue
            functions.append(
                SwiftFunction(
                    name=match.group(1),
                    path=path,
                    parameters=text[parameters_opening + 1 : parameters_closing],
                    body=text[body_opening + 1 : body_closing],
                    body_offset=body_opening + 1,
                )
            )
    return functions


def split_swift_arguments(arguments: str) -> list[str]:
    parts: list[str] = []
    start = 0
    index = 0
    depths = {"(": 0, "[": 0, "{": 0}
    closing_to_opening = {")": "(", "]": "[", "}": "{"}
    while index < len(arguments):
        if arguments.startswith("//", index):
            end = arguments.find("\n", index + 2)
            index = len(arguments) if end < 0 else end + 1
            continue
        if arguments.startswith("/*", index):
            end = arguments.find("*/", index + 2)
            index = len(arguments) if end < 0 else end + 2
            continue
        if arguments[index] == '"':
            _, index = swift_string(arguments, index)
            continue
        character = arguments[index]
        if character in depths:
            depths[character] += 1
        elif character in closing_to_opening:
            depths[closing_to_opening[character]] -= 1
        elif character == "," and not any(depths.values()):
            parts.append(arguments[start:index])
            start = index + 1
        index += 1
    parts.append(arguments[start:])
    return parts


def labelled_argument(arguments: str, label: str) -> str | None:
    for argument in split_swift_arguments(arguments):
        match = re.match(
            rf"\s*{re.escape(label)}\s*:\s*(.*)\Z",
            argument,
            flags=re.DOTALL,
        )
        if match:
            return match.group(1)
    return None


def component_prefixes(
    component: SwiftStruct,
    prefix_name: str,
    documents: dict[str, str],
) -> dict[str, list[SourceLocation]]:
    prefixes: dict[str, list[SourceLocation]] = {}

    default = re.search(
        rf"\b(?:let|var)\s+{re.escape(prefix_name)}\s*"
        rf"(?::\s*String\s*)?=\s*(\"(?:\\.|[^\"])*\")",
        component.body,
    )
    if default:
        for template, relative_line in source_strings(default.group(1)):
            if is_identifier_family_base(template):
                line = (
                    documents[component.path].count(
                        "\n", 0, component.body_offset + default.start()
                    )
                    + relative_line
                )
                prefixes.setdefault(template, []).append(
                    SourceLocation(component.path, line)
                )

    call = re.compile(rf"\b{re.escape(component.name)}\s*\(")
    for path, text in documents.items():
        for match in call.finditer(text):
            opening = text.find("(", match.start())
            closing = matching_parenthesis(text, opening)
            if closing is None:
                continue
            value = labelled_argument(text[opening + 1 : closing], prefix_name)
            if value is None:
                continue
            for template, relative_line in source_strings(value):
                if not is_identifier_family_base(template):
                    continue
                call_line = text.count("\n", 0, opening + 1) + relative_line
                prefixes.setdefault(template, []).append(
                    SourceLocation(path, call_line)
                )
    return prefixes


def function_prefixes(
    function: SwiftFunction,
    prefix_name: str,
    documents: dict[str, str],
) -> dict[str, list[SourceLocation]]:
    prefixes: dict[str, list[SourceLocation]] = {}
    declaration_value = labelled_argument(function.parameters, prefix_name)
    if declaration_value is not None:
        for template, relative_line in source_strings(declaration_value):
            if not is_identifier_family_base(template):
                continue
            prefixes.setdefault(template, []).append(
                SourceLocation(
                    function.path,
                    documents[function.path].count(
                        "\n", 0, function.body_offset - len(function.parameters)
                    )
                    + relative_line,
                )
            )

    call = re.compile(rf"\b{re.escape(function.name)}\s*\(")
    for path, text in documents.items():
        for match in call.finditer(text):
            opening = text.find("(", match.start())
            closing = matching_parenthesis(text, opening)
            if closing is None:
                continue
            value = labelled_argument(text[opening + 1 : closing], prefix_name)
            if value is None:
                continue
            for template, relative_line in source_strings(value):
                if not is_identifier_family_base(template):
                    continue
                call_line = text.count("\n", 0, opening + 1) + relative_line
                prefixes.setdefault(template, []).append(
                    SourceLocation(path, call_line)
                )
    return prefixes


def accessibility_identifier_expressions(body: str) -> list[tuple[str, int]]:
    expressions: list[tuple[str, int]] = []
    modifier = re.compile(r"\.accessibilityIdentifier\s*\(")
    for match in modifier.finditer(body):
        opening = body.find("(", match.start())
        closing = matching_parenthesis(body, opening)
        if closing is not None:
            expressions.append((body[opening + 1 : closing], opening + 1))

    labelled = re.compile(r"\baccessibilityIdentifier\s*:")
    for match in labelled.finditer(body):
        tail = body[match.end() :]
        argument = split_swift_arguments(tail)[0]
        expressions.append((argument, match.end()))
    return expressions


def runtime_identifier_templates(
    documents: dict[str, str],
) -> dict[str, list[SourceLocation]]:
    """Expand identifiers built from a component prefix supplied by its host."""
    expanded: dict[str, list[SourceLocation]] = {}
    dynamic_prefix = re.compile(
        r"^\{([A-Za-z_][A-Za-z0-9_]*)\}-(.+)\Z",
        flags=re.DOTALL,
    )

    owners: list[SwiftStruct | SwiftFunction] = [
        *swift_structs(documents),
        *swift_functions(documents),
    ]
    for owner in owners:
        templates: dict[str, list[SourceLocation]] = {}
        opaque_helpers: set[str] = set()
        for expression, expression_offset in accessibility_identifier_expressions(
            owner.body
        ):
            expression_strings = source_strings(expression)
            for template, relative_line in expression_strings:
                match = dynamic_prefix.fullmatch(template)
                if match is None:
                    continue
                location = SourceLocation(
                    owner.path,
                    documents[owner.path].count(
                        "\n", 0, owner.body_offset + expression_offset
                    )
                    + relative_line,
                )
                templates.setdefault(template, []).append(location)

            helper = re.fullmatch(
                r"\s*([A-Za-z_][A-Za-z0-9_]*)\s*\(.*\)\s*",
                expression,
                flags=re.DOTALL,
            )
            if helper and re.search(
                rf"\bfunc\s+{re.escape(helper.group(1))}\b[\s\S]*?"
                r'"\\\([A-Za-z_][A-Za-z0-9_]*\)-',
                owner.body,
            ):
                opaque_helpers.add(helper.group(1))

        if opaque_helpers:
            helpers = ", ".join(sorted(opaque_helpers))
            raise RuntimeIdentifierResolutionError(
                f"{owner.name} builds accessibility identifiers through "
                f"opaque helper(s) {helpers}; declare each child identifier as a "
                "prefix interpolation so the inventory can enumerate it"
            )

        by_prefix_name: dict[str, dict[str, list[SourceLocation]]] = {}
        for template in templates:
            prefix_name = dynamic_prefix.fullmatch(template).group(1)  # type: ignore[union-attr]
            if isinstance(owner, SwiftStruct):
                prefixes = component_prefixes(owner, prefix_name, documents)
            else:
                prefixes = function_prefixes(owner, prefix_name, documents)
            by_prefix_name.setdefault(
                prefix_name,
                prefixes,
            )

        for prefix_name, prefixes in by_prefix_name.items():
            if not prefixes:
                raise RuntimeIdentifierResolutionError(
                    f"{owner.name}.{prefix_name} has runtime accessibility "
                    "identifier children but no family-scoped call-site value"
                )
            for template, locations in templates.items():
                match = dynamic_prefix.fullmatch(template)
                if match is None or match.group(1) != prefix_name:
                    continue
                suffix = match.group(2)
                if re.fullmatch(r"\{(?:identifier)?suffix\}", suffix, re.IGNORECASE):
                    raise RuntimeIdentifierResolutionError(
                        f"{owner.name}.{prefix_name} leaves its accessibility "
                        f"child suffix unresolved in {template}"
                    )
                for prefix, prefix_locations in prefixes.items():
                    resolved = f"{prefix}-{suffix}"
                    expanded.setdefault(resolved, []).extend(
                        locations + prefix_locations
                    )
    return expanded


def family(template: str) -> str | None:
    for prefix in IDENTIFIER_FAMILIES:
        if template.startswith(prefix):
            return prefix.removesuffix("-")
    return None


def is_identifier_family_base(template: str) -> bool:
    return family(template) is not None or any(
        template == prefix.removesuffix("-") for prefix in IDENTIFIER_FAMILIES
    )


def identifier_role(template: str) -> tuple[str, str | None]:
    lowered = template.lower()
    if lowered in {
        "emby-search",
        "playerui-dockmenu",
        "playerui-videoformat",
    } or lowered.endswith((
        "-breadcrumb-current",
        "-error",
        "-panel",
        "-state",
        "-time-bubble",
        "-thumb",
        "-version",
    )):
        if lowered.endswith(("-breadcrumb-current", "-version")):
            return "operation", "activate"
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
            "-guest",
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


def runtime_identifier_role(template: str) -> tuple[str, str | None]:
    role, action = identifier_role(template)
    if role == "operation":
        return role, action
    lowered = template.lower()
    if lowered.endswith(("-error", "-success", "-sidebarselectionactions")):
        return "observation", None
    return "operation", "activate"


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
    documents: dict[str, str] = {}
    for root in SOURCE_ROOTS:
        for path in sorted(root.rglob("*.swift")):
            text = path.read_text(encoding="utf-8")
            relative = path.relative_to(REPOSITORY_ROOT).as_posix()
            documents[relative] = text
            for template, line in source_strings(text):
                if family(template) is None:
                    continue
                identifiers.setdefault(template, []).append(
                    SourceLocation(relative, line)
                )

    runtime_identifiers = runtime_identifier_templates(documents)
    for template, locations in runtime_identifiers.items():
        identifiers.setdefault(template, []).extend(locations)

    records: list[dict[str, object]] = []
    operations: list[dict[str, object]] = []
    for template, locations in sorted(identifiers.items()):
        role, action = (
            runtime_identifier_role(template)
            if template in runtime_identifiers
            else identifier_role(template)
        )
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
            operation: dict[str, object] = {
                "id": "accessibility:" + template,
                "kind": action,
                "identifierTemplate": template,
                "source": "accessibilityIdentifier",
            }
            equivalent = DEBUG_MENU_EQUIVALENTS.get(str(operation["id"]))
            if equivalent is not None:
                operation["debugEquivalent"] = {
                    "listVerb": "listMenuItems",
                    "selectVerb": "selectMenuItem",
                    **equivalent,
                }
            operations.append(operation)

    semantic_operations = [
        *[
            {
                "id": f"menu:settings:{family}",
                "kind": "menu-selection",
                "presentations": ["window"],
                "source": "Apps/Enchron/Screens/SettingsScreen.swift",
                "debugEquivalent": {
                    "listVerb": "listMenuItems",
                    "selectVerb": "selectMenuItem",
                    "host": "settings",
                    "families": [family],
                },
            }
            for family in SETTINGS_MENU_FAMILIES
        ],
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
            "id": "command:listMenuItems",
            "kind": "command",
            "presentations": ["window", "portal", "panorama", "docked"],
            "source": "Apps/Enchron/TestCommandChannel.swift",
        },
        {
            "id": "command:selectMenuItem",
            "kind": "command",
            "presentations": ["window", "portal", "panorama", "docked"],
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


def extend_matrix_baseline(
    baseline: dict[str, object],
    inventory: dict[str, object],
    *,
    presentations: tuple[str, ...] = PRESENTATIONS,
) -> dict[str, object]:
    expected = {
        (presentation, str(operation["id"]))
        for presentation in presentations
        for operation in inventory["operations"]  # type: ignore[index]
    }
    cells = baseline.get("cells", [])
    if not isinstance(cells, list):
        raise ValueError("reachability matrix baseline cells must be a list")

    existing: set[tuple[str, str]] = set()
    copied_cells: list[dict[str, object]] = []
    for cell in cells:
        if not isinstance(cell, dict):
            raise ValueError("reachability matrix baseline cells must be objects")
        key = (str(cell.get("presentation")), str(cell.get("operation")))
        if key in existing:
            raise ValueError(f"duplicate reachability matrix cell: {key}")
        if key not in expected:
            raise ValueError(f"stale reachability matrix cell: {key}")
        existing.add(key)
        copied_cells.append(dict(cell))

    presentation_order = {
        presentation: index for index, presentation in enumerate(presentations)
    }
    missing = sorted(
        expected - existing,
        key=lambda key: (presentation_order[key[0]], key[1]),
    )
    operations_by_id = {
        str(operation["id"]): operation
        for operation in inventory["operations"]  # type: ignore[index]
    }
    for presentation, operation_id in missing:
        explicit_presentations = operations_by_id[operation_id].get("presentations")
        applicable = (
            not isinstance(explicit_presentations, list)
            or presentation in explicit_presentations
        )
        copied_cells.append(
            {
                "operation": operation_id,
                "presentation": presentation,
                "verdict": "known-defect" if applicable else "not-applicable",
            }
        )
    return {**baseline, "cells": copied_cells}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--write",
        action="store_true",
        help="Replace the version-controlled inventory with the current source result.",
    )
    parser.add_argument(
        "--extend-baseline-known-defects",
        action="store_true",
        help=(
            "Append missing matrix cells as known defects without changing existing "
            "device verdicts."
        ),
    )
    arguments = parser.parse_args()
    inventory = build_inventory()
    generated = encoded_inventory()
    if arguments.write:
        OUTPUT.write_text(generated, encoding="utf-8")
        print(f"wrote {OUTPUT.relative_to(REPOSITORY_ROOT)}")
    if arguments.extend_baseline_known_defects:
        if not MATRIX_BASELINE.is_file():
            print(
                f"missing {MATRIX_BASELINE.relative_to(REPOSITORY_ROOT)}",
                file=sys.stderr,
            )
            return 1
        baseline = json.loads(MATRIX_BASELINE.read_text(encoding="utf-8"))
        extended = extend_matrix_baseline(baseline, inventory)
        MATRIX_BASELINE.write_text(
            json.dumps(extended, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        added = len(extended["cells"]) - len(baseline["cells"])
        print(
            f"extended {MATRIX_BASELINE.relative_to(REPOSITORY_ROOT)} "
            f"with {added} known-defect cells"
        )
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
