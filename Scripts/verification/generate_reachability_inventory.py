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
MAIN_WINDOW_BROWSER_CONTEXT = "main-window-browser"
PROOF_CONTEXTS = (MAIN_WINDOW_BROWSER_CONTEXT, *PRESENTATIONS)
LEGACY_TARGET_PRESENTATION_REMAPS = {
    ("docked", "accessibility:PlayerUI-DockMenu-skybox"): "window",
    ("docked", "accessibility:PlayerUI-DockMenu-{$0.rawValue}"): "window",
    ("docked", "accessibility:PlayerUI-TopAction-dock"): "window",
    ("docked", "accessibility:PlayerUI-TopAction-more"): "window",
    ("docked", "accessibility:PlayerUI-loadFailure-primary"): "window",
}
UNINSTANTIATED_RENDER_HOSTS = {
    "uninstantiatedPlayerControlDockVideoFormat",
    "uninstantiatedPortalPlayerControlDockBranch",
    "uninstantiatedPlayerDeckRetryCloseActions",
}
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
    REPOSITORY_ROOT / "Modules/Playback",
)
DERIVATION_SOURCE_PATHS = (
    "Modules/Playback/Domain/PlaybackUserVisibleIssue.swift",
)
IDENTIFIER_FAMILIES = (
    "AcousticCalibration-",
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
    "accessibility:PlayerUI-menu-audio": {
        "host": "playerUI",
        "families": ["audio"],
        "parentOperation": "accessibility:PlayerUI-TopAction-more",
    },
    "accessibility:PlayerUI-menu-speed": {
        "host": "playerUI",
        "families": ["speed"],
        "parentOperation": "accessibility:PlayerUI-TopAction-more",
    },
    "accessibility:PlayerUI-menu-episodes": {
        "host": "playerUI",
        "families": ["episodes"],
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
    ("MediaLibrary-Manage-addPhotos", "manage", "addPhotos"),
    ("MediaLibrary-Manage-addFolder", "manage", "addFolder"),
    ("MediaLibrary-Manage-newFolder", "manage", "newFolder"),
    ("MediaLibrary-Manage-selectMultiple", "manage", "selectMultiple"),
    ("FileBrowsing-SourcesSidebar-addFiles", "sourceAdd", "local"),
    ("FileBrowsing-SourcesSidebar-addFolder", "sourceAdd", "folder"),
    ("FileBrowsing-SourcesSidebar-addWebDAV", "sourceAdd", "webDAV"),
    ("FileBrowsing-SourcesSidebar-addSMB", "sourceAdd", "smb"),
    ("FileBrowsing-SourcesSidebar-add", "sourceAction", "add"),
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
            else "accessibility:FileBrowsing-SourcesSidebar-add"
            if family == "sourceAdd"
            else "accessibility:FileBrowsing-SourcesSidebar-sourceMore"
        ),
    }


@dataclass(frozen=True, order=True)
class SourceLocation:
    path: str
    line: int


class RuntimeIdentifierResolutionError(ValueError):
    """A component-built accessibility identifier cannot be enumerated."""


class PresentationDerivationError(ValueError):
    """A product operation cannot be assigned to a production render host."""


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


def source_without_preview_blocks(text: str) -> str:
    """Blank #Preview declarations while preserving source line positions."""
    characters = list(text)
    cursor = 0
    while True:
        preview = text.find("#Preview", cursor)
        if preview < 0:
            break
        opening = text.find("{", preview + len("#Preview"))
        if opening < 0:
            break
        closing = matching_brace(text, opening)
        if closing is None:
            break
        for index in range(preview, closing + 1):
            if characters[index] != "\n":
                characters[index] = " "
        cursor = closing + 1
    return "".join(characters)


def uninstantiated_view_identifier_owners(
    documents: dict[str, str],
    identifiers: dict[str, list[SourceLocation]],
) -> dict[str, SwiftStruct]:
    """Find identifier-owning SwiftUI views with no production construction."""
    structs = swift_structs(documents)
    ranges: list[tuple[SwiftStruct, int, int]] = []
    for component in structs:
        text = documents[component.path]
        first_line = text.count("\n", 0, component.body_offset) + 1
        last_line = text.count(
            "\n", 0, component.body_offset + len(component.body)
        ) + 1
        ranges.append((component, first_line, last_line))

    production_documents = {
        path: source_without_preview_blocks(text)
        for path, text in documents.items()
    }
    constructed = {
        component.name
        for component in structs
        if any(
            re.search(rf"\b{re.escape(component.name)}\s*(?:\(|\{{)", text)
            for text in production_documents.values()
        )
    }

    archived: dict[str, SwiftStruct] = {}
    for template, locations in identifiers.items():
        owners: list[SwiftStruct] = []
        for location in locations:
            matching = [
                component
                for component, first_line, last_line in ranges
                if component.path == location.path
                and first_line <= location.line <= last_line
            ]
            if not matching:
                owners = []
                break
            owners.append(min(matching, key=lambda component: len(component.body)))
        if (
            owners
            and all(owner.name == owners[0].name for owner in owners)
            and owners[0].name not in constructed
        ):
            archived[template] = owners[0]
    return archived


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
            "-menu",
            "dockmenu-",
            "-topaction-",
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
            "-trust",
            "-proceed",
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
            "-addphotos",
            "-addfolder",
            "-newfolder",
            "-selectmultiple",
            "-move",
            "-delete",
            "-done",
            "-close",
            "-refresh",
            "-action-",
            "-toggle",
            "-surface",
        )
    ):
        return "operation", "activate"
    return "observation", None


