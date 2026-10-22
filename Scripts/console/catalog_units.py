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

UNSUPPORTED = {"input.device-hub-pinch"}

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


def navigation(folder: str) -> list[dict[str, Any]]:
    return [
        {"verb": "device.app-command", "args": {"verb": "setViewMode", "arguments": {"mode": "grid"}}},
        {"verb": "device.command", "args": {"action": "tap", "identifier": "Navigation-Ornament-tab-files"}},
        {"verb": "device.command", "args": {"action": "tap", "identifier": f"MediaLibrary-grid-folder-{folder}"}},
    ]


def translate(payload: dict[str, Any], folder: str) -> tuple[list[dict[str, Any]], list[Path]]:
    steps: list[dict[str, Any]] = []
    fixtures: list[Path] = []
    rewound = False
    for action in payload["operations"]:
        name = str(action["operation"]).split(":")[1].split("@")[0]
        arguments = action.get("arguments", {})
        if name == "app.relaunch":
            steps.append({"verb": "app.relaunch", "args": {}})
            steps.extend(navigation(folder))
            rewound = True
        elif name == "navigation.select-tab":
            if not rewound or True:
                steps.append(
                    {
                        "verb": "device.command",
                        "args": {"action": "tap", "identifier": f"Navigation-Ornament-tab-{arguments['tab']}"},
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
        elif name == "library.snapshot":
            steps.append({"verb": "device.snapshot", "args": {}})
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
        "pace": "slow",
        "requires": ["mac", "device", "daemon"],
        "preconditions": [{"kind": "media-server", "provider": "emby"}],
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


def expressible(path: Path) -> bool:
    payload = scenario(path)
    if payload is None:
        return False
    names = operation_names(payload)
    return (
        bool(names)
        and all(name in DIRECT for name in names)
        and not any(name in UNSUPPORTED for name in names)
    )


def write_feature(journey: str, identifiers: list[str]) -> None:
    slugged = re.sub(r"[^a-z0-9]+", "-", journey.lower()).strip("-")
    target = REPOSITORY_ROOT / "Config/console/features" / f"journey-{slugged}.md"
    payload = {
        "schema": "enchron.console.feature",
        "schemaVersion": 1,
        "id": f"feature:journey.{slugged}",
        "title": journey.replace("-", " ").title(),
        "units": sorted(identifiers),
        "promises": [],
    }
    body = json.dumps(payload, indent=2, ensure_ascii=False)
    target.write_text(
        f"---\n{body}\n---\n\nEvery scenario of the {journey} journey that the direct vocabulary already carries.\n",
        encoding="utf-8",
    )


def main(argv: list[str]) -> int:
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
