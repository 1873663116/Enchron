#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))
import vocab as vocab_module


def required_capabilities(steps: list[dict[str, Any]]) -> list[str]:
    capabilities: set[str] = set()
    for step in steps:
        verb = vocab_module.verb_or_none(str(step.get("verb", "")))
        if verb is not None:
            capabilities |= set(verb.capabilities)
    return sorted(capabilities)

sys.path.insert(0, str(Path(__file__).resolve().parent))

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENARIOS = REPOSITORY_ROOT / "Regression/journeys"
MEDIA_ROOT = REPOSITORY_ROOT.parent / "TestMedia"

RESET_PRODUCT_STATE = "harness.reset-product-state"
FAULT_RECIPES = frozenset(
    {
        "credentials-rejected",
        "missing-object",
        "access-denied",
        "corrupt-media",
        "transport-interrupted",
    }
)

BLOCKERS = {
    "harness.reset-product-state": "the form connection path needs a product-side look before it can be driven",
    "evidence.capture-audio": "no verb captures audio",
    "evidence.structural-test": "the route runs repository checks before it inspects",
    "issue.present": "the induce route reads the issue control plane first",
    "playback.seek": "the seek needs the viewing-storage probe before it can land",
    "playback.select-subtitle": "the route reads the subtitle listing before it selects",
    "presentation.enter-docked-default": "immersive transitions need the device lane",
    "presentation.enter-panorama": "immersive transitions need the device lane",
    "presentation.exit-spatial": "immersive transitions need the device lane",
    "storage.clear": "the route needs the settings clear action and the viewing storage probe",
}

HANDLED_ELSEWHERE = {
    RESET_PRODUCT_STATE,
    "presentation.enter-docked-default",
    "presentation.enter-panorama",
    "presentation.exit-spatial",
    "evidence.structural-test",
    "playback.seek",
    "issue.present",
    "playback.select-subtitle",
    "storage.clear",
    "host.preflight",
    "media.import-staged",
    "transition-trace.arm",
    "transition-trace.disarm",
    "transition-trace.fetch",
}

UNSUPPORTED = {
    "evidence.capture-audio",
}

DIRECT = {
    "accessibility.activate",
    "accessibility.inspect",
    "accessibility.type",
    "app.relaunch",
    "diagnostics.browse-hierarchy",
    "diagnostics.playback-state",
    "diagnostics.surface-probe",
    "evidence.capture-frames",
    "format.apply",
    "harness.assert-channels",
    "library.snapshot",
    "media.open",
    "navigation.select-tab",
    "playback.await-window-state",
    "playback.wait-position",
}

PRESENTATION = {"either-main-window": None, "window": "window"}

LABEL_IDENTIFIERS = {
    "Playback surface": "PlayerUI-window-playback-surface",
    "Media Library": "FileBrowsing-SourcesSidebar-source-media-library",
    "Local Files": "FileBrowsing-SourcesSidebar-source-media-library",
}

HAND_WRITTEN = {
    "scenario:emby-server-lifecycle:series-season-episode-navigation",
}

PROGRESS_SCENARIOS = {
    "scenario:emby-server-lifecycle:home-poster-and-next-up",
    "scenario:viewing-state-and-storage:resume-entry-semantics",
}

VERIFIED_FILE = REPOSITORY_ROOT / "Config/console/verified-scenarios.json"
COLD_START_FILE = REPOSITORY_ROOT / "Config/console/cold-start-cases.json"