INTERACTIVE_CONSTRUCT = re.compile(
    r"\b(Button|Menu|Toggle|Picker|Slider|TextField|SecureField|NavigationLink)\b"
    r"|\.onTapGesture"
    r"|\.accessibilityAddTraits\(\.isButton\)"
    r"|\.accessibilityAction"
)

CHAIN_CONTINUATION = re.compile(r"^[.}\)\],]")

# The reason each of these really is an observation even though interactive code
# sits near it in the source.
REVIEWED_OBSERVATIONS: dict[str, str] = {
    "Emby-Connection-Error": "Error text. The retry button beside it has its own "
    "identifier.",
    "FileBrowsing-error": "The dialog prefix is not an element. Its primary and "
    "secondary buttons have separate action identifiers.",
    "FileBrowsing-FilesScreen-itemCount": "A count label in a toolbar full of "
    "buttons.",
    "MediaLibrary-MultiSelect-count": "A count label beside the multi-select "
    "buttons.",
    "FileBrowsing-SourcesSidebar-sidebarSelectionActions": "The HStack that holds "
    "the selection buttons; each button carries its own identifier. Its source "
    "location is the derived prefix in FilesScreen, whose neighbours belong to "
    "an unrelated alert.",
}


def modifier_chain(text: str, line: int) -> list[str]:
    """The modifier chain the identifier at `line` is part of.

    Everything from `.accessibilityIdentifier` upwards that sits at the same
    indentation and continues the chain, skipping the bodies of any trailing
    closures those modifiers open. What this returns is attached to the very
    element the identifier names, which is what separates it from whatever else
    happens to be nearby in the file.
    """
    lines = text.splitlines()
    if not 0 < line <= len(lines):
        return []
    anchor = lines[line - 1]
    indent = len(anchor) - len(anchor.lstrip())
    chain = [anchor.strip()]
    for candidate in reversed(lines[max(0, line - 40) : line - 1]):
        stripped = candidate.strip()
        if not stripped:
            continue
        depth = len(candidate) - len(candidate.lstrip())
        if depth > indent:
            continue
        if depth < indent or not CHAIN_CONTINUATION.match(stripped):
            break
        chain.append(stripped)
    return chain


def interactive_evidence(text: str, line: int) -> tuple[str, str] | None:
    """Source evidence that an identifier names something interactive.

    Returns how the evidence was found and the line that carries it. `attached`
    means the construct is a modifier on the identified element itself, which
    settles the question. `nearby` means it merely sits within a few lines, which
    a custom wrapper or a sibling control can produce, so it only asks for a
    decision.

    An interactive control filed as an observation never becomes a matrix cell,
    so nothing ever demands coverage for it and the gap stays invisible in every
    green report. That is how a settings row sat unreachable for months.
    """
    for candidate in modifier_chain(text, line):
        if INTERACTIVE_CONSTRUCT.search(candidate):
            return "attached", candidate
    lines = text.splitlines()
    for candidate in reversed(lines[max(0, line - 15) : line + 2]):
        if INTERACTIVE_CONSTRUCT.search(candidate):
            return "nearby", candidate.strip()
    return None


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
    if template.startswith("DesignSystem-"):
        return "component-default"
    if template == "PlayerUI-debug-evidence":
        return "debug-diagnostic"
    return "product"


def required_source_location(
    documents: dict[str, str],
    path: str,
    token: str,
) -> SourceLocation:
    text = documents.get(path)
    if text is None:
        raise PresentationDerivationError(f"missing production render source {path}")
    offset = text.find(token)
    if offset < 0:
        raise PresentationDerivationError(
            f"production render source {path} no longer contains {token!r}"
        )
    return SourceLocation(path, text.count("\n", 0, offset) + 1)


def playback_presentation_property_cases(
    documents: dict[str, str],
    property_name: str,
) -> tuple[list[str], SourceLocation]:
    path = "Modules/Playback/Model/PlaybackPresentation.swift"
    text = documents.get(path)
    if text is None:
        raise PresentationDerivationError(f"missing production render source {path}")
    declaration = re.search(
        rf"\bvar\s+{re.escape(property_name)}\s*:\s*Bool\s*\{{([^}}]+)\}}",
        text,
    )
    if declaration is None:
        raise PresentationDerivationError(
            f"cannot derive PlaybackPresentation.{property_name} cases"
        )
    cases = {
        match.group(1)
        for match in re.finditer(r"\.([A-Za-z_][A-Za-z0-9_]*)", declaration.group(1))
    }
    unknown = cases - set(PRESENTATIONS)
    if not cases or unknown:
        raise PresentationDerivationError(
            f"PlaybackPresentation.{property_name} has unsupported cases {sorted(unknown)}"
        )
    ordered = [presentation for presentation in PRESENTATIONS if presentation in cases]
    return ordered, SourceLocation(
        path,
        text.count("\n", 0, declaration.start()) + 1,
    )


