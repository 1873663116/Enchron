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
    "format.apply": "the custom angle route needs the menu picker",
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
    "format.apply",
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
            if labels:
                return str(labels[0])
            if arguments.get("identifier"):
                return str(arguments["identifier"])
    return None


def navigation(folder: str | None) -> list[dict[str, Any]]:
    steps: list[dict[str, Any]] = [
        {"verb": "device.home", "args": {}},
        {"verb": "device.app-command", "args": {"verb": "setViewMode", "arguments": {"mode": "grid"}}},
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
    for action in payload["operations"]:
        name = str(action["operation"]).split(":")[1].split("@")[0]
        arguments = action.get("arguments", {})
        if name == "app.relaunch":
            steps.append({"verb": "app.relaunch", "args": {}})
            steps.extend(navigation(folder))
            rewound = True
        elif name == "navigation.select-tab":
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
            found = fixture(identifier.split("MediaLibrary-grid-video-")[-1])
            if found is not None and found not in fixtures:
                fixtures.append(found)
            steps.append({"verb": "device.command", "args": {"action": "tap", "identifier": identifier}})
            landing = PRESENTATION.get(str(arguments.get("expectedLanding", "window")))
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
            steps.append(
                {
                    "verb": "device.await",
                    "args": {
                        "probe": "PlayerUI-window-control-plane",
                        "field": "mediaName",
                        "equals": identifier.split("MediaLibrary-grid-video-")[-1],
                        "timeoutMs": 15000,
                        "intervalMs": 300,
                    },
                }
            )
        elif name == "playback.await-window-state":
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
            labels = arguments.get("labels") or []
            if labels:
                label = str(labels[0])
                arguments_out: dict[str, Any] = {"action": "tap", "label": label}
                if "," in label:
                    arguments_out["labelPrefix"] = label.split(",")[0].strip()
                steps.append({"verb": "device.command", "args": arguments_out})
            else:
                steps.append(
                    {
                        "verb": "device.command",
                        "args": {"action": "tap", "identifier": arguments.get("identifier")},
                    }
                )
        elif name in {"accessibility.activate", "accessibility.type"}:
            args: dict[str, Any] = {"action": "tap", "identifier": arguments.get("identifier")}
            if name == "accessibility.type" and "text" in arguments:
                args["action"] = "typeText"
                args["text"] = arguments["text"]
            steps.append({"verb": "device.command", "args": args})
        elif name == "accessibility.inspect":
            steps.append({"verb": "device.probe", "args": {"probe": arguments.get("identifier")}})
        elif name in {"diagnostics.surface-probe", "diagnostics.browse-hierarchy", "harness.assert-channels"}:
            steps.append(
                {"verb": "device.probe", "args": {"probe": arguments.get("identifier", "PlayerUI-window-control-plane")}}
            )
        elif name in {"diagnostics.playback-state"}:
            steps.append({"verb": "device.probe", "args": {"probe": "PlayerUI-window-control-plane"}})
        elif name in {"host.preflight", "media.import-staged"}:
            pass
        elif name == "library.snapshot":
            steps.append({"verb": "device.snapshot", "args": {}})
        elif name == "format.apply":
            projection = str(arguments["projection"])
            projection_identifier = {
                "flat": "PlayerUI-VideoFormat-Projection-Flat",
                "equirectangular180": "PlayerUI-VideoFormat-Projection-180°",
                "equirectangular360": "PlayerUI-VideoFormat-Projection-360°",
            }[projection]
            stereo = {
                "mono": "Mono",
                "sideBySide": "Side-by-Side",
                "topBottom": "Top-Bottom",
            }[str(arguments["stereoLayout"])]
            steps.append(
                {
                    "verb": "device.app-command",
                    "args": {"verb": "toggleControls", "arguments": {"visible": "true"}},
                }
            )
            steps.append(
                {
                    "verb": "device.command",
                    "args": {"action": "tap", "identifier": "PlayerUI-TopAction-videoFormat"},
                }
            )
            steps.append(
                {
                    "verb": "device.command",
                    "args": {
                        "action": "tapSequence",
                        "identifiers": [
                            projection_identifier,
                            f"PlayerUI-VideoFormat-Stereo Layout-{stereo}",
                            "PlayerUI-VideoFormat-apply",
                        ],
                    },
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
    return steps, fixtures


def unit_for(path: Path) -> dict[str, Any]:
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
        actions.append(
            {"verb": "device.app-command", "args": {"verb": "deleteLibraryFolder", "arguments": {"name": folder}}}
        )
        actions.append(
            {
                "verb": "device.app-command",
                "args": {"verb": "importStagedFolder", "arguments": {"directory": folder, "entry": "root"}},
            }
        )
    actions.extend(steps)
    if fixtures:
        actions.append(
            {"verb": "device.app-command", "args": {"verb": "deleteLibraryFolder", "arguments": {"name": folder}}}
        )
    return {
        "schema": "enchron.console.unit",
        "schemaVersion": 1,
        "id": f"unit:catalog.{folder}@1",
        "layer": 3,
        "role": "verification",
        "pace": "slow" if identifier in verified_scenarios() else "catalog",
        "requires": ["mac", "device", "daemon"],
        "preconditions": [{"kind": "media-server", "provider": "emby"}]
        + ([{"kind": "media-progress"}] if identifier in PROGRESS_SCENARIOS else []),
        "actions": actions,
        "terminal": terminal_of(steps),
    }


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
        elif name == "format.apply" and str(arguments.get("projection")) == "customAngle":
            found.append("format.apply")
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
    existing_units: list[str] = []
    if target.exists():
        head = target.read_text(encoding="utf-8").split("---")[1]
        try:
            existing_units = [str(unit) for unit in json.loads(head).get("units", [])]
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
        body = json.dumps(unit_for(path), indent=2, ensure_ascii=False)
        title = str(payload.get("title", folder))
        target.write_text(
            f"---\n{body}\n---\n\n{title}\n\nGenerated from `{path.relative_to(REPOSITORY_ROOT)}`.\n",
            encoding="utf-8",
        )
        journeys.setdefault(str(payload.get("journey", folder)), []).append(
            f"unit:catalog.{folder}@1"
        )
        written += 1
    if "--check" not in argv:
        for journey, identifiers in journeys.items():
            write_feature(journey, identifiers)
    print(f"{written} scenario unit(s), {len(journeys)} journey feature(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
