#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENARIOS = REPOSITORY_ROOT / "Config/regression/catalog-root/journeys"
MEDIA_ROOT = REPOSITORY_ROOT.parent / "TestMedia"

RESET_PRODUCT_STATE = "harness.reset-product-state"

BLOCKERS = {
    "input.device-hub-pinch": "no verb carries the device hub pinch gesture",
    "input.device-hub-prepare": "no verb prepares the device hub",
    "evidence.capture-audio": "no verb captures audio",
    "evidence.structural-test": "no verb runs a structural check",
    "issue.present": "the induce route reads the issue control plane first",
    "playback.seek": "the seek reads the session, media name and duration before it acts",
    "playback.select-subtitle": "the route reads the subtitle listing before it selects",
    "presentation.enter-docked-default": "the route taps a dock placement sequence",
    "presentation.enter-panorama": "the route taps a panorama sequence and settles",
    "presentation.exit-spatial": "the route reads the spatial state before it exits",
    "storage.clear": "the route taps a settings action and compares storage observations",
    RESET_PRODUCT_STATE: "the reset signs out the source and clears the library the later steps need",
}

HANDLED_ELSEWHERE = {
    "host.preflight",
    "media.import-staged",
    "transition-trace.arm",
    "transition-trace.disarm",
    "transition-trace.fetch",
}

UNSUPPORTED = {
    RESET_PRODUCT_STATE,
    "input.device-hub-pinch",
    "evidence.capture-audio",
    "evidence.structural-test",
    "input.device-hub-prepare",
    "issue.present",
    "playback.seek",
    "playback.select-subtitle",
    "presentation.enter-docked-default",
    "presentation.enter-panorama",
    "presentation.exit-spatial",
    "storage.clear",
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
    "input.device-hub-pinch",
    "library.snapshot",
    "media.open",
    "navigation.select-tab",
    "playback.await-window-state",
    "playback.wait-position",
}

PRESENTATION = {"either-main-window": "window", "window": "window"}

HAND_WRITTEN = {
    "scenario:emby-server-lifecycle:series-season-episode-navigation",
}

PROGRESS_SCENARIOS = {
    "scenario:emby-server-lifecycle:home-poster-and-next-up",
    "scenario:viewing-state-and-storage:resume-entry-semantics",
}

VERIFIED_FILE = REPOSITORY_ROOT / "Config/console/verified-scenarios.json"