def presentation_derivation(
    template: str,
    documents: dict[str, str],
) -> tuple[list[str], dict[str, object]]:
    """Resolve one accessibility operation through its production render host.

    Rules name content hosts rather than individual operations. Their source
    anchors make a render-tree change fail inventory generation instead of
    silently retaining a stale applicability verdict.
    """

    main_window_presentations, main_window_source = (
        playback_presentation_property_cases(documents, "usesMainWindow")
    )
    immersive_presentations, immersive_source = (
        playback_presentation_property_cases(documents, "usesImmersiveSpace")
    )
    all_playback_presentations = [
        presentation
        for presentation in PRESENTATIONS
        if presentation in main_window_presentations
        or presentation in immersive_presentations
    ]

    browser_hosts = {
        "Emby": ("EmbyScreen {", "Apps/Enchron/MainView.swift"),
        "FileBrowsing": ("FilesScreenHost()", "Apps/Enchron/MainView.swift"),
        "MediaLibrary": ("FilesScreenHost()", "Apps/Enchron/MainView.swift"),
        "Navigation": ("private var browser: some View", "Apps/Enchron/MainView.swift"),
        "Settings": ("SettingsScreen()", "Apps/Enchron/MainView.swift"),
    }
    operation_family = family(template)
    if operation_family in browser_hosts:
        token, path = browser_hosts[operation_family]
        source = required_source_location(documents, path, token)
        return ["window"], {
            "host": "browserWindowSurface",
            "sources": [asdict(source)],
        }

    if operation_family == "EnvironmentCard":
        source = required_source_location(
            documents,
            "Modules/Playback/Views/SenseZoneVolumeRoot.swift",
            "EnvironmentCardCarousel(",
        )
        return ["window", "docked"], {
            "host": "environmentVolume",
            "sources": [asdict(source)],
        }

    if operation_family == "PlayerPanel":
        path = "Modules/Playback/Views/PlaybackPanel.swift"
        if template.startswith("PlayerPanel-menu-"):
            source = required_source_location(
                documents,
                path,
                "            playerControlDockControls",
            )
            return immersive_presentations, {
                "host": "playerControlDockControls",
                "sources": [asdict(source), asdict(immersive_source)],
            }
        if template.startswith("PlayerPanel-DockedPlacement") or template == (
            "PlayerPanel-{identifier}-slider"
        ):
            source = required_source_location(
                documents,
                path,
                "                    dockedPlacementControls(live)",
            )
            return ["docked"], {
                "host": "dockedPlacementControls",
                "sources": [asdict(source)],
            }
        if template.startswith("PlayerPanel-VideoFormat-"):
            source = required_source_location(
                documents,
                path,
                "                    videoFormatEditor(live)",
            )
            return [], {
                "host": "uninstantiatedPlayerControlDockVideoFormat",
                "sources": [asdict(source)],
            }
        if template == "PlayerPanel-button-settings":
            source = required_source_location(
                documents,
                path,
                "PlaybackPanelSettingsPolicy.settingsAreAvailable(",
            )
            return ["docked"], {
                "host": "dockedPlayerControlSettings",
                "sources": [asdict(source)],
            }
        if template == "PlayerPanel-button-enter-panorama":
            source = required_source_location(
                documents,
                path,
                "        } else if live.presentation == .portal {",
            )
            return [], {
                "host": "uninstantiatedPortalPlayerControlDockBranch",
                "sources": [asdict(source)],
            }
        if template == "PlayerPanel-button-exit-spatial":
            source = required_source_location(
                documents,
                path,
                "        if live.presentation == .panorama {",
            )
            return immersive_presentations, {
                "host": "immersiveReturnControls",
                "sources": [asdict(source), asdict(immersive_source)],
            }
        window_source = required_source_location(
            documents,
            path,
            "            surface: .windowOrnament,",
        )
        dock_source = required_source_location(
            documents,
            path,
            "            surface: .playerControlDock,",
        )
        return all_playback_presentations, {
            "host": "fusedPlayerPanelSharedContent",
            "sources": [
                asdict(window_source),
                asdict(dock_source),
                asdict(main_window_source),
                asdict(immersive_source),
            ],
        }

    if operation_family == "PlayerUI":
        if template == "PlayerUI-window-playback-surface":
            source = required_source_location(
                documents,
                "Modules/Playback/Views/WindowPlaybackRootView.swift",
                '"PlayerUI-window-playback-surface"',
            )
            gesture_source = required_source_location(
                documents,
                "Modules/Playback/Views/PlaybackVideoSurface.swift",
                ".targetedToEntity(playbackVideoEntityStore.windowInteractionSurface)",
            )
            collider_source = required_source_location(
                documents,
                "Modules/Playback/Views/PlaybackRealityPresenter.swift",
                "enum PlaybackWindowInteractionSurface",
            )
            return main_window_presentations, {
                "host": "windowPlaybackSurfaceEntityTapTarget",
                "sources": [
                    asdict(source),
                    asdict(gesture_source),
                    asdict(collider_source),
                    asdict(main_window_source),
                ],
            }
        if template.startswith("PlayerUI-DockMenu-") or template == (
            "PlayerUI-TopAction-dock"
        ):
            host_source = required_source_location(
                documents,
                "Modules/Playback/Views/PlayerInfoBarView.swift",
                "PlaybackTopActions(",
            )
            condition_source = required_source_location(
                documents,
                "Modules/Playback/Views/PlaybackTopActions.swift",
                "showsDock = immersiveEntryTarget == .docked",
            )
            return ["window"], {
                "host": "windowPlaybackDockEntryTopActions",
                "sources": [asdict(host_source), asdict(condition_source)],
            }
        if template == "PlayerUI-TopAction-resumePanorama":
            host_source = required_source_location(
                documents,
                "Modules/Playback/Views/PlayerInfoBarView.swift",
                "PlaybackTopActions(",
            )
            condition_source = required_source_location(
                documents,
                "Modules/Playback/Views/PlaybackTopActions.swift",
                "showsPanoramaEntry = immersiveEntryTarget == .panorama",
            )
            return ["portal"], {
                "host": "portalPlaybackPanoramaEntryTopActions",
                "sources": [asdict(host_source), asdict(condition_source)],
            }
        if template in {
            "PlayerUI-TopAction-more",
            "PlayerUI-menu-subtitles",
            "PlayerUI-menu-audio",
            "PlayerUI-menu-speed",
            "PlayerUI-menu-episodes",
            "PlayerUI-menu-{category}-{item.id}",
        }:
            source = required_source_location(
                documents,
                "Modules/Playback/Views/PlayerInfoBarView.swift",
                "ProductionPlaybackMoreMenu()",
            )
            return main_window_presentations, {
                "host": "windowPlaybackTopChromeMoreControl",
                "sources": [asdict(source), asdict(main_window_source)],
            }
        if template == "PlayerUI-InfoBar-button-back" or template.startswith(
            ("PlayerUI-TopAction-videoFormat", "PlayerUI-VideoFormat-")
        ):
            source = required_source_location(
                documents,
                "Apps/Enchron/MainView.swift",
                "PlayerInfoBarView(",
            )
            return main_window_presentations, {
                "host": "windowPlaybackTopChrome",
                "sources": [asdict(source), asdict(main_window_source)],
            }
        if template == "PlayerUI-audio-spectrum":
            source = required_source_location(
                documents,
                "Apps/Enchron/MainView.swift",
                "AudioSpectrumSurface(frame:",
            )
            return ["window"], {
                "host": "windowAudioOnlyPlaybackSurface",
                "sources": [asdict(source), asdict(main_window_source)],
            }
        if template.startswith("PlayerUI-resumeDecision-"):
            source = required_source_location(
                documents,
                "Apps/Enchron/MainView.swift",
                "ResumeDecisionCard(",
            )
            return ["window"], {
                "host": "browserWindowResumeDecision",
                "sources": [asdict(source)],
            }
        if template.startswith("PlayerUI-loadFailure-"):
            source = required_source_location(
                documents,
                "Apps/Enchron/MainView.swift",
                'case .mainWindow: "PlayerUI-loadFailure-primary"',
            )
            return main_window_presentations, {
                "host": "mainWindowPlaybackIssueActions",
                "sources": [asdict(source), asdict(main_window_source)],
            }
        if template.startswith("PlayerUI-spatialFailure-"):
            source = required_source_location(
                documents,
                "Apps/Enchron/MainView.swift",
                'case .immersiveSpace: "PlayerUI-spatialFailure-primary"',
            )
            return immersive_presentations, {
                "host": "immersivePlaybackIssueActions",
                "sources": [asdict(source), asdict(immersive_source)],
            }
        if template in {
            "PlayerUI-playbackIssue-primary",
            "PlayerUI-playbackIssue-secondary",
        }:
            identifier_source = required_source_location(
                documents,
                "Apps/Enchron/MainView.swift",
                'case .playerDeck, .mediaLibrary: "PlayerUI-playbackIssue-primary"',
            )
            policy_source = required_source_location(
                documents,
                "Modules/Playback/Domain/PlaybackUserVisibleIssue.swift",
                "presentationLocations: [.playerDeck]",
            )
            return [], {
                "host": "uninstantiatedPlayerDeckRetryCloseActions",
                "sources": [asdict(identifier_source), asdict(policy_source)],
            }
        if template == "PlayerUI-presentation-conversion-dismiss":
            source = required_source_location(
                documents,
                "Apps/Enchron/MainView.swift",
                'case .mediaLibrary: "PlayerUI-presentation-conversion-dismiss"',
            )
            return ["window"], {
                "host": "browserWindowPlaybackIssue",
                "sources": [asdict(source)],
            }
        if any(
            marker in template
            for marker in (
                "Failure-",
                "playbackIssue-",
                "presentation-conversion-",
                "unmetCapability-",
            )
        ):
            source = required_source_location(
                documents,
                "Apps/Enchron/MainView.swift",
                "func playbackIssueAlert(",
            )
            return all_playback_presentations, {
                "host": "playbackIssuePresentationSites",
                "sources": [
                    asdict(source),
                    asdict(main_window_source),
                    asdict(immersive_source),
                ],
            }

    raise PresentationDerivationError(
        f"cannot derive a production presentation host for accessibility:{template}"
    )


