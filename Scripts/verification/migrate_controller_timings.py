#!/usr/bin/env python3
from __future__ import annotations
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
LEGACY_PATH = REPOSITORY_ROOT / "Scripts/verification/controller_timings.json"
DEVICE_PATH = REPOSITORY_ROOT / "Scripts/verification/controller_timings.device.json"
SIMULATOR_PATH = REPOSITORY_ROOT / "Scripts/verification/controller_timings.simulator.json"
LIMIT = 40

def _load_legacy(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None

def _load_lane(path: Path):
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(data, dict) and isinstance(data.get("verbs"), dict):
            return data
        if isinstance(data, dict) and data:
            verbs = {}
            for key, value in data.items():
                if key in ("verbs", "updatedAt"):
                    continue
                if isinstance(value, dict) and "samples" in value:
                    verbs[key] = value
            if verbs:
                return {"verbs": verbs, "updatedAt": data.get("updatedAt", datetime.now(timezone.utc).isoformat(timespec="seconds"))}
        return {"verbs": {}, "updatedAt": datetime.now(timezone.utc).isoformat(timespec="seconds")}
    except Exception:
        return {"verbs": {}, "updatedAt": datetime.now(timezone.utc).isoformat(timespec="seconds")}

def _samples_from_entry(entry):
    samples = entry.get("samples") if isinstance(entry, dict) else None
    if not isinstance(samples, list):
        return []
    updated = entry.get("updatedAt") if isinstance(entry, dict) else None
    at = updated if isinstance(updated, str) and updated else datetime.now(timezone.utc).isoformat(timespec="seconds")
    converted = []
    for value in samples:
        if isinstance(value, dict) and "seconds" in value:
            seconds = value.get("seconds")
            censored = bool(value.get("censored", False))
            stamp = value.get("at") if isinstance(value.get("at"), str) else at
            try:
                seconds = float(seconds)
            except (TypeError, ValueError):
                continue
            converted.append({"seconds": round(float(seconds), 2), "censored": censored, "at": stamp})
        elif isinstance(value, (int, float)):
            converted.append({"seconds": round(float(value), 2), "censored": False, "at": at})
    return converted

def main() -> int:
    if not LEGACY_PATH.exists():
        return 0
    legacy = _load_legacy(LEGACY_PATH)
    if not isinstance(legacy, dict):
        try:
            LEGACY_PATH.unlink()
        except OSError:
            pass
        return 0
    device_data = _load_lane(DEVICE_PATH) if DEVICE_PATH.exists() else {"verbs": {}, "updatedAt": datetime.now(timezone.utc).isoformat(timespec="seconds")}
    simulator_data = _load_lane(SIMULATOR_PATH) if SIMULATOR_PATH.exists() else {"verbs": {}, "updatedAt": datetime.now(timezone.utc).isoformat(timespec="seconds")}
    if "verbs" in legacy and isinstance(legacy.get("verbs"), dict):
        legacy_verbs = legacy.get("verbs")
        is_prefixed = False
    else:
        legacy_verbs = legacy
        is_prefixed = True
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")
    for raw_key, entry in list(legacy_verbs.items()):
        if not isinstance(entry, dict):
            continue
        if raw_key in ("verbs", "updatedAt"):
            continue
        converted = _samples_from_entry(entry)
        if not converted:
            if isinstance(entry.get("samples"), list):
                converted = []
            else:
                continue
        if is_prefixed and isinstance(raw_key, str) and raw_key.startswith("simulator:"):
            verb = raw_key[len("simulator:"):]
            target = simulator_data
        elif is_prefixed and isinstance(raw_key, str):
            verb = raw_key
            target = device_data
        else:
            verb = raw_key
            target = device_data
            if isinstance(raw_key, str) and raw_key.startswith("simulator:"):
                verb = raw_key[len("simulator:"):]
                target = simulator_data
        verbs = target.get("verbs")
        if not isinstance(verbs, dict):
            verbs = {}
            target["verbs"] = verbs
        existing = verbs.get(verb, {})
        existing_samples = existing.get("samples") if isinstance(existing, dict) and isinstance(existing.get("samples"), list) else []
        normalized_existing = []
        for item in existing_samples:
            if isinstance(item, dict) and "seconds" in item:
                normalized_existing.append(item)
            elif isinstance(item, (int, float)):
                normalized_existing.append({"seconds": round(float(item), 2), "censored": False, "at": now})
        merged = normalized_existing + converted
        verbs[verb] = {"samples": merged[-LIMIT:]}
    for target_path, target_data in ((DEVICE_PATH, device_data), (SIMULATOR_PATH, simulator_data)):
        target_data["updatedAt"] = now
        try:
            tmp = target_path.with_name(target_path.name + ".tmp")
            tmp.write_text(json.dumps(target_data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
            tmp.replace(target_path)
        except Exception:
            return 1
    try:
        LEGACY_PATH.unlink()
    except Exception:
        return 1
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
