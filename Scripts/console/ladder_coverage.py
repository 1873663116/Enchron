#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from collections import Counter
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENARIOS = REPOSITORY_ROOT / "Config/regression/catalog-root/journeys"

DIRECT = {
    "accessibility.activate": "device.command",
    "accessibility.inspect": "device.snapshot",
    "accessibility.type": "device.command",
    "app.relaunch": "app.relaunch",
    "diagnostics.browse-hierarchy": "device.probe",
    "diagnostics.playback-state": "device.probe",
    "diagnostics.surface-probe": "device.probe",
    "evidence.capture-frames": "device.capture-frames",
    "harness.assert-channels": "device.probe",
    "input.device-hub-pinch": "device.command",
    "library.snapshot": "device.snapshot",
    "media.open": "device.command",
    "navigation.select-tab": "device.command",
    "playback.await-window-state": "device.await",
    "playback.wait-position": "device.await",
}

APP_CHANNEL = {
    "evidence.capture-audio",
    "evidence.structural-test",
    "harness.reset-product-state",
    "input.device-hub-prepare",
    "issue.present",
    "playback.seek",
    "playback.select-subtitle",
    "presentation.enter-docked-default",
    "presentation.enter-panorama",
    "presentation.exit-spatial",
    "storage.clear",
    "transition-trace.arm",
    "transition-trace.disarm",
    "transition-trace.fetch",
}

HOST_SIDE = {"format.apply", "host.preflight", "media.import-staged"}


def operations(path: Path) -> list[str]:
    parts = path.read_text(encoding="utf-8").split("---")
    if len(parts) < 3:
        return []
    try:
        payload = json.loads(parts[1])
    except json.JSONDecodeError:
        return []
    found: list[str] = []
    for action in payload.get("operations", []):
        name = str(action.get("operation", ""))
        if ":" in name:
            name = name.split(":", 1)[1]
        found.append(name.split("@", 1)[0])
    return found


def main() -> int:
    counts: Counter[str] = Counter()
    reasons: Counter[str] = Counter()
    for path in sorted(SCENARIOS.rglob("*.md")):
        required = operations(path)
        if not required:
            continue
        direct_only = all(item in DIRECT for item in required)
        reachable = all(item in DIRECT or item in APP_CHANNEL for item in required)
        host = [item for item in required if item in HOST_SIDE]
        if direct_only:
            counts["直接动词"] += 1
        elif reachable and not host:
            counts["需应用通道"] += 1
        else:
            counts["需宿主侧动作"] += 1
            for item in host:
                reasons[item] += 1
    total = sum(counts.values())
    print(f"场景 {total}")
    for name in ("直接动词", "需应用通道", "需宿主侧动作"):
        print(f"  {name}: {counts[name]}")
    for item, count in reasons.most_common():
        print(f"  阻塞 {item}: {count}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