def explicit_presentation_derivation(
    operation: dict[str, object],
    documents: dict[str, str],
) -> dict[str, object]:
    source_path = str(operation["source"])
    if source_path not in documents:
        raise PresentationDerivationError(
            f"explicit operation {operation['id']} names missing source {source_path}"
        )
    return {
        "host": "explicitOperationContract",
        "sources": [asdict(SourceLocation(source_path, 1))],
    }


def proof_context_contract(
    presentations: list[str],
    derivation: dict[str, object],
) -> tuple[str, list[str], dict[str, object]]:
    host = str(derivation.get("host", ""))
    if not host:
        raise PresentationDerivationError("proof context derivation has no host")
    domain = "browser" if host.startswith("browserWindow") else "playback"
    contexts = (
        [MAIN_WINDOW_BROWSER_CONTEXT]
        if domain == "browser"
        else list(presentations)
    )
    return domain, contexts, derivation


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
    for relative in DERIVATION_SOURCE_PATHS:
        path = REPOSITORY_ROOT / relative
        documents[relative] = path.read_text(encoding="utf-8")

    runtime_identifiers = runtime_identifier_templates(documents)
    for template, locations in runtime_identifiers.items():
        identifiers.setdefault(template, []).extend(locations)

    uninstantiated_view_identifiers = uninstantiated_view_identifier_owners(
        documents,
        identifiers,
    )

    records: list[dict[str, object]] = []
    operations: list[dict[str, object]] = []
    for template, locations in sorted(identifiers.items()):
        role, action = (
            runtime_identifier_role(template)
            if template in runtime_identifiers
            else identifier_role(template)
        )
        scope = source_scope(template)
        evidence = None
        if role == "observation" and scope == "product":
            for location in sorted(set(locations)):
                text = documents.get(location.path)
                if text is None:
                    continue
                found = interactive_evidence(text, location.line)
                if found:
                    evidence = (location, *found)
                    break
        if evidence and evidence[1] == "attached":
            role, action = "operation", "activate"
        record = {
            "template": template,
            "family": family(template),
            "scope": scope,
            "role": role,
            "action": action,
            "sources": [asdict(location) for location in sorted(set(locations))],
        }
        if (
            evidence
            and evidence[1] == "nearby"
            and template not in REVIEWED_OBSERVATIONS
        ):
            location, _, construct = evidence
            record["interactiveEvidence"] = {
                "path": location.path,
                "line": location.line,
                "construct": construct,
            }
        records.append(record)
        if role == "operation" and record["scope"] == "product":
            uninstantiated_owner = uninstantiated_view_identifiers.get(template)
            if uninstantiated_owner is not None:
                source = documents[uninstantiated_owner.path]
                record["role"] = "uninstantiated-identifier"
                record["renderDerivation"] = {
                    "host": "uninstantiatedSwiftUIView",
                    "sources": [asdict(SourceLocation(
                        uninstantiated_owner.path,
                        source.count("\n", 0, uninstantiated_owner.body_offset) + 1,
                    ))],
                }
                continue
            presentations, derivation = presentation_derivation(
                template,
                documents,
            )
            if not presentations:
                host = str(derivation.get("host", ""))
                if host not in UNINSTANTIATED_RENDER_HOSTS:
                    raise PresentationDerivationError(
                        f"accessibility:{template} has no production proof context"
                    )
                record["role"] = "uninstantiated-identifier"
                record["renderDerivation"] = derivation
                continue
            domain, contexts, context_derivation = proof_context_contract(
                presentations,
                derivation,
            )
            operation: dict[str, object] = {
                "id": "accessibility:" + template,
                "kind": action,
                "identifierTemplate": template,
                "proofDomain": domain,
                "proofContexts": contexts,
                "proofContextDerivation": context_derivation,
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
                "proofDomain": "browser",
                "proofContexts": [MAIN_WINDOW_BROWSER_CONTEXT],
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
            "proofDomain": "playback",
            "proofContexts": list(PRESENTATIONS),
            "source": "Apps/Enchron/TestCommandChannel.swift",
        },
        {
            "id": "command:setWindowSize",
            "kind": "command",
            "proofDomain": "playback",
            "proofContexts": ["portal"],
            "source": "Apps/Enchron/TestCommandChannel.swift",
        },
        {
            "id": "command:seekNormalized",
            "kind": "command",
            "proofDomain": "playback",
            "proofContexts": list(PRESENTATIONS),
            "source": "Apps/Enchron/TestCommandChannel.swift",
        },
        {
            "id": "command:setDockedPlacement",
            "kind": "command",
            "proofDomain": "playback",
            "proofContexts": ["docked"],
            "source": "Apps/Enchron/TestCommandChannel.swift",
        },
        {
            "id": "command:listMenuItems",
            "kind": "command",
            "proofDomain": "shared",
            "proofContexts": list(PROOF_CONTEXTS),
            "source": "Apps/Enchron/TestCommandChannel.swift",
        },
        {
            "id": "command:selectMenuItem",
            "kind": "command",
            "proofDomain": "shared",
            "proofContexts": list(PROOF_CONTEXTS),
            "source": "Apps/Enchron/TestCommandChannel.swift",
        },
        {
            "id": "environmentVolume:open-interact-close",
            "kind": "compound",
            "proofDomain": "playback",
            "proofContexts": ["window", "docked"],
            "source": "Apps/Enchron/MainView.swift",
        },
        {
            "id": "scroll:file-list",
            "kind": "scroll",
            "proofDomain": "browser",
            "proofContexts": [MAIN_WINDOW_BROWSER_CONTEXT],
            "source": "Modules/MediaLibrary/Views/FilesScreen.swift",
        },
        {
            "id": "scroll:emby",
            "kind": "scroll",
            "proofDomain": "browser",
            "proofContexts": [MAIN_WINDOW_BROWSER_CONTEXT],
            "source": "Modules/Emby/EmbyScreens.swift",
        },
        {
            "id": "negative:immersive-resident-window",
            "kind": "negative",
            "proofDomain": "playback",
            "proofContexts": ["panorama", "docked"],
            "source": "Apps/Enchron/EnchronApp.swift",
        },
    ]
    for operation in semantic_operations:
        operation["proofContextDerivation"] = explicit_presentation_derivation(
            operation,
            documents,
        )

    return {
        "version": 3,
        "sourceRoots": [
            root.relative_to(REPOSITORY_ROOT).as_posix() for root in SOURCE_ROOTS
        ],
        "identifierFamilies": [prefix.removesuffix("-") for prefix in IDENTIFIER_FAMILIES],
        "identifiers": records,
        "operations": sorted(operations + semantic_operations, key=lambda item: item["id"]),
    }