def verified_scenarios() -> set[str]:
    try:
        listed = json.loads(VERIFIED_FILE.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return set()
    return {str(item) for item in listed} if isinstance(listed, list) else set()


_COLD_START_CACHE: list[dict[str, Any]] | None = None


def cold_start_declarations() -> list[dict[str, Any]]:
    global _COLD_START_CACHE
    if _COLD_START_CACHE is not None:
        return _COLD_START_CACHE
    try:
        payload = json.loads(COLD_START_FILE.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return []
    entries = payload.get("cases") if isinstance(payload, dict) else None
    _COLD_START_CACHE = (
        [item for item in entries if isinstance(item, dict)]
        if isinstance(entries, list)
        else []
    )
    return _COLD_START_CACHE


def cold_start_calls(scenario_id: str) -> set[str]:
    return {
        str(item.get("callId"))
        for item in cold_start_declarations()
        if item.get("scenario") == scenario_id
        and item.get("requiresColdStart") is True
    }

TAB_IDENTIFIERS = {
    "files": "Navigation-Ornament-tab-files",
    "emby": "Emby-Navigation-Tab",
    "plex": "Plex-Navigation-Tab",
    "jellyfin": "Jellyfin-Navigation-Tab",
}


def scenario(path: Path) -> dict[str, Any] | None:
    parts = path.read_text(encoding="utf-8").split("---")
    if len(parts) < 3:
        return None
    try:
        return json.loads(parts[1])
    except json.JSONDecodeError:
        return None


PREPARATION_ROOT = REPOSITORY_ROOT / "Regression" / "preparations"
FIXTURE_REGISTRY = REPOSITORY_ROOT / "Tests" / "Fixtures" / "fixture-registry.json"


def fixture_device_import_path(fixture_id: str) -> str | None:
    try:
        registry = json.loads(FIXTURE_REGISTRY.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    entries = registry.get("fixtures") if isinstance(registry, dict) else registry
    if not isinstance(entries, list):
        return None
    for entry in entries:
        if isinstance(entry, dict) and entry.get("id") == fixture_id:
            path = entry.get("deviceImportPath")
            return str(path) if path else None
    return None


def preparation_import_steps(payload: dict[str, Any]) -> list[dict[str, Any]]:
    keys = {
        str(item.get("key"))
        for item in payload.get("prerequisites") or []
        if isinstance(item, dict)
        and item.get("schema") == "media-source.local-directory-sidecars@1"
    }
    if not keys or not PREPARATION_ROOT.is_dir():
        return []
    for path in sorted(PREPARATION_ROOT.glob("*.md")):
        preparation = scenario(path)
        if not preparation:
            continue
        outputs = {
            str(item.get("key")) for item in preparation.get("produces") or []
        }
        if not (outputs & keys):
            continue
        members: dict[str, str] = {}
        directory = ""
        for action in preparation.get("operations") or []:
            name = str(action.get("operation", "")).split(":")[1].split("@")[0]
            arguments = action.get("arguments") or {}
            if name == "media.stage-fixture":
                fixture_id = str(arguments.get("fixtureID") or "")
                import_path = fixture_device_import_path(fixture_id)
                if import_path:
                    members[Path(import_path).name] = import_path
            elif name == "preparation.local-directory-subtitle-source":
                directory = str(arguments.get("directoryName") or "")
                wanted = {
                    str(item) for item in arguments.get("memberFileNames") or []
                }
                if wanted:
                    members = {
                        name: value for name, value in members.items() if name in wanted
                    }
        if not directory or not members:
            continue
        media_file = ""
        for action in preparation.get("operations") or []:
            name = str(action.get("operation", "")).split(":")[1].split("@")[0]
            if name != "preparation.local-directory-subtitle-source":
                continue
            media_file = str((action.get("arguments") or {}).get("mediaFileName") or "")
        if not media_file:
            continue
        sources = [f"test-media:{members[name]}" for name in members]
        return [
            {
                "verb": "device.stage-media",
                "args": {"source": sources, "target": "."},
            },
            {
                "verb": "device.app-command",
                "args": {
                    "verb": "importMediaDirectory",
                    "arguments": {
                        "directory": directory,
                        "media": media_file,
                        "files": json.dumps(list(members)),
                    },
                },
            },
        ]
    return []


def operation_names(payload: dict[str, Any]) -> list[str]:
    return [
        str(action.get("operation", "")).split(":")[1].split("@")[0]
        for action in payload.get("operations", [])
    ]


def fixture(name: str) -> Path | None:
    for path in MEDIA_ROOT.rglob(name):
        if path.is_file():
            return path
    return None


def slug(identifier: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", identifier.lower()).strip("-")


ISSUE_RECIPES = {
    "source-file-missing": "missing-object",
    "source-access-denied": "access-denied",
    "connection-interrupted": "transport-interrupted",
    "media-data-corrupt": "corrupt-media",
    "server-certificate-changed": "certificate-rotation",
}
ISSUE_SLOT_POLICY = {
    "source-file-missing": ("Playback Error", True, True, False),
    "source-access-denied": ("Playback Error", True, True, False),
    "connection-interrupted": ("Playback Error", True, True, False),
    "media-data-corrupt": ("Playback Error", True, True, False),
    "server-certificate-changed": ("Server Certificate Changed", False, True, False),
}
ISSUE_MEDIA_IDENTIFIER = "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv"

AUDIO_TRACK_LABELS = {
    "1": "AAC 880 Hz sync pulse · aac · 2ch",
    "2": "FLAC 660 Hz sync pulse · flac · 2ch",
    "3": "AC-3 440 Hz sync pulse · ac3 · 2ch",
    "4": "E-AC-3 550 Hz sync pulse · eac3 · 2ch",
}
LIBRARY_LABEL = "Enchron Regression Emby"
LIBRARY_ITEM_PREFIX = "Enchron Regression"
EPISODE_PREFIX = "Enchron Regression Episode"
SERIES_PREFIX = "Enchron Regression Series"


def first_emby_label(payload: dict[str, Any]) -> str | None:
    seen_emby = False
    for action in payload.get("operations", []):
        name = str(action.get("operation", "")).split(":")[1].split("@")[0]
        arguments = action.get("arguments", {})
        if name == "navigation.select-tab" and str(arguments.get("tab")) == "emby":
            seen_emby = True
            continue
        if seen_emby and name == "accessibility.activate":
            labels = arguments.get("labels") or []
            for label in labels:
                found_fixture = fixture(str(label))
                if found_fixture is not None and found_fixture not in fixtures:
                    fixtures.append(found_fixture)
            if labels:
                return str(labels[0])
            if arguments.get("identifier"):
                return str(arguments["identifier"])
    return None


def navigation(folder: str | None, clear: bool = False) -> list[dict[str, Any]]:
    steps: list[dict[str, Any]] = [
        {"verb": "device.home", "args": {"clear": True} if clear else {}},
    ]
    if folder:
        steps.append(
            {
                "verb": "device.command",
                "args": {"action": "tap", "identifier": f"MediaLibrary-grid-folder-{folder}"},
            }
        )
    return steps


def translate(payload: dict[str, Any], folder: str) -> tuple[list[dict[str, Any]], list[Path]]:
    cancels_format_editor = "PlayerUI-VideoFormat-cancel" in json.dumps(
        payload.get("operations") or [], ensure_ascii=False
    )
    source_rows: list[str] = []
    remote_source_labels: set[str] = {
        str(label)
        for action in payload.get("operations", [])
        for label in ((action.get("arguments") or {}).get("labels") or [])
        if "webdav" in str(label).lower() or "smb" in str(label).lower()
    }
    remote_opened = any(
        str(action.get("operation", "")).startswith("operation:media.open")
        and str((action.get("arguments") or {}).get("identifier", "")).startswith("FileBrowsing-")
        for action in payload.get("operations", [])
    )
    remote_flow = remote_opened
    if remote_opened and not remote_source_labels:
        remote_source_labels = {"Enchron Regression WebDAV"}

    def panoramic(media: str | None) -> bool:
        return bool(media) and any(
            token in str(media).lower()
            for token in ("apmp", "180", "360", "panorama", "spatial", "immersive")
        )

    def browser_card_steps(identifier: str) -> list[dict[str, Any]]:
        produced: list[dict[str, Any]] = [
            {
                "verb": "device.app-command",
                "args": {"verb": "leavePlayback", "arguments": {}},
            },
            {
                "verb": "device.command",
                "args": {
                    "action": "tap",
                    "identifier": "Navigation-Ornament-tab-files",
                },
            },
            {
                "verb": "device.await",
                "args": {
                    "probe": "element",
                    "field": "identifier",
                    "equals": "FileBrowsing-FilesScreen",
                    "timeoutMs": 20000,
                    "intervalMs": 400,
                },
            },
        ]
        if identifier.startswith("FileBrowsing-"):
            produced.append(
                {
                    "verb": "device.command",
                    "args": {
                        "action": "tap",
                        "identifier": "FileBrowsing-SourcesSidebar-source-",
                        "identifierPrefix": "FileBrowsing-SourcesSidebar-source-",
                        "index": 1,
                    },
                }
            )
        else:
            produced.append(
                {
                    "verb": "device.command",
                    "args": {
                        "action": "tap",
                        "identifier": "FileBrowsing-SourcesSidebar-source-media-library",
                    },
                }
            )
            if not imports_at_root(payload):
                folder_identifier = f"MediaLibrary-grid-folder-{staging_folder}"
                produced.append(
                    {
                        "verb": "device.await",
                        "args": {
                            "probe": "element",
                            "field": "identifier",
                            "equals": folder_identifier,
                            "timeoutMs": 20000,
                            "intervalMs": 300,
                        },
                    }
                )
                produced.append(
                    {
                        "verb": "device.command",
                        "args": {"action": "tap", "identifier": folder_identifier},
                    }
                )
        produced.append(
            {
                "verb": "device.await",
                "args": {
                    "probe": "element",
                    "field": "identifier",
                    "equals": identifier,
                    "timeoutMs": 20000,
                    "intervalMs": 300,
                },
            }
        )
        return produced

    def window_root_wait(timeout_ms: int) -> dict[str, Any]:
        return {
            "verb": "device.await",
            "args": {
                "probe": "element",
                "field": "identifier",
                "equals": "WindowPlayback-root",
                "timeoutMs": timeout_ms,
                "intervalMs": 300,
            },
        }

    def reopen_steps(opened_folder: str, media: str) -> list[dict[str, Any]]:
        produced: list[dict[str, Any]] = [
            {"verb": "device.app-command", "args": {"verb": "leavePlayback", "arguments": {}}}
        ]
        if media and not remote_flow:
            produced.append(
                {
                    "verb": "device.app-command",
                    "args": {"verb": "resetState", "arguments": {"keepSession": "true"}},
                }
            )
            produced.extend(import_actions())
            produced.append(
                {
                    "verb": "device.app-command",
                    "args": {"verb": "playMedia", "arguments": {"name": media}},
                }
            )
            produced.append(
                {
                    "verb": "device.await",
                    "args": {
                        "probe": "PlayerUI-window-control-plane",
                        "equals": {
                            "presentation": PRESENTATION.get("window"),
                            "mediaName": media,
                        },
                        "timeoutMs": 45000,
                        "intervalMs": 400,
                    },
                }
            )
            return produced
        if remote_flow:
            produced.append(
                {
                    "verb": "device.command",
                    "args": {
                        "action": "tap",
                        "identifier": "FileBrowsing-SourcesSidebar-source-",
                        "identifierPrefix": "FileBrowsing-SourcesSidebar-source-",
                        "index": 1,
                    },
                }
            )
            produced.append(
                {
                    "verb": "device.await",
                    "args": {
                        "probe": "element",
                        "field": "identifier",
                        "equals": f"FileBrowsing-grid-video-{media}",
                        "timeoutMs": 20000,
                        "intervalMs": 400,
                    },
                }
            )
            produced.append(
                {
                    "verb": "device.command",
                    "args": {
                        "action": "tap",
                        "identifier": f"FileBrowsing-grid-video-{media}",
                    },
                }
            )
            return produced
        produced.extend(navigation(opened_folder))
        produced.append(
            {
                "verb": "device.await",
                "args": {
                    "probe": "element",
                    "field": "identifier",
                    "equals": f"MediaLibrary-grid-video-{media}",
                    "timeoutMs": 20000,
                    "intervalMs": 400,
                },
            }
        )
        produced.append(
            {
                "verb": "device.command",
                "args": {
                    "action": "tap",
                    "identifier": f"MediaLibrary-grid-video-{media}",
                },
            }
        )
        produced.append(
            {
                "verb": "device.await",
                "args": {
                    "probe": "PlayerUI-window-control-plane",
                    "field": "presentation",
                    "equals": "window",
                    "timeoutMs": 45000,
                    "intervalMs": 400,
                },
            }
        )
        produced.append(
            {
                "verb": "device.await",
                "args": {
                    "probe": "PlayerUI-window-control-plane",
                    "field": "mediaName",
                    "equals": media,
                    "timeoutMs": 15000,
                    "intervalMs": 300,
                },
            }
        )
        produced.append(
            {
                "verb": "device.app-command",
                "args": {"verb": "toggleControls", "arguments": {"visible": "true"}},
            }
        )
        return produced

    def open_identifier(identifier: str) -> str:
        if remote_flow and identifier.startswith("FileBrowsing-"):
            return identifier
        return library_identifier(identifier)

    folder = None if imports_at_root(payload) else folder
    staged = any(
        str(action.get("operation", "")).startswith("operation:media.import-staged")
        or str(action.get("operation", "")).startswith("operation:media.open")
        for action in payload.get("operations", [])
    )
    folder = folder if staged else None
    steps: list[dict[str, Any]] = []
    fixtures: list[Path] = []
    rewound = False
    reset_emitted = False
    library_opened = False
    series_opened = False
    folder_opened = False
    home_emitted = False
    episode_card_opened = False
    episode_played = False
    current_media: str | None = None
    player_interactions = 0
    menu_opened = False
    portal_projection = False
    reset_scenario = RESET_PRODUCT_STATE in operation_names(payload)
    form_facts_emitted = False
    trace_generation = 0
    storage_probes = 0
    import_emitted = False
    in_settings = False
    issue_played = False
    issue_presented = False
    replay_pending = False
    ui_tab = "files"
    settings_category: str | None = None
    cold_calls = cold_start_calls(str(payload.get("id", "")))
    staging_folder = slug(str(payload.get("id", "")))
    local_library_flow = any(
        str(action.get("operation", "")).startswith("operation:media.open")
        and str((action.get("arguments") or {}).get("identifier", "")).startswith(
            "MediaLibrary-grid-video-"
        )
        for action in payload.get("operations", [])
    ) and any(
        str(label) in {"Media Library", "Local Files"}
        for action in payload.get("operations", [])
        for label in ((action.get("arguments") or {}).get("labels") or [])
    )

    def import_actions() -> list[dict[str, Any]]:
        if not fixtures:
            return []
        if remote_flow and not any(
            str(action.get("operation", "")).startswith(
                "operation:media.import-staged"
            )
            for action in payload.get("operations", [])
        ):
            return []
        if imports_at_root(payload) or local_library_flow:
            return [
                {
                    "verb": "device.app-command",
                    "args": {
                        "verb": "importStagedFiles",
                        "arguments": {"directory": staging_folder},
                    },
                }
            ]
        return [
            {
                "verb": "device.app-command",
                "args": {
                    "verb": "importStagedFolder",
                    "arguments": {"directory": staging_folder, "entry": "root"},
                },
            }
        ]

    def relink_source() -> list[dict[str, Any]]:
        if not remote_source_labels:
            return []
        label = sorted(remote_source_labels)[0]
        provider = "smb" if "smb" in label.lower() else "webdav"
        return [
            {
                "verb": "device.connect-source",
                "args": {"provider": provider, "name": label},
            }
        ]

    def reset_case() -> None:
        steps.append(
            {"verb": "device.app-command", "args": {"verb": "leavePlayback", "arguments": {}}}
        )
        steps.append(
            {
                "verb": "device.app-command",
                "args": {"verb": "resetState", "arguments": {"keepSession": "true"}},
            }
        )
        steps.extend(relink_source())
        preparation = preparation_import_steps(payload)
        if preparation:
            steps.extend(preparation)
        else:
            steps.extend(import_actions())

    def already_awaited(probe: str, field: str, equals: str) -> bool:
        for step in reversed(steps):
            verb = str(step.get("verb"))
            if verb == "app.relaunch":
                return False
            if verb == "device.app-command" and step["args"].get("verb") == "resetState":
                return False
            if verb == "device.app-commands" and any(
                call.get("verb") == "resetState"
                for call in step["args"].get("calls", [])
            ):
                return False
            if verb != "device.await":
                continue
            arguments = step.get("args") or {}
            if arguments.get("probe") != probe or arguments.get("mode", "equals") != "equals":
                continue
            if arguments.get("field") == field and str(arguments.get("equals")) == equals:
                return True
            merged = arguments.get("equals")
            if isinstance(merged, dict) and str(merged.get(field)) == equals:
                return True
        return False

    def ensure_files_context() -> None:
        nonlocal in_settings
        if not in_settings:
            return
        in_settings = False
        steps.append(
            {
                "verb": "device.command",
                "args": {
                    "action": "tap",
                    "identifier": "Navigation-Ornament-tab-files",
                },
            }
        )
        steps.append(
            {
                "verb": "device.await",
                "args": {
                    "probe": "element",
                    "field": "identifier",
                    "equals": "FileBrowsing-FilesScreen",
                    "timeoutMs": 20000,
                    "intervalMs": 400,
                },
            }
        )

    operations = payload["operations"]
    for action in operations:
        arguments = action.get("arguments") or {}
        name_text = str(arguments.get("fileName") or "")
        if name_text:
            found = fixture(name_text)
            if found is not None and found not in fixtures:
                fixtures.append(found)
        for key in ("identifier", "identifiers", "alsoInspect"):
            value = arguments.get(key)
            for candidate in value if isinstance(value, list) else [value]:
                if candidate:
                    collect_fixture(str(candidate), fixtures, remote_flow)
    source_name_text = ""
    fault_recipe = ""
    for action in operations:
        arguments = action.get("arguments") or {}
        if arguments.get("identifier") != "FileBrowsing-SourceConnection-webDAV-name":
            continue
        source_name_text = str(arguments.get("text", ""))
        for token in source_name_text.split():
            if token in FAULT_RECIPES:
                fault_recipe = token
        break
    manual_source_flow = bool(fault_recipe)
    form_flow = bool(source_name_text) and not manual_source_flow
    issue_flow = any(
        str(action.get("operation", "")).startswith("operation:issue.present")
        for action in payload.get("operations", [])
    )
    remote_flow = remote_flow or form_flow or issue_flow
    if manual_source_flow:
        name_text = source_name_text
        recipe = fault_recipe
        operations = [
            {
                "operation": "operation:device.connect-source@1",
                "arguments": {
                    "provider": "webdav",
                    "name": name_text or "Failure Matrix",
                    "recipe": recipe,
                    "expectFailure": True,
                },
                "callId": "call:manual-source",
            },
            *[
                action
                for action in operations
                if str(action.get("operation", "")).startswith(
                    ("operation:app.relaunch", "operation:navigation.select-tab")
                )
            ],
        ]
    for operation_index, action in enumerate(operations):
        name = str(action["operation"]).split(":")[1].split("@")[0]
        arguments = action.get("arguments", {})
        if name == RESET_PRODUCT_STATE:
            if form_flow and not form_facts_emitted:
                steps.append(
                    {
                        "verb": "device.source-facts",
                        "args": {"provider": "webdav"},
                        "capture": {
                            "url": "webdavUrl",
                            "username": "webdavUser",
                            "password": "webdavPassword",
                        },
                    }
                )
                form_facts_emitted = True
            reset_arguments: dict[str, str] = {"keepSession": "true"}
            folder_name = arguments.get("rootFolderName")
            if folder_name:
                reset_arguments["libraryFolder"] = str(folder_name)
            steps.append(
                {
                    "verb": "device.app-command",
                    "args": {"verb": "resetState", "arguments": reset_arguments},
                }
            )
            current_media = None
            menu_opened = False
            folder_opened = False
        elif name == "app.relaunch":
            if str(action.get("callId", "")) in cold_calls:
                steps.append({"verb": "app.relaunch", "args": {}})
                current_media = None
                menu_opened = False
                folder_opened = False
                if (
                    reset_scenario
                    and fixtures
                    and not imports_at_root(payload)
                    and not import_emitted
                ):
                    import_emitted = True
                    steps.append(
                        {
                            "verb": "device.app-command",
                            "args": {
                                "verb": "importStagedFolder",
                                "arguments": {
                                    "directory": slug(str(payload["id"])),
                                    "entry": "root",
                                },
                            },
                        }
                    )
                steps.extend(navigation(folder))
                folder_opened = folder is not None
                rewound = True
            elif steps:
                reset_case()
                current_media = None
                menu_opened = False
                folder_opened = False
                rewound = True
            else:
                current_media = None
                menu_opened = False
                folder_opened = False
                rewound = True
        elif name == "navigation.select-tab":
            tab = str(arguments.get("tab"))
            if tab == "settings" and ui_tab == "settings":
                continue
            ui_tab = tab
            if tab != "settings":
                settings_category = None
            if remote_flow and tab == "files":
                continue
            if tab == "emby" and not reset_emitted:
                steps.append(
                    {
                        "verb": "device.app-command",
                        "args": {"verb": "resetMediaNavigation", "arguments": {}},
                    }
                )
                reset_emitted = True
            in_settings = str(arguments["tab"]) == "settings"
            steps.append(
                {
                    "verb": "device.command",
                    "args": {"action": "tap", "identifier": TAB_IDENTIFIERS.get(str(arguments["tab"]), f"Navigation-Ornament-tab-{arguments['tab']}")},
                }
            )
            if str(arguments["tab"]) == "emby":
                steps.append(
                    {
                        "verb": "device.command",
                        "args": {"action": "tap", "identifier": "Emby-Sidebar-home"},
                    }
                )
                target = first_emby_label(payload)
                if target is not None and target.startswith(SERIES_PREFIX):
                    steps.append(
                        {
                            "verb": "device.command",
                            "args": {"action": "tap", "label": LIBRARY_LABEL},
                        }
                    )
        elif name == "media.import-staged":
            file_name = str(arguments.get("fileName") or "")
            found = fixture(file_name) if file_name else None
            if found is not None and found not in fixtures:
                fixtures.append(found)
            local_library_flow = any(
                str(action.get("operation", "")).startswith("operation:media.open")
                and str((action.get("arguments") or {}).get("identifier", "")).startswith(
                    "MediaLibrary-grid-video-"
                )
                for action in payload.get("operations", [])
            ) and any(
                str(label) in {"Media Library", "Local Files"}
                for action in payload.get("operations", [])
                for label in ((action.get("arguments") or {}).get("labels") or [])
            )
            if (
                RESET_PRODUCT_STATE in operation_names(payload)
                and fixtures
                and not import_emitted
            ):
                import_emitted = True
                if imports_at_root(payload) or local_library_flow:
                    steps.append(
                        {
                            "verb": "device.app-command",
                            "args": {
                                "verb": "importStagedFiles",
                                "arguments": {"directory": slug(str(payload["id"]))},
                            },
                        }
                    )
                else:
                    steps.append(
                        {
                            "verb": "device.app-command",
                            "args": {
                                "verb": "importStagedFolder",
                                "arguments": {
                                    "directory": slug(str(payload["id"])),
                                    "entry": "root",
                                },
                            },
                        }
                    )
        elif name == "device.connect-source":
            source_name = str(arguments.get("name") or "")
            if source_name:
                source_rows.append(source_name)
            steps.append({"verb": "device.connect-source", "args": arguments})
        elif name == "media.open":
            ensure_files_context()
            identifier = str(arguments["identifier"])
            if current_media == media_name(identifier):
                steps.append(
                    {
                        "verb": "device.await",
                        "args": {
                            "probe": "PlayerUI-window-control-plane",
                            "field": "mediaName",
                            "equals": current_media,
                            "timeoutMs": 15000,
                            "intervalMs": 300,
                        },
                    }
                )
                continue
            if current_media is not None:
                steps.append(
                    {"verb": "device.app-command", "args": {"verb": "leavePlayback", "arguments": {}}}
                )
                steps.append(
                    {
                        "verb": "device.app-command",
                        "args": {"verb": "resetMediaNavigation", "arguments": {}},
                    }
                )
                steps.append(
                    {
                        "verb": "device.await",
                        "args": {
                            "probe": "element",
                            "field": "identifier",
                            "equals": "Navigation-Ornament-tab-files",
                            "timeoutMs": 10000,
                            "intervalMs": 200,
                        },
                    }
                )
            current_media = media_name(identifier)
            direct_open = identifier.startswith("MediaLibrary-grid-video-")
            replay_open = identifier.startswith("MediaLibrary-grid-video-") and replay_pending
            replay_pending = False
            if folder and not folder_opened and not direct_open:
                steps.append(
                    {
                        "verb": "device.command",
                        "args": {"action": "tap", "identifier": f"MediaLibrary-grid-folder-{folder}"},
                    }
                )
                folder_opened = True
            found = fixture(media_name(identifier))
            if (
                found is not None
                and found not in fixtures
                and not (remote_flow and identifier.startswith("FileBrowsing-"))
            ):
                fixtures.append(found)
            opened = open_identifier(identifier)
            if form_flow and identifier.startswith("FileBrowsing-"):
                steps.append(
                    {
                        "verb": "device.await",
                        "args": {
                            "probe": "element",
                            "field": "identifier",
                            "equals": opened,
                            "timeoutMs": int(arguments.get("deadlineSeconds", 45)) * 1000,
                            "intervalMs": 400,
                        },
                    }
                )
            if replay_open:
                steps.extend(browser_card_steps(opened))
                steps.append(
                    {
                        "verb": "device.command",
                        "args": {"action": "tap", "identifier": opened},
                    }
                )
            elif direct_open:
                steps.append(
                    {
                        "verb": "device.await",
                        "args": {
                            "probe": "element",
                            "field": "identifier",
                            "equals": "PlayerUI-window-control-plane",
                            "mode": "absent",
                            "timeoutMs": 15000,
                            "intervalMs": 200,
                        },
                    }
                )
                steps.append(
                    {
                        "verb": "device.app-command",
                        "args": {
                            "verb": "playMedia",
                            "arguments": {"name": media_name(identifier)},
                        },
                    }
                )
            else:
                if not identifier.startswith("FileBrowsing-"):
                    steps.append(
                        {
                            "verb": "device.await",
                            "args": {
                                "probe": "element",
                                "field": "identifier",
                                "equals": opened,
                                "timeoutMs": 20000,
                                "intervalMs": 400,
                            },
                        }
                    )
                steps.append(
                    {
                        "verb": "device.command",
                        "args": {"action": "tap", "identifier": opened},
                    }
                )
            expects_failure = "loadFailure" in json.dumps(payload, ensure_ascii=False)
            landing = None if expects_failure else PRESENTATION.get(
                str(arguments.get("expectedLanding", "window"))
            )
            if panoramic(current_media):
                landing = None
            if landing:
                steps.append(
                    {
                        "verb": "device.await",
                        "args": {
                            "probe": "PlayerUI-window-control-plane",
                            "field": "presentation",
                            "equals": landing,
                            "timeoutMs": int(arguments.get("deadlineSeconds", 45)) * 1000,
                            "intervalMs": 400,
                        },
                    }
                )
            if not expects_failure and panoramic(current_media):
                steps.append(window_root_wait(45000))
            elif not expects_failure:
                steps.append(
                    {
                        "verb": "device.await",
                        "args": {
                            "probe": "PlayerUI-window-control-plane",
                            "field": "mediaName",
                            "equals": media_name(identifier),
                            "timeoutMs": 15000,
                            "intervalMs": 300,
                        },
                    }
                )
        elif name == "playback.await-window-state":
            episode_card_opened = False
            presentation = PRESENTATION.get(str(arguments.get("presentation", "window")))
            if panoramic(current_media):
                presentation = None
            if presentation and already_awaited(
                "PlayerUI-window-control-plane", "presentation", presentation
            ):
                continue
            if presentation:
                steps.append(
                    {
                        "verb": "device.await",
                        "args": {
                            "probe": "PlayerUI-window-control-plane",
                            "field": "presentation",
                            "equals": presentation,
                            "timeoutMs": int(arguments.get("deadlineSeconds", 45)) * 1000,
                            "intervalMs": 400,
                        },
                    }
                )
        elif name == "playback.wait-position":
            minimum_millis = int(arguments.get("minimumPositionMillis", 0))
            if minimum_millis >= 1000:
                steps.append(
                    {
                        "verb": "device.app-command",
                        "args": {
                            "verb": "seekNormalized",
                            "arguments": {"position": "0.1"},
                        },
                    }
                )
            steps.append(
                {
                    "verb": "device.await",
                    "args": {
                        "probe": "PlayerUI-window-control-plane",
                        "field": "position",
                        "equals": minimum_millis / 1000,
                        "mode": "atLeast",
                        "timeoutMs": int(arguments.get("deadlineSeconds", 45)) * 1000,
                        "intervalMs": 400,
                    },
                }
            )
        elif name == "evidence.capture-frames":
            steps.append(
                {
                    "verb": "device.capture-frames",
                    "args": {
                        "count": 1,
                        "intervalMs": int(arguments.get("minimumIntervalMillis", 1000)),
                    },
                }
            )
        elif name == "accessibility.activate":
            activation_targets = [
                str(item)
                for item in (
                    arguments.get("identifiers")
                    or [arguments.get("identifier")]
                )
                if item
            ]
            activation_labels = arguments.get("labels") or []
            if (
                activation_targets
                and not any(item.startswith("Settings-") for item in activation_targets)
            ) or (not activation_targets and activation_labels):
                ensure_files_context()
            targets = [str(item) for item in (arguments.get("labels") or [])]
            def reaches_emby() -> bool:
                return any(
                    str(item.get("operation", "")) == "operation:navigation.select-tab@1"
                    and item.get("arguments", {}).get("tab") == "emby"
                    for item in payload.get("operations", [])
                )

            if targets and str(targets[0]) in {"以后", "Later", "Not Now"}:
                if activation_targets:
                    steps.append(
                        {
                            "verb": "device.command",
                            "args": {
                                "action": "tapEach",
                                "identifiers": activation_targets,
                            },
                        }
                    )
                continue
            emby_target = bool(targets) and (
                targets[0] == LIBRARY_LABEL
                or targets[0].startswith((SERIES_PREFIX, EPISODE_PREFIX))
            )
            if (
                emby_target
                and str(targets[0]) not in remote_source_labels
                and reaches_emby()
            ):
                if not library_opened:
                    steps.append(
                        {"verb": "device.command", "args": {"action": "tap", "label": LIBRARY_LABEL}}
                    )
                    library_opened = True
                if targets[0].startswith(EPISODE_PREFIX) and not series_opened:
                    steps.append(
                        {
                            "verb": "device.command",
                            "args": {
                                "action": "tap",
                                "label": f"{SERIES_PREFIX}, poster",
                                "labelPrefix": SERIES_PREFIX,
                            },
                        }
                    )
                    series_opened = True
                if len(targets) > 1:
                    for target in targets[1:]:
                        if target.startswith(SERIES_PREFIX):
                            if not series_opened:
                                steps.append(
                                    {
                                        "verb": "device.command",
                                        "args": {
                                            "action": "tap",
                                            "label": f"{SERIES_PREFIX}, poster",
                                            "labelPrefix": SERIES_PREFIX,
                                        },
                                    }
                                )
                                series_opened = True
                        elif target.startswith(EPISODE_PREFIX):
                            steps.append(
                                {
                                    "verb": "device.command",
                                    "args": {
                                        "action": "tap",
                                        "identifier": "Emby-Episode-",
                                        "identifierPrefix": "Emby-Episode-",
                                        "waitMilliseconds": 1200,
                                    },
                                }
                            )
                    continue
            summed = str(arguments.get("summonControls", ""))
            if summed and summed not in {"false", "none"}:
                steps.append(
                    {
                        "verb": "device.app-command",
                        "args": {"verb": "toggleControls", "arguments": {"visible": "true"}},
                    }
                )
            labels = arguments.get("labels") or []
            for label in labels:
                found_fixture = fixture(str(label))
                if found_fixture is not None and found_fixture not in fixtures:
                    fixtures.append(found_fixture)
            if labels and str(labels[0]).startswith(EPISODE_PREFIX) and reaches_emby():
                episode_card_opened = True
                episode_played = True
                steps.append(
                    {
                        "verb": "device.command",
                        "args": {
                            "action": "tap",
                            "identifier": "Emby-Episode-",
                            "identifierPrefix": "Emby-Episode-",
                            "waitMilliseconds": 1200,
                        },
                    }
                )
            elif labels and str(labels[0]) in remote_source_labels:
                source_row = {
                    "action": "tap",
                    "identifier": "FileBrowsing-SourcesSidebar-source-",
                    "identifierPrefix": "FileBrowsing-SourcesSidebar-source-",
                    "index": 1,
                }
                steps.append({"verb": "device.command", "args": source_row})
            elif labels and str(labels[0]) in LABEL_IDENTIFIERS:
                target_identifier = LABEL_IDENTIFIERS[str(labels[0])]
                if target_identifier.startswith("FileBrowsing-SourcesSidebar-"):
                    steps.append(
                        {
                            "verb": "device.command",
                            "args": {
                                "action": "tap",
                                "identifier": "Navigation-Ornament-tab-files",
                            },
                        }
                    )
                    steps.append(
                        {
                            "verb": "device.await",
                            "args": {
                                "probe": "element",
                                "field": "identifier",
                                "equals": "FileBrowsing-FilesScreen",
                                "timeoutMs": 20000,
                                "intervalMs": 400,
                            },
                        }
                    )
                steps.append(
                    {
                        "verb": "device.command",
                        "args": {"action": "tap", "identifier": target_identifier},
                    }
                )
            elif labels:
                label = str(labels[0])
                arguments_out: dict[str, Any] = {"action": "tap", "label": label}
                if "," in label:
                    arguments_out["labelPrefix"] = label.split(",")[0].strip()
                menu_targets = [
                    str(item) for item in (arguments.get("identifiers") or []) if item
                ]
                if menu_targets and arguments.get("labelsAfterIdentifiers"):
                    steps.append(
                        {
                            "verb": "device.command",
                            "args": {"action": "tapEach", "identifiers": menu_targets},
                        }
                    )
                steps.append(
                    {
                        "verb": "device.await",
                        "args": {
                            "probe": "element",
                            "field": "label",
                            "equals": label,
                            "timeoutMs": 20000,
                            "intervalMs": 400,
                        },
                    }
                )
                if menu_targets and not arguments.get("labelsAfterIdentifiers"):
                    steps.append(
                        {
                            "verb": "device.command",
                            "args": {"action": "tapEach", "identifiers": menu_targets},
                        }
                    )
                steps.append({"verb": "device.command", "args": arguments_out})
                menu_opened = False
            else:
                targets = [
                    str(item)
                    for item in (arguments.get("identifiers") or [arguments.get("identifier")])
                    if item
                ]
                if targets and targets[0].endswith("SourceConnection-webDAV-connect"):
                    steps.append(
                        {
                            "verb": "device.await",
                            "args": {
                                "probe": "element",
                                "field": "identifier",
                                "equals": targets[0],
                                "timeoutMs": 30000,
                                "intervalMs": 400,
                            },
                        }
                    )
                    steps.append(
                        {
                            "verb": "device.command",
                            "args": {
                                "action": "tapEach",
                                "identifiers": targets,
                            },
                        }
                    )
                    continue
                if not targets:
                    raise SystemExit(
                        f"{name} names neither identifiers nor a label in {payload.get('id')}"
                    )
                if targets == ["PlayerUI-VideoFormat-cancel"]:
                    continue
                if replay_pending and targets[0].startswith(
                    ("MediaLibrary-grid-video-", "FileBrowsing-grid-video-")
                ):
                    replay_pending = False
                    steps.extend(browser_card_steps(targets[0]))
                    steps.append(
                        {
                            "verb": "device.command",
                            "args": {"action": "tap", "identifier": targets[0]},
                        }
                    )
                    continue
                if targets == ["PlayerUI-InfoBar-button-back"]:
                    steps.append(
                        {
                            "verb": "device.app-command",
                            "args": {"verb": "leavePlayback", "arguments": {}},
                        }
                    )
                    steps.append(
                        {
                            "verb": "device.app-command",
                            "args": {"verb": "resetMediaNavigation", "arguments": {}},
                        }
                    )
                    steps.append(
                        {
                            "verb": "device.await",
                            "args": {
                                "probe": "element",
                                "field": "identifier",
                                "equals": "Navigation-Ornament-tab-files",
                                "timeoutMs": 10000,
                                "intervalMs": 200,
                            },
                        }
                    )
                    replay_pending = True
                    current_media = None
                    continue
                if targets and all(
                    item.startswith("PlayerUI-loadFailure-")
                    or item.startswith("PlayerUI-playbackIssue-")
                    for item in targets
                ):
                    steps.append(
                        {
                            "verb": "device.app-command",
                            "args": {"verb": "clearPlaybackIssue", "arguments": {}},
                        }
                    )
                    continue
                if targets == ["PlayerUI-resumeDecision-secondary"]:
                    steps.append(
                        {
                            "verb": "device.app-command",
                            "args": {
                                "verb": "resolveResumePrompt",
                                "arguments": {"action": "startOver"},
                            },
                        }
                    )
                    continue
                if targets == ["PlayerUI-resumeDecision-primary"]:
                    steps.append(
                        {
                            "verb": "device.app-command",
                            "args": {
                                "verb": "resolveResumePrompt",
                                "arguments": {"action": "resume"},
                            },
                        }
                    )
                    continue
                if targets == ["PlayerPanel-button-play"]:
                    steps.append(
                        {
                            "verb": "device.await",
                            "args": {
                                "probe": "PlayerUI-window-control-plane",
                                "field": "lifecycle",
                                "equals": "Playing",
                                "timeoutMs": 15000,
                                "intervalMs": 300,
                            },
                        }
                    )
                    continue
                for target in targets:
                    collect_fixture(target, fixtures)
                if episode_card_opened and all(
                    target == "Emby-Detail-Play" or target.startswith("PlayerUI-resumeDecision")
                    for target in targets
                ):
                    continue
                if "Emby-Detail-Play" in targets and episode_played:
                    targets = [item for item in targets if item != "Emby-Detail-Play"]
                    steps.append(
                        {
                            "verb": "device.command",
                            "args": {
                                "action": "tap",
                                "identifier": "Emby-Episode-",
                                "identifierPrefix": "Emby-Episode-",
                                "waitMilliseconds": 1200,
                            },
                        }
                    )
                    if not targets:
                        continue
                player_targets = any(
                    str(target).startswith(("PlayerUI-TopAction-", "PlayerUI-menu-"))
                    for target in targets
                )
                if player_targets and menu_opened and current_media:
                    steps.extend(reopen_steps(folder, current_media))
                    menu_opened = False
                if player_targets:
                    player_interactions += 1
                    menu_opened = True
                if targets and all(
                    item.startswith("PlayerUI-TopAction-")
                    or item == "PlayerUI-VideoFormat-cancel"
                    for item in targets
                ):
                    continue
                audio_target = next(
                    (
                        item
                        for item in targets
                        if re.fullmatch(r"PlayerUI-menu-audio-\d+", str(item))
                    ),
                    None,
                )
                audio_label = None
                if (
                    audio_target is not None
                    and current_media == "sdr-bframe-aggregate-30s.mkv"
                ):
                    ordinal = str(audio_target).rsplit("-", 1)[-1]
                    audio_label = AUDIO_TRACK_LABELS.get(ordinal)
                if audio_label is not None:
                    label = audio_label
                    remaining = [item for item in targets if item != audio_target]
                    if remaining:
                        if any(item.startswith("PlayerUI-TopAction-") for item in remaining):
                            steps.append(
                                {
                                    "verb": "device.app-command",
                                    "args": {
                                        "verb": "toggleControls",
                                        "arguments": {"visible": "true"},
                                    },
                                }
                            )
                        steps.append(
                            {
                                "verb": "device.command",
                                "args": {"action": "tapEach", "identifiers": remaining},
                            }
                        )
                    steps.append(
                        {
                            "verb": "device.command",
                            "args": {"action": "tap", "label": label},
                        }
                    )
                    menu_opened = False
                    continue
                if len(targets) > 1 and any(
                    item.startswith("PlayerUI-VideoFormat-") for item in targets
                ):
                    steps.append(
                        {
                            "verb": "device.app-command",
                            "args": {"verb": "reapplyFormat", "arguments": {}},
                        }
                    )
                    continue
                if len(targets) > 1:
                    targets = [
                        item
                        for item in targets
                        if item != "PlayerUI-window-playback-surface"
                    ] or targets
                    if episode_card_opened and "Emby-Detail-Play" in targets:
                        targets = [item for item in targets if item != "Emby-Detail-Play"]
                    if len(targets) > 1:
                        alternatives = any(
                            item.startswith("PlayerUI-resumeDecision") for item in targets
                        )
                        if any(item.startswith("PlayerUI-TopAction-") for item in targets):
                            steps.append(
                                {
                                    "verb": "device.app-command",
                                    "args": {
                                        "verb": "toggleControls",
                                        "arguments": {"visible": "true"},
                                    },
                                }
                            )
                        steps.append(
                            {
                                "verb": "device.command",
                                "args": {
                                    "action": "tapAnyOf" if alternatives else "tapEach",
                                    "identifiers": targets,
                                },
                            }
                        )
                        if labels:
                            label = str(labels[0])
                            arguments_out: dict[str, Any] = {
                                "action": "tap",
                                "label": label,
                            }
                            if "," in label:
                                arguments_out["labelPrefix"] = label.split(",")[0].strip()
                            steps.append({"verb": "device.command", "args": arguments_out})
                        continue
                for target in targets:
                    if target == "PlayerUI-resumeDecision-secondary":
                        steps.append(
                            {
                                "verb": "device.app-command",
                                "args": {
                                    "verb": "seekNormalized",
                                    "arguments": {"position": "0"},
                                },
                            }
                        )
                        continue
                    if target == "PlayerUI-resumeDecision-primary":
                        continue
                    action_name = (
                        "press"
                        if str(arguments.get("gesture") or "") == "press"
                        else "tap"
                    )
                    action_args: dict[str, Any] = {
                        "action": action_name,
                        "identifier": target,
                    }
                    if action_name == "press":
                        action_args["duration"] = (
                            float(arguments.get("durationMillis", 1000)) / 1000.0
                        )
                    steps.append({"verb": "device.command", "args": action_args})
        elif name in {"accessibility.activate", "accessibility.type"}:
            activated_identifier = str(arguments.get("identifier") or "")
            if replay_pending and activated_identifier.startswith(
                ("MediaLibrary-grid-video-", "FileBrowsing-grid-video-")
            ):
                replay_pending = False
                steps.extend(browser_card_steps(activated_identifier))
                steps.append(
                    {
                        "verb": "device.command",
                        "args": {"action": "tap", "identifier": activated_identifier},
                    }
                )
                continue
            if (
                (activated_identifier.startswith("FileBrowsing-grid-video-")
                 or activated_identifier.startswith("MediaLibrary-grid-video-"))
                and not already_awaited("element", "identifier", activated_identifier)
            ):
                steps.append(
                    {
                        "verb": "device.await",
                        "args": {
                            "probe": "element",
                            "field": "identifier",
                            "equals": activated_identifier,
                            "timeoutMs": 20000,
                            "intervalMs": 300,
                        },
                    }
                )
            if activated_identifier.startswith("Settings-category-"):
                if settings_category == activated_identifier:
                    continue
                settings_category = activated_identifier
            args: dict[str, Any] = {"action": "tap", "identifier": arguments.get("identifier")}
            gesture = str(arguments.get("gesture") or "")
            if gesture == "press":
                args["action"] = "press"
                args["duration"] = float(arguments.get("durationMillis", 1000)) / 1000.0
            if name == "accessibility.type" and "text" in arguments:
                args["action"] = "typeText"
                args["text"] = arguments["text"]
            elif name == "accessibility.type" and form_flow:
                field = str(arguments.get("identifier") or "")
                references = {
                    "webDAV-address": "$webdavUrl",
                    "webDAV-username": "$webdavUser",
                    "webDAV-password": "$webdavPassword",
                }
                for marker, reference in references.items():
                    if field.endswith(marker):
                        args["action"] = "typeText"
                        args["text"] = reference
                        break
            steps.append({"verb": "device.command", "args": args})
        elif name == "accessibility.inspect":

            raw = str(arguments.get("identifier"))
            if not raw.startswith("Settings-"):
                ensure_files_context()
            collect_fixture(raw, fixtures)
            if "-grid-video-" in raw and not raw.startswith("Settings-"):
                steps.extend(browser_card_steps(raw))
                steps.append({"verb": "device.probe", "args": {"probe": raw}})
                continue
            if form_flow and arguments.get("requireMatchedElement"):
                steps.append(
                    {
                        "verb": "device.await",
                        "args": {
                            "probe": "element",
                            "field": "identifier",
                            "equals": open_identifier(raw),
                            "timeoutMs": int(arguments.get("deadlineSeconds", 45)) * 1000,
                            "intervalMs": 400,
                        },
                    }
                )
                continue
            if any(marker in raw for marker in ("loadFailure", "SourceConnection-")):
                expected = open_identifier(raw)
                field = "identifier"
                if expected == "PlayerUI-loadFailure-secondary" and any(
                    category in json.dumps(payload, ensure_ascii=False)
                    for category in ("unsupportedVideoCodec", "mediaRequestFailed")
                ):
                    expected = "Unable to Play"
                    field = "label"
                steps.append(
                    {
                        "verb": "device.await",
                        "args": {
                            "probe": "element",
                            "field": field,
                            "equals": expected,
                            "timeoutMs": int(arguments.get("deadlineSeconds", 45)) * 1000,
                            "intervalMs": 400,
                        },
                    }
                )
                continue
            if raw == "PlayerUI-playbackIssue-confirm":
                steps.append(
                    {
                        "verb": "device.await",
                        "args": {
                            "probe": "element",
                            "field": "identifier",
                            "equals": raw,
                            "mode": "absent",
                            "timeoutMs": 20000,
                            "intervalMs": 400,
                        },
                    }
                )
                continue
            if raw.startswith("PlayerUI-resumeDecision"):
                steps.append(
                    {
                        "verb": "device.app-command",
                        "args": {
                            "verb": "resolveResumePrompt",
                            "arguments": {
                                "action": "startOver" if raw.endswith("secondary") else "resume"
                            },
                        },
                    }
                )
                continue
            if raw == "Emby-Detail-Play" and episode_card_opened:
                raw = "PlayerUI-window-control-plane"
            steps.append(
                {
                    "verb": "device.probe",
                    "args": {"probe": open_identifier(raw)},
                }
            )
        elif name == "evidence.structural-test":
            steps.append(
                {
                    "verb": "static.structural-test",
                    "args": {"check": str(arguments.get("check", ""))},
                }
            )
        elif name == "issue.present":
            category = str(arguments.get("category") or "")
            recipe = ISSUE_RECIPES.get(category)
            policy = ISSUE_SLOT_POLICY.get(category)
            if recipe is None or policy is None:
                continue
            deadline_ms = int(arguments.get("deadlineSeconds", 45)) * 1000
            activate_step = {
                "verb": "device.fault-source",
                "args": {
                    "provider": "webdav",
                    "phase": "activate",
                    "recipe": recipe,
                },
            }
            if not issue_played:
                ensure_files_context()
                steps.append(
                    {
                        "verb": "device.command",
                        "args": {
                            "action": "tap",
                            "identifier": "FileBrowsing-SourcesSidebar-source-",
                            "identifierPrefix": "FileBrowsing-SourcesSidebar-source-",
                            "index": 1,
                        },
                    }
                )
                steps.append(
                    {
                        "verb": "device.await",
                        "args": {
                            "probe": "element",
                            "field": "identifier",
                            "equals": ISSUE_MEDIA_IDENTIFIER,
                            "timeoutMs": 20000,
                            "intervalMs": 400,
                        },
                    }
                )
                steps.append(
                    {
                        "verb": "device.command",
                        "args": {"action": "tap", "identifier": ISSUE_MEDIA_IDENTIFIER},
                    }
                )
                steps.append(
                    {
                        "verb": "device.await",
                        "args": {
                            "probe": "PlayerUI-window-control-plane",
                            "field": "position",
                            "equals": 1.0,
                            "mode": "atLeast",
                            "timeoutMs": deadline_ms,
                            "intervalMs": 400,
                        },
                    }
                )
                issue_played = True
                steps.append(activate_step)
                steps.append(
                    {
                        "verb": "device.app-command",
                        "args": {
                            "verb": "seekNormalized",
                            "arguments": {"position": "0.92"},
                        },
                    }
                )
            else:
                steps.append(activate_step)
                steps.append(
                    {
                        "verb": "device.command",
                        "args": {
                            "action": "tap",
                            "identifier": "PlayerUI-loadFailure-primary",
                        },
                    }
                )
            title, primary, secondary, confirm = policy
            steps.append(
                {
                    "verb": "device.await",
                    "args": {
                        "probe": "element",
                        "field": "label",
                        "equals": title,
                        "timeoutMs": deadline_ms,
                        "intervalMs": 400,
                    },
                }
            )
            for identifier, required in (
                ("PlayerUI-loadFailure-primary", primary),
                ("PlayerUI-loadFailure-secondary", secondary),
                ("PlayerUI-playbackIssue-confirm", confirm),
            ):
                args: dict[str, Any] = {
                    "probe": "element",
                    "field": "identifier",
                    "equals": identifier,
                    "timeoutMs": 20000,
                    "intervalMs": 400,
                }
                if not required:
                    args["mode"] = "absent"
                steps.append({"verb": "device.await", "args": args})
            steps.append(
                {
                    "verb": "device.fault-source",
                    "args": {
                        "provider": "webdav",
                        "phase": "restore",
                        "recipe": recipe,
                    },
                }
            )
            issue_presented = True
        elif name == "storage.clear":
            target_name = str(arguments.get("target", ""))
            action_identifier = "Settings-action-" + STORAGE_CLEAR_ACTIONS.get(
                target_name, f"clear-{target_name}"
            )
            in_settings = True
            steps.append(
                {
                    "verb": "device.command",
                    "args": {
                        "action": "tap",
                        "identifier": "Navigation-Ornament-tab-settings",
                    },
                }
            )
            steps.append(
                {
                    "verb": "device.await",
                    "args": {
                        "probe": "element",
                        "field": "identifier",
                        "equals": "Settings-SettingsScreen",
                        "timeoutMs": 20000,
                        "intervalMs": 400,
                    },
                }
            )
            steps.append(
                {
                    "verb": "device.await",
                    "args": {
                        "probe": "element",
                        "field": "identifier",
                        "equals": "Settings-category-storagePrivacy",
                        "timeoutMs": 20000,
                        "intervalMs": 400,
                    },
                }
            )
            steps.append(
                {
                    "verb": "device.command",
                    "args": {
                        "action": "tap",
                        "identifier": "Settings-category-storagePrivacy",
                        "waitMilliseconds": 800,
                    },
                }
            )
            steps.append(
                {
                    "verb": "device.await",
                    "args": {
                        "probe": "element",
                        "field": "identifier",
                        "equals": action_identifier,
                        "timeoutMs": 20000,
                        "intervalMs": 400,
                    },
                }
            )
            steps.append(
                {
                    "verb": "device.command",
                    "args": {"action": "tap", "identifier": action_identifier},
                }
            )
        elif name in {"diagnostics.surface-probe", "diagnostics.browse-hierarchy", "harness.assert-channels"}:
            if arguments.get("includeViewingStorage"):
                call = re.findall(r":([0-9]{2})$", str(action.get("callId") or ""))
                probe_index = int(call[0]) if call else storage_probes + 1
                storage_probes = probe_index
                capture = {
                    "viewingStateRecordCount": f"viewingRecords{probe_index}",
                    "viewingStateProtectedStateDigest": f"viewingProtectedDigest{probe_index}",
                    "protectedStateDigest": f"libraryProtectedDigest{probe_index}",
                    "snapshotDigest": f"viewingStorageDigest{probe_index}",
                }
                steps.append(
                    {"verb": "device.viewing-storage", "args": {}, "capture": capture}
                )
                deadline_ms = int(arguments.get("deadlineSeconds", 30)) * 1000
                empty_stores = [
                    str(item) for item in (arguments.get("awaitEmptyStores") or [])
                ]
                if "viewing-state" in empty_stores:
                    steps.append(
                        {
                            "verb": "device.await",
                            "args": {
                                "probe": "viewing-storage",
                                "field": "viewingStateRecordCount",
                                "equals": "0",
                                "timeoutMs": deadline_ms,
                                "intervalMs": 400,
                            },
                        }
                    )
                if "container-index" in empty_stores:
                    steps.append(
                        {
                            "verb": "device.await",
                            "args": {
                                "probe": "viewing-storage",
                                "field": "containerIndexEntryCount",
                                "equals": "0",
                                "timeoutMs": deadline_ms,
                                "intervalMs": 400,
                            },
                        }
                    )
                if not arguments.get("identifier"):
                    continue
            if arguments.get("identifier"):
                steps.append(
                    {
                        "verb": "device.probe",
                        "args": {"probe": open_identifier(str(arguments["identifier"]))},
                    }
                )
            else:
                steps.append({"verb": "device.snapshot", "args": {}})
        elif name in {"diagnostics.playback-state"}:
            if portal_projection:
                steps.append(window_root_wait(30000))
                continue
            steps.append(
                {
                    "verb": "device.app-command",
                    "args": {"verb": "toggleControls", "arguments": {"visible": "true"}},
                }
            )
            if menu_opened and current_media:
                steps.extend(reopen_steps(folder, current_media))
                menu_opened = False
            steps.append({"verb": "device.snapshot", "args": {}})
        elif name == "host.preflight":
            if arguments.get("check") == "remote-faults":
                recipe = str(arguments.get("recipe", ""))
                phase = "restore" if arguments.get("phase") == "restore" else "activate"
                steps.append(
                    {
                        "verb": "device.fault-source",
                        "args": {
                            "provider": "webdav",
                            "phase": phase,
                            "recipe": recipe,
                        },
                    }
                )
                if phase == "activate":
                    steps.append(
                        {
                            "verb": "device.app-command",
                            "args": {
                                "verb": "seekNormalized",
                                "arguments": {"position": "0.92"},
                            },
                        }
                    )
        elif name == "library.snapshot":
            steps.append({"verb": "device.snapshot", "args": {}})
        elif name == "format.apply":
            if cancels_format_editor:
                continue
            projection = str(arguments["projection"])
            arguments_out = {
                "projection": projection,
                "stereo": str(arguments["stereoLayout"]),
            }
            field_of_view = arguments.get("horizontalFieldOfViewDegrees")
            if field_of_view is not None:
                arguments_out["horizontalFieldOfViewDegrees"] = str(field_of_view)
            next_is_format_apply = (
                operation_index + 1 < len(operations)
                and str(operations[operation_index + 1].get("operation", "")).startswith(
                    "operation:format.apply"
                )
            )
            steps.append(
                {
                    "verb": "device.app-command",
                    "args": {"verb": "applyFormat", "arguments": arguments_out},
                }
            )
            leaves_window = projection.startswith("equirectangular") or panoramic(
                current_media
            )
            portal_projection = leaves_window
            if leaves_window and next_is_format_apply:
                steps.append(
                    {
                        "verb": "device.await",
                        "args": {
                            "probe": "PlayerUI-window-control-plane",
                            "field": "presentation",
                            "equals": "portal",
                            "timeoutMs": int(arguments.get("deadlineSeconds", 30))
                            * 1000,
                            "intervalMs": 400,
                        },
                    }
                )
            elif not leaves_window:
                steps.append(
                    {
                        "verb": "device.await",
                        "args": {
                            "probe": "PlayerUI-window-control-plane",
                            "field": "projection",
                            "equals": projection,
                            "timeoutMs": int(arguments.get("deadlineSeconds", 30)) * 1000,
                            "intervalMs": 300,
                        },
                    }
                )
        elif name in {
            "presentation.enter-panorama",
            "presentation.enter-docked-default",
            "presentation.exit-spatial",
        }:
            deadline_ms = int(arguments.get("deadlineSeconds", 30)) * 1000
            if name == "presentation.exit-spatial":
                steps.append(
                    {
                        "verb": "device.app-command",
                        "args": {"verb": "exitSpatial", "arguments": {}},
                    }
                )
                expected = "portal" if portal_projection else "window"
                steps.append(
                    {
                        "verb": "device.await",
                        "args": {
                            "probe": "PlayerUI-window-control-plane",
                            "field": "presentation",
                            "equals": expected,
                            "timeoutMs": deadline_ms,
                            "intervalMs": 400,
                        },
                    }
                )
            else:
                landing = "portal" if portal_projection else "window"
                steps.append(
                    {
                        "verb": "device.await",
                        "args": {
                            "probe": "PlayerUI-window-control-plane",
                            "field": "presentation",
                            "equals": landing,
                            "timeoutMs": deadline_ms,
                            "intervalMs": 400,
                        },
                    }
                )
                spatial_arguments: dict[str, Any] = {}
                if name == "presentation.enter-docked-default":
                    spatial_arguments["environment"] = "quiet-room"
                steps.append(
                    {
                        "verb": "device.app-command",
                        "args": {"verb": "enterSpatial", "arguments": spatial_arguments},
                    }
                )
                steps.append(
                    {
                        "verb": "device.await",
                        "args": {
                            "probe": "element",
                            "field": "identifier",
                            "equals": "PlayerPanel-button-exit-spatial",
                            "timeoutMs": deadline_ms,
                            "intervalMs": 400,
                        },
                    }
                )
        elif name == "playback.select-subtitle":
            deadline_ms = int(arguments.get("deadlineSeconds", 30)) * 1000
            host = str(arguments.get("host") or "playerUI")
            if host == "playerPanel":
                more_identifier = "PlayerPanel-menu-more"
                subtitles_identifier = "PlayerPanel-menu-subtitles"
            else:
                more_identifier = "PlayerUI-TopAction-more"
                subtitles_identifier = "PlayerUI-menu-subtitles"
            track_label = str(arguments.get("trackLabel") or "")
            steps.append(
                {
                    "verb": "device.app-command",
                    "args": {
                        "verb": "toggleControls",
                        "arguments": {"visible": "true"},
                    },
                }
            )
            for identifier in (more_identifier, subtitles_identifier):
                steps.append(
                    {
                        "verb": "device.await",
                        "args": {
                            "probe": "element",
                            "field": "identifier",
                            "equals": identifier,
                            "timeoutMs": 20000,
                            "intervalMs": 300,
                        },
                    }
                )
                steps.append(
                    {
                        "verb": "device.command",
                        "args": {"action": "tap", "identifier": identifier},
                    }
                )
            if track_label:
                steps.append(
                    {
                        "verb": "device.await",
                        "args": {
                            "probe": "element",
                            "field": "label",
                            "equals": track_label,
                            "timeoutMs": 20000,
                            "intervalMs": 300,
                        },
                    }
                )
                steps.append(
                    {
                        "verb": "device.command",
                        "args": {"action": "tap", "label": track_label},
                    }
                )
            else:
                emby_stream_label = "English (SRT)"
                steps.append(
                    {
                        "verb": "device.await",
                        "args": {
                            "probe": "element",
                            "field": "label",
                            "equals": emby_stream_label,
                            "timeoutMs": 20000,
                            "intervalMs": 300,
                        },
                    }
                )
                steps.append(
                    {
                        "verb": "device.command",
                        "args": {"action": "tap", "label": emby_stream_label},
                    }
                )
            steps.append(
                {
                    "verb": "device.await",
                    "args": {
                        "probe": "PlayerUI-window-control-plane",
                        "field": "subtitleTrack",
                        "mode": "differs",
                        "equals": "off",
                        "timeoutMs": deadline_ms,
                        "intervalMs": 400,
                    },
                }
            )
            steps.append(
                {
                    "verb": "device.await",
                    "args": {
                        "probe": "PlayerUI-window-control-plane",
                        "field": "subtitleCues",
                        "mode": "atLeast",
                        "equals": 1,
                        "timeoutMs": 20000,
                        "intervalMs": 400,
                    },
                }
            )
        elif name == "playback.seek":
            if arguments.get("summonControls"):
                steps.append(
                    {
                        "verb": "device.app-command",
                        "args": {"verb": "toggleControls", "arguments": {"visible": "true"}},
                    }
                )
            millionths = int(arguments["positionMillionths"])
            steps.append(
                {
                    "verb": "device.command",
                    "args": {
                        "action": "coordinateTap",
                        "identifier": "PlayerPanel-progress",
                        "normalizedX": round(millionths / 1_000_000, 4),
                        "normalizedY": 0.5,
                    },
                }
            )
            steps.append(
                {
                    "verb": "device.await",
                    "args": {
                        "probe": "PlayerUI-window-control-plane",
                        "field": "presentation",
                        "equals": "window",
                        "timeoutMs": 20000,
                        "intervalMs": 400,
                    },
                }
            )
        elif name == "transition-trace.arm":
            arguments_out: dict[str, Any] = {}
            if arguments.get("fault") not in (None, "none"):
                arguments_out["fault"] = str(arguments["fault"])
            trace_generation += 1
            steps.append(
                {
                    "verb": "device.app-command",
                    "args": {"verb": "armTransitionTrace", "arguments": arguments_out},
                    "capture": {"generation": f"traceGeneration{trace_generation}"},
                }
            )
        elif name == "transition-trace.fetch":
            steps.append(
                {
                    "verb": "device.app-command",
                    "args": {
                        "verb": "fetchTransitionTraceSnapshot",
                        "arguments": {"generation": f"$traceGeneration{trace_generation}"},
                    },
                }
            )
        elif name == "transition-trace.disarm":
            steps.append(
                {
                    "verb": "device.app-command",
                    "args": {
                        "verb": "disarmTransitionTrace",
                        "arguments": {"generation": f"$traceGeneration{trace_generation}"},
                    },
                }
            )
        else:
            raise SystemExit(f"{name} is outside the direct vocabulary")
    imports_local_files = any(
        str(action.get("operation", "")).startswith("operation:media.import-staged")
        for action in payload.get("operations", [])
    )
    if remote_flow and not imports_local_files:
        fixtures = []
    return steps, fixtures


VIDEO_PREFIXES = ("MediaLibrary-grid-video-", "FileBrowsing-grid-video-")
RECORDED_VIDEO_PREFIX = "FileBrowsing-grid-video-"
LIBRARY_VIDEO_PREFIX = "MediaLibrary-grid-video-"


IDENTIFIER_ALIASES = {
    "Emby-Home": "Emby-Root",
}


def library_identifier(identifier: str) -> str:
    identifier = IDENTIFIER_ALIASES.get(identifier, identifier)
    if identifier.startswith(RECORDED_VIDEO_PREFIX):
        return LIBRARY_VIDEO_PREFIX + identifier[len(RECORDED_VIDEO_PREFIX):]
    return identifier


def media_name(identifier: str) -> str:
    for prefix in VIDEO_PREFIXES:
        if prefix in identifier:
            return identifier.split(prefix)[-1]
    return identifier.split("-video-")[-1]


ROOT_LEVEL_IDS = (
    "MediaLibrary-Manage-",
    "MediaLibrary-MultiSelect-",
)


def imports_at_root(payload: dict[str, Any]) -> bool:
    inspect_only = all(
        str(action.get("operation", "")).split(":")[1].split("@")[0]
        in {"evidence.structural-test", "accessibility.inspect"}
        for action in payload.get("operations", [])
    )
    if inspect_only:
        return True
    for action in payload.get("operations", []):
        name = str(action.get("operation", ""))
        arguments = action.get("arguments", {})
        if name.endswith("media.open@2"):
            identifier = str(arguments.get("identifier", ""))
            if identifier.startswith("FileBrowsing-grid-video-"):
                return True
            continue
        if not name.endswith("accessibility.activate@2"):
            continue
        text = " ".join(
            [
                *[str(item) for item in arguments.get("identifiers") or []],
                *[str(item) for item in arguments.get("alsoInspect") or []],
            ]
        )
        if any(marker in text for marker in ROOT_LEVEL_IDS):
            return True
    return False


SOURCE_PRECONDITIONS = {
    "webdav-test-source-ready": {"kind": "media-source", "provider": "webdav"},
    "smb-test-source-ready": {"kind": "media-source", "provider": "smb"},
}


def source_preconditions(payload: dict[str, Any]) -> list[dict[str, Any]]:
    declared = []
    for prerequisite in payload.get("prerequisites") or []:
        entry = SOURCE_PRECONDITIONS.get(str(prerequisite.get("key")))
        if entry is not None and entry not in declared:
            declared.append(entry)
    operation_text = json.dumps(payload.get("operations") or [], ensure_ascii=False).lower()
    if "remote-faults" in operation_text:
        entry = {"kind": "media-source", "provider": "webdav"}
        if entry not in declared:
            declared.append(entry)
    for provider in ("webdav", "smb"):
        entry = {"kind": "media-source", "provider": provider}
        if provider in operation_text and entry not in declared:
            declared.append(entry)
    return declared


def collect_fixture(
    identifier: str,
    fixtures: list[Path],
    remote_flow: bool = False,
) -> None:
    if "-grid-video-" not in identifier:
        return
    if remote_flow and identifier.startswith(RECORDED_VIDEO_PREFIX):
        return
    found = fixture(media_name(identifier))
    if found is not None and found not in fixtures:
        fixtures.append(found)


def simplify(actions: list[dict[str, Any]]) -> list[dict[str, Any]]:
    collapsed: list[dict[str, Any]] = []
    for position, action in enumerate(actions):
        last = position == len(actions) - 1
        if collapsed:
            previous = collapsed[-1]
            if previous["verb"] == action["verb"] == "app.relaunch" and not last:
                continue
            if previous["verb"] == action["verb"] == "device.home" and not last:
                continue
            repeated_navigation = (
                action["verb"] == "device.command"
                and "navBackForward" in str(action.get("args", {}).get("identifier", ""))
            )
            if (
                previous["verb"] == action["verb"]
                and previous["verb"] in {"device.command", "device.app-command"}
                and previous.get("args", {}) == action.get("args", {})
                and not repeated_navigation
            ):
                continue
            if previous["verb"] == "device.probe" and action["verb"] == "device.command":
                if previous.get("args", {}).get("probe") == action.get("args", {}).get("identifier"):
                    collapsed[-1] = action
                    continue
            opens_menu = (
                previous["verb"] == "device.command"
                and str(previous.get("args", {}).get("identifier", "")).startswith("PlayerUI-TopAction-")
            )
            probes_plane = (
                action["verb"] == "device.probe"
                and action.get("args", {}).get("probe") == "PlayerUI-window-control-plane"
            )
            if opens_menu and probes_plane:
                collapsed.append(action)
                collapsed.append(previous)
                collapsed.pop(-3)
                continue
            if previous["verb"] == "device.snapshot" and action["verb"] == "device.probe":
                continue
            if (
                previous["verb"] == "device.home"
                and action["verb"] == "device.app-command"
                and action.get("args", {}).get("verb") == "setViewMode"
            ):
                continue
            if previous["verb"] == action["verb"] == "device.await":
                same_probe = previous["args"].get("probe") == action["args"].get("probe")
                simple = (
                    previous["args"].get("mode", "equals") == "equals"
                    and action["args"].get("mode", "equals") == "equals"
                    and previous["args"].get("field")
                    and action["args"].get("field")
                    and previous["args"]["field"] != action["args"]["field"]
                )
                if same_probe and simple:
                    merged = dict(previous)
                    merged["args"] = dict(previous["args"])
                    merged["args"]["equals"] = {
                        str(previous["args"]["field"]): previous["args"].get("equals"),
                        str(action["args"]["field"]): action["args"].get("equals"),
                    }
                    merged["args"].pop("field", None)
                    merged["args"]["timeoutMs"] = max(
                        int(previous["args"].get("timeoutMs", 30_000)),
                        int(action["args"].get("timeoutMs", 30_000)),
                    )
                    collapsed[-1] = merged
                    continue
            if (
                previous["verb"] == action["verb"] == "device.app-command"
                and not previous.get("capture")
                and not action.get("capture")
                and previous["args"].get("verb") not in CASE_COMMANDS
                and action["args"].get("verb") not in CASE_COMMANDS
            ):
                merged = {
                    "verb": "device.app-commands",
                    "args": {
                        "calls": [
                            {
                                "verb": previous["args"]["verb"],
                                "arguments": previous["args"].get("arguments", {}),
                            },
                            {
                                "verb": action["args"]["verb"],
                                "arguments": action["args"].get("arguments", {}),
                            },
                        ]
                    },
                }
                collapsed[-1] = merged
                continue
            if (
                previous["verb"] == "device.app-commands"
                and action["verb"] == "device.app-command"
                and action["args"].get("verb") not in CASE_COMMANDS
            ):
                call = {
                    "verb": action["args"]["verb"],
                    "arguments": action["args"].get("arguments", {}),
                }
                if call not in previous["args"]["calls"]:
                    previous["args"]["calls"].append(call)
                continue
        collapsed.append(action)
    return collapsed


def unit_for(path: Path) -> dict[str, Any]:
    return unit_parts(path)[0]


def unit_parts(path: Path) -> list[dict[str, Any]]:
    payload = scenario(path)
    assert payload is not None
    identifier = str(payload["id"])
    folder = slug(identifier)
    steps, fixtures = translate(payload, folder)
    actions = [
        {"verb": "device.session.ensure", "args": {"lane": "simulator"}},
        {"verb": "device.app-command", "args": {"verb": "leavePlayback", "arguments": {}}},
    ]
    actions.append(
        {
            "verb": "device.app-command",
            "args": {
                "verb": "resetState",
                "arguments": {"keepSession": "true"},
            },
        }
    )
    reset_scenario = RESET_PRODUCT_STATE in operation_names(payload)
    if fixtures:
        actions.append(
            {
                "verb": "device.stage-media",
                "args": {
                    "source": [f"test-media:{found.relative_to(MEDIA_ROOT)}" for found in fixtures],
                    "target": folder,
                },
            }
        )
        if reset_scenario:
            pass
        elif imports_at_root(payload):
            actions.append(
                {
                    "verb": "device.app-command",
                    "args": {"verb": "importStagedFiles", "arguments": {"directory": folder}},
                }
            )
        else:
            actions.append(
                {
                    "verb": "device.app-command",
                    "args": {
                        "verb": "importStagedFolder",
                        "arguments": {"directory": folder, "entry": "root"},
                    },
                }
            )
    actions.extend(preparation_import_steps(payload))
    remote_opened = any(
        str(action.get("operation", "")).startswith("operation:media.open")
        and str((action.get("arguments") or {}).get("identifier", "")).startswith("FileBrowsing-")
        for action in payload.get("operations", [])
    )
    form_scenario = any(
        str(action.get("operation", "")).startswith("operation:accessibility.type")
        and str((action.get("arguments") or {}).get("identifier", "")).endswith(
            "webDAV-address"
        )
        for action in payload.get("operations", [])
    )
    issue_scenario = any(
        str(action.get("operation", "")).startswith("operation:issue.present")
        for action in payload.get("operations", [])
    )
    remote_operations = (remote_opened or issue_scenario) and not form_scenario
    source_labels = {
        str(label)
        for action in payload.get("operations", [])
        for label in ((action.get("arguments") or {}).get("labels") or [])
        if "webdav" in str(label).lower()
    }
    browser_remote = any(
        str(action.get("operation", "")).startswith("operation:accessibility.inspect")
        and str((action.get("arguments") or {}).get("identifier", "")).startswith(
            "FileBrowsing-grid-video-"
        )
        for action in payload.get("operations", [])
    )
    defaulted_source = remote_operations and not source_labels
    if browser_remote and not source_labels:
        source_labels = {"Enchron Regression WebDAV"}
    if defaulted_source:
        source_labels = {"Enchron Regression WebDAV"}
    if source_labels:
        actions.append(
            {
                "verb": "device.connect-source",
                "args": {
                    "provider": "webdav",
                    "name": sorted(source_labels)[0],
                },
            }
        )
        reset_index = next(
            (
                index
                for index, action in enumerate(actions)
                if action["verb"] == "device.app-command"
                and action["args"].get("verb") == "resetState"
            ),
            None,
        )
        if reset_index is not None:
            insertion = reset_index + 1
        else:
            insertion = next(
                (
                    index + 1
                    for index, action in enumerate(actions)
                    if action["verb"] == "app.relaunch"
                ),
                len(actions),
            )
        actions.insert(insertion, actions.pop())
        if defaulted_source:
            actions.insert(
                insertion + 1,
                {
                    "verb": "device.command",
                    "args": {
                        "action": "tap",
                        "label": sorted(source_labels)[0],
                    },
                },
            )
    teardown = [
        {
            "verb": "device.app-command",
            "args": {"verb": "leavePlayback", "arguments": {}},
        }
    ]
    if fixtures:
        teardown.append(
            {
                "verb": "device.app-command",
                "args": {"verb": "deleteLibraryFolder", "arguments": {"name": folder}},
            }
        )
    simplified = simplify(steps)
    scenario_reset = next(
        (
            index
            for index, action in enumerate(simplified)
            if action["verb"] == "device.app-command"
            and action["args"].get("verb") == "resetState"
        ),
        None,
    )
    if scenario_reset is not None and reset_scenario:
        imports = [
            action
            for action in actions
            if action["verb"] == "device.app-command"
            and action["args"].get("verb") in {"importStagedFolder", "importStagedFiles"}
        ]
        if imports:
            actions = [action for action in actions if action not in imports]
            simplified[scenario_reset + 1 : scenario_reset + 1] = imports
    segment_starts = [0] + [
        position
        for position, action in enumerate(simplified)
        if position > 0 and begins_case(action)
    ]
    names = case_names(payload, segment_starts)
    segment_index = {start: index for index, start in enumerate(segment_starts)}
    simplified = dedupe_settings(dedupe_steps(simplified))
    chunks = split_steps(simplified)
    preamble_length = len(actions)
    missing_fixtures = [
        str(action.get("arguments", {}).get("identifier", "")).split("-grid-video-")[-1]
        for action in payload.get("operations", [])
        if action.get("operation", "").startswith("operation:media.open")
        and fixture(media_name(str(action.get("arguments", {}).get("identifier", "")))) is None
    ]
    preconditions = (
        [{"kind": "media-server", "provider": "emby"}]
        + ([{"kind": "media-progress"}] if identifier in PROGRESS_SCENARIOS else [])
        + source_preconditions(payload)
        + ([{"kind": "media-fixture", "fixtures": missing_fixtures}] if missing_fixtures else [])
    )
    pace = "scenario" if identifier in verified_scenarios() else "catalog"
    parts: list[dict[str, Any]] = []
    chunk_offset = 0
    for position, chunk in enumerate(chunks, start=1):
        part_steps = list(chunk)
        part_cases = []
        for local_index in range(len(part_steps)):
            simplified_index = chunk_offset + local_index
            if local_index == 0 and simplified_index not in segment_index:
                earlier = [start for start in segment_starts if start <= simplified_index]
                owner = segment_index[earlier[-1]] if earlier else 0
            elif simplified_index in segment_index:
                owner = segment_index[simplified_index]
            else:
                continue
            part_cases.append(
                {
                    "key": names[owner],
                    "start": preamble_length + local_index,
                }
            )
        if not part_cases and part_steps:
            part_cases.append({"key": names[0], "start": preamble_length})
        chunk_offset += len(part_steps)
        if part_steps and part_steps[-1]["verb"] not in EVIDENCE_VERBS:
            part_steps.append({"verb": "device.snapshot", "args": {}})
        suffix = "" if position == 1 else f".part{position}"
        parts.append(
            {
                "schema": "enchron.console.unit",
                "schemaVersion": 1,
                "id": f"unit:catalog.{folder}{suffix}@1",
                "layer": 3,
                "role": "verification",
                "pace": pace,
                "requires": (
                    ["mac", "device", "daemon"]
                    if set(required_capabilities(actions + part_steps + list(teardown)))
                    == {"mac", "device", "daemon"}
                    else required_capabilities(actions + part_steps + list(teardown))
                ),
                "isolation": "clean-library",
                "preconditions": preconditions,
                "actions": actions + part_steps,
                "teardown": teardown,
                "terminal": terminal_of(part_steps),
                "cases": part_cases,
            }
        )
    return parts


MAX_PART_STEPS = 26
EVIDENCE_VERBS = ("device.probe", "device.snapshot", "device.capture-frames")
CASE_COMMANDS = frozenset(
    {
        "leavePlayback",
        "resetState",
        "importStagedFolder",
        "importStagedFiles",
        "playMedia",
    }
)


def begins_case(step: dict[str, Any]) -> bool:
    if step["verb"] == "app.relaunch":
        return True
    if step["verb"] == "device.app-command":
        return step["args"].get("verb") == "resetState"
    if step["verb"] == "device.app-commands":
        return any(
            call.get("verb") == "resetState"
            for call in step["args"].get("calls", [])
        )
    return False


def dedupe_steps(steps: list[dict[str, Any]]) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    index = 0
    while index < len(steps):
        if index + 3 < len(steps):
            first, second, third, fourth = steps[index : index + 4]
            if (
                first == third
                and second == fourth
                and first != second
            ):
                result.extend([first, second])
                index += 4
                continue
        result.append(steps[index])
        index += 1
    return result


def dedupe_settings(steps: list[dict[str, Any]]) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    tab = "files"
    category = ""
    skip_awaits = False
    for step in steps:
        verb = step["verb"]
        arguments = step.get("args") or {}
        identifier = str(arguments.get("identifier") or "")
        if skip_awaits and verb == "device.await":
            expected = str(arguments.get("equals") or "")
            if expected in {"Settings-SettingsScreen", "Settings-category-storagePrivacy"}:
                continue
            skip_awaits = False
        elif verb != "device.await":
            skip_awaits = False
        if verb == "device.home" or verb == "app.relaunch":
            tab = "files"
            category = ""
            result.append(step)
            continue
        if verb == "device.command" and identifier == "Navigation-Ornament-tab-settings":
            if tab == "settings":
                skip_awaits = True
                continue
            tab = "settings"
            category = ""
            result.append(step)
            continue
        if verb == "device.command" and identifier.startswith("Navigation-Ornament-tab-"):
            tab = identifier.removeprefix("Navigation-Ornament-tab-")
            category = ""
            result.append(step)
            continue
        if verb == "device.command" and identifier.startswith("Settings-category-"):
            if tab == "settings" and category == identifier:
                continue
            category = identifier
            result.append(step)
            continue
        result.append(step)
    return result


def split_steps(steps: list[dict[str, Any]]) -> list[list[dict[str, Any]]]:
    chunks: list[list[dict[str, Any]]] = []
    current: list[dict[str, Any]] = []
    for position, step in enumerate(steps):
        starts_case = position > 0 and begins_case(step)
        if starts_case and current and len(current) + 4 > MAX_PART_STEPS:
            chunks.append(current)
            current = []
        current.append(step)
    if current:
        chunks.append(current)
    return chunks


def case_names(payload: dict[str, Any], starts: list[int]) -> list[str]:
    declared = [str(item) for item in payload.get("staticCases") or []]
    if len(declared) == len(starts):
        return declared
    return [f"case-{position}" for position in range(1, len(starts) + 1)]


EVIDENCE_FALLBACK = {
    "device.capture-frames": "frames.json",
    "device.snapshot": "hierarchy.json",
    "device.probe": "probe.json",
    "device.command": "command.json",
    "device.app-command": "app-command.json",
}


def terminal_of(actions: list[dict[str, Any]]) -> dict[str, Any]:
    import vocab
    for action in reversed(actions):
        verb = vocab.verb_or_none(str(action["verb"]))
        if verb is not None and verb.evidence:
            return {"kind": "artifact", "path": verb.evidence, "schema": verb.schema}
    return {"kind": "exit", "equals": 0}


def blocked(payload: dict[str, Any]) -> list[str]:
    found: list[str] = []
    for action in payload.get("operations", []):
        name = str(action.get("operation", "")).split(":")[1].split("@")[0]
        arguments = action.get("arguments", {})
        if name in UNSUPPORTED:
            found.append(name)

        elif name not in DIRECT and name not in HANDLED_ELSEWHERE:
            found.append(name)
    return found


FORM_FACTS: frozenset[str] = frozenset()

STORAGE_CLEAR_ACTIONS = {
    "artwork-cache": "clear-artwork-cache",
    "container-index-cache": "clear-container-index-cache",
    "playback-progress": "clear-progress",
}


VERIFIED_SEEK_SCENARIOS = frozenset(
    {
        "scenario:viewing-state-and-storage:clear-all-local-progress",
        "scenario:viewing-state-and-storage:completed-media-starts-from-beginning",
        "scenario:presentation-tour:track-selection-survives-seek-and-presentation",
    }
)
VERIFIED_CLEAR_SCENARIOS = frozenset(
    {
        "scenario:local-media-lifecycle:artwork-captured-on-exit",
        "scenario:viewing-state-and-storage:clear-all-local-progress",
        "scenario:viewing-state-and-storage:local-playback-does-not-write-index",
        "scenario:viewing-state-and-storage:remote-index-reused-on-second-open",
        "scenario:viewing-state-and-storage:storage-rows-report-and-clear",
    }
)
SKIPPED_FILE = REPOSITORY_ROOT / "Config/console/skipped-scenarios.json"


def skipped_scenarios() -> dict[str, str]:
    try:
        payload = json.loads(SKIPPED_FILE.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return {
        str(item["scenario"]): str(item.get("reason", ""))
        for item in payload.get("skipped", [])
        if isinstance(item, dict) and item.get("scenario")
    }
PRESENTATION_OPS = frozenset(
    {
        "presentation.enter-panorama",
        "presentation.enter-docked-default",
        "presentation.exit-spatial",
    }
)
VERIFIED_PRESENTATION_SCENARIOS = frozenset(
    {
        "scenario:presentation-tour:docked-episode-switch-settles-and-exits",
        "scenario:presentation-tour:panorama-to-portal-exit",
        "scenario:presentation-tour:track-selection-survives-seek-and-presentation",
        "scenario:presentation-tour:portal-format-and-panorama-actions-coexist",
        "scenario:presentation-tour:portal-to-panorama-explicit-entry",
        "scenario:presentation-tour:transition-timeout-rolls-back",
        "scenario:presentation-tour:window-docked-round-trip",
        "scenario:projection-and-stereo:panorama-coverage-angle",
    }
)

VERIFIED_RESET_SCENARIOS = frozenset(
    {
        "scenario:library-management:confirmed-batch-deletion",
        "scenario:library-management:current-folder-search-counts",
        "scenario:library-management:folder-delete-rehomes-references",
        "scenario:library-management:folder-naming",
        "scenario:library-management:move-references",
        "scenario:local-media-lifecycle:clean-flat-playback-main-gate",
        "scenario:local-media-lifecycle:clean-start-position-zero",
        "scenario:webdav-source-lifecycle:webdav-add-source",
    }
)


def expressible(path: Path) -> bool:
    payload = scenario(path)
    if payload is None:
        return False
    return (
        bool(operation_names(payload))
        and not blocked(payload)
        and str(payload.get("id")) not in HAND_WRITTEN
        and str(payload.get("id")) not in FORM_FACTS
        and (
            RESET_PRODUCT_STATE not in operation_names(payload)
            or str(payload.get("id")) in VERIFIED_RESET_SCENARIOS
        )
        and (
            not (PRESENTATION_OPS & set(operation_names(payload)))
            or str(payload.get("id")) in VERIFIED_PRESENTATION_SCENARIOS
        )
        and (
            "playback.seek" not in operation_names(payload)
            or str(payload.get("id")) in VERIFIED_SEEK_SCENARIOS
        )
        and (
            "storage.clear" not in operation_names(payload)
            or str(payload.get("id")) in VERIFIED_CLEAR_SCENARIOS
        )
        and str(payload.get("id")) not in skipped_scenarios()
    )


def write_feature(journey: str, identifiers: list[str]) -> None:
    slugged = re.sub(r"[^a-z0-9]+", "-", journey.lower()).strip("-")
    target = REPOSITORY_ROOT / "Config/console/features" / f"journey-{slugged}.md"
    declared: set[str] = set()
    for unit_path in (REPOSITORY_ROOT / "Config/console/units").glob("*.md"):
        try:
            head = unit_path.read_text(encoding="utf-8").split("---")[1]
            identifier = str(json.loads(head).get("id", ""))
        except (json.JSONDecodeError, IndexError):
            continue
        if identifier:
            declared.add(identifier)
    existing_units: list[str] = []
    if target.exists():
        head = target.read_text(encoding="utf-8").split("---")[1]
        try:
            existing_units = [
                str(unit)
                for unit in json.loads(head).get("units", [])
                if str(unit) in declared
            ]
        except (json.JSONDecodeError, IndexError):
            existing_units = []
    payload = {
        "schema": "enchron.console.feature",
        "schemaVersion": 1,
        "id": f"feature:journey.{slugged}",
        "title": journey.replace("-", " ").title(),
        "units": sorted(set(identifiers) | set(existing_units)),
        "promises": [],
    }
    body = json.dumps(payload, indent=2, ensure_ascii=False)
    target.write_text(
        f"---\n{body}\n---\n\nEvery scenario of the {journey} journey that the direct vocabulary already carries.\n",
        encoding="utf-8",
    )


def prune_features() -> None:
    declared: set[str] = set()
    for unit_path in (REPOSITORY_ROOT / "Config/console/units").glob("*.md"):
        try:
            head = unit_path.read_text(encoding="utf-8").split("---")[1]
            identifier = str(json.loads(head).get("id", ""))
        except (json.JSONDecodeError, IndexError):
            continue
        if identifier:
            declared.add(identifier)
    for feature_path in (REPOSITORY_ROOT / "Config/console/features").glob("*.md"):
        try:
            head = feature_path.read_text(encoding="utf-8").split("---")[1]
            payload = json.loads(head)
        except (json.JSONDecodeError, IndexError):
            continue
        units = [str(unit) for unit in payload.get("units", []) if str(unit) in declared]
        if units == [str(unit) for unit in payload.get("units", [])]:
            continue
        if not units:
            feature_path.unlink()
            continue
        payload["units"] = units
        body = json.dumps(payload, indent=2, ensure_ascii=False)
        feature_path.write_text(
            f"---\n{body}\n---\n\n{feature_path.read_text(encoding='utf-8').split('---', 2)[2].lstrip()}\n",
            encoding="utf-8",
        )


def report_gaps() -> int:
    registered = skipped_scenarios()
    blocking: dict[str, list[str]] = {}
    for path in sorted(SCENARIOS.rglob("*.md")):
        payload = scenario(path)
        if payload is None:
            continue
        names = operation_names(payload)
        if not names:
            continue
        if str(payload["id"]) in registered:
            continue
        if blocked(payload):
            for name in set(blocked(payload)):
                blocking.setdefault(name, []).append(str(payload["id"]))
    for name in sorted(blocking, key=lambda item: -len(blocking[item])):
        reason = BLOCKERS.get(name, "no mapping yet")
        print(f"{len(blocking[name]):3d} scenario(s)  {name}: {reason}")
    pending = [
        str(payload["id"])
        for path in SCENARIOS.rglob("*.md")
        if (payload := scenario(path)) is not None
        and str(payload["id"]) not in registered
        and RESET_PRODUCT_STATE in operation_names(payload)
        and str(payload["id"]) not in VERIFIED_RESET_SCENARIOS
    ]
    if pending:
        print(
            f"{len(pending):3d} scenario(s)  {RESET_PRODUCT_STATE}: "
            "translated, waiting for a verification run"
        )
    gates = (
        (PRESENTATION_OPS, VERIFIED_PRESENTATION_SCENARIOS),
        (frozenset({"playback.seek"}), VERIFIED_SEEK_SCENARIOS),
        (frozenset({"storage.clear"}), VERIFIED_CLEAR_SCENARIOS),
    )
    waiting: dict[str, list[str]] = {}
    for path in sorted(SCENARIOS.rglob("*.md")):
        payload = scenario(path)
        if payload is None:
            continue
        names = set(operation_names(payload))
        if not names or str(payload["id"]) in registered:
            continue
        for operations, verified in gates:
            if operations & names and str(payload["id"]) not in verified:
                waiting.setdefault(sorted(operations)[0], []).append(str(payload["id"]))
    if registered:
        reasons = sorted({reason for reason in registered.values()})
        print(
            f"{len(registered):3d} scenario(s)  {SKIPPED_FILE.relative_to(REPOSITORY_ROOT)}: "
            + "; ".join(reasons)
        )
    for name in sorted(waiting, key=lambda item: -len(waiting[item])):
        print(
            f"{len(waiting[name]):3d} scenario(s)  {name}: "
            "translated, waiting for a verification run"
        )
    return 0


def report_restarts() -> int:
    declared = {
        (str(item.get("scenario")), str(item.get("callId"))): item
        for item in cold_start_declarations()
    }
    actual: list[tuple[str, str, str]] = []
    for path in sorted(SCENARIOS.rglob("*.md")):
        payload = scenario(path)
        if payload is None:
            continue
        for action in payload.get("operations", []):
            if str(action.get("operation", "")).startswith("operation:app.relaunch"):
                actual.append(
                    (
                        str(payload["id"]),
                        str(action.get("callId")),
                        str(action.get("caseKey", "")),
                    )
                )
    missing = [item for item in actual if (item[0], item[1]) not in declared]
    stale = sorted(set(declared) - {(item[0], item[1]) for item in actual})
    cold = sum(
        1 for item in declared.values() if item.get("requiresColdStart") is True
    )
    for scenario_id, call_id, _ in actual:
        item = declared.get((scenario_id, call_id), {})
        decision = "cold-start" if item.get("requiresColdStart") else "isolation"
        print(f"{decision:10s}  {scenario_id}  {call_id}  {item.get('reason', 'undeclared')}")
    print(
        f"{len(actual)} relaunch operation(s), {cold} cold-start, "
        f"{len(actual) - cold} isolation"
    )
    if missing:
        for scenario_id, call_id, _ in missing:
            print(f"undeclared  {scenario_id}  {call_id}", file=sys.stderr)
    for scenario_id, call_id in stale:
        print(f"stale  {scenario_id}  {call_id}", file=sys.stderr)
    return 0 if not missing and not stale else 1


def main(argv: list[str]) -> int:
    if "--gaps" in argv:
        return report_gaps()
    if "--restarts" in argv:
        return report_restarts()
    written = 0
    journeys: dict[str, list[str]] = {}
    if "--check" not in argv:
        for stale in (REPOSITORY_ROOT / "Config/console/units").glob("catalog-*.md"):
            if "series-navigation" in stale.name:
                continue
            stale.unlink()
    for path in sorted(SCENARIOS.rglob("*.md")):
        if not expressible(path):
            continue
        payload = scenario(path)
        assert payload is not None
        folder = slug(str(payload["id"]))
        target = REPOSITORY_ROOT / "Config/console/units" / f"catalog-{folder}.md"
        if "--check" in argv:
            print(f"would write {target.name}")
            written += 1
            continue
        title = str(payload.get("title", folder))
        for position, unit in enumerate(unit_parts(path), start=1):
            suffix = "" if position == 1 else f"-part{position}"
            name = f"catalog-{folder}{suffix}.md"
            body = json.dumps(unit, indent=2, ensure_ascii=False)
            (REPOSITORY_ROOT / "Config/console/units" / name).write_text(
                f"---\n{body}\n---\n\n{title}\n\nGenerated from `{path.relative_to(REPOSITORY_ROOT)}`.\n",
                encoding="utf-8",
            )
            journeys.setdefault(str(payload.get("journey", folder)), []).append(unit["id"])
            written += 1
    if "--check" not in argv:
        for journey, identifiers in journeys.items():
            write_feature(journey, identifiers)
        prune_features()
    print(f"{written} scenario unit(s), {len(journeys)} journey feature(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
