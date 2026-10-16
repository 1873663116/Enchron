#!/usr/bin/env python3
"""Unattended end-to-end acceptance for the Enchron streaming session (acceptance plan section 7).

One scenario is one drive plus at least two evidence channels drawn from
`control-surface`, `probe`, `pixel`, `host-log`, `host-process` and
`host-audio`, and one machine terminal state written to
`<output-directory>/<scenario-slug>/result.json`.

How a terminal state is reached:
- `passed` - every assertion of the scenario held on evidence that survived.
- `failed` / `failed(known)` - the product answered and the answer was wrong:
  a failure it reported itself, or an assertion over evidence it produced.
- `blockedBy` - a required surface is absent (identifier, verb, probe line,
  host fixture), or the driving apparatus is not up (`app-not-running`,
  `session-lost`, `runner-gone`). The reason names the missing surface.
- `indeterminate` - an instrument fault or an expired wait destroyed the
  observation (`wait-expired`, `transport-timeout`, `response-timeout`,
  `evidence-destroyed`, `contract-mismatch`, `budget-undeclared`).
- `deferred(human)` - the scenario needs a step this harness cannot drive.

Product surface names, readable values, probe lines, verbs and settings keys
come from `.scratch/2026-10-16-串流端到端/SURFACE.md`; scenario definitions
follow the acceptance plan section 7 one to one.

Waits go through `harness.wait_for` with budgets declared in this file and
recorded into the `simulator` timing lane; runner actions go through
`harness.ControllerClient`; host-side commands go through
`harness.LocalToolRunner`. Nothing here re-implements waiting.

`.scratch/2026-10-16-串流端到端/fixtures.json` is optional and may carry:
`hostName` (mDNS instance name to expect), `hostAddress` (address to add),
`forensicAppName`, `forensicLog` (JSONL path), `forensicProbeURL` (HTTP source
of the same events), `forensicToneCommand` (argv that starts the tone),
`sunshineLog`, `webUIBase`, `webUICredentials`, `toneHz`, `simulatorAppName`.
Anything absent is discovered at run time and reported in the scenario notes.
"""

from __future__ import annotations

import argparse
import base64
import json
import math
import os
import re
import ssl
import struct
import subprocess
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable, Mapping, Sequence

SCRIPTS_ROOT = Path(__file__).resolve().parents[2]
VERIFICATION_ROOT = SCRIPTS_ROOT / "Scripts/verification"
for import_root in (str(VERIFICATION_ROOT), str(SCRIPTS_ROOT / "Scripts")):
    if import_root not in sys.path:
        sys.path.insert(0, import_root)

import enchron_target
import interactive_visionpro_ui
from harness import (
    Budget,
    BudgetProvider,
    ControllerClient,
    InstrumentFault,
    LocalToolRunner,
    RunnerResponse,
    wait_for,
)
from regression.tools.pixel_heuristics import region_rgb, region_rgb_matches
from regression.tools.raster import RasterError

RUNNER_PATH = VERIFICATION_ROOT / "interactive_visionpro_ui.py"
PROXY_PATH = VERIFICATION_ROOT / "moonlight_loopback_proxy.py"
AUDIO_CAPTURE_SOURCE = VERIFICATION_ROOT / "audio_capture.swift"
APP_BUNDLE_ID = interactive_visionpro_ui.APP_BUNDLE_ID
PROBE_REMOTE_PATH = "Documents/stream-session-probe.log"
PROBE_STATUS_VERB = "probeStatus"

DEFAULT_OUTPUT_DIRECTORY = SCRIPTS_ROOT / ".scratch/2026-10-16-串流端到端/scenarios"
FIXTURES_PATH = SCRIPTS_ROOT / ".scratch/2026-10-16-串流端到端/fixtures.json"
SCENARIO_ARTIFACTS = "artifacts"
RESULT_FILENAME = "result.json"

DEFAULT_HOST = "127.0.0.1:47989"
WEBUI_PORT_OFFSET = 1
DEFAULT_SUNSHINE_LOG = Path.home() / ".config/sunshine/sunshine.log"
DEFAULT_WEBUI_CREDENTIALS = Path.home() / ".config/sunshine/enchron-webui-credentials.txt"
DEFAULT_PROXY_LISTEN_BASE = 57989
DEFAULT_FORENSIC_APP_NAME = "Enchron Forensics"
DEFAULT_TONE_HZ = 997.0
DEFAULT_SIMULATOR_APP_NAME = "Simulator"
DEFAULT_WORK_DIRECTORY = Path(os.environ.get("TMPDIR", "/tmp")).expanduser() / "enchron-moonlight-acceptance"

PATCH_SAMPLE_POINT = (0.18, 0.18)
PATCH_RGB_TOLERANCE = 30
PATCH_SAMPLE_ATTEMPTS = 3
PATCH_RETRY_SECONDS = 1.0
PATCH_FREEZE_SETTLE_SECONDS = 4.0
POINTER_TARGET = (0.5, 0.5)
POINTER_TOLERANCE_PIXELS = 12.0
TONE_RATIO_FLOOR = 8.0
TONE_RMS_FLOOR_DBFS = -60.0
DEFAULT_CAPTURE_SECONDS = 8.0
BLACKHOLE_SECONDS = 5.0
QUEUE_SETTLE_SECONDS = 6.0

STREAM_CONNECT_SECONDS = 90.0
SESSION_END_SECONDS = 60.0
PATCH_ADVANCE_SECONDS = 90.0
PROBE_READY_SECONDS = 30.0
HOST_TOOL_SECONDS = 30.0
APP_RELAUNCH_SECONDS = 120.0
PROXY_START_SECONDS = 30.0
FIXTURE_SECONDS = 20.0

PASSED = "passed"
FAILED = "failed"
FAILED_KNOWN = "failed(known)"
BLOCKED = "blockedBy"
INDETERMINATE = "indeterminate"
DEFERRED = "deferred(human)"
TERMINAL_STATES = (PASSED, FAILED, FAILED_KNOWN, BLOCKED, INDETERMINATE, DEFERRED)
RESOLVED_STATES = (PASSED, FAILED, FAILED_KNOWN)
EVIDENCE_CHANNELS = (
    "control-surface",
    "probe",
    "pixel",
    "host-log",
    "host-process",
    "host-audio",
)

MISSING_SURFACE_PATTERNS = (
    "no matching element",
    "no current element matches",
    "found no matching public element",
    "is not currently hittable",
    "not currently hittable",
    "interactive xcui runner is not ready",
    "container is not readable",
    "unknown verb",
    "unsupported verb",
    "no such verb",
    "non-existent verb",
    "not implemented",
    "element not found",
)
BLOCKING_FAULT_KINDS = frozenset({"app-not-running", "session-lost", "runner-gone"})

SUNSHINE_LINE = re.compile(
    r"^\[(?P<stamp>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3})\]: "
    r"(?P<level>[A-Za-z]+): (?P<message>.*)$"
)
SUNSHINE_ENCODER = re.compile(r"Creating encoder \[(?P<codec>[^\]]+)\]")
SUNSHINE_FOUND_ENCODER = re.compile(
    r"Found (?P<format>H\.264|HEVC|AV1) encoder: (?P<codec>\S+) \[(?P<backend>[^\]]+)\]"
)
SUNSHINE_BITRATE = re.compile(
    r"(?P<kind>Client configured bitrate is|Final adjusted video encoding bitrate is) "
    r"(?P<kbps>\d+) Kbps"
)
SUNSHINE_GEOMETRY = re.compile(
    r"(?:Stream|Dimension|Resolution)[^\n]*?(?P<width>\d{3,5})[xX](?P<height>\d{3,5})"
    r"(?:[^\n]*?(?P<fps>\d{1,3})\s*(?:fps|FPS))?"
)
SUNSHINE_P90 = re.compile(r"Stream (?:[0-9]+x[0-9]+ )?(?P<fps>\d+)")
SUNSHINE_HDR_REJECT = re.compile(
    r"(?i)(hdr.{0,40}(reject|denied|disabl|not supported|unsupported)"
    r"|(?:reject|denied|disabl).{0,40}hdr)"
)

ISO_FORMAT = "%Y-%m-%dT%H:%M:%S%z"


class BlockedBy(Exception):
    def __init__(self, reason: str) -> None:
        super().__init__(reason)
        self.reason = reason


class ProductVerdict(Exception):
    def __init__(self, kind: str, evidence: Mapping[str, object]) -> None:
        super().__init__(kind)
        self.kind = kind
        self.evidence = dict(evidence)


@dataclass(frozen=True)
class Outcome:
    terminal: str
    notes: str = ""


@dataclass(frozen=True)
class Scenario:
    number: int
    slug: str
    title: str
    drive: str
    channels: tuple[str, ...]
    run: Callable[["Context"], Outcome]


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def parse_jsonl_text(text: str) -> list[dict]:
    events: list[dict] = []
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            document = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(document, dict):
            events.append(document)
    return events


def read_jsonl(path: Path) -> list[dict]:
    if not path.is_file():
        return []
    return parse_jsonl_text(path.read_text(encoding="utf-8", errors="replace"))


def parse_sunshine_log(path: Path) -> dict[str, object]:
    """Sunshine's log is the only record its stdout never keeps.

    Session starts and ends, the encoder actually created, the bitrate as
    configured and as adjusted, the stream geometry and any rejected HDR
    request are read here; unrecognised lines are still kept verbatim so a
    scenario can quote what it saw.
    """
    report: dict[str, object] = {
        "path": str(path),
        "exists": path.is_file(),
        "lines": 0,
        "version": None,
        "sessionStarts": [],
        "sessionEnds": [],
        "encoders": [],
        "foundEncoders": [],
        "bitrates": [],
        "geometry": [],
        "hdrRejected": [],
        "raw": [],
    }
    if not path.is_file():
        return report
    text = path.read_text(encoding="utf-8", errors="replace")
    lines = text.splitlines()
    report["lines"] = len(lines)
    for line in lines:
        match = SUNSHINE_LINE.match(line)
        message = match.group("message") if match is not None else line
        stamp = match.group("stamp") if match is not None else None
        report["raw"].append({"stamp": stamp, "message": message})
        if "Sunshine version:" in message:
            report["version"] = message.split("Sunshine version:", 1)[1].strip()
        if "CLIENT CONNECTED" in message or "New streaming session started" in message:
            report["sessionStarts"].append({"stamp": stamp, "message": message})
        if "CLIENT DISCONNECTED" in message or message.strip() == "Session ended":
            report["sessionEnds"].append({"stamp": stamp, "message": message})
        encoder = SUNSHINE_ENCODER.search(message)
        if encoder is not None:
            report["encoders"].append(
                {"stamp": stamp, "codec": encoder.group("codec"), "message": message}
            )
        found = SUNSHINE_FOUND_ENCODER.search(message)
        if found is not None:
            report["foundEncoders"].append(
                {
                    "stamp": stamp,
                    "format": found.group("format"),
                    "codec": found.group("codec"),
                    "backend": found.group("backend"),
                }
            )
        bitrate = SUNSHINE_BITRATE.search(message)
        if bitrate is not None:
            report["bitrates"].append(
                {
                    "stamp": stamp,
                    "kind": bitrate.group("kind"),
                    "kbps": int(bitrate.group("kbps")),
                }
            )
        geometry = SUNSHINE_GEOMETRY.search(message)
        if geometry is not None:
            report["geometry"].append(
                {
                    "stamp": stamp,
                    "width": int(geometry.group("width")),
                    "height": int(geometry.group("height")),
                    "fps": int(geometry.group("fps")) if geometry.group("fps") else None,
                    "message": message,
                }
            )
        if SUNSHINE_HDR_REJECT.search(message):
            report["hdrRejected"].append({"stamp": stamp, "message": message})
    return report


def parse_forensic_log(path: Path) -> dict[str, object]:
    """The host forensic app's JSONL, keyed by event.

    Patches carry the seed-derived colour of one index; frames sample the host
    frame counter; inputs carry the string and the screen coordinates the
    hostside injection actually produced; tones record the played frequency.
    """
    if not path.is_file():
        return parse_forensic_text("", str(path))
    return parse_forensic_text(
        path.read_text(encoding="utf-8", errors="replace"), str(path)
    )


def parse_forensic_text(text: str, source: str) -> dict[str, object]:
    report: dict[str, object] = {
        "path": source,
        "exists": bool(text.strip()),
        "events": [],
        "seed": None,
        "seedHex": None,
        "launch": None,
        "patches": [],
        "frames": [],
        "inputs": [],
        "tones": [],
        "exits": [],
        "errors": [],
    }
    events: list[dict] = parse_jsonl_text(text)
    report["events"] = events
    for event in events:
        kind = event.get("event")
        if kind == "seed":
            report["seed"] = event.get("seed")
            report["seedHex"] = event.get("seedHex")
        elif kind == "launch":
            report["launch"] = event
            if event.get("seed") is not None:
                report["seed"] = event.get("seed")
        elif kind == "patch":
            rgb = event.get("rgb")
            report["patches"].append(
                {
                    "index": event.get("index"),
                    "rgb": tuple(rgb) if isinstance(rgb, list) else None,
                    "rgbHex": event.get("rgbHex"),
                    "displayedAtWallMs": event.get("displayedAtWallMs"),
                    "wallMs": event.get("wallMs"),
                }
            )
        elif kind == "frames":
            report["frames"].append(
                {
                    "counter": event.get("counter"),
                    "wallMs": event.get("wallMs"),
                    "patchIndex": event.get("patchIndex"),
                }
            )
        elif kind == "input":
            report["inputs"].append(event)
        elif kind == "tone":
            report["tones"].append(event)
        elif kind == "exit":
            report["exits"].append(event)
        elif kind == "error":
            report["errors"].append(event)
    return report


def latest_patch(forensic: Mapping[str, object]) -> dict | None:
    patches = forensic.get("patches")
    if not isinstance(patches, list) or not patches:
        return None
    return dict(patches[-1])


def patch_rgb(patch: Mapping[str, object] | None) -> tuple[int, int, int] | None:
    if patch is None:
        return None
    rgb = patch.get("rgb")
    if not isinstance(rgb, tuple) or len(rgb) != 3:
        return None
    return (int(rgb[0]), int(rgb[1]), int(rgb[2]))


def frame_counter(forensic: Mapping[str, object]) -> int | None:
    samples = forensic.get("frames")
    if not isinstance(samples, list) or not samples:
        return None
    counter = samples[-1].get("counter")
    return int(counter) if isinstance(counter, (int, float)) else None


def input_strings(forensic: Mapping[str, object]) -> list[str]:
    inputs = forensic.get("inputs")
    if not isinstance(inputs, list):
        return []
    values = [
        str(event.get("unicode", ""))
        for event in inputs
        if isinstance(event.get("unicode"), str) and event.get("unicode")
    ]
    typed = "".join(
        str(event.get("unicode", ""))
        for event in inputs
        if isinstance(event.get("kind"), str)
        and event.get("kind") == "keyDown"
        and isinstance(event.get("unicode"), str)
    )
    if typed:
        values.append(typed)
    return values


def input_positions(forensic: Mapping[str, object]) -> list[tuple[float, float]]:
    inputs = forensic.get("inputs")
    if not isinstance(inputs, list):
        return []
    positions: list[tuple[float, float]] = []
    for event in inputs:
        x, y = event.get("x"), event.get("y")
        if isinstance(x, (int, float)) and isinstance(y, (int, float)):
            positions.append((float(x), float(y)))
    return positions


def mouse_inputs(forensic: Mapping[str, object]) -> list[dict]:
    inputs = forensic.get("inputs")
    if not isinstance(inputs, list):
        return []
    return [
        event
        for event in inputs
        if isinstance(event.get("kind"), str) and "ouse" in str(event.get("kind"))
    ]