def encoded_inventory() -> str:
    """The inventory as it is committed. `interactiveEvidence` is a demand for a
    human decision, not a fact about the product, so it never reaches the file."""
    inventory = build_inventory()
    for record in inventory["identifiers"]:  # type: ignore[index]
        record.pop("interactiveEvidence", None)
    return json.dumps(inventory, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def extend_matrix_baseline(
    baseline: dict[str, object],
    inventory: dict[str, object],
) -> dict[str, object]:
    expected = {
        (str(context), str(operation["id"]))
        for operation in inventory["operations"]  # type: ignore[index]
        for context in operation["proofContexts"]  # type: ignore[index]
    }
    cells = baseline.get("cells", [])
    if not isinstance(cells, list):
        raise ValueError("reachability matrix baseline cells must be a list")

    existing: set[tuple[str, str]] = set()
    copied_cells: list[dict[str, object]] = []
    for cell in cells:
        if not isinstance(cell, dict):
            raise ValueError("reachability matrix baseline cells must be objects")
        key = (str(cell.get("context")), str(cell.get("operation")))
        if key in existing:
            raise ValueError(f"duplicate reachability decision: {key}")
        if key not in expected:
            raise ValueError(f"stale reachability decision: {key}")
        existing.add(key)
        copied_cells.append(dict(cell))

    context_order = {context: index for index, context in enumerate(PROOF_CONTEXTS)}
    missing = sorted(
        expected - existing,
        key=lambda key: (context_order[key[0]], key[1]),
    )
    for context, operation_id in missing:
        copied_cells.append(
            {
                "operation": operation_id,
                "context": context,
                "verdict": "known-defect",
            }
        )
    return {**baseline, "schemaVersion": 2, "cells": copied_cells}


def migrate_matrix_baseline(
    old_baseline: dict[str, object],
    inventory: dict[str, object],
) -> tuple[dict[str, object], dict[str, object]]:
    """Map the four-presentation baseline onto source-derived proof contexts."""
    operations_by_id = {
        str(operation["id"]): operation
        for operation in inventory["operations"]  # type: ignore[index]
    }
    cells = old_baseline.get("cells")
    if not isinstance(cells, list):
        raise ValueError("reachability matrix baseline cells must be a list")
    if any(isinstance(cell, dict) and "context" in cell for cell in cells):
        return reconcile_proof_context_baseline(old_baseline, inventory)

    old_by_key: dict[tuple[str, str], dict[str, object]] = {}
    for cell in cells:
        if not isinstance(cell, dict):
            raise ValueError("reachability matrix baseline cells must be objects")
        key = (str(cell.get("presentation")), str(cell.get("operation")))
        if key in old_by_key:
            raise ValueError(f"duplicate old reachability matrix cell: {key}")
        old_by_key[key] = cell

    context_order = {context: index for index, context in enumerate(PROOF_CONTEXTS)}
    new_cells: list[dict[str, object]] = []
    used_old_keys: set[tuple[str, str]] = set()
    new_by_key: dict[tuple[str, str], dict[str, object]] = {}
    for operation_id, operation in operations_by_id.items():
        contexts = operation.get("proofContexts")
        domain = str(operation.get("proofDomain", ""))
        if not isinstance(contexts, list) or domain not in {
            "browser", "playback", "shared"
        }:
            raise ValueError(
                f"operation {operation_id} has no derived proof context contract"
            )
        for context_value in contexts:
            context = str(context_value)
            source_presentation: str | None
            if context == MAIN_WINDOW_BROWSER_CONTEXT:
                source_presentation = "window"
            elif domain == "shared" and context == "window":
                source_presentation = None
            else:
                source_presentation = context
            source_key = (
                (source_presentation, operation_id)
                if source_presentation is not None
                else None
            )
            source_cell = old_by_key.get(source_key) if source_key else None
            if source_key is not None and source_cell is not None:
                used_old_keys.add(source_key)
            new_cell = {
                "context": context,
                "operation": operation_id,
                "verdict": (
                    "reachable"
                    if source_cell is not None
                    and source_cell.get("verdict") == "reachable"
                    else "known-defect"
                ),
            }
            new_cells.append(new_cell)
            new_by_key[(context, operation_id)] = new_cell

    new_cells.sort(
        key=lambda cell: (
            context_order[str(cell["context"])],
            str(cell["operation"]),
        )
    )
    retired_reachable: list[dict[str, str]] = []
    remapped_reachable: list[dict[str, str]] = []
    reachable_regressions: list[dict[str, str]] = []
    mapped_reachable_count = 0
    mapped_reachable_decisions: set[tuple[str, str]] = set()
    for key, cell in old_by_key.items():
        if cell.get("verdict") != "reachable":
            continue
        presentation, operation_id = key
        operation = operations_by_id.get(operation_id)
        if operation is None:
            raise ValueError(f"unknown reachability operation {operation_id}")
        domain = str(operation["proofDomain"])
        contexts = [str(value) for value in operation["proofContexts"]]
        target = (
            MAIN_WINDOW_BROWSER_CONTEXT
            if presentation == "window" and domain in {"browser", "shared"}
            else presentation
        )
        was_remapped = False
        if target not in contexts:
            remapped_target = LEGACY_TARGET_PRESENTATION_REMAPS.get(key)
            if remapped_target not in contexts:
                retired_reachable.append({
                    "operation": operation_id,
                    "presentation": presentation,
                    "reason": "source-derived-proof-context-does-not-exist",
                })
                continue
            target = str(remapped_target)
            was_remapped = True
            remapped_reachable.append({
                "operation": operation_id,
                "presentation": presentation,
                "context": target,
                "reason": (
                    "legacy-cell-used-target-presentation-instead-of-render-host"
                ),
            })
        migrated = new_by_key[(target, operation_id)]
        if was_remapped:
            migrated["verdict"] = "reachable"
        if migrated["verdict"] == "reachable":
            mapped_reachable_count += 1
            mapped_reachable_decisions.add((target, operation_id))
        else:
            reachable_regressions.append({
                "operation": operation_id,
                "presentation": presentation,
                "context": target,
                "reason": "reachable-old-cell-became-non-reachable",
            })

    migrated_baseline = {
        key: value
        for key, value in old_baseline.items()
        if key not in {"schemaVersion", "cells"}
    }
    migrated_baseline.update({
        "schemaVersion": 2,
        "coordinateSystem": "proof-context-v1",
        "cells": new_cells,
    })
    report: dict[str, object] = {
        "oldCellCount": len(cells),
        "newDecisionCount": len(new_cells),
        "oldReachableCount": sum(
            cell.get("verdict") == "reachable" for cell in old_by_key.values()
        ),
        "mappedReachableCount": mapped_reachable_count,
        "mappedReachableDecisionCount": len(mapped_reachable_decisions),
        "coalescedReachableEvidenceCount": (
            mapped_reachable_count - len(mapped_reachable_decisions)
        ),
        "remappedReachableCount": len(remapped_reachable),
        "remappedReachableCells": sorted(
            remapped_reachable,
            key=lambda item: (item["presentation"], item["operation"]),
        ),
        "retiredReachableCount": len(retired_reachable),
        "retiredReachableCells": sorted(
            retired_reachable,
            key=lambda item: (item["presentation"], item["operation"]),
        ),
        "reachableRegressionCount": len(reachable_regressions),
        "reachableRegressions": reachable_regressions,
        "removedNotApplicableCount": sum(
            cell.get("verdict") == "not-applicable" and key not in used_old_keys
            for key, cell in old_by_key.items()
        ),
    }
    return migrated_baseline, report


def reconcile_proof_context_baseline(
    baseline: dict[str, object],
    inventory: dict[str, object],
) -> tuple[dict[str, object], dict[str, object]]:
    """Reconcile a proof-context baseline after a render-host derivation change."""
    cells = baseline.get("cells")
    if not isinstance(cells, list):
        raise ValueError("reachability matrix baseline cells must be a list")
    existing: dict[tuple[str, str], dict[str, object]] = {}
    for cell in cells:
        if not isinstance(cell, dict):
            raise ValueError("reachability matrix baseline cells must be objects")
        key = (str(cell.get("context")), str(cell.get("operation")))
        if key in existing:
            raise ValueError(f"duplicate reachability decision: {key}")
        existing[key] = cell

    expected = {
        (str(context), str(operation["id"]))
        for operation in inventory["operations"]  # type: ignore[index]
        for context in operation["proofContexts"]  # type: ignore[index]
    }
    context_order = {context: index for index, context in enumerate(PROOF_CONTEXTS)}
    reconciled_cells = [
        {
            "context": context,
            "operation": operation,
            "verdict": str(existing.get((context, operation), {}).get(
                "verdict", "known-defect"
            )),
        }
        for context, operation in sorted(
            expected,
            key=lambda key: (context_order[key[0]], key[1]),
        )
    ]
    retired_reachable = [
        {
            "context": context,
            "operation": operation,
            "reason": "source-derived-proof-context-does-not-exist",
        }
        for (context, operation), cell in sorted(existing.items())
        if (context, operation) not in expected
        and cell.get("verdict") == "reachable"
    ]
    mapped_reachable_count = sum(
        cell.get("verdict") == "reachable" and key in expected
        for key, cell in existing.items()
    )
    reconciled = {
        **baseline,
        "schemaVersion": 2,
        "coordinateSystem": "proof-context-v1",
        "cells": reconciled_cells,
    }
    report: dict[str, object] = {
        "oldCellCount": len(cells),
        "newDecisionCount": len(reconciled_cells),
        "oldReachableCount": sum(
            cell.get("verdict") == "reachable" for cell in existing.values()
        ),
        "mappedReachableCount": mapped_reachable_count,
        "mappedReachableDecisionCount": mapped_reachable_count,
        "coalescedReachableEvidenceCount": 0,
        "remappedReachableCount": 0,
        "remappedReachableCells": [],
        "retiredReachableCount": len(retired_reachable),
        "retiredReachableCells": retired_reachable,
        "reachableRegressionCount": 0,
        "reachableRegressions": [],
        "removedNotApplicableCount": 0,
    }
    return reconciled, report


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
    parser.add_argument(
        "--migrate-baseline-proof-contexts",
        action="store_true",
        help=(
            "Replace the legacy four-presentation matrix with source-derived "
            "proof-context decisions and print an executable migration report."
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
    if arguments.migrate_baseline_proof_contexts:
        if not MATRIX_BASELINE.is_file():
            print(
                f"missing {MATRIX_BASELINE.relative_to(REPOSITORY_ROOT)}",
                file=sys.stderr,
            )
            return 1
        baseline = json.loads(MATRIX_BASELINE.read_text(encoding="utf-8"))
        migrated, report = migrate_matrix_baseline(baseline, inventory)
        if report["reachableRegressionCount"] != 0:
            print(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True))
            return 1
        MATRIX_BASELINE.write_text(
            json.dumps(migrated, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        print(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True))
    flagged = [
        record
        for record in inventory["identifiers"]
        if "interactiveEvidence" in record
    ]
    if flagged:
        for record in flagged:
            found = record["interactiveEvidence"]
            print(
                f"FAIL {record['template']} is filed as an observation, but "
                f"{found['path']}:{found['line']} sits under {found['construct']!r}. "
                "Either it is an operation and the classifier must say so, or it "
                "is genuinely inert and belongs in REVIEWED_OBSERVATIONS with the "
                "reason.",
                file=sys.stderr,
            )
        return 1
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
            (str(context), str(operation["id"]))
            for operation in inventory["operations"]
            for context in operation["proofContexts"]
        }
        actual = {
            (str(cell.get("context")), str(cell.get("operation")))
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
        if any(
            cell.get("verdict") == "not-applicable"
            for cell in baseline.get("cells", [])
            if isinstance(cell, dict)
        ):
            print(
                "proof-context baseline must not contain not-applicable filler",
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