def verified_scenarios() -> set[str]:
    try:
        listed = json.loads(VERIFIED_FILE.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return set()
    return {str(item) for item in listed} if isinstance(listed, list) else set()

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
    operation_text = json.dumps(payload.get("operations") or [], ensure_ascii=False).lower()
    remote_flow = any(
        marker in operation_text for marker in ("webdav", "smb", "filebrowsing-grid-video-")
    )

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
    for action in payload["operations"]:
        name = str(action["operation"]).split(":")[1].split("@")[0]
        arguments = action.get("arguments", {})
        if name == "app.relaunch":
            steps.append({"verb": "app.relaunch", "args": {}})
            steps.extend(navigation(folder))
            folder_opened = folder is not None
            rewound = True
        elif name == "navigation.select-tab":
            if remote_flow:
                continue
            if str(arguments["tab"]) == "emby" and not reset_emitted:
                steps.append(
                    {
                        "verb": "device.app-command",
                        "args": {"verb": "resetMediaNavigation", "arguments": {}},
                    }
                )
                reset_emitted = True
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
        elif name == "media.open":
            identifier = str(arguments["identifier"])
            current_media = media_name(identifier)
            if folder and not folder_opened:
                steps.append(
                    {
                        "verb": "device.command",
                        "args": {"action": "tap", "identifier": f"MediaLibrary-grid-folder-{folder}"},
                    }
                )
                folder_opened = True
            if identifier.startswith("FileBrowsing-"):
                fixtures.clear()
            found = fixture(media_name(identifier))
            if found is not None and found not in fixtures and not identifier.startswith("FileBrowsing-"):
                fixtures.append(found)
            steps.append(
                {
                    "verb": "device.command",
                    "args": {"action": "tap", "identifier": open_identifier(identifier)},
                }
            )
            expects_failure = "loadFailure" in json.dumps(payload, ensure_ascii=False)
            landing = None if expects_failure else PRESENTATION.get(
                str(arguments.get("expectedLanding", "window"))
            )
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
            if not expects_failure:
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
            steps.append(
                {
                    "verb": "device.await",
                    "args": {
                        "probe": "PlayerUI-window-control-plane",
                        "field": "position",
                        "equals": int(arguments.get("minimumPositionMillis", 0)) / 1000,
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
                        "count": int(arguments.get("count", 3)),
                        "intervalMs": int(arguments.get("minimumIntervalMillis", 1000)),
                    },
                }
            )
        elif name == "accessibility.activate":
            targets = [str(item) for item in (arguments.get("labels") or [])]
            def reaches_emby() -> bool:
                return any(
                    str(item.get("operation", "")) == "operation:navigation.select-tab@1"
                    and item.get("arguments", {}).get("tab") == "emby"
                    for item in payload.get("operations", [])
                )

            if targets and targets[0].startswith(LIBRARY_ITEM_PREFIX) and reaches_emby():
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
            elif labels:
                label = str(labels[0])
                arguments_out: dict[str, Any] = {"action": "tap", "label": label}
                if "," in label:
                    arguments_out["labelPrefix"] = label.split(",")[0].strip()
                menu_targets = [
                    str(item) for item in (arguments.get("identifiers") or []) if item
                ]
                if menu_targets:
                    steps.append(
                        {
                            "verb": "device.command",
                            "args": {"action": "tapEach", "identifiers": menu_targets},
                        }
                    )
                steps.append({"verb": "device.command", "args": arguments_out})
            else:
                targets = [
                    str(item)
                    for item in (arguments.get("identifiers") or [arguments.get("identifier")])
                    if item
                ]
                if not targets:
                    raise SystemExit(
                        f"{name} names neither identifiers nor a label in {payload.get('id')}"
                    )
                if targets == ["PlayerUI-InfoBar-button-back"]:
                    steps.append(
                        {
                            "verb": "device.app-command",
                            "args": {"verb": "leavePlayback", "arguments": {}},
                        }
                    )
                    continue
                if targets == ["PlayerUI-resumeDecision-secondary"]:
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
                if targets == ["PlayerUI-resumeDecision-primary"]:
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
                    steps.extend(navigation(folder))
                    steps.append(
                        {
                            "verb": "device.command",
                            "args": {
                                "action": "tap",
                                "identifier": f"MediaLibrary-grid-video-{current_media}",
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
                                "timeoutMs": 45000,
                                "intervalMs": 400,
                            },
                        }
                    )
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
                    steps.append(
                        {
                            "verb": "device.app-command",
                            "args": {
                                "verb": "toggleControls",
                                "arguments": {"visible": "true"},
                            },
                        }
                    )
                    menu_opened = False
                if player_targets:
                    player_interactions += 1
                    menu_opened = True
                if len(targets) > 1:
                    if episode_card_opened and "Emby-Detail-Play" in targets:
                        targets = [item for item in targets if item != "Emby-Detail-Play"]
                    if len(targets) > 1:
                        alternatives = any(
                            item.startswith("PlayerUI-resumeDecision") for item in targets
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
                    steps.append(
                        {
                            "verb": "device.command",
                            "args": {"action": "tap", "identifier": target},
                        }
                    )
        elif name in {"accessibility.activate", "accessibility.type"}:
            args: dict[str, Any] = {"action": "tap", "identifier": arguments.get("identifier")}
            if name == "accessibility.type" and "text" in arguments:
                args["action"] = "typeText"
                args["text"] = arguments["text"]
            steps.append({"verb": "device.command", "args": args})
        elif name == "accessibility.inspect":

            raw = str(arguments.get("identifier"))
            collect_fixture(raw, fixtures)
            if any(marker in raw for marker in ("loadFailure", "SourceConnection-")):
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
            if raw == "Emby-Detail-Play" and episode_card_opened:
                raw = "PlayerUI-window-control-plane"
            steps.append(
                {
                    "verb": "device.probe",
                    "args": {"probe": open_identifier(raw)},
                }
            )
        elif name in {"diagnostics.surface-probe", "diagnostics.browse-hierarchy", "harness.assert-channels"}:
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
            steps.append({"verb": "device.probe", "args": {"probe": "PlayerUI-window-control-plane"}})
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
        elif name == "media.import-staged":
            pass
        elif name == "library.snapshot":
            steps.append({"verb": "device.snapshot", "args": {}})
        elif name == "format.apply":
            projection = str(arguments["projection"])
            arguments_out = {
                "projection": projection,
                "stereo": str(arguments["stereoLayout"]),
            }
            field_of_view = arguments.get("horizontalFieldOfViewDegrees")
            if field_of_view is not None:
                arguments_out["horizontalFieldOfViewDegrees"] = str(field_of_view)
            steps.append(
                {
                    "verb": "device.app-command",
                    "args": {"verb": "applyFormat", "arguments": arguments_out},
                }
            )
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
        elif name == "transition-trace.arm":
            arguments_out: dict[str, Any] = {}
            if arguments.get("fault") not in (None, "none"):
                arguments_out["fault"] = str(arguments["fault"])
            steps.append(
                {
                    "verb": "device.app-command",
                    "args": {"verb": "armTransitionTrace", "arguments": arguments_out},
                }
            )
        elif name == "transition-trace.fetch":
            steps.append(
                {
                    "verb": "device.app-command",
                    "args": {"verb": "fetchTransitionTraceSnapshot", "arguments": {}},
                }
            )
        elif name == "transition-trace.disarm":
            steps.append(
                {
                    "verb": "device.app-command",
                    "args": {"verb": "disarmTransitionTrace", "arguments": {}},
                }
            )
        elif name == RESET_PRODUCT_STATE:
            steps.append(
                {
                    "verb": "device.app-command",
                    "args": {
                        "verb": "resetState",
                        "arguments": {"libraryFolder": arguments.get("rootFolderName", "")},
                    },
                }
            )
        else:
            raise SystemExit(f"{name} is outside the direct vocabulary")
    if any(
        str((action.get("arguments") or {}).get("identifier", "")).startswith("FileBrowsing-")
        for action in payload.get("operations", [])
    ):
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


def imports_at_root(payload: dict[str, Any]) -> bool:
    for action in payload.get("operations", []):
        if str(action.get("operation", "")).endswith("media.open@2") is False:
            continue
        identifier = str(action.get("arguments", {}).get("identifier", ""))
        if identifier.startswith("FileBrowsing-grid-video-"):
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


def collect_fixture(identifier: str, fixtures: list[Path]) -> None:
    if "-grid-video-" not in identifier:
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
            if previous["verb"] == action["verb"] == "device.app-command":
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
            if previous["verb"] == "device.app-commands" and action["verb"] == "device.app-command":
                previous["args"]["calls"].append(
                    {
                        "verb": action["args"]["verb"],
                        "arguments": action["args"].get("arguments", {}),
                    }
                )
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
    actions = [{"verb": "device.session.ensure", "args": {"lane": "simulator"}}]
    actions.append({"verb": "app.relaunch", "args": {}})
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
        if imports_at_root(payload):
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
    operation_text = json.dumps(payload.get("operations") or [], ensure_ascii=False).lower()
    remote_operations = any(
        marker in operation_text
        for marker in ("webdav", "smb", "filebrowsing-grid-video-", "remote-faults")
    )
    source_labels = {
        str(label)
        for action in payload.get("operations", [])
        for label in ((action.get("arguments") or {}).get("labels") or [])
        if "webdav" in str(label).lower()
    }
    defaulted_source = remote_operations and not source_labels
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
        actions.insert(2, actions.pop())
        if defaulted_source:
            actions.insert(
                3,
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
    chunks = split_steps(simplified)
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
    for position, chunk in enumerate(chunks, start=1):
        part_steps = list(chunk)
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
                "requires": ["mac", "device", "daemon"],
                "isolation": "clean-library",
                "preconditions": preconditions,
                "actions": actions + part_steps,
                "teardown": teardown,
                "terminal": terminal_of(part_steps),
            }
        )
    return parts


MAX_PART_STEPS = 26
EVIDENCE_VERBS = ("device.probe", "device.snapshot", "device.capture-frames")


def split_steps(steps: list[dict[str, Any]]) -> list[list[dict[str, Any]]]:
    chunks: list[list[dict[str, Any]]] = []
    current: list[dict[str, Any]] = []
    for position, step in enumerate(steps):
        begins_case = step["verb"] == "app.relaunch" and position > 0
        if begins_case and current and len(current) + 4 > MAX_PART_STEPS:
            chunks.append(current)
            current = []
        current.append(step)
    if current:
        chunks.append(current)
    return chunks


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


def expressible(path: Path) -> bool:
    payload = scenario(path)
    if payload is None:
        return False
    return (
        bool(operation_names(payload))
        and not blocked(payload)
        and str(payload.get("id")) not in HAND_WRITTEN
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


def report_gaps() -> int:
    blocking: dict[str, list[str]] = {}
    for path in sorted(SCENARIOS.rglob("*.md")):
        payload = scenario(path)
        if payload is None:
            continue
        names = operation_names(payload)
        if not names:
            continue
        if blocked(payload):
            for name in set(blocked(payload)):
                blocking.setdefault(name, []).append(str(payload["id"]))
    for name in sorted(blocking, key=lambda item: -len(blocking[item])):
        reason = BLOCKERS.get(name, "no mapping yet")
        print(f"{len(blocking[name]):3d} scenario(s)  {name}: {reason}")
    return 0


def main(argv: list[str]) -> int:
    if "--gaps" in argv:
        return report_gaps()
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
    print(f"{written} scenario unit(s), {len(journeys)} journey feature(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