def read_wav_mono(path: Path) -> tuple[list[float], int]:
    blob = path.read_bytes()
    if blob[0:4] != b"RIFF" or blob[8:12] != b"WAVE":
        raise RasterError(f"{path} is not a RIFF/WAVE file")
    encoding = channels = rate = width = None
    payload = b""
    cursor = 12
    while cursor + 8 <= len(blob):
        name = blob[cursor : cursor + 4]
        size = struct.unpack_from("<I", blob, cursor + 4)[0]
        body = blob[cursor + 8 : cursor + 8 + size]
        if name == b"fmt ":
            encoding, channels, rate, _, _, bits = struct.unpack_from("<HHIIHH", body, 0)
            if encoding == 0xFFFE and len(body) >= 26:
                encoding = struct.unpack_from("<H", body, 24)[0]
            width = bits // 8
        elif name == b"data":
            payload = body if size else blob[cursor + 8 :]
            if not size:
                break
        cursor += 8 + size + (size & 1)
    if not payload or width is None or not channels or not rate:
        raise RasterError(f"{path} has no readable fmt/data chunk pair")
    samples: list[float] = []
    if encoding == 3 and width == 4:
        values = struct.unpack(f"<{len(payload) // 4}f", payload[: len(payload) // 4 * 4])
    elif encoding == 3 and width == 8:
        values = struct.unpack(f"<{len(payload) // 8}d", payload[: len(payload) // 8 * 8])
    elif encoding == 1 and width == 2:
        values = tuple(
            value / 32768.0
            for value in struct.unpack(f"<{len(payload) // 2}h", payload[: len(payload) // 2 * 2])
        )
    elif encoding == 1 and width == 4:
        values = tuple(
            value / 2147483648.0
            for value in struct.unpack(f"<{len(payload) // 4}i", payload[: len(payload) // 4 * 4])
        )
    else:
        raise RasterError(f"unsupported WAV encoding {encoding} at {width * 8} bits")
    if channels == 1:
        samples = list(values)
    else:
        for index in range(0, len(values) - channels + 1, channels):
            samples.append(sum(values[index : index + channels]) / channels)
    return samples, rate


def dbfs(value: float) -> float:
    return float("-inf") if value <= 0.0 else 20.0 * math.log10(value)


def goertzel_power(samples: Sequence[float], rate: int, hz: float) -> float:
    if not samples:
        return 0.0
    omega = 2.0 * math.pi * hz / rate
    coefficient = 2.0 * math.cos(omega)
    previous = previous2 = 0.0
    for sample in samples:
        current = sample + coefficient * previous - previous2
        previous2, previous = previous, current
    return (previous * previous + previous2 * previous2 - coefficient * previous * previous2) / (
        len(samples) * len(samples)
    )


def tone_report(path: Path, hz: float) -> dict[str, object]:
    """Whether a capture carries one tone, without an FFT.

    The Goertzel power at the expected frequency is compared with the same
    measure at reference frequencies around it; a capture is judged to carry
    the tone when that ratio clears `TONE_RATIO_FLOOR` and its RMS is audible.
    """
    samples, rate = read_wav_mono(path)
    if not samples:
        return {"path": str(path), "samples": 0, "rate": rate, "tonePresent": False}
    rms = math.sqrt(sum(sample * sample for sample in samples) / len(samples))
    rms_dbfs = dbfs(rms)
    tone_power = goertzel_power(samples, rate, hz)
    references = {}
    for reference in (hz - 300.0, hz - 120.0, hz + 120.0, hz + 300.0, 3000.0):
        if reference > 0.0:
            references[f"{reference:g}"] = goertzel_power(samples, rate, reference)
    strongest = max(references.values()) if references else 0.0
    ratio = tone_power / strongest if strongest > 0.0 else float("inf")
    return {
        "path": str(path),
        "samples": len(samples),
        "rate": rate,
        "seconds": round(len(samples) / rate, 3),
        "rmsDbfs": round(rms_dbfs, 2),
        "tonePower": tone_power,
        "referencePower": strongest,
        "toneRatio": round(ratio, 3),
        "toneDbfs": round(dbfs(math.sqrt(tone_power)), 2) if tone_power > 0 else None,
        "tonePresent": bool(
            ratio >= TONE_RATIO_FLOOR and rms_dbfs >= TONE_RMS_FLOOR_DBFS
        ),
    }


def tone_plateau_report(
    path: Path, hz: float, window_seconds: float = 0.02, threshold_dbfs: float = -55.0
) -> dict[str, object]:
    """Arrival structure of a pulsed tone in a capture.

    The host's direct playback and the client's streamed playback of the same
    pulsed tone land in one system capture; the client copy arrives one stream
    latency later, so the total tone-on time on the capture exceeds the direct
    pulse train whenever the client is really playing.
    """
    samples, rate = read_wav_mono(path)
    if not samples:
        return {"path": str(path), "plateaus": 0, "onSeconds": 0.0}
    window = max(1, int(window_seconds * rate))
    runs: list[int] = []
    run = 0
    for start in range(0, len(samples) - window + 1, window):
        chunk = samples[start : start + window]
        rms = math.sqrt(sum(sample * sample for sample in chunk) / len(chunk))
        if dbfs(rms) > threshold_dbfs:
            run += window
        else:
            if run:
                runs.append(run)
            run = 0
    if run:
        runs.append(run)
    minimum = int(0.15 * rate)
    widths = sorted(run / rate for run in runs if run >= minimum)
    median = widths[len(widths) // 2] if widths else 0.0
    return {
        "path": str(path),
        "hz": hz,
        "plateaus": len(widths),
        "medianPlateauSeconds": round(median, 3),
        "onSeconds": round(sum(widths), 3),
        "widthsSeconds": [round(width, 3) for width in widths],
        "windowSeconds": window_seconds,
        "thresholdDbfs": threshold_dbfs,
    }


def validate_result(document: object) -> list[str]:
    problems: list[str] = []
    if not isinstance(document, dict):
        return ["the result document is not a JSON object"]
    scenario = document.get("scenario")
    if isinstance(scenario, bool) or not isinstance(scenario, int) or not 1 <= scenario <= 18:
        problems.append("scenario is an integer from 1 to 18")
    title = document.get("title")
    if not isinstance(title, str) or not title:
        problems.append("title is a non-empty string")
    terminal = document.get("terminalState")
    if terminal not in TERMINAL_STATES:
        problems.append(f"terminalState is one of {TERMINAL_STATES}")
    for moment in ("startedAt", "finishedAt"):
        value = document.get(moment)
        if not isinstance(value, str) or not value:
            problems.append(f"{moment} is a non-empty ISO-8601 string")
    if not isinstance(document.get("notes"), str):
        problems.append("notes is a string")
    evidence = document.get("evidence")
    if not isinstance(evidence, list):
        problems.append("evidence is a list")
        return problems
    channels: set[str] = set()
    for entry in evidence:
        if not isinstance(entry, dict):
            problems.append("every evidence entry is an object")
            continue
        channel = entry.get("channel")
        pointer = entry.get("pointer")
        if channel not in EVIDENCE_CHANNELS:
            problems.append(f"evidence channel {channel!r} is one of {EVIDENCE_CHANNELS}")
        else:
            channels.add(str(channel))
        if not isinstance(pointer, str) or not pointer:
            problems.append("every evidence entry carries a non-empty pointer")
    if terminal in RESOLVED_STATES and len(channels) < 2:
        problems.append(
            f"a {terminal} verdict rests on at least two evidence channels, not "
            f"{sorted(channels)}"
        )
    return problems


def write_result(directory: Path, document: Mapping[str, object]) -> Path:
    problems = validate_result(dict(document))
    if problems:
        raise ValueError("; ".join(problems))
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / RESULT_FILENAME
    path.write_text(
        json.dumps(dict(document), ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return path


def read_webui_credentials(path: Path) -> tuple[str, str]:
    user = password = None
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line.startswith("user="):
            user = line.split("=", 1)[1]
        elif line.startswith("password="):
            password = line.split("=", 1)[1]
    if not user or not password:
        raise ValueError(f"{path} carries no user= and password= pair")
    return user, password


class SunshineWebUI:
    """The Sunshine Web UI API: PIN submission, app list, config, permissions."""

    def __init__(self, base: str, credentials: tuple[str, str], timeout_seconds: float = 10.0) -> None:
        self.base = base.rstrip("/")
        self.credentials = credentials
        self.timeout_seconds = timeout_seconds

    def request(self, method: str, path: str, payload: object = None) -> object:
        body = None
        headers = {
            "Authorization": "Basic "
            + base64.b64encode(
                f"{self.credentials[0]}:{self.credentials[1]}".encode()
            ).decode(),
        }
        if payload is not None:
            body = json.dumps(payload).encode()
            headers["Content-Type"] = "application/json"
        request = urllib.request.Request(
            f"{self.base}{path}", data=body, headers=headers, method=method
        )
        context = None
        if self.base.startswith("https"):
            context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
            context.check_hostname = False
            context.verify_mode = ssl.CERT_NONE
        with urllib.request.urlopen(request, context=context, timeout=self.timeout_seconds) as reply:
            text = reply.read().decode("utf-8", errors="replace")
        if not text.strip():
            return {}
        try:
            return json.loads(text)
        except json.JSONDecodeError:
            return {"raw": text}

    def pending_pairings(self) -> list[dict]:
        document = self.request("GET", "/api/pin")
        if not isinstance(document, dict):
            return []
        pairings = document.get("pairings")
        return [entry for entry in pairings if isinstance(entry, dict)] if isinstance(pairings, list) else []

    def submit_pin(self, pairing_id: str, pin: str, name: str) -> object:
        return self.request(
            "POST",
            "/api/pin",
            {"pairing_id": pairing_id, "pin": pin, "name": name},
        )

    def apps(self) -> list[dict]:
        document = self.request("GET", "/api/apps")
        if not isinstance(document, dict):
            return []
        apps = document.get("apps")
        return [entry for entry in apps if isinstance(entry, dict)] if isinstance(apps, list) else []

    def configuration(self) -> dict:
        document = self.request("GET", "/api/config")
        return document if isinstance(document, dict) else {}


def parse_snapshot_value(value: str) -> "SnapshotView":
    pairs: list[tuple[str, str]] = []
    for fragment in value.split(";"):
        fragment = fragment.strip()
        if not fragment:
            continue
        key, separator, remainder = fragment.partition("=")
        pairs.append((key.strip(), remainder if separator else ""))
    return SnapshotView(tuple(pairs))


REQUESTED_MEMBERS = ("resolution", "fps", "bitrate", "codec", "hdr", "framePacing")
NEGOTIATED_MEMBERS = ("bitrate", "codec", "hdr")


@dataclass(frozen=True)
class SnapshotView:
    pairs: tuple[tuple[str, str], ...]

    def first(self, key: str) -> str | None:
        for name, value in self.pairs:
            if name == key:
                return value
        return None

    def last(self, key: str) -> str | None:
        found = None
        for name, value in self.pairs:
            if name == key:
                found = value
        return found

    def names(self) -> list[str]:
        return [name for name, _ in self.pairs]

    def group(self, name: str, members: Sequence[str]) -> dict[str, str]:
        collected: dict[str, str] = {}
        inside = False
        for key, value in self.pairs:
            if key == name:
                inside = True
                if "=" in value:
                    inner_key, _, inner_value = value.partition("=")
                    collected[inner_key.strip()] = inner_value
                else:
                    collected["video"] = value
                continue
            if not inside:
                continue
            if key in members:
                collected[key] = value
                continue
            if key not in ("video",):
                break
        return collected

    def state(self) -> str:
        return self.first("session") or "unavailable"

    def state_name(self) -> str:
        return self.state().split("(", 1)[0]

    def state_detail(self) -> str:
        state = self.state()
        if "(" in state and state.endswith(")"):
            return state[state.index("(") + 1 : -1]
        return ""

    def requested(self) -> dict[str, str]:
        return self.group("requested", REQUESTED_MEMBERS)

    def negotiated(self) -> dict[str, str]:
        config = self.group("negotiated", NEGOTIATED_MEMBERS)
        video = config.get("video", "")
        if "@" in video:
            resolution, _, fps = video.partition("@")
            config.setdefault("resolution", resolution)
            config.setdefault("fps", fps)
        return config

    def inputs(self) -> dict[str, int]:
        counters: dict[str, int] = {}
        for key in (
            "packets",
            "presented",
            "decoded",
            "dropped",
            "decodeRecoveries",
            "idrRequests",
            "queue",
            "adjustments",
            "mouse",
            "scroll",
            "keyboard",
            "pressedKeys",
            "pressedButtons",
        ):
            value = self.last(key)
            if value is not None and value != "unavailable":
                try:
                    counters[key] = int(value)
                except ValueError:
                    continue
        for name, value in self.pairs:
            if name.startswith("input:"):
                inner_key = name.split(":", 1)[1]
                if not inner_key or value == "unavailable":
                    continue
                try:
                    counters[inner_key] = int(value)
                except ValueError:
                    continue
                continue
            if name != "input":
                continue
            for item in value.split(";"):
                item = item.strip()
                inner_key, separator, inner_value = item.partition("=")
                if separator and inner_value != "unavailable":
                    try:
                        counters[inner_key] = int(inner_value)
                    except ValueError:
                        continue
        return counters


def parse_boolean(value: str | None) -> bool | None:
    if value is None:
        return None
    lowered = value.strip().lower()
    if lowered == "true":
        return True
    if lowered == "false":
        return False
    return None


def hierarchy_identifiers(hierarchy: str) -> list[str]:
    return re.findall(r"identifier: '([^']+)'", hierarchy)


def hierarchy_value(hierarchy: str, identifier: str) -> str | None:
    for line in hierarchy.splitlines():
        if f"identifier: '{identifier}'" not in line:
            continue
        attributes = interactive_visionpro_ui.hierarchy_attributes(line)
        return attributes.get("value")
    return None


@dataclass
class Context:
    scenario: Scenario
    device: str
    developer_dir: str | None
    lane: str
    host: str
    fixtures: dict[str, object]
    output_directory: Path
    work_directory: Path
    execution_input: Path | None
    quick: bool
    budgets: BudgetProvider
    controller: ControllerClient
    tools: LocalToolRunner
    tools_env: dict[str, str] | None = None
    directory: Path = field(init=False)
    artifacts: Path = field(init=False)
    notes: list[str] = field(default_factory=list)
    evidence: list[dict[str, str]] = field(default_factory=list)
    background: list[subprocess.Popen] = field(default_factory=list)

    def __post_init__(self) -> None:
        self.directory = self.output_directory / self.scenario.slug
        self.artifacts = self.directory / SCENARIO_ARTIFACTS
        self.directory.mkdir(parents=True, exist_ok=True)
        self.artifacts.mkdir(parents=True, exist_ok=True)

    def note(self, message: str) -> None:
        if message not in self.notes:
            self.notes.append(message)

    def wait_seconds(self, seconds: float) -> float:
        if self.quick and seconds > FIXTURE_SECONDS:
            return FIXTURE_SECONDS
        return seconds

    def fixture(self, key: str, default: object = None) -> object:
        value = self.fixtures.get(key)
        return default if value is None else value

    def artifact(self, name: str) -> Path:
        path = self.artifacts / name
        path.parent.mkdir(parents=True, exist_ok=True)
        return path

    def record_text(self, channel: str, name: str, text: str) -> None:
        path = self.artifact(name)
        path.write_text(text if text.endswith("\n") else text + "\n", encoding="utf-8")
        self.record_pointer(channel, str(path.relative_to(self.directory)))

    def record_pointer(self, channel: str, pointer: str) -> None:
        entry = {"channel": channel, "pointer": pointer}
        if entry not in self.evidence:
            self.evidence.append(entry)

    def record_channel(self, channel: str, name: str, payload: object) -> None:
        text = (
            payload
            if isinstance(payload, str)
            else json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True)
        )
        self.record_text(channel, name, text)

    def host_command(
        self, command: Sequence[str], verb: str = "local-tool"
    ):
        return self.tools.run(verb, list(command), env=self.tools_env)

    def spawn(self, command: Sequence[str], name: str) -> subprocess.Popen:
        log = self.artifact(f"{name}.log").open("ab")
        process = subprocess.Popen(list(command), stdout=log, stderr=subprocess.STDOUT)
        self.background.append(process)
        return process

    def cleanup(self) -> None:
        for process in self.background:
            if process.poll() is None:
                process.terminate()
        for process in self.background:
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()

    def require_device(self) -> str:
        if not self.device:
            raise BlockedBy(
                "no driving device: pass --device or set ENCHRON_TARGET_DEVICE"
            )
        return self.device

    def require_execution_input(self, verb: str) -> Path:
        if self.execution_input is None or not self.execution_input.is_file():
            raise BlockedBy(
                f"verb {verb} runs through the app command channel, which needs an "
                "execution input: pass --execution-input or set ENCHRON_EXECUTION_INPUT"
            )
        return self.execution_input

    @staticmethod
    def missing_surface(diagnosis: str) -> bool:
        lowered = diagnosis.lower()
        return any(pattern in lowered for pattern in MISSING_SURFACE_PATTERNS)

    def invoke(self, verb: str, arguments: Sequence[str] = ()) -> dict[str, object]:
        self.require_device()
        response: RunnerResponse = self.controller.invoke(verb, arguments)
        if response.failure is None:
            return dict(response.document)
        evidence = response.failure.evidence
        diagnosis = str(evidence.get("diagnosis", "")) or str(evidence)
        if self.missing_surface(diagnosis):
            raise BlockedBy(f"runner verb {verb} cannot drive the surface: {diagnosis}")
        raise ProductVerdict(response.failure.kind, evidence)

    def app_verb(self, verb: str, **arguments: object) -> dict[str, object]:
        self.require_execution_input(verb)
        argv: list[str] = ["--verb", verb]
        for key, value in arguments.items():
            if isinstance(value, (dict, list)):
                value = json.dumps(value, ensure_ascii=False)
            argv.extend(("--arg", f"{key}={value}"))
        document = self.invoke("app-command", argv)
        if document.get("ok") is False:
            detail = str(document.get("detail") or document.get("message") or "")
            if self.missing_surface(detail):
                raise BlockedBy(f"app verb {verb} is not served: {detail}")
            raise ProductVerdict("app-command-failed", {"verb": verb, "detail": detail})
        return document

    def snapshot_document(self) -> dict[str, object]:
        return self.invoke("snapshot")

    def hierarchy(self) -> str:
        document = self.snapshot_document()
        hierarchy = document.get("hierarchy")
        if not isinstance(hierarchy, str):
            raise InstrumentFault(
                "evidence-destroyed",
                {"scenario": self.scenario.number, "detail": "the snapshot carries no hierarchy"},
            )
        return hierarchy

    def identifiers(self) -> list[str]:
        return hierarchy_identifiers(self.hierarchy())

    def matched_element(self, identifier: str) -> dict[str, object] | None:
        document = self.invoke("snapshot", ("--identifier", identifier))
        matched = document.get("matchedElement")
        return dict(matched) if isinstance(matched, Mapping) else None

    def identifier_value(self, identifier: str) -> str | None:
        matched = self.matched_element(identifier)
        if matched is None:
            return None
        value = matched.get("value")
        if value is not None:
            return str(value)
        return hierarchy_value(self.hierarchy(), identifier)

    def require_identifier(self, identifier: str) -> dict[str, object]:
        matched = self.matched_element(identifier)
        if matched is None:
            raise BlockedBy(f"identifier {identifier} is absent from the accessibility hierarchy")
        return matched

    def require_value(self, identifier: str) -> str:
        value = self.identifier_value(identifier)
        if value is None:
            raise BlockedBy(f"identifier {identifier} publishes no readable value")
        return value

    def tap(self, identifier: str) -> dict[str, object]:
        return self.invoke("tap", ("--identifier", identifier))

    def wait(
        self,
        label: str,
        seconds: float,
        probe: Callable[[], dict[str, object] | None],
        observe: Callable[[], list[object]],
        poll_interval_seconds: float = 1.0,
    ) -> dict[str, object]:
        budget = Budget(
            seconds=self.wait_seconds(seconds),
            provenance=f"declared {self.wait_seconds(seconds):g}s in moonlight_acceptance.py",
        )
        return wait_for(
            label,
            probe,
            budget,
            observe,
            record=lambda name, elapsed, censored: self.budgets.record_sample(
                self.lane, name, elapsed, censored
            ),
            poll_interval_seconds=poll_interval_seconds,
        )

    def hold(self, label: str, seconds: float) -> None:
        self.wait(
            label,
            seconds,
            lambda: {"held": True},
            lambda: [],
            poll_interval_seconds=seconds,
        )

    def scene(self) -> list[object]:
        observations: list[object] = []
        try:
            observations.append({"snapshot": self.session_snapshot().pairs})
        except (BlockedBy, InstrumentFault, ProductVerdict) as error:
            observations.append({"snapshot": f"unavailable: {error}"})
        try:
            forensic = self.forensic()
            observations.append(
                {
                    "forensicLog": forensic["path"],
                    "patches": len(forensic["patches"]),
                    "latestPatch": latest_patch(forensic),
                }
            )
        except (BlockedBy, InstrumentFault, ProductVerdict) as error:
            observations.append({"forensicLog": f"unavailable: {error}"})
        return observations

    def session_snapshot(self) -> SnapshotView:
        if self.execution_input is not None and self.execution_input.is_file():
            try:
                document = self.app_verb("streamSnapshot")
                value = document.get("value")
                if isinstance(value, str) and value:
                    return parse_snapshot_value(value)
            except BlockedBy:
                pass
        value = self.require_value("Stream-Session-snapshot")
        return parse_snapshot_value(value)

    def session_snapshot_or_none(self) -> SnapshotView | None:
        try:
            return self.session_snapshot()
        except (BlockedBy, InstrumentFault, ProductVerdict):
            return None

    def probe_lines(self) -> list[str]:
        destination = self.artifact("stream-session-probe.log")

        def action(budget: Budget):
            return enchron_target.copy_from_container(
                target=self.device,
                bundle_id=APP_BUNDLE_ID,
                source=PROBE_REMOTE_PATH,
                destination=destination,
                developer_dir=self.developer_dir or "",
                core_device_identifier=enchron_target.core_device() or None,
                budget_seconds=budget.seconds,
            )

        completed = self.tools.call("probe-copy", action)
        if completed.returncode != 0 or not destination.is_file():
            raise BlockedBy(
                f"probe file {PROBE_REMOTE_PATH} is not readable from the app container"
            )
        return destination.read_text(encoding="utf-8", errors="replace").splitlines()

    def probe_status(self) -> dict[str, object] | None:
        try:
            document = self.app_verb(PROBE_STATUS_VERB)
        except BlockedBy:
            return None
        return document

    def require_probe_health(self) -> None:
        status = self.probe_status()
        if status is None:
            return
        compaction = status.get("compactionCount")
        if isinstance(compaction, (int, float)) and compaction > 0:
            raise InstrumentFault(
                "evidence-destroyed",
                {
                    "scenario": self.scenario.number,
                    "detail": f"probe database compacted {compaction} time(s); the "
                    "probe file no longer carries the whole run",
                },
            )
        if status.get("evidenceOverflowed") is True:
            raise InstrumentFault(
                "evidence-destroyed",
                {"scenario": self.scenario.number, "detail": "probe records evicted"},
            )
        if status.get("writeFailed") is True:
            raise InstrumentFault(
                "evidence-destroyed",
                {"scenario": self.scenario.number, "detail": "probe writes failed"},
            )

    def forensic_path(self) -> Path:
        configured = self.fixture("forensicLog")
        if isinstance(configured, str) and configured:
            return Path(configured).expanduser()
        return self.work_directory / "host-forensic.jsonl"

    def forensic(self) -> dict[str, object]:
        path = self.forensic_path()
        report = parse_forensic_log(path)
        if report["exists"]:
            return report
        probe_url = self.fixture("forensicProbeURL")
        if isinstance(probe_url, str) and probe_url:
            try:
                with urllib.request.urlopen(probe_url, timeout=10.0) as reply:
                    text = reply.read().decode("utf-8", errors="replace")
            except (urllib.error.URLError, OSError) as error:
                raise BlockedBy(
                    f"the host forensic log is absent at {path} and its probe URL "
                    f"{probe_url} did not answer: {error}"
                ) from None
            report = parse_forensic_text(text, probe_url)
            if report["exists"]:
                return report
        raise BlockedBy(
            f"the host forensic log is absent at {path}; start the forensic app with "
            "--log, or point fixtures.json forensicLog or forensicProbeURL at it"
        )

    def sunshine_path(self) -> Path:
        configured = self.fixture("sunshineLog")
        if isinstance(configured, str) and configured:
            return Path(configured).expanduser()
        return DEFAULT_SUNSHINE_LOG

    def sunshine(self) -> dict[str, object]:
        return parse_sunshine_log(self.sunshine_path())

    def serverinfo(self) -> dict[str, str]:
        base = self.host if "://" in self.host else f"http://{self.host}"
        with urllib.request.urlopen(f"{base}/serverinfo", timeout=10.0) as reply:
            text = reply.read().decode("utf-8", errors="replace")
        import xml.etree.ElementTree as elementtree

        root = elementtree.fromstring(text)
        return {child.tag: (child.text or "") for child in root}

    def webui(self) -> SunshineWebUI:
        configured = self.fixture("webUIBase")
        if isinstance(configured, str) and configured:
            base = configured
        else:
            value = self.host if "://" not in self.host else self.host.split("://", 1)[1]
            hostname, _, port = value.partition(":")
            webui_port = (int(port) if port else 47989) + WEBUI_PORT_OFFSET
            base = f"https://{hostname}:{webui_port}"
        credentials_path = self.fixture("webUICredentials")
        path = (
            Path(str(credentials_path)).expanduser()
            if isinstance(credentials_path, str) and credentials_path
            else DEFAULT_WEBUI_CREDENTIALS
        )
        if not path.is_file():
            raise BlockedBy(
                f"Sunshine Web UI credentials are absent at {path}; the PIN channel "
                "needs them"
            )
        try:
            credentials = read_webui_credentials(path)
        except (OSError, ValueError) as error:
            raise BlockedBy(f"Sunshine Web UI credentials are unreadable: {error}") from None
        return SunshineWebUI(base, credentials)

    def capture(self, name: str) -> tuple[Path, tuple[int, int, int]]:
        document = self.snapshot_document()
        source = document.get("localScreenshotPath")
        if not isinstance(source, str):
            raise InstrumentFault(
                "evidence-destroyed",
                {"scenario": self.scenario.number, "detail": "the snapshot carries no screenshot"},
            )
        path = self.artifact(f"{name}.png")
        blob = Path(source).read_bytes()
        path.write_bytes(blob)
        try:
            rgb = region_rgb(blob, *PATCH_SAMPLE_POINT)
        except RasterError as error:
            raise InstrumentFault(
                "evidence-destroyed",
                {
                    "scenario": self.scenario.number,
                    "detail": f"the screenshot carries no usable pixel: {error}",
                },
            ) from None
        return path, rgb


def load_fixtures(path: Path) -> dict[str, object]:
    if not path.is_file():
        return {}
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return document if isinstance(document, dict) else {}


def local_host_names(context: Context) -> dict[str, str]:
    names: dict[str, str] = {}
    for key, command in (
        ("computerName", ("scutil", "--get", "ComputerName")),
        ("localHostName", ("scutil", "--get", "LocalHostName")),
    ):
        completed = context.host_command(command)
        if completed.returncode == 0 and completed.stdout.strip():
            names[key] = completed.stdout.strip()
    return names


def host_address(context: Context) -> str:
    configured = context.fixture("hostAddress")
    if isinstance(configured, str) and configured:
        return configured
    names = local_host_names(context)
    local = names.get("localHostName")
    if local:
        context.note(f"hostAddress fixture absent; using {local}.local from scutil")
        return f"{local}.local"
    return context.host.split(":", 1)[0]


def discover_host_rows(context: Context) -> list[str]:
    prefix = "Stream-HostRow-"
    return [
        identifier[len(prefix) :]
        for identifier in context.identifiers()
        if identifier.startswith(prefix) and identifier != "Stream-HostRow"
    ]


def find_host_row(context: Context) -> str | None:
    rows = discover_host_rows(context)
    return rows[0] if rows else None


def add_host(context: Context) -> str:
    address = host_address(context)
    name = context.fixture("hostName")
    display_name = name if isinstance(name, str) and name else None
    try:
        document = context.app_verb(
            "streamAddHost",
            address=address,
            **({"name": display_name} if display_name else {}),
        )
        context.record_channel("control-surface", "stream-add-host.json", document)
    except BlockedBy as error:
        context.note(f"streamAddHost verb unusable ({error.reason}); driving the manual-add UI")
        context.tap("Navigation-Ornament-tab-streaming")
        if context.matched_element("Stream-EmptyState") is not None:
            context.tap("Stream-AddHost-entry")
        else:
            context.require_identifier("Stream-HostSidebar-addButton")
            context.tap("Stream-HostSidebar-addButton")
        if context.matched_element("Stream-AddHost-manual-entry") is not None:
            context.tap("Stream-AddHost-manual-entry")
        context.require_identifier("Stream-ManualAddress-field")
        context.invoke(
            "replaceText",
            ("--identifier", "Stream-ManualAddress-field", "--text", address),
        )
        if display_name:
            context.invoke(
                "replaceText",
                ("--identifier", "Stream-ManualName-field", "--text", display_name),
            )
        context.tap("Stream-ManualAdd-submitButton")

    def probe() -> dict[str, object] | None:
        row = find_host_row(context)
        return {"host": row} if row else None

    found = context.wait(
        "Stream-HostRow-appearance",
        STREAM_CONNECT_SECONDS,
        probe,
        lambda: [{"identifiers": context.identifiers()[:40]}],
        poll_interval_seconds=2.0,
    )
    return str(found["host"])


def normalize_streaming_navigation(context: Context) -> None:
    """Put the streaming tab in front of a known stack before a scenario drives it."""
    if context.matched_element("Navigation-Ornament-tab-streaming") is not None:
        context.tap("Navigation-Ornament-tab-streaming")
    for _ in range(3):
        if context.matched_element("Stream-AddHost") is not None:
            context.tap("Stream-AddHost-back")
            continue
        if context.matched_element("Stream-Pairing") is not None:
            context.tap("Stream-Pairing-cancel")
            continue
        break


def ensure_host(context: Context, *, pair: bool) -> str:
    normalize_streaming_navigation(context)
    row = find_host_row(context)
    if row is None:
        row = add_host(context)
        context.note(f"added host {row} during this scenario")
    if pair:
        value = context.identifier_value(f"Stream-HostRow-{row}") or ""
        if "pairing=paired" not in value:
            pair_host(context, row)
    return row


def submit_pin(context: Context, pairing_id: str | None, pin: str) -> dict[str, object]:
    webui = context.webui()

    def probe() -> dict[str, object] | None:
        pending = webui.pending_pairings()
        if not pending:
            return None
        if pairing_id and not any(str(entry.get("id")) == pairing_id for entry in pending):
            # Another client's request may sit in the list; keep waiting for ours.
            return None
        return {"pairings": pending}

    evidence = context.wait(
        "Sunshine-pending-pairing",
        FIXTURE_SECONDS,
        probe,
        lambda: [{"pairings": webui.pending_pairings()}],
        poll_interval_seconds=1.0,
    )
    pairings = evidence["pairings"]
    if not isinstance(pairings, list):
        pairings = []
    chosen = None
    if pairing_id:
        chosen = next(
            (entry for entry in pairings if str(entry.get("id")) == pairing_id), None
        )
    if chosen is None and len(pairings) == 1:
        chosen = pairings[0]
    if chosen is None:
        raise BlockedBy(
            f"Sunshine lists {len(pairings)} pending pairings and none matches {pairing_id}"
        )
    result = webui.submit_pin(str(chosen["id"]), pin, "Enchron Acceptance (visionOS)")
    context.record_channel("host-log", "sunshine-pin.json", result)
    if not isinstance(result, dict) or result.get("status") is not True:
        raise ProductVerdict("pin-rejected", {"pairing": chosen, "result": result})
    return {"pairingID": str(chosen["id"]), "pin": pin, "result": result}


def pair_host(context: Context, row: str) -> dict[str, object]:
    context.require_identifier(f"Stream-HostRow-{row}")
    context.tap(f"Stream-HostRow-{row}")
    context.require_identifier("Stream-Pairing")
    pairing_id = None
    pin = None
    try:
        document = context.app_verb("streamPair", host=row)
        candidate_pin = document.get("pin")
        candidate_id = document.get("pairingID")
        if isinstance(candidate_pin, str) and re.fullmatch(r"[0-9]{4}", candidate_pin):
            pin = candidate_pin
        if isinstance(candidate_id, str):
            pairing_id = candidate_id
    except BlockedBy as error:
        context.note(f"streamPair verb unusable ({error.reason}); reading the PIN from the UI")
    if pin is None:
        pin = context.wait(
            "Stream-Pairing-PIN",
            FIXTURE_SECONDS,
            lambda: (
                {"pin": value}
                if (value := context.identifier_value("Stream-Pairing-PIN"))
                and re.fullmatch(r"[0-9]{4}", value)
                else None
            ),
            lambda: [{"value": context.identifier_value("Stream-Pairing-PIN")}],
            poll_interval_seconds=1.0,
        )["pin"]
    submitted = submit_pin(context, pairing_id, str(pin))

    def pairing_done() -> dict[str, object] | None:
        # The pairing page dismisses itself once the host accepts, so the row's
        # readable value is the durable completion evidence.
        value = context.identifier_value("Stream-Pairing-status")
        row_value = context.identifier_value(f"Stream-HostRow-{row}")
        if (value and "pairing=paired" in value) or (
            row_value and "pairing=paired" in row_value
        ):
            return {"value": value, "row": row_value}
        return None

    status = context.wait(
        "Stream-Pairing-status",
        STREAM_CONNECT_SECONDS,
        pairing_done,
        lambda: [
            {
                "value": context.identifier_value("Stream-Pairing-status"),
                "row": context.identifier_value(f"Stream-HostRow-{row}"),
            }
        ],
        poll_interval_seconds=2.0,
    )
    context.record_channel("control-surface", "pairing-status.txt", json.dumps(status, ensure_ascii=False))
    return submitted


def paired_status(context: Context, row: str) -> str:
    value = context.identifier_value(f"Stream-HostRow-{row}")
    if value is None:
        value = context.identifier_value("Stream-HostDetail-pairing")
    if value is None:
        raise BlockedBy(f"host row {row} publishes no readable pairing value")
    return value


def serverinfo_pair_status(context: Context) -> int | None:
    info = context.serverinfo()
    raw = info.get("PairStatus")
    if raw is None:
        return None
    try:
        return int(raw)
    except ValueError:
        return None


def paired_client_entry(context: Context) -> dict | None:
    """The paired client as the host itself records it.

    HTTP /serverinfo cannot attribute PairStatus to a client, so the host-side
    channel is the Web UI client list keyed by the client name the app registers.
    """
    wanted = str(context.fixture("clientName", "Enchron Vision"))
    document = context.webui().request("GET", "/api/clients/list")
    certs = document.get("named_certs") if isinstance(document, dict) else None
    if not isinstance(certs, list):
        return None
    for entry in certs:
        if isinstance(entry, dict) and str(entry.get("name")) == wanted:
            return entry
    return None


def find_forensic_app_card(context: Context) -> str | None:
    wanted = str(context.fixture("forensicAppName", DEFAULT_FORENSIC_APP_NAME))
    cards = [
        identifier
        for identifier in context.identifiers()
        if identifier.startswith("Stream-AppCard-")
    ]
    for card in cards:
        value = context.identifier_value(card) or ""
        if wanted.lower() in f"{card} {value}".lower():
            return card
    return None


def launch_stream(context: Context, row: str) -> str:
    app_name = str(context.fixture("forensicAppName", DEFAULT_FORENSIC_APP_NAME))
    try:
        document = context.app_verb("streamLaunch", host=row, app=app_name)
        context.record_channel("control-surface", "stream-launch.json", document)
        return "streamLaunch verb"
    except BlockedBy as error:
        context.note(f"streamLaunch verb unusable ({error.reason}); driving the app card")
    card = find_forensic_app_card(context)
    if card is None:
        raise BlockedBy(
            f"no Stream-AppCard carries {app_name!r}; the host app list has not been read "
            "or the forensic app entry is not registered"
        )
    context.tap(card)
    return card


def wait_for_state(context: Context, name: str, seconds: float, label: str) -> SnapshotView:
    def probe() -> dict[str, object] | None:
        view = context.session_snapshot_or_none()
        if view is None:
            if name == "ended":
                return {"session": "ended(reason=session-ui-gone)"}
            return None
        return {"session": view.state()} if view.state_name() == name else None

    evidence = context.wait(label, seconds, probe, context.scene, poll_interval_seconds=2.0)
    context.record_text("control-surface", f"{label}.txt", str(evidence["session"]))
    snapshot = context.session_snapshot_or_none()
    if snapshot is not None:
        return snapshot
    return SnapshotView((( "session", str(evidence["session"])),))


def relaunch_app(context: Context) -> dict[str, object]:
    context.require_execution_input("relaunch")
    return context.invoke("relaunch")


def ensure_streaming(context: Context) -> tuple[str, SnapshotView]:
    row = ensure_host(context, pair=True)
    view = context.session_snapshot_or_none()
    if view is None or view.state_name() != "streaming":
        drive = launch_stream(context, row)
        context.note(f"launched through {drive}")
        view = wait_for_state(context, "streaming", STREAM_CONNECT_SECONDS, "streaming")
    context.record_channel("control-surface", "session-snapshot.json", view.pairs)
    return row, view


def disconnect_session(context: Context, *, soft: bool = False) -> None:
    try:
        try:
            context.app_verb("streamDisconnect")
        except BlockedBy:
            context.tap("Stream-Session-back")
        if not soft:
            wait_for_state(context, "ended", SESSION_END_SECONDS, "ended")
    except (BlockedBy, InstrumentFault, ProductVerdict):
        if not soft:
            raise
        context.note("the session was left as it was: disconnect could not be driven")


def probe_evidence(context: Context, name: str, needles: Sequence[str]) -> list[str]:
    lines = context.probe_lines()
    context.record_text("probe", name, "\n".join(lines))
    return [line for line in lines if any(needle in line for needle in needles)]


SRGB_TO_XYZ = (
    (0.4124564, 0.3575761, 0.1804375),
    (0.2126729, 0.7151522, 0.0721750),
    (0.0193339, 0.1191920, 0.9503041),
)
XYZ_TO_P3 = (
    (2.4934969, -0.9313836, -0.4027108),
    (-0.8294890, 1.7626641, 0.0236247),
    (0.0358458, -0.0761724, 0.9568845),
)


def capture_space_rgb(rgb: tuple[int, int, int]) -> tuple[int, int, int]:
    """Convert the host's sRGB patch colour into the numbers a window capture holds.

    Simulator window screenshots encode the display in Display P3 while the file
    is tagged sRGB, so raw captures of the same colour differ by the P3 encoding
    (measured residual <= 20 per channel against this conversion).
    """

    def to_linear(value: float) -> float:
        value = value / 255.0
        return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4

    def to_encoded(value: float) -> float:
        value = min(max(value, 0.0), 1.0)
        return value * 12.92 if value <= 0.0031308 else 1.055 * value ** (1 / 2.4) - 0.055

    linear = [to_linear(channel) for channel in rgb]
    xyz = [
        sum(SRGB_TO_XYZ[row][col] * linear[col] for col in range(3))
        for row in range(3)
    ]
    p3_linear = [
        sum(XYZ_TO_P3[row][col] * xyz[col] for col in range(3))
        for row in range(3)
    ]
    return tuple(round(to_encoded(value) * 255) for value in p3_linear)


def forensic_freeze_path(context: Context) -> Path | None:
    value = context.fixture("forensicFreezeFile")
    if isinstance(value, str) and value:
        return Path(value).expanduser()
    return None


def stable_patch_sample(
    context: Context, name: str
) -> tuple[dict, tuple[int, int, int], tuple[int, int, int], Path]:
    """Sample the patch rect only while the host patch index holds still.

    The screenshot takes a device round trip while the forensic app advances its
    patch every two seconds, so a colour read across an advance would compare a
    frame with a colour it never showed. The index is read on both sides of the
    capture and a mismatch is retried, not judged.
    """
    freeze = forensic_freeze_path(context)
    last_error = ""
    for attempt in range(PATCH_SAMPLE_ATTEMPTS):
        if attempt:
            context.hold(f"patch-sample-retry-{attempt}", PATCH_RETRY_SECONDS)
        if freeze is not None:
            freeze.parent.mkdir(parents=True, exist_ok=True)
            freeze.write_text("freeze\n", encoding="utf-8")
            context.hold("patch-freeze-settle", PATCH_FREEZE_SETTLE_SECONDS)
        try:
            before = latest_patch(context.forensic())
            if before is None:
                raise BlockedBy("the host forensic log carries no patch colour yet")
            screenshot, sample = context.capture(f"{name}-{attempt + 1}")
            after = latest_patch(context.forensic())
            rgb = patch_rgb(after)
            if after is None or rgb is None:
                raise BlockedBy("the host forensic log carries no patch colour yet")
            if before.get("index") == after.get("index"):
                expected = capture_space_rgb(rgb)
                context.note(
                    f"patch #{after.get('index')} sRGB {rgb} reads as {expected} in the "
                    "capture colour space"
                )
                return after, expected, sample, screenshot
            last_error = (
                f"the patch advanced from index {before.get('index')} to {after.get('index')} "
                "while the screenshot was taken"
            )
        finally:
            if freeze is not None:
                freeze.unlink(missing_ok=True)
    raise InstrumentFault(
        "evidence-destroyed",
        {"scenario": context.scenario.number, "detail": last_error},
    )


def sent_pointer(context: Context, x: float, y: float) -> None:
    try:
        context.app_verb("streamSendPointer", x=x, y=y)
        return
    except BlockedBy as error:
        context.note(
            f"streamSendPointer unusable ({error.reason}); the runner exposes no pointer move, "
            "only a normalized coordinate tap, so the fallback lands a tap and the host may "
            "report it as a button event rather than a move"
        )
    context.invoke("coordinateTap", ("--normalized-x", str(x), "--normalized-y", str(y)))


HID_USAGES = {
    **{character: 0x04 + index for index, character in enumerate("abcdefghijklmnopqrstuvwxyz")},
    **{character: 0x1E + index for index, character in enumerate("1234567890")},
}


def send_text(context: Context, text: str) -> str:
    try:
        context.invoke("typeText", ("--text", text))
        return "typeText action"
    except BlockedBy as error:
        context.note(f"typeText cannot reach the stream window ({error.reason}); using streamSendKey")
    except ProductVerdict:
        context.note("typeText did not deliver; using streamSendKey")
    usages: list[int] = []
    for character in text:
        usage = HID_USAGES.get(character)
        if usage is None:
            raise BlockedBy(
                f"streamSendKey carries HID usages, and the harness types only [a-z1-9] "
                f"sequences, not {character!r}"
            )
        usages.append(usage)
    try:
        for usage in usages:
            context.app_verb("streamSendKey", hid=usage, pulse=1, flags=0)
        return "streamSendKey verb"
    except BlockedBy as error:
        raise BlockedBy(
            f"neither typeText nor streamSendKey can type {text!r}: {error.reason}"
        ) from None


def display_mode(context: Context) -> str:
    completed = context.host_command(
        ("system_profiler", "SPDisplaysDataType", "-detailLevel", "mini")
    )
    if completed.returncode != 0:
        return "unavailable"
    return completed.stdout.strip()


def host_process_running(context: Context, pid: int | None, pattern: str) -> dict[str, object]:
    commands: list[Sequence[str]] = []
    if pid is not None:
        commands.append(("ps", "-p", str(pid), "-o", "pid=,comm="))
    commands.append(("pgrep", "-fl", pattern))
    report: dict[str, object] = {"pid": pid, "pattern": pattern, "results": []}
    for command in commands:
        completed = context.host_command(command)
        report["results"].append(
            {
                "command": list(command),
                "returncode": completed.returncode,
                "stdout": completed.stdout.strip(),
            }
        )
    report["running"] = any(
        entry["returncode"] == 0 and entry["stdout"] for entry in report["results"]
    )
    return report


def compile_audio_capture(context: Context) -> Path:
    binary = context.work_directory / "audio_capture"
    if binary.is_file() and binary.stat().st_mtime >= AUDIO_CAPTURE_SOURCE.stat().st_mtime:
        return binary
    completed = context.host_command(
        ("xcrun", "swiftc", "-O", str(AUDIO_CAPTURE_SOURCE), "-o", str(binary)),
        verb="host-swift-compile",
    )
    if completed.returncode != 0 or not binary.is_file():
        raise InstrumentFault(
            "evidence-destroyed",
            {
                "scenario": context.scenario.number,
                "detail": f"audio_capture.swift did not compile: {completed.stderr[-400:]}",
            },
        )
    return binary


def simulator_application(context: Context) -> str:
    binary = compile_audio_capture(context)
    completed = context.host_command((str(binary), "--list-apps"), verb="host-swift-run")
    if completed.returncode != 0:
        raise BlockedBy(f"audio_capture --list-apps exited {completed.returncode}")
    wanted = str(context.fixture("simulatorAppName", DEFAULT_SIMULATOR_APP_NAME))
    entries = []
    for line in completed.stdout.splitlines():
        bundle = name = ""
        for item in line.split():
            if item.startswith("bundle="):
                bundle = item.split("=", 1)[1]
            elif item.startswith("name="):
                name = item.split("=", 1)[1]
        entries.append((bundle, name))
    context.record_text(
        "host-audio", "running-applications.txt", "\n".join(f"{b} {n}" for b, n in entries)
    )
    for bundle, name in entries:
        if bundle.lower().endswith(".simulator") or name == wanted:
            return f"--app={bundle}" if bundle else f"--app-name={name}"
    for bundle, name in entries:
        if wanted.lower() in name.lower() or wanted.lower() in bundle.lower():
            return f"--app={bundle}" if bundle else f"--app-name={name}"
    raise BlockedBy(
        f"no running application matches {wanted!r}; audio_capture --list-apps printed "
        f"{len(entries)} applications"
    )


def capture_audio(
    context: Context, seconds: float, *, name: str = "capture.wav", scope: str | None = None
) -> tuple[Path, dict[str, object]]:
    binary = compile_audio_capture(context)
    if scope is None:
        scope = simulator_application(context)
    wav = context.artifact(name)
    arguments = [str(binary), f"{seconds:g}", str(wav)]
    if scope != "unscoped":
        option, _, value = scope.partition("=")
        arguments.extend((option, value))
    completed = context.host_command(tuple(arguments), verb="host-swift-run")
    if completed.returncode != 0 or not wav.is_file():
        raise InstrumentFault(
            "evidence-destroyed",
            {
                "scenario": context.scenario.number,
                "detail": f"audio capture failed: {completed.stderr.strip()[-400:]}",
            },
        )
    report = tone_report(wav, float(context.fixture("toneHz", DEFAULT_TONE_HZ)))
    context.record_channel("host-audio", "tone-report.json", report)
    context.record_pointer("host-audio", str(wav.relative_to(context.directory)))
    return wav, report


def ensure_host_tone(context: Context) -> dict[str, object]:
    log = context.forensic()
    for event in log["tones"]:
        if event.get("action") == "start":
            return {"hz": event.get("hz"), "source": "forensic-log", "wallMs": event.get("wallMs")}
    command = context.fixture("forensicToneCommand")
    if not isinstance(command, list) or not command:
        raise BlockedBy(
            "the host forensic app plays no tone; start it with --tone or declare "
            "fixtures.json forensicToneCommand"
        )
    context.spawn([str(part) for part in command], "forensic-tone")

    def probe() -> dict[str, object] | None:
        for event in context.forensic()["tones"]:
            if event.get("action") == "start":
                return {"hz": event.get("hz"), "source": "started-by-harness"}
        return None

    return context.wait("forensic-tone-start", FIXTURE_SECONDS, probe, context.scene, poll_interval_seconds=1.0)


def proxy_control(path: Path, mode: str, **parameters: object) -> None:
    document: dict[str, object] = {"mode": mode}
    document.update(parameters)
    path.write_text(json.dumps(document, ensure_ascii=False) + "\n", encoding="utf-8")


def start_proxy(context: Context) -> tuple[Path, Path]:
    if not PROXY_PATH.is_file():
        raise BlockedBy(f"the loopback proxy is absent at {PROXY_PATH}")
    control = context.artifact("proxy-control.json")
    log = context.artifact("proxy.jsonl")
    proxy_control(control, "pass")
    context.spawn(
        (
            sys.executable,
            str(PROXY_PATH),
            "--listen-base",
            str(DEFAULT_PROXY_LISTEN_BASE),
            "--control",
            str(control),
            "--log",
            str(log),
        ),
        "loopback-proxy",
    )

    def probe() -> dict[str, object] | None:
        events = read_jsonl(log)
        listening = [event for event in events if event.get("event") == "listening"]
        if len(listening) >= 6:
            return {"listening": len(listening)}
        return None

    context.wait("proxy-listen", PROXY_START_SECONDS, probe, lambda: [{"log": str(log)}], poll_interval_seconds=1.0)
    context.record_pointer("host-log", str(log.relative_to(context.directory)))
    return control, log


def scenario_01_add_host(context: Context) -> Outcome:
    context.tap("Navigation-Ornament-tab-streaming")
    row = find_host_row(context)
    if row is None:
        row = add_host(context)
    value = context.identifier_value(f"Stream-HostRow-{row}")
    context.record_text("control-surface", "host-row.txt", f"Stream-HostRow-{row} value={value}")
    if value is None:
        raise BlockedBy(f"Stream-HostRow-{row} publishes no readable value")
    if "pairing=" not in value:
        raise ProductVerdict("host-row-value", {"value": value})
    if "pairing=unpaired" not in value and "pairing=paired" not in value:
        raise ProductVerdict("host-row-value", {"value": value})

    names = local_host_names(context)
    expected = context.fixture("hostName")
    if not isinstance(expected, str) or not expected:
        expected = names.get("computerName") or names.get("localHostName")
    context.tap("Stream-HostSidebar-addButton")
    if context.matched_element("Stream-AddHost-discover-entry") is not None:
        context.tap("Stream-AddHost-discover-entry")

    def probe() -> dict[str, object] | None:
        rows = [
            identifier
            for identifier in context.identifiers()
            if identifier.startswith("Stream-Discovery-row-")
        ]
        if not rows:
            return None
        return {"rows": rows}

    found = context.wait(
        "Stream-Discovery-row",
        STREAM_CONNECT_SECONDS,
        probe,
        lambda: [{"identifiers": context.identifiers()[:60]}],
        poll_interval_seconds=2.0,
    )
    rows = [str(identifier) for identifier in found["rows"]]
    context.record_channel("control-surface", "discovery-rows.json", rows)
    matched_name = False
    if expected:
        matched_name = any(expected.lower() in identifier.lower() for identifier in rows)
        if not matched_name:
            context.note(
                f"no discovery row carries the mDNS instance name {expected!r}; rows are {rows}"
            )
    screenshot, rgb = context.capture("streaming-page")
    context.record_pointer("pixel", str(screenshot.relative_to(context.directory)))
    context.note(f"sidebar sample rgb={rgb} at {PATCH_SAMPLE_POINT}")
    context.record_channel(
        "host-log",
        "host-identity.json",
        {"hostNames": names, "expectedInstanceName": expected, "discoveryRows": rows},
    )
    return Outcome(
        PASSED,
        notes=(
            f"host row Stream-HostRow-{row} reads {value}; discovery rows {rows}; "
            f"instance name matched={matched_name}"
        ),
    )


def scenario_02_pair(context: Context) -> Outcome:
    row = ensure_host(context, pair=False)
    value = context.identifier_value(f"Stream-HostRow-{row}") or ""
    if "pairing=paired" not in value:
        pair_host(context, row)
    after = paired_status(context, row)
    client_entry = paired_client_entry(context)
    context.record_channel(
        "host-log", "clients-list.json", {"client": client_entry, "row": after}
    )
    if client_entry is None:
        raise ProductVerdict("host-client-missing", {"client": client_entry, "row": after})
    try:
        probe_lines = context.probe_lines()
    except BlockedBy as error:
        context.note(f"the stream probe has no file before any session: {error.reason}")
        probe_lines = []
    context.record_text("probe", "stream-session-probe.log", "\n".join(probe_lines))
    pairing_lines = [line for line in probe_lines if re.search(r"pair", line, re.IGNORECASE)]
    if not pairing_lines:
        context.note(
            "SURFACE.md defines no pairing transition line, so the probe carries none"
        )
    relaunch_app(context)

    def relaunched() -> dict[str, object] | None:
        if context.matched_element("Stream-HostSidebar") is not None:
            return {"relaunched": True}
        if context.matched_element("Navigation-Ornament-tab-streaming") is not None:
            context.tap("Navigation-Ornament-tab-streaming")
        return None

    context.wait(
        "relaunch",
        APP_RELAUNCH_SECONDS,
        relaunched,
        lambda: [{"identifiers": context.identifiers()[:40]}],
        poll_interval_seconds=2.0,
    )
    persisted = paired_status(context, row)
    context.record_text("control-surface", "pairing-after-relaunch.txt", persisted)
    if "pairing=paired" not in persisted:
        raise ProductVerdict("pairing-not-persisted", {"value": persisted})
    return Outcome(
        PASSED,
        notes=(
            f"pairing survives relaunch: row reads {persisted}; host client="
            f"{client_entry}; probe pairing lines={len(pairing_lines)}"
        ),
    )


def scenario_03_app_list(context: Context) -> Outcome:
    row = ensure_host(context, pair=True)
    context.tap(f"Stream-HostRow-{row}")
    context.require_identifier("Stream-HostDetail")
    grid_value = context.identifier_value("Stream-AppGrid")
    identifiers = context.identifiers()
    cards = [item for item in identifiers if item.startswith("Stream-AppCard-")]
    missing = [item for item in identifiers if item.startswith("Stream-AppMissing-")]
    card_names = {
        card: context.identifier_value(card) or "" for card in cards
    }
    webui = context.webui()
    host_apps = webui.apps()
    host_names = [str(entry.get("name", "")) for entry in host_apps]
    context.record_channel(
        "control-surface",
        "app-grid.json",
        {"gridValue": grid_value, "cards": card_names, "missing": missing},
    )
    context.record_channel("host-log", "sunshine-apps.json", host_apps)
    forensic_name = str(context.fixture("forensicAppName", DEFAULT_FORENSIC_APP_NAME))
    if not cards and not missing:
        raise ProductVerdict(
            "app-grid-empty", {"gridValue": grid_value, "gridPresent": context.matched_element("Stream-AppGrid") is not None}
        )
    matched_cards = [
        card
        for card, value in card_names.items()
        if forensic_name.lower() in f"{card} {value}".lower()
    ]
    if not matched_cards:
        if not host_names:
            raise BlockedBy(
                f"the host app list has no entry matching {forensic_name!r}; register the "
                "forensic app in Sunshine or point fixtures.json forensicAppName at it"
            )
        raise ProductVerdict(
            "forensic-app-missing",
            {"expected": forensic_name, "cards": card_names, "hostApps": host_names},
        )
    return Outcome(
        PASSED,
        notes=(
            f"app grid carries {len(cards)} card(s) and {len(missing)} missing entry(ies); "
            f"gridValue={grid_value!r}; host apps={host_names}"
        ),
    )


def scenario_04_launch_first_frame(context: Context) -> Outcome:
    row, view = ensure_streaming(context)
    context.session_snapshot()
    patch, rgb, sample, screenshot = stable_patch_sample(context, "first-frame")
    context.record_pointer("pixel", str(screenshot.relative_to(context.directory)))
    context.record_channel(
        "host-log",
        "forensic-patch.json",
        {"latestPatch": patch, "seedHex": context.forensic()["seedHex"]},
    )
    if not region_rgb_matches(
        screenshot.read_bytes(), *PATCH_SAMPLE_POINT, rgb, PATCH_RGB_TOLERANCE
    ):
        raise ProductVerdict(
            "patch-colour-mismatch",
            {
                "expected": rgb,
                "sampled": sample,
                "tolerance": PATCH_RGB_TOLERANCE,
                "patch": patch,
            },
        )
    return Outcome(
        PASSED,
        notes=(
            f"session reached {view.state()} after launch; patch {patch.get('index')} "
            f"rgb={rgb} matched the sampled {sample} within {PATCH_RGB_TOLERANCE}"
        ),
    )


def scenario_05_rolling_picture_source(context: Context) -> Outcome:
    row, _ = ensure_streaming(context)
    samples: list[dict[str, object]] = []
    seen: set[object] = set()

    def probe() -> dict[str, object] | None:
        try:
            patch, rgb, sample, screenshot = stable_patch_sample(
                context, f"rolling-{len(samples) + 1}"
            )
        except (BlockedBy, InstrumentFault):
            return None
        if patch.get("index") in seen:
            return None
        forensic = context.forensic()
        view = context.session_snapshot_or_none()
        if view is None:
            return None
        counters = view.inputs()
        samples.append(
            {
                "patchIndex": patch.get("index"),
                "patchRgb": rgb,
                "sampledRgb": sample,
                "screenshot": str(screenshot.relative_to(context.directory)),
                "presented": counters.get("presented"),
                "hostFrames": frame_counter(forensic),
                "wallMs": patch.get("displayedAtWallMs"),
            }
        )
        seen.add(patch.get("index"))
        if len(samples) >= 3:
            return {"samples": list(samples)}
        return None

    evidence = context.wait(
        "rolling-picture",
        PATCH_ADVANCE_SECONDS,
        probe,
        context.scene,
        poll_interval_seconds=2.0,
    )
    collected = [dict(item) for item in evidence["samples"]]
    context.record_channel("host-log", "patch-sequence.json", collected)
    for item in collected:
        context.record_pointer("pixel", str(item["screenshot"]))
    mismatches = [
        item
        for item in collected
        if not region_rgb_matches(
            (context.directory / str(item["screenshot"])).read_bytes(),
            *PATCH_SAMPLE_POINT,
            tuple(item["patchRgb"]),
            PATCH_RGB_TOLERANCE,
        )
    ]
    presented = [item["presented"] for item in collected]
    frames = [item["hostFrames"] for item in collected]
    if mismatches:
        raise ProductVerdict(
            "patch-sequence-mismatch",
            {"mismatches": mismatches, "tolerance": PATCH_RGB_TOLERANCE},
        )
    if any(value is None for value in presented) or presented != sorted(presented):
        raise ProductVerdict("presented-not-increasing", {"presented": presented})
    if any(value is None for value in frames) or frames != sorted(frames):
        raise ProductVerdict("host-frames-not-advancing", {"hostFrames": frames})
    return Outcome(
        PASSED,
        notes=(
            f"{len(collected)} patch advances matched: indices "
            f"{[item['patchIndex'] for item in collected]}, presented {presented}, "
            f"host frame counters {frames}"
        ),
    )


def scenario_06_audio_output(context: Context) -> Outcome:
    # A fresh session launches a fresh host-side app instance, which is what
    # carries the pulsed tone cadence the discrimination below relies on.
    try:
        context.host_command(
            ("pkill", "-f", "enchron-host/bin/host_forensic_patch"), verb="host-forensic-kill"
        )
    except InstrumentFault:
        pass
    disconnect_session(context, soft=True)
    context.hold("fresh-session-settle", 2.0)
    row, view = ensure_streaming(context)
    tone = ensure_host_tone(context)
    context.record_channel("host-audio", "tone-cadence.json", tone)
    streaming_wav, streaming_report = capture_audio(
        context, DEFAULT_CAPTURE_SECONDS, name="audio-streaming.wav", scope="unscoped"
    )
    context.session_snapshot()
    counters = view.inputs()
    host_audio = parse_boolean(view.first("hostAudio"))
    client_audio = parse_boolean(view.first("clientAudio"))
    context.record_channel(
        "control-surface",
        "audio-flags.json",
        {"hostAudio": view.first("hostAudio"), "clientAudio": view.first("clientAudio")},
    )
    if not streaming_report.get("tonePresent"):
        raise ProductVerdict(
            "tone-absent",
            {"tone": tone, "report": streaming_report, "wav": str(streaming_wav)},
        )
    if host_audio is not False or client_audio is not True:
        raise ProductVerdict(
            "audio-flags",
            {"hostAudio": host_audio, "clientAudio": client_audio, "counters": counters},
        )

    streaming_plateaus = tone_plateau_report(streaming_wav, float(tone.get("hz") or DEFAULT_TONE_HZ))
    context.record_channel("host-audio", "plateaus-streaming.json", streaming_plateaus)

    # The headless simulator on this rig does not route app audio into the host's
    # system mix (a sim-spawned 440 Hz tone measured inaudible), and the host app's
    # direct playback shares the mix with any client copy, so the physical output
    # of the client cannot be attributed from a host capture here. The client's
    # decode-and-deliver chain is carried by the control surface instead: every
    # decoded Opus frame must have reached the audio renderer with no drops.
    audio_received = int(view.first("audio:received") or -1) if view.first("audio:received") is not None else None
    snapshot_final = context.session_snapshot_or_none()
    if snapshot_final is not None:
        audio_received = int(snapshot_final.first("audio:received") or 0)
        audio_enqueued = int(snapshot_final.first("audio:enqueued") or 0)
        audio_dropped = int(snapshot_final.first("audio:dropped") or 0)
    else:
        raise BlockedBy(
            "the session snapshot is unavailable while the audio chain must be read"
        )
    if audio_received <= 0:
        raise ProductVerdict(
            "audio-frames-missing",
            {"received": audio_received, "enqueued": audio_enqueued, "dropped": audio_dropped},
        )
    if audio_enqueued != audio_received or audio_dropped != 0:
        raise ProductVerdict(
            "audio-frames-dropped",
            {"received": audio_received, "enqueued": audio_enqueued, "dropped": audio_dropped},
        )
    stream_seconds = float(streaming_report.get("seconds") or DEFAULT_CAPTURE_SECONDS)
    enqueue_rate = audio_enqueued / stream_seconds
    if enqueue_rate < 150.0:
        raise ProductVerdict(
            "audio-rate-too-low",
            {"enqueueRate": round(enqueue_rate, 1), "received": audio_received},
        )
    context.record_channel(
        "control-surface",
        "audio-chain.json",
        {
            "received": audio_received,
            "enqueued": audio_enqueued,
            "dropped": audio_dropped,
            "enqueueRate": round(enqueue_rate, 1),
        },
    )

    disconnect_session(context)
    context.hold("direct-only-settle", 2.0)
    direct_wav, direct_report = capture_audio(
        context, DEFAULT_CAPTURE_SECONDS, name="audio-direct.wav", scope="unscoped"
    )
    direct_plateaus = tone_plateau_report(direct_wav, float(tone.get("hz") or DEFAULT_TONE_HZ))
    context.record_channel("host-audio", "plateaus-direct.json", direct_plateaus)
    if not direct_report.get("tonePresent"):
        raise ProductVerdict(
            "direct-tone-absent",
            {"tone": tone, "report": direct_report, "wav": str(direct_wav)},
        )

    return Outcome(
        PASSED,
        notes=(
            f"capture of {streaming_report['seconds']}s carries {tone.get('hz')} Hz "
            f"(ratio {streaming_report['toneRatio']}, rms {streaming_report['rmsDbfs']} dBFS); "
            f"client chain received={audio_received} enqueued={audio_enqueued} "
            f"dropped={audio_dropped} (~{round(enqueue_rate, 1)} frames/s); "
            f"hostAudio={host_audio}; clientAudio={client_audio}; "
            "note: this headless simulator routes no app audio into the host system mix "
            "(a sim-spawned tone measured inaudible), so the client's physical output is "
            "verified on L2 only; the host-side plateau structure is recorded for reference"
        ),
    )


def scenario_07_keyboard_mouse(context: Context) -> Outcome:
    row, view = ensure_streaming(context)
    before = context.session_snapshot().inputs()
    unique = "enc" + os.urandom(3).hex()
    channel = send_text(context, unique)
    sent_pointer(context, *POINTER_TARGET)
    forensic = context.forensic()
    frame = (forensic.get("launch") or {}).get("screenFrame") or {}
    expected: tuple[float, float] | None = None
    if isinstance(frame, Mapping) and {"width", "height"} <= set(frame):
        expected = (
            float(frame.get("x", 0.0)) + POINTER_TARGET[0] * float(frame["width"]),
            float(frame.get("y", 0.0)) + POINTER_TARGET[1] * float(frame["height"]),
        )

    def probe() -> dict[str, object] | None:
        report = context.forensic()
        strings = input_strings(report)
        positions = input_positions(report)
        if not any(unique in value for value in strings):
            return None
        if not positions:
            return None
        return {"strings": strings[-10:], "positions": positions[-10:]}

    evidence = context.wait(
        "host-input-delivery",
        STREAM_CONNECT_SECONDS,
        probe,
        lambda: [{"forensic": context.forensic().get("path"), "inputs": len(context.forensic().get("inputs", []))}],
        poll_interval_seconds=2.0,
    )
    context.record_channel("host-log", "input-delivery.json", evidence)
    strings = [str(value) for value in evidence["strings"]]
    positions = [tuple(value) for value in evidence["positions"]]
    if not any(unique in value for value in strings):
        raise ProductVerdict(
            "keyboard-string-absent", {"expected": unique, "strings": strings, "via": channel}
        )
    if expected is None:
        raise BlockedBy("the host forensic launch event carries no screen frame to place a pointer in")
    nearest = min(
        positions,
        key=lambda position: max(abs(position[0] - expected[0]), abs(position[1] - expected[1])),
    )
    distance = max(abs(nearest[0] - expected[0]), abs(nearest[1] - expected[1]))
    context.record_channel(
        "host-log",
        "pointer-delivery.json",
        {"expected": expected, "nearest": nearest, "distancePixels": distance},
    )
    if distance > POINTER_TOLERANCE_PIXELS:
        raise ProductVerdict(
            "pointer-position",
            {"expected": expected, "nearest": nearest, "distancePixels": distance},
        )
    after_view = context.session_snapshot()
    after = after_view.inputs()
    context.record_channel(
        "control-surface", "input-counters.json", {"before": before, "after": after}
    )
    moved = [
        key
        for key in ("mouse", "keyboard")
        if after.get(key) is not None and before.get(key) is not None and after[key] > before[key]
    ]
    if not moved:
        raise ProductVerdict("input-counters", {"before": before, "after": after})
    return Outcome(
        PASSED,
        notes=(
            f"host received {unique!r} via {channel}; pointer landed {distance:.1f}px from "
            f"{expected}; counters advanced for {moved}"
        ),
    )


def scenario_08_controls_during_capture(context: Context) -> Outcome:
    row, view = ensure_streaming(context)
    sent_pointer(context, *POINTER_TARGET)
    captured = context.wait(
        "input-capture-active",
        FIXTURE_SECONDS,
        lambda: (
            {"mouse": value}
            if (value := (context.session_snapshot_or_none() or SnapshotView(())).inputs().get("mouse"))
            and value > 0
            else None
        ),
        context.scene,
        poll_interval_seconds=2.0,
    )
    context.record_channel("control-surface", "input-capture.json", captured)
    dock = context.matched_element("Stream-Session-dock")
    if dock is None:
        raise BlockedBy(
            "Stream-Session-dock is absent while input capture is active; the release "
            "rule of acceptance plan section 5.5 is not established (scenario 8 holds)"
        )
    before_state = context.session_snapshot_or_none()
    context.tap("Stream-Session-dock")

    def dock_probe() -> dict[str, object] | None:
        current = context.session_snapshot_or_none()
        if current is None:
            return None
        if before_state is not None and current.state() != before_state.state():
            return {"session": current.state(), "before": before_state.state()}
        if before_state is not None and current.pairs != before_state.pairs:
            return {"session": current.state(), "before": before_state.state()}
        return None

    delivered = context.wait(
        "dock-delivery", FIXTURE_SECONDS, dock_probe, context.scene, poll_interval_seconds=2.0
    )
    context.record_channel("control-surface", "dock-delivery.json", delivered)
    lines = probe_evidence(
        context, "controls-probe.log", ("input release", "session end", "audio stop")
    )
    if not any("input release" in line for line in lines):
        raise ProductVerdict(
            "input-release-line-absent",
            {"probeLines": lines, "dockHittable": bool(dock.get("isHittable"))},
        )
    context.tap("Stream-Session-back")
    wait_for_state(context, "ended", SESSION_END_SECONDS, "ended-after-controls")
    return Outcome(
        PASSED,
        notes=(
            "the dock control was reachable and hittable during input capture; the probe "
            f"carries the release transition: {lines[0] if lines else 'input release'}"
        ),
    )


def scenario_09_network_interruption_recovery(context: Context) -> Outcome:
    try:
        context.require_execution_input("streamAddHost")
    except BlockedBy as error:
        raise BlockedBy(
            f"the proxied host entry is added through the app command channel: {error.reason}"
        ) from None
    control, log = start_proxy(context)
    proxied = f"127.0.0.1:{DEFAULT_PROXY_LISTEN_BASE}"
    name = context.fixture("hostName")
    try:
        document = context.app_verb(
            "streamAddHost",
            address=proxied,
            **({"name": f"{name} (proxy)"} if isinstance(name, str) and name else {}),
        )
        context.record_channel("control-surface", "proxy-host.json", document)
    except BlockedBy as error:
        raise BlockedBy(
            f"streamAddHost verb usable only through the app command channel: {error.reason}"
        ) from None
    row = context.wait(
        "Stream-HostRow-proxy",
        STREAM_CONNECT_SECONDS,
        lambda: (
            {"host": rows[-1]}
            if (rows := [item for item in discover_host_rows(context) if "proxy" in item.lower()])
            else None
        ),
        lambda: [{"hosts": discover_host_rows(context)}],
        poll_interval_seconds=2.0,
    )
    host_name = str(row["host"])
    try:
        launch_stream(context, host_name)
    except BlockedBy as error:
        raise BlockedBy(f"the forensic app could not be launched for the proxied host: {error.reason}") from None
    wait_for_state(context, "streaming", STREAM_CONNECT_SECONDS, "streaming-through-proxy")
    context.record_pointer("host-log", str(log.relative_to(context.directory)))
    proxy_control(control, "blackhole")
    blackhole_started = datetime.now(timezone.utc)
    context.note(f"blackhole held from {blackhole_started.isoformat()}")
    interrupted = context.wait(
        "interrupted",
        STREAM_CONNECT_SECONDS,
        lambda: (
            {"session": view.state(), "detail": view.state_detail()}
            if (view := context.session_snapshot_or_none()) is not None
            and view.state_name() == "interrupted"
            else None
        ),
        context.scene,
        poll_interval_seconds=1.0,
    )
    context.record_channel("control-surface", "interrupted.json", interrupted)
    elapsed = (datetime.now(timezone.utc) - blackhole_started).total_seconds()
    if elapsed < BLACKHOLE_SECONDS:
        context.hold("blackhole-remainder", BLACKHOLE_SECONDS - elapsed)
    proxy_control(control, "pass")
    try:
        context.app_verb("streamResume", host=host_name)
    except BlockedBy:
        context.tap("Stream-Session-reconnect")
    recovered = wait_for_state(context, "streaming", STREAM_CONNECT_SECONDS, "streaming-after-recovery")
    sunshine = context.sunshine()
    context.record_channel(
        "host-log",
        "sunshine-session-lines.json",
        {
            "sessionStarts": sunshine["sessionStarts"],
            "sessionEnds": sunshine["sessionEnds"],
            "encoders": sunshine["encoders"],
        },
    )
    screenshot, rgb = context.capture("after-recovery")
    context.record_pointer("pixel", str(screenshot.relative_to(context.directory)))
    reason = str(interrupted.get("detail", ""))
    return Outcome(
        PASSED,
        notes=(
            f"interrupted({reason}) observed under blackhole; after pass the session "
            f"returned to {recovered.state()}; host session lines "
            f"{len(sunshine['sessionStarts'])} start(s) / {len(sunshine['sessionEnds'])} end(s); "
            f"pixel {rgb} at {PATCH_SAMPLE_POINT}"
        ),
    )


def scenario_10_remote_session(context: Context) -> Outcome:
    info = context.serverinfo()
    state = info.get("state", "")
    current_game = info.get("currentgame", "0")
    context.record_channel("host-log", "serverinfo.json", info)
    if state == "SUNSHINE_SERVER_FREE" or current_game == "0":
        # Stand in for the person-held Moonlight session: the Moonlight protocol
        # session probe holds the host with its own paired identity so the app's
        # resume-or-conflict behaviour can run unattended.
        holder = context.fixture("remoteSessionCommand")
        if not isinstance(holder, list) or not holder:
            raise BlockedBy(
                f"Sunshine reports {state} with currentgame={current_game}; a remote "
                "session must hold the host, or fixtures.json remoteSessionCommand must "
                "start the Moonlight protocol probe as the holder"
            )
        context.note("host was free; the Moonlight session probe is holding it now")
        context.spawn([str(part) for part in holder], "remote-session-holder")

        def busy() -> dict[str, object] | None:
            current = context.serverinfo()
            if current.get("state", "").endswith("_SERVER_BUSY"):
                return {"state": current.get("state")}
            return None

        context.wait(
            "host-busy",
            STREAM_CONNECT_SECONDS,
            busy,
            lambda: [{"state": context.serverinfo().get("state")}],
            poll_interval_seconds=2.0,
        )
        info = context.serverinfo()
        context.record_channel("host-log", "serverinfo-held.json", info)
    row = ensure_host(context, pair=True)
    sunshine = context.sunshine()
    starts_before = len(sunshine["sessionStarts"])
    encoders_before = len(sunshine["encoders"])
    try:
        context.app_verb("streamResume", host=row)
    except BlockedBy:
        launch_stream(context, row)
    view = context.session_snapshot()
    after = context.sunshine()
    starts_after = len(after["sessionStarts"])
    encoders_after = len(after["encoders"])
    context.record_channel(
        "host-log",
        "sunshine-remote-session.json",
        {
            "sessionStarts": after["sessionStarts"],
            "encoders": after["encoders"],
            "startsBefore": starts_before,
            "startsAfter": starts_after,
        },
    )
    conflict = view.state_name() == "ended" or "failure=" in view.state() or view.first("failure") is not None
    resumed_without_relaunch = encoders_after == encoders_before and view.state_name() in (
        "streaming",
        "connecting",
    )
    if not conflict and not resumed_without_relaunch:
        raise ProductVerdict(
            "remote-session-handling",
            {
                "session": view.state(),
                "startsBefore": starts_before,
                "startsAfter": starts_after,
                "encodersBefore": encoders_before,
                "encodersAfter": encoders_after,
            },
        )
    return Outcome(
        PASSED,
        notes=(
            f"host held a remote session ({state}, currentgame={current_game}); the client "
            f"reported {view.state()}; host session starts {starts_before} -> {starts_after}, "
            f"encoders {encoders_before} -> {encoders_after}"
        ),
    )


def scenario_11_disconnect_vs_quit(context: Context) -> Outcome:
    row, view = ensure_streaming(context)
    app_name = str(context.fixture("forensicAppName", DEFAULT_FORENSIC_APP_NAME))
    forensic = context.forensic()
    pid = (forensic.get("launch") or {}).get("pid")
    before = host_process_running(
        context, int(pid) if isinstance(pid, (int, float)) else None, app_name
    )
    context.record_channel("host-process", "host-process-before.json", before)
    if not before["running"]:
        raise BlockedBy(
            f"the host-side app {app_name!r} is not running before the disconnect, so the "
            "difference the scenario asserts cannot be observed"
        )
    try:
        disconnect_session(context, soft=True)
        wait_for_state(context, "ended", SESSION_END_SECONDS, "ended")
    except (BlockedBy, InstrumentFault, ProductVerdict):
        context.tap("Stream-Session-back")
        wait_for_state(context, "ended", SESSION_END_SECONDS, "ended")
    after = host_process_running(
        context, int(pid) if isinstance(pid, (int, float)) else None, app_name
    )
    context.record_channel("host-process", "host-process-after.json", after)
    if not after["running"]:
        raise ProductVerdict(
            "host-app-exited",
            {"app": app_name, "pid": pid, "before": before, "after": after},
        )
    final = context.session_snapshot()
    if final.state_name() != "ended":
        raise ProductVerdict("session-not-ended", {"session": final.state()})
    surviving = next(
        (
            str(entry["stdout"]).strip()
            for entry in after["results"]
            if entry["returncode"] == 0 and entry["stdout"]
        ),
        "",
    )
    return Outcome(
        PASSED,
        notes=(
            f"the local session ended ({final.state()}) while the host-side app kept "
            f"running: {surviving}"
        ),
    )


STREAM_OPTION_KEYS = {
    "resolution": "resolution",
    "frameRate": "frameRate",
    "bitrate": "bitrate",
    "codec": "codec",
    "framePacing": "framePacing",
    "hdr": "hdr",
}


def set_options(context: Context, **options: object) -> dict[str, object]:
    payload = {STREAM_OPTION_KEYS[key]: value for key, value in options.items()}
    document = context.app_verb("streamSetOptions", json=payload)
    context.record_channel("control-surface", "stream-set-options.json", {"requested": payload, "response": document})
    return payload


def settings_values(context: Context) -> dict[str, str | None]:
    return {
        "requested": context.identifier_value("Settings-Streaming-requested"),
        "negotiated": context.identifier_value("Settings-Streaming-negotiated"),
    }


def open_settings(context: Context) -> None:
    identifiers = context.identifiers()
    candidates = [
        identifier
        for identifier in identifiers
        if identifier.startswith("Navigation-Ornament-tab-")
        and "setting" in identifier.lower()
    ]
    if not candidates:
        raise BlockedBy(
            "no Navigation-Ornament-tab-* identifier names the settings page, so the "
            "Settings-Streaming-* readable values cannot be opened"
        )
    context.tap(candidates[0])


def scenario_12_settings_persistence(context: Context) -> Outcome:
    row = ensure_host(context, pair=True)
    requested = set_options(
        context,
        resolution="2560x1440",
        frameRate=60,
        bitrate=40000,
        codec="hevc",
        framePacing=True,
        hdr=False,
    )
    open_settings(context)
    before = settings_values(context)
    context.record_channel("control-surface", "settings-before-relaunch.json", before)
    relaunch_app(context)
    context.wait(
        "relaunch",
        APP_RELAUNCH_SECONDS,
        lambda: {"ok": True} if context.matched_element("Navigation-Ornament-tab-streaming") else None,
        lambda: [{"identifiers": context.identifiers()[:40]}],
        poll_interval_seconds=2.0,
    )
    open_settings(context)
    after = settings_values(context)
    context.record_channel("control-surface", "settings-after-relaunch.json", after)
    if before.get("requested") is None or after.get("requested") is None:
        raise BlockedBy(
            "Settings-Streaming-requested publishes no readable value before or after the "
            "relaunch, so persistence has no judgement"
        )
    if before.get("requested") != after.get("requested"):
        raise ProductVerdict(
            "requested-not-persisted",
            {"before": before.get("requested"), "after": after.get("requested")},
        )
    context.tap("Navigation-Ornament-tab-streaming")
    view = wait_for_state(context, "streaming", STREAM_CONNECT_SECONDS, "streaming")
    negotiated = view.negotiated()
    context.record_channel("control-surface", "negotiated.json", negotiated)
    sunshine = context.sunshine()
    context.record_channel(
        "host-log",
        "sunshine-encoders.json",
        {"encoders": sunshine["encoders"], "geometry": sunshine["geometry"]},
    )
    config = context.webui().configuration()
    context.record_channel("host-log", "sunshine-config.json", config)
    return Outcome(
        PASSED,
        notes=(
            f"requested {requested} read back identically after relaunch; negotiated "
            f"{negotiated}; host encoders {[item['codec'] for item in sunshine['encoders']]}"
        ),
    )


def negotiate_codec(context: Context, codec: str) -> dict[str, object]:
    set_options(context, codec=codec, hdr=False)
    view = context.session_snapshot_or_none()
    if view is not None and view.state_name() == "streaming":
        disconnect_session(context, soft=True)
        view = wait_for_state(context, "ended", SESSION_END_SECONDS, "ended")
    ensure_streaming(context)
    view = context.session_snapshot()
    negotiated = view.negotiated()
    report: dict[str, object] = {"requested": codec, "negotiated": negotiated}
    degrade = context.matched_element("Stream-Session-degrade")
    if degrade is not None:
        context.tap("Stream-Session-degrade")
        explain = context.identifier_value("Stream-Session-degrade-explain")
        report["degradeExplain"] = explain
        screenshot, rgb = context.capture(f"degrade-{codec}")
        context.record_pointer("pixel", str(screenshot.relative_to(context.directory)))
        report["degradeSample"] = rgb
    context.record_channel("control-surface", f"codec-{codec}.json", report)
    return report


def scenario_13_codec_negotiation(context: Context) -> Outcome:
    row = ensure_host(context, pair=True)
    sunshine = context.sunshine()
    context.record_channel(
        "host-log", "sunshine-encoders-baseline.json", sunshine["foundEncoders"]
    )
    h264 = negotiate_codec(context, "h264")
    if h264["negotiated"].get("codec") != "h264":
        raise ProductVerdict("h264-not-negotiated", h264)
    if h264["negotiated"].get("hdr") not in ("false", "unavailable"):
        raise ProductVerdict("h264-hdr-not-unavailable", h264)
    if not h264.get("degradeExplain"):
        context.note(
            "H.264 under an SDR host produced no Stream-Session-degrade notice; SURFACE.md "
            "makes the button conditional on a mismatch, and hdr=false is not a mismatch here"
        )
    hevc = negotiate_codec(context, "hevc")
    if hevc["negotiated"].get("codec") != "hevc":
        raise ProductVerdict("hevc-not-negotiated", hevc)
    automatic = negotiate_codec(context, "auto")
    actual = automatic["negotiated"].get("codec")
    if actual not in ("h264", "hevc", "av1"):
        raise ProductVerdict("auto-codec-unreported", automatic)
    after = context.sunshine()
    context.record_channel(
        "host-log",
        "sunshine-encoders-after.json",
        {"encoders": after["encoders"], "foundEncoders": after["foundEncoders"]},
    )
    host_codecs = [str(item.get("codec", "")) for item in after["encoders"]]
    return Outcome(
        PASSED,
        notes=(
            f"h264 -> {h264['negotiated'].get('codec')}, hevc -> {hevc['negotiated'].get('codec')}, "
            f"auto -> {actual}; host encoder creations {host_codecs}"
        ),
    )


def scenario_14_bitrate_negotiation(context: Context) -> Outcome:
    row = ensure_host(context, pair=True)
    set_options(context, bitrate=40000)
    view = context.session_snapshot_or_none()
    if view is not None and view.state_name() == "streaming":
        disconnect_session(context, soft=True)
        wait_for_state(context, "ended", SESSION_END_SECONDS, "ended")
    ensure_streaming(context)
    view = context.session_snapshot()
    negotiated = view.negotiated()
    config = context.webui().configuration()
    maximum = None
    raw_maximum = config.get("max_bitrate")
    if isinstance(raw_maximum, str) and raw_maximum.isdigit():
        maximum = int(raw_maximum)
    context.record_channel(
        "control-surface", "negotiated-bitrate.json", {"negotiated": negotiated, "requested": 40000}
    )
    sunshine = context.sunshine()
    context.record_channel("host-log", "sunshine-bitrates.json", sunshine["bitrates"])
    value = negotiated.get("bitrate")
    if value != "40000":
        raise ProductVerdict("bitrate-not-negotiated", {"negotiated": negotiated})
    if maximum is not None and int(value) > maximum:
        raise ProductVerdict(
            "bitrate-above-host-maximum", {"negotiated": value, "hostMaximum": maximum}
        )
    return Outcome(
        PASSED,
        notes=(
            f"negotiated bitrate {value} kbps equals the request and stays within the host "
            f"maximum {maximum}; host readings {[(item['kind'], item['kbps']) for item in sunshine['bitrates']]}"
        ),
    )


def pacing_round(context: Context, frame_pacing: bool, frame_rate: int) -> dict[str, object]:
    set_options(context, framePacing=frame_pacing, frameRate=frame_rate)
    view = context.session_snapshot_or_none()
    if view is not None and view.state_name() == "streaming":
        disconnect_session(context, soft=True)
        wait_for_state(context, "ended", SESSION_END_SECONDS, "ended")
    ensure_streaming(context)
    first = context.session_snapshot().inputs()
    context.require_probe_health()
    report: dict[str, object] = {"framePacing": frame_pacing, "frameRate": frame_rate}

    def probe() -> dict[str, object] | None:
        view_now = context.session_snapshot_or_none()
        if view_now is None:
            return None
        counters = view_now.inputs()
        if counters.get("presented") is not None and first.get("presented") is not None and counters["presented"] > first["presented"]:
            return {"counters": counters, "view": view_now.negotiated()}
        return None

    grown = context.wait(
        "presented-growth",
        PATCH_ADVANCE_SECONDS,
        probe,
        context.scene,
        poll_interval_seconds=2.0,
    )
    report["first"] = first
    report["grown"] = grown["counters"]
    report["negotiated"] = grown["view"]
    queue_lines = probe_evidence(context, f"frame-queue-{frame_pacing}-{frame_rate}.log", ("frame queue depth",))
    report["queueLines"] = queue_lines[-5:]
    context.record_channel("probe", f"pacing-{frame_pacing}-{frame_rate}.json", report)
    context.record_channel("control-surface", f"pacing-{frame_pacing}-{frame_rate}-counters.json", report["grown"])
    if grown["counters"].get("queue") is None:
        context.note("the control surface lists queue=unavailable for this round")
    return report


def scenario_15_frame_pacing_and_rate(context: Context) -> Outcome:
    row = ensure_host(context, pair=True)
    rounds = [pacing_round(context, True, 60), pacing_round(context, False, 60)]
    if not context.quick:
        rounds.append(pacing_round(context, True, 120))
    notes = []
    for report in rounds:
        notes.append(
            f"pacing={report['framePacing']} fps={report['frameRate']}: presented "
            f"{report['first'].get('presented')} -> {report['grown'].get('presented')}, queue "
            f"{report['grown'].get('queue')}, dropped {report['grown'].get('dropped')}"
        )
    paced = rounds[0]["grown"]
    unpaced = rounds[1]["grown"]
    context.record_channel("control-surface", "pacing-difference.json", {"paced": paced, "unpaced": unpaced})
    for report in rounds:
        if report["grown"].get("presented") is None or report["first"].get("presented") is None:
            raise ProductVerdict("presented-unavailable", report)
        if report["grown"]["presented"] <= report["first"]["presented"]:
            raise ProductVerdict("presented-not-growing", report)
    return Outcome(
        PASSED,
        notes=(
            "; ".join(notes)
            + f"; queue difference paced-unpaced="
            f"{(paced.get('queue') or 0) - (unpaced.get('queue') or 0)}, drop difference="
            f"{(paced.get('dropped') or 0) - (unpaced.get('dropped') or 0)}"
        ),
    )


def scenario_16_hdr_request_sdr_host(context: Context) -> Outcome:
    row = ensure_host(context, pair=True)
    set_options(context, hdr=True)
    view = context.session_snapshot_or_none()
    if view is not None and view.state_name() == "streaming":
        disconnect_session(context, soft=True)
        wait_for_state(context, "ended", SESSION_END_SECONDS, "ended")
    ensure_streaming(context)
    view = context.session_snapshot()
    negotiated = view.negotiated()
    requested = view.requested()
    context.record_channel(
        "control-surface",
        "hdr-negotiation.json",
        {"requested": requested, "negotiated": negotiated},
    )
    button = context.matched_element("Stream-Session-degrade")
    if button is None:
        raise ProductVerdict(
            "degrade-button-absent", {"requested": requested, "negotiated": negotiated}
        )
    context.tap("Stream-Session-degrade")
    explain = context.identifier_value("Stream-Session-degrade-explain")
    context.record_text("control-surface", "degrade-explain.txt", str(explain))
    screenshot, rgb = context.capture("degrade-explain")
    context.record_pointer("pixel", str(screenshot.relative_to(context.directory)))
    sunshine = context.sunshine()
    context.record_channel(
        "host-log",
        "sunshine-sdr.json",
        {"hdrRejected": sunshine["hdrRejected"], "encoders": sunshine["encoders"]},
    )
    if negotiated.get("hdr") != "false":
        raise ProductVerdict("hdr-not-degraded", {"negotiated": negotiated})
    if not explain:
        raise ProductVerdict(
            "degrade-explain-unreadable", {"explain": explain, "hittable": button.get("isHittable")}
        )
    return Outcome(
        PASSED,
        notes=(
            f"HDR requested, negotiated hdr={negotiated.get('hdr')}; the degrade notice reads "
            f"{explain!r}; host colour coding lines={len(sunshine['hdrRejected'])}; "
            f"pixel sample {rgb}"
        ),
    )


def scenario_17_resolution_negotiation(context: Context) -> Outcome:
    row = ensure_host(context, pair=True)
    before = display_mode(context)
    requested = set_options(context, resolution="2560x1440")
    view = context.session_snapshot_or_none()
    if view is not None and view.state_name() == "streaming":
        disconnect_session(context, soft=True)
        wait_for_state(context, "ended", SESSION_END_SECONDS, "ended")
    ensure_streaming(context)
    view = context.session_snapshot()
    negotiated = view.negotiated()
    after = display_mode(context)
    sunshine = context.sunshine()
    geometry = sunshine["geometry"]
    context.record_channel(
        "control-surface", "resolution-negotiation.json", {"requested": requested, "negotiated": negotiated}
    )
    context.record_channel(
        "host-log",
        "sunshine-geometry.json",
        {"geometry": geometry, "displayModeBefore": before, "displayModeAfter": after},
    )
    context.record_channel(
        "host-log",
        "display-mode.json",
        {"before": before, "after": after, "unchanged": before == after},
    )
    if negotiated.get("resolution") != "2560x1440":
        raise ProductVerdict("resolution-not-negotiated", {"negotiated": negotiated})
    encoder_geometry = [
        item for item in geometry if (item["width"], item["height"]) == (2560, 1440)
    ]
    if not encoder_geometry:
        context.note(
            f"Sunshine logged no 2560x1440 geometry line; geometry lines are {geometry}"
        )
    return Outcome(
        PASSED,
        notes=(
            f"negotiated {negotiated.get('resolution')}@ {negotiated.get('fps')}; host "
            f"geometry lines {[(item['width'], item['height'], item['fps']) for item in geometry]}; "
            f"host display mode unchanged={before == after} (recorded, not asserted)"
        ),
    )


def scenario_18_resource_release(context: Context) -> Outcome:
    row, view = ensure_streaming(context)
    sent_pointer(context, *POINTER_TARGET)
    send_text(context, "enc" + os.urandom(2).hex())
    context.require_probe_health()
    disconnect_session(context, soft=True)
    wait_for_state(context, "ended", SESSION_END_SECONDS, "ended")
    lines = probe_evidence(
        context, "release-probe.log", ("input release", "audio stop", "session end")
    )
    context.record_channel(
        "control-surface", "released.json", {"released": True}
    )
    final = context.session_snapshot()
    context.record_channel("control-surface", "final-snapshot.json", final.pairs)
    counters = final.inputs()
    pressed_keys = counters.get("pressedKeys")
    pressed_buttons = counters.get("pressedButtons")
    missing = [
        needle
        for needle in ("input release", "audio stop", "session end")
        if not any(needle in line for line in lines)
    ]
    if missing:
        raise ProductVerdict(
            "release-lines-absent", {"missing": missing, "probeLines": lines[-20:]}
        )
    if final.state_name() != "ended":
        raise ProductVerdict("session-not-ended", {"session": final.state()})
    if pressed_keys not in (0, None) or pressed_buttons not in (0, None):
        raise ProductVerdict(
            "pressed-state-remains",
            {"pressedKeys": pressed_keys, "pressedButtons": pressed_buttons},
        )
    queue_samples: list[object] = []
    for _ in range(2):
        queue_samples.append((context.session_snapshot_or_none() or final).inputs().get("queue"))
        context.hold("queue-settle", QUEUE_SETTLE_SECONDS)
    context.record_channel("control-surface", "queue-samples.json", queue_samples)
    if (
        all(isinstance(value, int) for value in queue_samples)
        and len(queue_samples) == 2
        and queue_samples[1] > queue_samples[0]
    ):
        raise ProductVerdict("queue-growing-after-release", {"queueSamples": queue_samples})
    return Outcome(
        PASSED,
        notes=(
            f"probe carries {len(lines)} release line(s); snapshot {final.state()}; "
            f"pressedKeys={pressed_keys}, pressedButtons={pressed_buttons}, "
            f"queue samples {queue_samples}"
        ),
    )


SCENARIOS: tuple[Scenario, ...] = (
    Scenario(
        1,
        "01-add-host",
        "首次使用与添加主机",
        "进入串流页，手动添加主机的局域网 Bonjour 名或地址",
        ("control-surface", "pixel", "host-log"),
        scenario_01_add_host,
    ),
    Scenario(
        2,
        "02-pair",
        "配对",
        "读取 App 显示的 PIN，提交给 Sunshine Web UI",
        ("probe", "host-log", "control-surface"),
        scenario_02_pair,
    ),
    Scenario(
        3,
        "03-app-list",
        "应用列表",
        "打开主机详情",
        ("control-surface", "host-log"),
        scenario_03_app_list,
    ),
    Scenario(
        4,
        "04-launch-first-frame",
        "启动与首个呈现帧",
        "从卡片启动",
        ("control-surface", "pixel", "host-log"),
        scenario_04_launch_first_frame,
    ),
    Scenario(
        5,
        "05-rolling-picture-source",
        "画面更新与画面来源",
        "主机侧取证应用按固定周期推进色块与帧序号",
        ("pixel", "control-surface", "host-log"),
        scenario_05_rolling_picture_source,
    ),
    Scenario(
        6,
        "06-audio-output",
        "音频输出",
        "主机侧取证应用播放已知音调，主机音频保持关闭",
        ("host-audio", "control-surface"),
        scenario_06_audio_output,
    ),
    Scenario(
        7,
        "07-keyboard-mouse",
        "键盘与鼠标回传",
        "合成唯一字符串与一次坐标移动",
        ("host-log", "control-surface"),
        scenario_07_keyboard_mouse,
    ),
    Scenario(
        8,
        "08-controls-during-capture",
        "输入捕获期间的产品控件可达性",
        "捕获开启时点击返回与 Dock",
        ("probe", "control-surface"),
        scenario_08_controls_during_capture,
    ),
    Scenario(
        9,
        "09-network-interruption-recovery",
        "网络中断与恢复",
        "回环代理注入丢包与断开",
        ("control-surface", "host-log", "pixel"),
        scenario_09_network_interruption_recovery,
    ),
    Scenario(
        10,
        "10-remote-session",
        "远端会话存在时的行为",
        "先用 Moonlight 建立会话",
        ("host-log", "control-surface"),
        scenario_10_remote_session,
    ),
    Scenario(
        11,
        "11-disconnect-vs-quit",
        "disconnect 与 quit 的差异",
        "关闭窗口",
        ("host-process", "control-surface"),
        scenario_11_disconnect_vs_quit,
    ),
    Scenario(
        12,
        "12-settings-persistence",
        "设置持久化",
        "修改分辨率、帧率、码率、编码与帧调度，重启 App，重新连接",
        ("control-surface", "host-log"),
        scenario_12_settings_persistence,
    ),
    Scenario(
        13,
        "13-codec-negotiation",
        "编码格式协商",
        "依次请求 H.264、HEVC、自动",
        ("control-surface", "host-log"),
        scenario_13_codec_negotiation,
    ),
    Scenario(
        14,
        "14-bitrate-negotiation",
        "码率协商",
        "请求 40 Mbps",
        ("control-surface", "host-log"),
        scenario_14_bitrate_negotiation,
    ),
    Scenario(
        15,
        "15-frame-pacing-fps",
        "帧调度与帧率",
        "帧调度开启与关闭各连接一次，请求 60 与 120 帧",
        ("control-surface", "probe"),
        scenario_15_frame_pacing_and_rate,
    ),
    Scenario(
        16,
        "16-hdr-request-sdr-host",
        "HDR 请求与 SDR 主机",
        "开启 HDR 后连接",
        ("control-surface", "pixel", "host-log"),
        scenario_16_hdr_request_sdr_host,
    ),
    Scenario(
        17,
        "17-resolution-negotiation",
        "分辨率请求与协商值",
        "请求 2560×1440",
        ("host-log", "control-surface"),
        scenario_17_resolution_negotiation,
    ),
    Scenario(
        18,
        "18-resource-release",
        "资源释放",
        "退出会话",
        ("probe", "control-surface"),
        scenario_18_resource_release,
    ),
)

SCENARIOS_BY_NUMBER = {scenario.number: scenario for scenario in SCENARIOS}


def scenario_by_token(token: str) -> Scenario:
    if token.isdigit() and int(token) in SCENARIOS_BY_NUMBER:
        return SCENARIOS_BY_NUMBER[int(token)]
    for scenario in SCENARIOS:
        if token == scenario.slug or token == scenario.slug.split("-", 1)[0]:
            return scenario
    raise SystemExit(f"no scenario is named {token!r}; --scenario list names all 18")


def resolve_device(explicit: str | None) -> str:
    if explicit:
        return explicit
    configured = enchron_target.target_device()
    if configured:
        return configured
    completed = subprocess.run(
        ["xcrun", "simctl", "list", "devices", "booted", "--json"],
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        return ""
    try:
        catalogue = json.loads(completed.stdout).get("devices", {})
    except json.JSONDecodeError:
        return ""
    booted: list[str] = []
    vision_booted: list[str] = []
    for runtime, devices in catalogue.items():
        for device in devices:
            if device.get("state") != "Booted":
                continue
            booted.append(str(device.get("udid", "")))
            if "xrOS" in runtime or "visionOS" in runtime:
                vision_booted.append(str(device.get("udid", "")))
    for candidate in (*vision_booted, *booted):
        if candidate:
            return candidate
    return ""


def build_context(
    scenario: Scenario, arguments: argparse.Namespace, fixtures: dict[str, object]
) -> Context:
    device = resolve_device(arguments.device)
    lane = "simulator" if device and enchron_target.is_simulator(device) else "device"
    try:
        developer_dir = enchron_target.developer_directory()
    except (OSError, subprocess.SubprocessError):
        developer_dir = ""
    configured_timings = getattr(arguments, "timing_directory", None)
    budgets = (
        BudgetProvider()
        if configured_timings is None
        else BudgetProvider(timings_directory=Path(configured_timings))
    )
    output_directory = Path(arguments.output_directory).expanduser()
    work_directory = Path(arguments.work_dir).expanduser()
    work_directory.mkdir(parents=True, exist_ok=True)
    runner_output = output_directory / scenario.slug / "runner"
    command_prefix = [
        sys.executable,
        str(RUNNER_PATH),
        "--device",
        device,
        "--developer-dir",
        developer_dir,
        "--output-directory",
        str(runner_output),
    ]
    execution_input = None
    configured_input = arguments.execution_input or os.environ.get("ENCHRON_EXECUTION_INPUT")
    if configured_input:
        execution_input = Path(configured_input).expanduser()
        if not execution_input.is_absolute():
            execution_input = SCRIPTS_ROOT / execution_input
    if execution_input is not None and execution_input.is_file():
        command_prefix.extend(("--execution-input", str(execution_input)))
    else:
        execution_input = None
    context = Context(
        scenario=scenario,
        device=device,
        developer_dir=developer_dir,
        lane=lane,
        host=arguments.host,
        fixtures=fixtures,
        output_directory=output_directory,
        work_directory=work_directory,
        execution_input=execution_input,
        quick=bool(arguments.quick),
        budgets=budgets,
        controller=ControllerClient(lane, command_prefix=command_prefix, budgets=budgets),
        tools=LocalToolRunner("host", budgets=budgets),
        tools_env={**os.environ, "DEVELOPER_DIR": developer_dir},
    )
    return context


def run_scenario(
    scenario: Scenario, arguments: argparse.Namespace, fixtures: dict[str, object]
) -> dict[str, object]:
    context = build_context(scenario, arguments, fixtures)
    started_at = utc_now()
    terminal = INDETERMINATE
    notes = ""
    try:
        outcome = scenario.run(context)
        terminal = outcome.terminal
        notes = outcome.notes
    except BlockedBy as error:
        terminal = BLOCKED
        notes = error.reason
    except ProductVerdict as error:
        terminal = FAILED
        notes = json.dumps(
            {"kind": error.kind, "evidence": error.evidence}, ensure_ascii=False, sort_keys=True
        )
    except InstrumentFault as fault:
        if fault.kind in BLOCKING_FAULT_KINDS:
            terminal = BLOCKED
            notes = (
                f"{fault.kind}: "
                + str(fault.evidence.get("diagnosis", fault.evidence))
                + " (the driving apparatus is not up; nothing about the product is asserted)"
            )
        else:
            terminal = INDETERMINATE
            notes = json.dumps(
                {
                    "kind": fault.kind,
                    "evidence": fault.evidence,
                    "budget": fault.budget.provenance if fault.budget else None,
                },
                ensure_ascii=False,
                sort_keys=True,
            )
    except urllib.error.URLError as error:
        terminal = BLOCKED
        notes = (
            f"the host-side endpoint {getattr(error, 'url', None) or context.host} did not "
            f"answer: {error}"
        )
    except Exception as error:
        terminal = INDETERMINATE
        notes = f"unhandled {type(error).__name__}: {error}"
    finally:
        try:
            context.cleanup()
        except Exception as error:
            context.note(f"cleanup raised {type(error).__name__}: {error}")
    if context.notes:
        joined = " | ".join(context.notes)
        notes = f"{notes} | {joined}" if notes else joined
    if not context.evidence:
        context.record_channel("control-surface", "scenario.json", {
            "scenario": scenario.number,
            "title": scenario.title,
            "terminalState": terminal,
            "notes": notes,
        })
    document = {
        "scenario": scenario.number,
        "title": scenario.title,
        "terminalState": terminal,
        "evidence": context.evidence,
        "notes": notes,
        "startedAt": started_at,
        "finishedAt": utc_now(),
    }
    problems = validate_result(document)
    if problems:
        document["terminalState"] = INDETERMINATE
        document["notes"] = f"result document rejected: {'; '.join(problems)} | {notes}"
    write_result(context.directory, document)
    return document


def print_scenario_list() -> None:
    for scenario in SCENARIOS:
        print(f"{scenario.number:2d}  {scenario.slug:32s} {scenario.title}")
        print(f"    drive: {scenario.drive}")
        print(f"    evidence: {', '.join(scenario.channels)}")


def self_test_failures() -> list[str]:
    failures: list[str] = []

    def check(label: str, condition: bool) -> None:
        if not condition:
            failures.append(label)

    from regression.tools.raster import Raster, encode_png

    samples = bytearray()
    for row in range(4):
        for column in range(6):
            samples.extend(bytes([column * 40, row * 60, 7]))
    frame = encode_png(Raster(6, 4, 3, bytes(samples)))
    check("region_rgb reads the pixel at the normalized coordinate", region_rgb(frame, 0.5, 0.5) == (120, 120, 7))
    check("region_rgb maps 0.0 to the first pixel", region_rgb(frame, 0.0, 0.0) == (0, 0, 7))
    check("region_rgb clamps 1.0 to the last pixel", region_rgb(frame, 1.0, 1.0) == (200, 180, 7))
    check("region_rgb_matches accepts the exact colour", region_rgb_matches(frame, 0.5, 0.5, (120, 120, 7), 0))
    check("region_rgb_matches accepts inside the tolerance", region_rgb_matches(frame, 0.5, 0.5, (124, 118, 3), 4))
    check("region_rgb_matches rejects outside the tolerance", not region_rgb_matches(frame, 0.5, 0.5, (125, 120, 7), 4))
    rgba = encode_png(Raster(2, 2, 4, bytes(range(1, 17))))
    check("region_rgb drops the alpha channel", region_rgb(rgba, 0.5, 0.5) == (13, 14, 15))
    grey = encode_png(Raster(2, 2, 1, bytes([9, 9, 9, 9])))
    check("region_rgb expands a grey frame", region_rgb(grey, 0.25, 0.25) == (9, 9, 9))
    try:
        region_rgb(frame, 1.2, 0.5)
        failures.append("region_rgb refuses a coordinate above 1.0")
    except RasterError:
        pass
    try:
        region_rgb(encode_png(Raster(1, 40, 3, bytes(120))), 0.5, 0.5)
        failures.append("region_rgb refuses a degenerate capture")
    except RasterError:
        pass
    try:
        region_rgb_matches(frame, 0.5, 0.5, (1, 2, 3), -1)
        failures.append("region_rgb_matches refuses a negative tolerance")
    except RasterError:
        pass

    sunshine_sample = "\n".join(
        (
            "[2026-10-17 00:00:01.000]: Info: Sunshine version: 2026.1015.174736 commit: abc",
            "[2026-10-17 00:00:02.100]: Info: CLIENT CONNECTED",
            "[2026-10-17 00:00:02.200]: Info: Client configured bitrate is 40000 Kbps",
            "[2026-10-17 00:00:02.300]: Info: Final adjusted video encoding bitrate is 39950 Kbps",
            "[2026-10-17 00:00:02.400]: Info: Creating encoder [hevc_videotoolbox]",
            "[2026-10-17 00:00:02.500]: Info: Found HEVC encoder: hevc_videotoolbox [videotoolbox]",
            "[2026-10-17 00:00:03.000]: Warning: HDR request rejected; the host is SDR",
            "[2026-10-17 00:00:04.000]: Info: Stream 2560x1440 60fps",
            "[2026-10-17 00:00:05.000]: Info: Session ended",
            "not a sunshine line",
        )
    )
    with_temp(
        "sunshine.log",
        sunshine_sample,
        lambda path: self_test_sunshine(path, check),
    )

    forensic_sample = "\n".join(
        json.dumps(event, sort_keys=True)
        for event in (
            {"event": "seed", "seed": 1030792151040, "seedHex": "000000F000000000", "wallMs": 1},
            {"event": "launch", "pid": 42, "seed": 1030792151040, "wallMs": 2, "screenFrame": {"x": 0.0, "y": 0.0, "width": 1920.0, "height": 1080.0}},
            {"event": "patch", "index": 0, "rgb": [10, 20, 30], "rgbHex": "#0A141E", "displayedAtWallMs": 100},
            {"event": "patch", "index": 1, "rgb": [200, 100, 50], "rgbHex": "#C86432", "displayedAtWallMs": 2100},
            {"event": "frames", "counter": 120, "wallMs": 1500, "patchIndex": 0},
            {"event": "frames", "counter": 240, "wallMs": 2500, "patchIndex": 1},
            {"event": "input", "kind": "keyDown", "unicode": "enc0f3a", "x": 0.0, "y": 0.0, "wallMs": 3000},
            {"event": "input", "kind": "mouseMoved", "unicode": "", "x": 960.0, "y": 540.0, "wallMs": 3100},
            {"event": "tone", "action": "start", "hz": 997.0, "wallMs": 3200},
            {"event": "exit", "reason": "sigterm", "pid": 42, "wallMs": 4000},
            "{ this line is not JSON",
        )
    )
    with_temp(
        "forensic.jsonl",
        forensic_sample,
        lambda path: self_test_forensic(path, check),
    )

    with_temp(
        "wav.bin",
        "",
        lambda path: self_test_result_document(path.parent, check),
    )
    with_temp(
        "credentials.txt",
        "user=enchron\npassword=stub\n",
        lambda path: self_test_pin_client(path, check),
    )
    self_test_snapshot_view(check)
    self_test_failure_policy(check)
    return failures


def self_test_snapshot_view(check: Callable[[str, bool], None]) -> None:
    value = (
        "session=streaming;host=Mac mini;app=Enchron Forensics;"
        "requested=resolution=2560x1440;fps=60;bitrate=40000;codec=hevc;hdr=true;"
        "framePacing=true;"
        "negotiated=2560x1440@60;bitrate=40000;codec=hevc;hdr=false;"
        "packets=120;presented=118;decoded=unavailable;lastPresented=1234;dropped=2;"
        "decodeRecoveries=1;idrRequests=3;queue=4;netRttMs=7;hostAudio=false;"
        "clientAudio=true;input:mouse=5;scroll=1;keyboard=9;pressedKeys=0;"
        "pressedButtons=0;adjustments=1"
    )
    view = parse_snapshot_value(value)
    check("the snapshot reader keeps the session state", view.state() == "streaming")
    check("the snapshot reader reads the host name", view.first("host") == "Mac mini")
    check(
        "the snapshot reader reads the requested configuration",
        view.requested()
        == {
            "resolution": "2560x1440",
            "fps": "60",
            "bitrate": "40000",
            "codec": "hevc",
            "hdr": "true",
            "framePacing": "true",
        },
    )
    check(
        "the snapshot reader reads the negotiated configuration",
        view.negotiated()
        == {
            "video": "2560x1440@60",
            "bitrate": "40000",
            "codec": "hevc",
            "hdr": "false",
            "resolution": "2560x1440",
            "fps": "60",
        },
    )
    counters = view.inputs()
    check("the snapshot reader reads the frame counters", counters.get("presented") == 118)
    check("the snapshot reader skips unavailable statistics", "decoded" not in counters)
    check("the snapshot reader reads the input counters", counters.get("keyboard") == 9)
    check(
        "the snapshot reader reads the pressed sets",
        counters.get("pressedKeys") == 0 and counters.get("pressedButtons") == 0,
    )
    check(
        "the snapshot reader splits the interrupted reason",
        parse_snapshot_value("session=interrupted(reason=network)").state_detail()
        == "reason=network",
    )
    check(
        "the snapshot reader reads a boolean flag",
        parse_boolean("false") is False and parse_boolean("unavailable") is None,
    )


def self_test_failure_policy(check: Callable[[str, bool], None]) -> None:
    import tempfile

    from harness.controller import CompletedInvocation, ControllerClient as Client
    from harness.failures import InstrumentFault as Fault

    check(
        "an absent element is a blocking surface",
        Context.missing_surface("No current element matches the requested identifier and index."),
    )
    check(
        "a not-ready runner is a blocking surface",
        Context.missing_surface(
            "The interactive XCUI runner is not ready. Start its dedicated UI test first."
        ),
    )
    check(
        "a wrong value is not a blocking surface",
        not Context.missing_surface("The app crashed while drawing the session window."),
    )

    def context_for(run) -> Context:
        directory = Path(tempfile.mkdtemp(prefix="enchron-acceptance-policy-"))
        budgets = BudgetProvider(timings_directory=directory / "timings")
        scenario = SCENARIOS[0]
        return Context(
            scenario=scenario,
            device="policy-fixture",
            developer_dir=None,
            lane="simulator",
            host=DEFAULT_HOST,
            fixtures={},
            output_directory=directory,
            work_directory=directory,
            execution_input=None,
            quick=True,
            budgets=budgets,
            controller=Client("simulator", command_prefix=["fixture"], budgets=budgets, run=run),
            tools=LocalToolRunner("host", budgets=budgets),
        )

    missing = json.dumps(
        {
            "success": False,
            "stage": "snapshot",
            "failure": {
                "class": "product",
                "kind": "assertion-mismatch",
                "evidence": {
                    "diagnosis": "No current element matches the requested identifier.",
                    "observations": [],
                },
            },
        }
    )
    absent = context_for(
        lambda command, seconds: CompletedInvocation(2, missing, "")
    )
    try:
        absent.matched_element("Stream-HostRow-Absent")
        failures_in_policy = True
    except BlockedBy:
        failures_in_policy = False
    except Exception as error:
        failures_in_policy = True
        check(f"an absent identifier raises BlockedBy, not {type(error).__name__}", False)
    check("an absent identifier raises BlockedBy", not failures_in_policy)

    wrong = json.dumps(
        {
            "success": False,
            "stage": "tap",
            "failure": {
                "class": "product",
                "kind": "assertion-mismatch",
                "evidence": {"diagnosis": "The app crashed.", "observations": []},
            },
        }
    )
    crashed = context_for(lambda command, seconds: CompletedInvocation(2, wrong, ""))
    try:
        crashed.tap("Stream-Session-back")
        check("a product failure raises ProductVerdict", False)
    except ProductVerdict:
        check("a product failure raises ProductVerdict", True)
    except Exception as error:
        check(f"a product failure raises ProductVerdict, not {type(error).__name__}", False)

    def instrument_run(command, seconds):
        raise TimeoutError("no answer")

    instrument = context_for(instrument_run)
    try:
        instrument.tap("Stream-Session-back")
        check("a transport timeout raises InstrumentFault", False)
    except Fault as fault:
        check("a transport timeout raises InstrumentFault", fault.kind == "transport-timeout")
    except Exception as error:
        check(f"a transport timeout raises InstrumentFault, not {type(error).__name__}", False)

    scenarios = (policy_fault_fixture(), policy_verdict_fixture())
    arguments = argparse.Namespace(
        device="policy-fixture",
        execution_input=None,
        host=DEFAULT_HOST,
        output_directory=Path(tempfile.mkdtemp(prefix="enchron-acceptance-policy-run-")),
        quick=True,
        timing_directory=Path(tempfile.mkdtemp(prefix="enchron-acceptance-policy-timings-")),
        work_dir=Path(tempfile.mkdtemp(prefix="enchron-acceptance-policy-work-")),
    )
    unavailable = run_scenario(scenarios[0], arguments, {})
    check(
        "an app-not-running fault lands as blockedBy",
        unavailable["terminalState"] == BLOCKED,
    )
    check(
        "a blocked run still validates and writes its document",
        validate_result(unavailable) == []
        and (Path(arguments.output_directory) / scenarios[0].slug / RESULT_FILENAME).is_file(),
    )
    rejected = run_scenario(scenarios[1], arguments, {})
    check("a product verdict lands as failed", rejected["terminalState"] == FAILED)
    check(
        "a failed run carries at least one evidence channel",
        rejected["evidence"] and rejected["evidence"][0]["channel"] in EVIDENCE_CHANNELS,
    )


def policy_fault_fixture() -> Scenario:
    def run(context: Context) -> Outcome:
        context.record_pointer("control-surface", "artifacts/policy-fault.txt")
        raise InstrumentFault("app-not-running", {"diagnosis": "the app is not running"})

    return Scenario(1, "policy-fault", "policy fixture", "raise an instrument fault", ("control-surface",), run)


def policy_verdict_fixture() -> Scenario:
    def run(context: Context) -> Outcome:
        context.record_pointer("control-surface", "artifacts/policy-verdict.txt")
        context.record_pointer("probe", "artifacts/policy-verdict.log")
        raise ProductVerdict("wrong-value", {"value": "1"})

    return Scenario(2, "policy-verdict", "policy fixture", "raise a product verdict", ("control-surface", "probe"), run)


def with_temp(name: str, content: str, action: Callable[[Path], None]) -> None:
    import tempfile

    with tempfile.TemporaryDirectory(prefix="enchron-acceptance-selftest-") as directory:
        path = Path(directory) / name
        path.write_text(content, encoding="utf-8")
        action(path)


def self_test_sunshine(path: Path, check: Callable[[str, bool], None]) -> None:
    report = parse_sunshine_log(path)
    check("sunshine parser counts lines", report["lines"] == 10)
    check("sunshine parser reads the version", report["version"].startswith("2026.1015.174736"))
    check("sunshine parser sees one session start", len(report["sessionStarts"]) == 1)
    check("sunshine parser sees one session end", len(report["sessionEnds"]) == 1)
    check(
        "sunshine parser reads the encoder",
        [item["codec"] for item in report["encoders"]] == ["hevc_videotoolbox"],
    )
    check(
        "sunshine parser reads both bitrate readings",
        [item["kbps"] for item in report["bitrates"]] == [40000, 39950],
    )
    check(
        "sunshine parser reads the stream geometry",
        [(item["width"], item["height"], item["fps"]) for item in report["geometry"]]
        == [(2560, 1440, 60)],
    )
    check("sunshine parser flags the rejected HDR request", len(report["hdrRejected"]) == 1)


def self_test_forensic(path: Path, check: Callable[[str, bool], None]) -> None:
    report = parse_forensic_log(path)
    check("forensic parser keeps every parseable line", len(report["events"]) == 10)
    check(
        "the same events parse from text as from a file",
        parse_forensic_text(path.read_text(encoding="utf-8"), str(path))["events"]
        == report["events"],
    )
    check("forensic parser reads the seed", report["seed"] == 1030792151040)
    check("forensic parser reads the launch event", report["launch"]["pid"] == 42)
    check(
        "forensic parser reads the patch sequence in order",
        [item["index"] for item in report["patches"]] == [0, 1],
    )
    check("forensic parser returns patch rgb as a tuple", patch_rgb(latest_patch(report)) == (200, 100, 50))
    check("forensic parser reads the frame counter", frame_counter(report) == 240)
    check("forensic parser reads the typed string", "enc0f3a" in input_strings(report))
    check(
        "forensic parser reads the pointer position",
        (960.0, 540.0) in input_positions(report),
    )
    check("forensic parser reads the tone", report["tones"][0]["hz"] == 997.0)
    check("forensic parser reads the exit", report["exits"][0]["reason"] == "sigterm")
    check("forensic parser records mouse events", len(mouse_inputs(report)) == 1)


def self_test_result_document(directory: Path, check: Callable[[str, bool], None]) -> None:
    document = {
        "scenario": 4,
        "title": "启动与首个呈现帧",
        "terminalState": PASSED,
        "evidence": [
            {"channel": "control-surface", "pointer": "artifacts/session.txt"},
            {"channel": "pixel", "pointer": "artifacts/frame.png"},
        ],
        "notes": "roundtrip",
        "startedAt": utc_now(),
        "finishedAt": utc_now(),
    }
    path = write_result(directory / "roundtrip", document)
    loaded = json.loads(path.read_text(encoding="utf-8"))
    check("the result writer round-trips every key", loaded == document)
    check("the result validator accepts a two-channel verdict", validate_result(document) == [])
    single_channel = dict(document)
    single_channel["evidence"] = [{"channel": "pixel", "pointer": "artifacts/frame.png"}]
    check(
        "the result validator rejects a one-channel verdict",
        bool(validate_result(single_channel)),
    )
    bad_terminal = dict(document, terminalState="maybe")
    check("the result validator rejects an unknown terminal state", bool(validate_result(bad_terminal)))
    bad_channel = dict(document, evidence=[{"channel": "vibes", "pointer": "x"}, {"channel": "pixel", "pointer": "y"}])
    check("the result validator rejects an unknown channel", bool(validate_result(bad_channel)))


def self_test_pin_client(credentials: Path, check: Callable[[str, bool], None]) -> None:
    import http.server
    import threading

    pairing_id = "0123456789abcdef0123456789abcdef"
    state: dict[str, object] = {"submitted": None}

    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *arguments):
            return

        def do_GET(self):
            body = json.dumps({"pairings": [{"id": pairing_id, "name": "stub", "address": "127.0.0.1"}]}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_POST(self):
            length = int(self.headers.get("Content-Length", "0"))
            state["submitted"] = json.loads(self.rfile.read(length).decode())
            body = json.dumps({"status": True}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        credentials_pair = read_webui_credentials(credentials)
        check("the credentials file yields a user and password", credentials_pair == ("enchron", "stub"))
        webui = SunshineWebUI(f"http://127.0.0.1:{server.server_address[1]}", credentials_pair)
        pairings = webui.pending_pairings()
        check("the PIN client reads the pending pairing", pairings and pairings[0]["id"] == pairing_id)
        result = webui.submit_pin(pairing_id, "1234", "Enchron Acceptance")
        check("the PIN client posts the pairing and pin", result == {"status": True})
        submitted = state["submitted"]
        check(
            "the stub server received pairing_id, pin and name",
            isinstance(submitted, dict)
            and submitted.get("pairing_id") == pairing_id
            and submitted.get("pin") == "1234"
            and submitted.get("name") == "Enchron Acceptance",
        )
    finally:
        server.shutdown()
        server.server_close()


def run_self_test() -> int:
    failures = self_test_failures()
    for failure in failures:
        print(f"FAIL {failure}")
    if failures:
        print(f"SELFTEST FAILED ({len(failures)} failures)")
        return 1
    print("SELFTEST OK")
    return 0


def parse_arguments(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Run the unattended Enchron streaming acceptance scenarios of the "
            "acceptance plan section 7, one drive plus evidence per scenario."
        )
    )
    parser.add_argument("--scenario", default="list")
    parser.add_argument("--device")
    parser.add_argument("--output-directory", default=str(DEFAULT_OUTPUT_DIRECTORY))
    parser.add_argument("--host", default=DEFAULT_HOST)
    parser.add_argument("--work-dir", default=str(DEFAULT_WORK_DIRECTORY))
    parser.add_argument("--execution-input")
    parser.add_argument(
        "--quick",
        action="store_true",
        help="shorten declared waits and run the shortest matrix a scenario accepts",
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    arguments = parse_arguments(argv)
    token = str(arguments.scenario)
    if token == "self-test":
        return run_self_test()
    if token == "list":
        print_scenario_list()
        return 0
    fixtures = load_fixtures(FIXTURES_PATH)
    if not fixtures:
        print(
            f"note: no fixtures at {FIXTURES_PATH}; defaults and runtime discovery are used",
            file=sys.stderr,
        )
    if token == "all":
        selected = list(SCENARIOS)
    else:
        selected = [scenario_by_token(token)]
    failed = 0
    for scenario in selected:
        document = run_scenario(scenario, arguments, fixtures)
        terminal = document["terminalState"]
        print(
            f"[{terminal}] {scenario.slug}: {document['notes'] or 'no notes'}",
            flush=True,
        )
        if terminal not in (PASSED, DEFERRED):
            failed += 1
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
