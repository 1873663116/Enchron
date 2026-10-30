#!/usr/bin/env python3
from __future__ import annotations
import re
import sys
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
CHANNEL_PATH = REPOSITORY_ROOT / "Apps/Enchron/DebugSupport/TestCommandChannel.swift"
INVENTORY_PATH = REPOSITORY_ROOT / "Config/reachability_operation_inventory.json"
EXEMPT_VERBS = {
    "primaryTransport": (
        "Reports the action the current lifecycle's transport would take, and "
        "performs it when asked. A reading taken by hand while probing the "
        "end-of-playback affordance; no operation asserts against it."
    ),
    "setDeveloperMode": (
        "Flips the developer-mode setting so a person can reach the UI behind "
        "it by hand. Nothing automates an assertion against the setting, so no "
        "operation declares the verb."
    ),
    "audioSelfTest": (
        "Plays a tone through the session and reports the route, sample rate "
        "and output volume. A reading taken by hand while probing audio "
        "output; no operation asserts against it."
    ),
    "streamQuitApp": (
        "Quits an application on a reachable stream host and refreshes that "
        "host's reachability. Driven by hand when preparing a streaming "
        "probe; no operation asserts against it."
    ),
    "playbackProbe": (
        "Reports the current audio and subtitle track labels with the playback "
        "facts a probe reads by hand while checking disc track mapping; no "
        "operation asserts against it."
    ),
    "setStallLimit": (
        "Shortens the stall limit so a run can observe the stalled state and "
        "its recovery inside one experiment. A knob turned by hand while "
        "measuring; no operation asserts against it."
    ),
    "selectAudioTrack": (
        "Switches the playing audio track so a person can check a disc's track "
        "mapping by ear and by the probe journal; no operation asserts against "
        "it."
    ),
    "selectSubtitleTrack": (
        "Selects or clears the playing subtitle track so a person can check a "
        "disc's subtitle mapping by eye and by the probe journal; no operation "
        "asserts against it."
    ),
    "sceneSessions": (
        "Lists the app's live UIScene sessions with their activation and "
        "destruction state. A reading taken by hand while probing wearer-close "
        "and restored-scene behavior; no operation asserts against it."
    ),
    "addLibraryFile": (
        "Adds a file to the media library by absolute path so a person can "
        "play a sample the library does not hold yet; no operation asserts "
        "against it."
    ),
    "answerResumePrompt": (
        "Answers the resume prompt from the command channel so a person can "
        "continue an interrupted run without touching the screen; no "
        "operation asserts against it."
    ),
    "fileBrowserState": (
        "Reports the file browser's root, source and entry counts. A reading "
        "taken by hand while checking a source connection; no operation "
        "asserts against it."
    ),
    "libraryReferences": (
        "Lists the library's references with their locators. A reading taken "
        "by hand while checking which entries a run left behind; no operation "
        "asserts against it."
    ),
    "openSourceFile": (
        "Opens a file inside the connected source so a person can start "
        "playback of a chosen sample; no operation asserts against it."
    ),
    "pipelineStats": (
        "Reports the demux and delivery counters. A reading taken by hand "
        "while checking a pipeline by eye; no operation asserts against it."
    ),
    "playDiscTitle": (
        "Starts a disc title by playlist and title index so a person can check "
        "a disc's structure by hand; no operation asserts against it."
    ),
    "playLibraryTitle": (
        "Starts a library entry by reference so a person can check an imported "
        "file by hand; no operation asserts against it."
    ),
    "playServerItem": (
        "Starts a title held by the signed-in media server so a person can "
        "check remote playback by hand; no operation asserts against it."
    ),
    "probeCapacity": (
        "Measures the output route's capacity by hand while checking an audio "
        "path; no operation asserts against it."
    ),
    "probeLatency": (
        "Measures the output route's latency by hand while checking an audio "
        "path; no operation asserts against it."
    ),
    "probeSamples": (
        "Reports sample counts from the output route by hand while checking an "
        "audio path; no operation asserts against it."
    ),
    "resetFirstFrameProbe": (
        "Clears the first frame probe so a run can watch the next start from "
        "the beginning. A knob turned by hand while measuring; no operation "
        "asserts against it."
    ),
    "streamStats": (
        "Reports the stream server's counters. A reading taken by hand while "
        "checking a source connection; no operation asserts against it."
    ),
    "throttle": (
        "Shapes the stream server's throughput so a person can watch a "
        "buffering path by hand; no operation asserts against it."
    ),
}

def failures() -> list[str]:
    found: list[str] = []
    try:
        text = CHANNEL_PATH.read_text(encoding="utf-8")
    except OSError:
        return [f"{CHANNEL_PATH}: cannot read file"]
    verbs = sorted(set(re.findall(r'case\s+"([^"]+)"', text)))
    try:
        inventory_text = INVENTORY_PATH.read_text(encoding="utf-8") if INVENTORY_PATH.exists() else ""
    except OSError:
        inventory_text = ""
    scripts_text = ""
    for root in [REPOSITORY_ROOT / "Scripts", REPOSITORY_ROOT / "Regression/operations"]:
        if not root.exists():
            continue
        for path in root.rglob("*"):
            if not path.is_file():
                continue
            if path.suffix not in {".py", ".md", ".json", ".sh", ".zsh"}:
                continue
            try:
                scripts_text += path.read_text(encoding="utf-8", errors="ignore") + "\n"
            except OSError:
                continue
    combined = scripts_text + inventory_text
    for verb in verbs:
        if verb in EXEMPT_VERBS:
            continue
        if verb not in combined:
            found.append(f"{CHANNEL_PATH.relative_to(REPOSITORY_ROOT)}: orphan verb \"{verb}\" has no owner in Scripts/, Regression/operations or Config/reachability_operation_inventory.json")
    return sorted(found)

def main() -> int:
    found = failures()
    for line in found:
        print(line)
    if found:
        print(f"{len(found)} orphan verb violations")
        return 1
    print("no orphan verb violations")
    return 0

if __name__ == "__main__":
    sys.exit(main())
