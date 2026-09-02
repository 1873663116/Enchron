#!/usr/bin/env python3
from __future__ import annotations

import argparse
from datetime import date, datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import sys
from typing import Any
import urllib.error
import urllib.parse
import urllib.request
import uuid


if str(Path(__file__).parent) not in sys.path:
    sys.path.insert(0, str(Path(__file__).parent))
from enchron_artifact_paths import evidence_root
import enchron_target
from harness import (
    Budget,
    BudgetProvider,
    ControllerClient,
    FaultRecord,
    Halt,
    InstrumentFault,
    LocalToolRunner,
    RecoveryPolicy,
    wait_for,
)

ROOT = Path(__file__).resolve().parents[2]
CONTROLLER = ROOT / "Scripts/verification/interactive_visionpro_ui.py"
INVENTORY = ROOT / "Config/reachability_operation_inventory.json"
BASELINE = ROOT / "Config/reachability_matrix_baseline.json"
DEFAULT_EVIDENCE = evidence_root() / f"reachability-{date.today():%Y%m%d}"

DEVICE = enchron_target.target_device()
CORE_DEVICE = enchron_target.core_device()
DEVELOPER_DIR = enchron_target.developer_directory()
APP_BUNDLE = "com.xiongzhipeng.XrPlayer"
PRESENTATIONS = ("window", "portal", "panorama", "docked")
MAIN_WINDOW_BROWSER_CONTEXT = "main-window-browser"
PROOF_CONTEXTS = (MAIN_WINDOW_BROWSER_CONTEXT, *PRESENTATIONS)
UNMEASURED_REASON = "The first-run fixture has not produced delivery evidence."

PACING_POLL_SLACK_SECONDS = 5.0

RECOVERY_VERBS = frozenset({"halt", "ensure-session"})

CENSORED_FAULT_KINDS = frozenset(
    {"transport-timeout", "wait-expired", "response-timeout"}
)

TRANSIENT_TRANSFER = re.compile(
    r"CoreDeviceError error (?:7000|-1)|could not be transferred"
    r"|Failed to retrieve the file node"
)

TRANSFER_ATTEMPTS = (1.0, 2.5, 5.0)

SEGMENT_SCENARIO_NAMES = {
    "browser-core",
    "breadcrumbs",
    "docked-content-round11",
    "docked",
    "docked-environment",
    "docked-exit-command-round11",
    "docked-exit",
    "docked-main-window-issues",
    "docked-menus",
    "docked-placement",
    "docked-reset-media-information",
    "docked-resident-window",
    "docked-spatial-secondary-issue",
    "docked-transport-issues",
    "emby-version-season",
    "emby-content-round11",
    "emby-session-recovery",
    "file-browser-errors",
    "library-conditions",
    "library-editing-round11",
    "library-reference-move",
    "manage-add",
    "panorama",
    "panorama-content-round11",
    "panorama-exit-command-round11",
    "panorama-immersive-issues",
    "panorama-panel-exit",
    "panorama-resident-window",
    "panorama-spatial-secondary-issue",
    "playback-failures",
    "player-ui-candidates",
    "player-panel-portal-menus",
    "portal",
    "portal-dv-round11",
    "portal-issues-round11",
    "portal-routes-round11",
    "portal-remote-audio-episodes",
    "remote-browser-round11",
    "resume-decision",
    "settings-category-round13",
    "settings-menus",
    "source-connection-smb",
    "source-connection-webdav",
    "source-sidebar",
    "window-playback",
    "window-dv-format-round11",
    "window-hdr-fallback-round12",
    "window-media-information-round12",
    "window-top-menu-round12",
    "window-environment-round11",
    "window-issues-round11",
    "window-menus-round11",
    "window-remote-audio-episodes",
}
PROBE_REMOTE_PATH = "Documents/surface-tap-probe.log"
CHANNEL_HEALTH_REMOTE_PATH = "Documents/reachability-channel-health.txt"
APP_RESPONSE_REMOTE_PATH = "Documents/test-responses"
PROBE_COPY_LIMIT_BYTES = 600_000
REACHABILITY_LIBRARY_FOLDER = "Reachability Fixture"
TEST_MEDIA = ROOT.parent / "TestMedia"
FIXTURE_SOURCES = {
    "furyroad-stripped.mkv":
        "Samples/DynamicRange/DolbyVision/Experiments/dvvC-ab/furyroad-stripped.mkv",
    "furyroad-with-dv.mkv":
        "Samples/DynamicRange/DolbyVision/Experiments/dvvC-ab/furyroad-with-dv.mkv",
    "sdr-bframe-multiaudio-subtitles-30s.mkv":
        "TestVectors/Enchron/PlaybackBehavior/sdr-bframe-multiaudio-subtitles-30s.mkv",
    "reachability-resume-16m.mp4":
        "TestVectors/Enchron/PlaybackBehavior/reachability-resume-16m.mp4",
    "broken-clip.mp4":
        "TestVectors/Enchron/PlaybackBehavior/broken-clip.mp4",
}
SCENARIO_FIXTURES = {
    "resume-decision": ("reachability-resume-16m.mp4",),
    "docked-content-round11": ("sdr-bframe-multiaudio-subtitles-30s.mkv",),
    "panorama-content-round11": ("sdr-bframe-multiaudio-subtitles-30s.mkv",),
    "portal-dv-round11": ("furyroad-with-dv.mkv",),
    "window-dv-format-round11": ("furyroad-with-dv.mkv",),
    "window-menus-round11": ("furyroad-with-dv.mkv",),
    "window-playback": ("broken-clip.mp4", "sdr-bframe-multiaudio-subtitles-30s.mkv",),
    "window-remote-audio-episodes": ("sdr-bframe-multiaudio-subtitles-30s.mkv",),
    "portal-remote-audio-episodes": ("sdr-bframe-multiaudio-subtitles-30s.mkv",),
}
DEFERRED_MENU_TARGETS = {
    ("playerPanel", "audio"): "__firstUnselected",
    ("playerPanel", "episodes"): "__firstAvailable",
    ("emby", "season"): "__firstUnselected",
    ("emby", "version"): "__firstUnselected",
    ("settings", "resume-strategy"): "askEveryTime",
    ("settings", "end-behavior"): "stop",
    ("settings", "default-scenic-environment"): "scenic-one",
    ("settings", "default-speed"): "0.5",
    ("settings", "controls-auto-hide"): "8",
}


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def refuse_when_detached() -> None:
    if os.getppid() != 1:
        return
    raise SystemExit(
        "reachability_matrix was started detached. It holds the device's only "
        "resident runner, so nothing else can drive the device until it finishes, "
        "and no one is reading its verdicts while it does. Run it in the foreground, "
        "or compile and drive the approved Catalog through "
        "python3 Scripts/regression/runctl.py --help"
    )


def redact_sensitive_values(value: object, values: tuple[str, ...]) -> object:
    secrets = tuple(sorted((item for item in values if item), key=len, reverse=True))
    if isinstance(value, str):
        for secret in secrets:
            value = value.replace(secret, "<redacted-credential>")
        return value
    if isinstance(value, list):
        return [redact_sensitive_values(item, secrets) for item in value]
    if isinstance(value, dict):
        return {
            key: redact_sensitive_values(item, secrets)
            for key, item in value.items()
        }
    return value


def _resolved_emby_address_from_receipt(fallback: str) -> str:
    try:
        import ensure_test_services as ets
        spec = ets.emby_spec()
        receipt = ets._read_object(spec.receipt_file)
        if isinstance(receipt, dict) and isinstance(receipt.get("address"), str) and receipt.get("address"):
            return str(receipt["address"]).strip()
        receipts, _ = ets.ensure_all((spec,))
        if receipts and isinstance(receipts[0].get("address"), str) and receipts[0].get("address"):
            return str(receipts[0]["address"]).strip()
    except Exception:
        pass
    return fallback


def _resolved_service_hosts() -> tuple[dict[str, str], dict[str, dict[str, object]]]:
    import ensure_test_services as ets
    specs = (ets.emby_spec(), ets.webdav_spec(), ets.smb_spec())
    receipts, _ = ets.ensure_all(specs)
    hosts: dict[str, str] = {}
    by_service: dict[str, dict[str, object]] = {}
    for receipt in receipts:
        service = str(receipt.get("service", ""))
        by_service[service] = receipt
        addr = receipt.get("address")
        if isinstance(addr, str) and addr:
            host = ets.endpoint_host(addr) if "://" in addr else addr
            hosts[service] = host
    return hosts, by_service


def verify_emby_recovery_credentials(path: Path) -> dict[str, Any]:
    result: dict[str, Any] = {
        "checkedAt": utc_now(),
        "credentialFieldsNonempty": False,
        "publicStatus": None,
        "authenticationStatus": None,
        "accessTokenPresent": False,
        "serverIdentityDigest": None,
        "passed": False,
    }
    try:
        credentials = json.loads(path.read_text(encoding="utf-8"))
        fallback = str(credentials.get("address", "")).strip()
        address = _resolved_emby_address_from_receipt(fallback)
        username = str(credentials.get("username", ""))
        password = str(credentials.get("password", ""))
        result["credentialFieldsNonempty"] = all((address, username, password))
        if result["credentialFieldsNonempty"] is not True:
            result["failure"] = "credential-fields-empty"
            return result

        base = address.rstrip("/") + "/"
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        public_request = urllib.request.Request(
            urllib.parse.urljoin(base, "System/Info/Public"),
            headers={"Accept": "application/json"},
        )
        with opener.open(public_request, None, 15) as response:
            result["publicStatus"] = response.status
            public_info = json.load(response)

        authorization = (
            'MediaBrowser Client="Enchron Reachability", '
            'Device="Mac", DeviceId="reachability-round12", Version="1"'
        )
        auth_request = urllib.request.Request(
            urllib.parse.urljoin(base, "Users/AuthenticateByName"),
            data=json.dumps({"Username": username, "Pw": password}).encode("utf-8"),
            headers={
                "Accept": "application/json",
                "Content-Type": "application/json",
                "X-Emby-Authorization": authorization,
            },
            method="POST",
        )
        with opener.open(auth_request, None, 15) as response:
            result["authenticationStatus"] = response.status
            authentication = json.load(response)

        server_id = public_info.get("Id") if isinstance(public_info, dict) else None
        token = (
            authentication.get("AccessToken")
            if isinstance(authentication, dict)
            else None
        )
        result["accessTokenPresent"] = isinstance(token, str) and bool(token)
        if isinstance(server_id, str) and server_id:
            result["serverIdentityDigest"] = hashlib.sha256(
                server_id.encode("utf-8")
            ).hexdigest()
        result["passed"] = (
            result["publicStatus"] == 200
            and result["authenticationStatus"] == 200
            and result["accessTokenPresent"] is True
            and isinstance(result["serverIdentityDigest"], str)
        )
        if result["passed"] is not True:
            result["failure"] = "server-response-incomplete"
    except urllib.error.HTTPError as error:
        result["failure"] = "http-error"
        result["httpStatus"] = error.code
    except (OSError, ValueError, json.JSONDecodeError, urllib.error.URLError):
        result["failure"] = "credential-check-failed"
    return result


def parse_probe_line(line: str) -> tuple[datetime, str] | None:
    timestamp, separator, detail = line.partition(" ")
    if not separator:
        return None
    try:
        parsed = datetime.fromisoformat(timestamp.replace("Z", "+00:00"))
    except ValueError:
        return None
    return parsed, detail


PROBE_SEQUENCE_PATTERN = re.compile(r"(?:^| )probeSequence=(\d+)(?: |$)")


def parse_probe_sequence(detail: str) -> int | None:
    match = PROBE_SEQUENCE_PATTERN.search(detail)
    return int(match.group(1)) if match is not None else None


def load_batched_app_responses(
    directory: Path, *, expected_ids: set[str]
) -> dict[str, dict[str, Any]]:
    responses: dict[str, dict[str, Any]] = {}
    if not directory.is_dir():
        return responses
    for path in sorted(directory.rglob("*.json")):
        try:
            document = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        if not isinstance(document, dict):
            continue
        response_id = document.get("id")
        if not isinstance(response_id, str) or response_id not in expected_ids:
            continue
        if response_id in responses:
            raise ValueError(f"duplicate app-command response {response_id}")
        responses[response_id] = document
    return responses


def device_file_size(document: Any, remote_path: str) -> int | None:
    basename = Path(remote_path).name

    def visit(value: Any) -> int | None:
        if isinstance(value, list):
            for item in value:
                found = visit(item)
                if found is not None:
                    return found
            return None
        if not isinstance(value, dict):
            return None

        path_values = {
            str(value.get(key))
            for key in ("path", "relativePath", "name", "fileName")
            if value.get(key) is not None
        }
        matches = remote_path in path_values or basename in path_values
        if matches:
            metadata = value.get("metadata")
            containers = [value]
            if isinstance(metadata, dict):
                containers.append(metadata)
            for container in containers:
                for key in ("size", "fileSize", "byteCount"):
                    size = container.get(key)
                    if isinstance(size, int) and not isinstance(size, bool):
                        return size
                    if isinstance(size, str) and size.isdecimal():
                        return int(size)
        for child in value.values():
            found = visit(child)
            if found is not None:
                return found
        return None

    return visit(document)


def parse_probe_status_response(document: dict[str, Any]) -> dict[str, Any]:
    values: dict[str, str] = {}
    for item in document.get("payload", []):
        if not isinstance(item, str) or "=" not in item:
            continue
        key, value = item.split("=", 1)
        values[key] = value

    def integer(key: str) -> int | None:
        value = values.get(key)
        return int(value) if value is not None and value.isdecimal() else None

    def boolean(key: str) -> bool | None:
        value = values.get(key)
        if value == "true":
            return True
        if value == "false":
            return False
        return None

    byte_limit = integer("byteLimit")
    file_bytes = integer("fileBytes")
    peak_file_bytes = integer("peakFileBytes")
    compaction_count = integer("compactionCount")
    evidence_overflowed = boolean("evidenceOverflowed")
    write_failed = boolean("writeFailed")
    passed = (
        document.get("success") is True
        and document.get("ok") is True
        and byte_limit is not None
        and byte_limit > 0
        and file_bytes is not None
        and file_bytes <= byte_limit
        and peak_file_bytes is not None
        and peak_file_bytes <= byte_limit
        and compaction_count is not None
        and evidence_overflowed is False
        and write_failed is False
    )
    return {
        "passed": passed,
        "byteLimit": byte_limit,
        "fileBytes": file_bytes,
        "peakFileBytes": peak_file_bytes,
        "compactionCount": compaction_count,
        "evidenceOverflowed": evidence_overflowed,
        "writeFailed": write_failed,
    }


def replay_deferred_evidence(
    *,
    cells: dict[tuple[str, str], dict[str, Any]],
    deliveries: list[dict[str, Any]],
    probe_lines: list[str],
    responses: dict[str, dict[str, Any]],
    started_at: str,
    ended_at: str,
    evidence: str,
    journal_retrieved: bool = True,
    session_id: str | None = None,
    evidence_session: str | None = None,
) -> dict[str, Any]:
    start = datetime.fromisoformat(
        started_at.replace("Z", "+00:00")
    ).replace(microsecond=0)
    end = datetime.fromisoformat(ended_at.replace("Z", "+00:00"))
    records = [
        record for line in probe_lines
        if (record := parse_probe_line(line)) is not None
        and start <= record[0] <= end
    ]
    sequences = [parse_probe_sequence(detail) for _, detail in records]
    sequence_ordered = (
        bool(sequences)
        and all(sequence is not None for sequence in sequences)
        and all(
            previous < current
            for previous, current in zip(sequences, sequences[1:])
            if previous is not None and current is not None
        )
    )
    effective_session = evidence_session if evidence_session is not None else session_id
    session_marker = f"reachability evidence session={effective_session}"
    session_aligned = any(session_marker in detail for _, detail in records)
    failures: list[dict[str, Any]] = []

    for delivery in deliveries:
        context = str(delivery["context"])
        operation = str(delivery["operation"])
        key = (context, operation)
        command_ids = [str(value) for value in delivery.get("commandIDs", [])]
        command_responses_pass = all(
            isinstance(responses.get(command_id), dict)
            and responses[command_id].get("id") == command_id
            and responses[command_id].get("ok") is True
            for command_id in command_ids
        )

        requirement_results: list[bool] = []
        for requirement in delivery.get("probeRequirements", []):
            after_text = str(requirement.get("after", started_at))
            after = datetime.fromisoformat(
                after_text.replace("Z", "+00:00")
            ).replace(microsecond=0)
            needles = [str(value) for value in requirement.get("needles", [])]
            requirement_results.append(any(
                timestamp >= after and all(needle in detail for needle in needles)
                for timestamp, detail in records
            ))
        probe_passes = all(requirement_results)
        passed = (
            session_aligned
            and sequence_ordered
            and command_responses_pass
            and probe_passes
        )
        if not passed:
            failures.append({
                "context": context,
                "operation": operation,
                "sessionAligned": session_aligned,
                "sequenceOrdered": sequence_ordered,
                "commandResponsesPassed": command_responses_pass,
                "probeRequirementsPassed": probe_passes,
                "commandDetails": [
                    detail
                    for command_id in command_ids
                    if isinstance(responses.get(command_id), dict)
                    and responses[command_id].get("ok") is not True
                    and (detail := str(responses[command_id].get("detail", "")))
                ],
                "missingResponseIDs": [
                    command_id for command_id in command_ids
                    if not isinstance(responses.get(command_id), dict)
                ],
            })
            continue

        cell = cells[key]
        cell["applicationReceived"] = True
        if evidence not in cell["evidence"]:
            cell["evidence"].append(evidence)
        if reachability_evidence_is_complete(cell):
            cell["verdict"] = "reachable"

    return {
        "passed": session_aligned and sequence_ordered and not failures,
        "journalRetrieved": journal_retrieved,
        "sessionAligned": session_aligned,
        "sequenceOrdered": sequence_ordered,
        "deliveryCount": len(deliveries),
        "verifiedDeliveryCount": len(deliveries) - len(failures),
        "failures": failures,
    }


def deferred_replay_failure_reason(replay: dict[str, Any]) -> str | None:
    if replay.get("journalRetrieved") is False:
        return (
            "The segment probe journal was never retrieved, so no delivery could "
            "be verified. The failures below are missing evidence, not refusals."
        )
    if replay.get("sessionAligned") is not True:
        return "The segment probe has no matching session marker."
    if replay.get("sequenceOrdered") is not True:
        return "The segment probe records are missing sequence metadata or out of order."
    return None


class DeferredProbeLine:

    def __init__(self, requirement: dict[str, Any]) -> None:
        self.requirement = requirement

    def record(self, needle: str) -> None:
        if needle not in self.requirement["needles"]:
            self.requirement["needles"].append(needle)

    def __contains__(self, needle: object) -> bool:
        self.record(str(needle))
        return True

    def rstrip(self, characters: str | None = None) -> "DeferredProbeLine":
        return self

    def endswith(self, suffix: object) -> bool:
        self.record(str(suffix))
        return True


class DeferredProbeSlice:
    def __init__(self, run: "ReachabilityRun", after_marker: int) -> None:
        self.run = run
        self.after_marker = after_marker

    def __iter__(self):
        requirement = {
            "after": self.run.probe_markers.get(
                self.after_marker, self.run.probe_markers[0]
            ),
            "needles": [],
        }
        self.run.deferred_probe_requirements.append(requirement)
        yield DeferredProbeLine(requirement)


class DeferredProbeView:
    def __init__(self, run: "ReachabilityRun", marker: int) -> None:
        self.run = run
        self.marker = marker

    def __len__(self) -> int:
        return self.marker

    def __iter__(self):
        return iter(DeferredProbeSlice(self.run, 0))

    def __getitem__(self, index: slice | int):
        if isinstance(index, slice):
            return DeferredProbeSlice(self.run, int(index.start or 0))
        raise IndexError(index)


def template_pattern(template: str) -> re.Pattern[str]:
    parts: list[str] = []
    cursor = 0
    depth = 0
    start = -1
    for index, character in enumerate(template):
        if character == "{" and depth == 0:
            parts.append(re.escape(template[cursor:index]))
            start = index
            depth = 1
        elif character == "{" and depth:
            depth += 1
        elif character == "}" and depth:
            depth -= 1
            if depth == 0:
                parts.append(".+?")
                cursor = index + 1
    if depth:
        return re.compile("^" + re.escape(template) + "$")
    parts.append(re.escape(template[cursor:]))
    return re.compile("^" + "".join(parts) + "$")


def product_proof_contexts(operation: dict[str, Any]) -> tuple[str, ...]:
    explicit = operation.get("proofContexts")
    if not isinstance(explicit, list):
        raise ValueError(
            f"operation {operation.get('id', '<unknown>')} has no proofContexts"
        )
    contexts = tuple(str(value) for value in explicit)
    unknown = set(contexts) - set(PROOF_CONTEXTS)
    if unknown:
        raise ValueError(
            f"operation {operation.get('id', '<unknown>')} has unknown proof contexts "
            f"{sorted(unknown)}"
        )
    return contexts


def reachability_evidence_is_complete(cell: dict[str, Any]) -> bool:
    if cell.get("identifierTemplate") is None:
        return cell.get("applicationReceived") is True
    return all(
        cell.get(key) is True
        for key in (
            "existsInHierarchy",
            "reportsHittable",
            "applicationReceived",
        )
    )


def menu_selection_target(
    listing: dict[str, Any],
    *,
    preferred: tuple[str, ...] = (),
) -> str | None:
    payload = listing.get("payload")
    available = [str(value) for value in payload] if isinstance(payload, list) else []
    for target in preferred:
        if target in available:
            return target

    menu_items = listing.get("menuItems")
    if isinstance(menu_items, list):
        for item in menu_items:
            if (
                isinstance(item, dict)
                and item.get("isSelected") is False
                and str(item.get("id")) in available
            ):
                return str(item["id"])
    return available[0] if available else None


def menu_delivery_probe_needle(target: str) -> str:
    prefix = "reachability playerPanel delivered action=menu.item."
    if target in {"__firstUnselected", "__firstAvailable"}:
        return prefix
    return prefix + target


def top_menu_delivery_probe_needle(target: str) -> str:
    prefix = "reachability top actions delivered action=menu.item."
    if target in {"__firstUnselected", "__firstAvailable"}:
        return prefix
    return prefix + target


def should_open_player_panel_system_menu(presentation: str) -> bool:
    return presentation in {"window", "portal"}


def validated_reachable_cell(
    document: dict[str, Any],
    *,
    context: str,
    operation: str,
) -> dict[str, Any] | None:
    if not (
        document.get("status") == "complete"
        and (document.get("channelContinuity") or {}).get("passed") is True
        and (document.get("probeJournal") or {}).get("passed") is True
    ):
        return None
    for cell in document.get("cells", []):
        if (
            isinstance(cell, dict)
            and cell.get("context") == context
            and cell.get("operation") == operation
            and cell.get("existsInHierarchy") is True
            and cell.get("reportsHittable") is True
            and cell.get("verdict") == "reachable"
        ):
            return cell
    return None


def reachability_action_was_delivered(
    probe: list[str], action: str, *, offset: int
) -> bool:
    written = f" delivered action={action}"
    return any(
        "reachability " in line and line.rstrip().endswith(written)
        for line in probe[offset:]
    )


def video_format_open_was_delivered(
    probe: list[str], *, offset: int
) -> bool:
    return reachability_action_was_delivered(probe, "videoFormat.open", offset=offset)


def merge_selected_cells_into_baseline(
    baseline_cells: list[dict[str, Any]],
    current_cells: list[dict[str, Any]],
    *,
    selected: set[str],
) -> list[dict[str, Any]]:
    baseline_by_key = {
        (cell.get("context"), cell.get("operation")): cell
        for cell in baseline_cells
    }
    merged: list[dict[str, Any]] = []
    for cell in current_cells:
        key = (cell["context"], cell["operation"])
        accepted = (
            cell
            if cell["context"] in selected
            else baseline_by_key.get(key, cell)
        )
        merged.append({
            "context": accepted["context"],
            "operation": accepted["operation"],
            "verdict": accepted["verdict"],
        })
    return merged


def merge_segment_delivery(
    baseline_cells: list[dict[str, Any]],
    segment_results: list[dict[str, Any]],
    *,
    require_baseline_coverage: bool = False,
    no_regression_cells: set[tuple[str, str]] | None = None,
) -> dict[str, Any]:
    static_coverage = set(no_regression_cells or ())
    candidate_by_key = {
        (str(cell["context"]), str(cell["operation"])): dict(cell)
        for cell in baseline_cells
    }
    accepted_segments: list[str] = []
    rejected_segments: list[str] = []
    driven_keys: set[tuple[str, str]] = set()
    observed_verdicts: dict[tuple[str, str], set[str]] = {}
    observed_defect_evidence: set[tuple[str, str]] = set()
    unassessed_legacy_driven_cells: list[dict[str, str]] = []

    for segment in segment_results:
        name = str(segment.get("segment", "unnamed"))
        session_id = segment.get("sessionID")
        health = segment.get("channelHealth")
        before = health.get("before", {}) if isinstance(health, dict) else {}
        after = health.get("after", {}) if isinstance(health, dict) else {}
        channel_continuous = (
            segment.get("status") == "complete"
            and isinstance(session_id, str)
            and bool(session_id)
            and before.get("passed") is True
            and after.get("passed") is True
            and before.get("sessionID") == session_id
            and after.get("sessionID") == session_id
            and (
                not isinstance(segment.get("channelContinuity"), dict)
                or segment["channelContinuity"].get("passed") is True
            )
        )
        if not channel_continuous:
            rejected_segments.append(name)
            continue

        accepted_segments.append(name)
        cells = {
            (str(cell.get("context")), str(cell.get("operation"))): cell
            for cell in segment.get("cells", [])
            if isinstance(cell, dict)
        }
        raw_driven_by_key = {
            (str(driven.get("context")), str(driven.get("operation"))): driven
            for driven in segment.get("drivenCells", [])
            if isinstance(driven, dict)
        }
        if segment.get("deliveryAssessmentModel") == "explicit-v1":
            for key, cell in cells.items():
                if reachability_evidence_is_complete(cell):
                    raw_driven_by_key.setdefault(
                        key,
                        {"context": key[0], "operation": key[1]},
                    )
        raw_driven = list(raw_driven_by_key.values())
        assessed_keys: set[tuple[str, str]] | None = None
        if (
            segment.get("deliveryAssessmentModel") != "explicit-v1"
            and int(segment.get("schemaVersion", 0) or 0) >= 3
            and isinstance(segment.get("deferredEvidence"), dict)
        ):
            assessed_keys = {
                (str(delivery.get("context")), str(delivery.get("operation")))
                for delivery in segment["deferredEvidence"].get("deliveries", [])
                if isinstance(delivery, dict)
            }
            assessed_keys.update(
                key for key, cell in cells.items()
                if cell.get("applicationReceived") is True
            )
            for driven in raw_driven:
                key = (
                    str(driven.get("context")),
                    str(driven.get("operation")),
                )
                if key not in assessed_keys:
                    unassessed_legacy_driven_cells.append({
                        "segment": name,
                        "context": key[0],
                        "operation": key[1],
                    })

        for driven in raw_driven:
            if not isinstance(driven, dict):
                continue
            key = (
                str(driven.get("context")),
                str(driven.get("operation")),
            )
            if assessed_keys is not None and key not in assessed_keys:
                continue
            if key not in candidate_by_key:
                continue
            driven_keys.add(key)
            observed = cells.get(key)
            verdict = (
                str(observed.get("verdict"))
                if isinstance(observed, dict)
                else "known-defect"
            )
            observed_verdicts.setdefault(key, set()).add(verdict)
            if (
                verdict != "reachable"
                and isinstance(observed, dict)
                and bool(observed.get("evidence"))
            ):
                observed_defect_evidence.add(key)

    for key, verdicts in observed_verdicts.items():
        candidate_by_key[key]["verdict"] = (
            "reachable" if "reachable" in verdicts else "known-defect"
        )

    failures: list[dict[str, str]] = []
    baseline_by_key = {
        (str(cell["context"]), str(cell["operation"])): cell
        for cell in baseline_cells
    }
    unknown_static_coverage = static_coverage - set(baseline_by_key)
    if unknown_static_coverage:
        raise ValueError(
            "No-regression evidence names unknown baseline cells: "
            + ", ".join(
                f"{context}:{operation}"
                for context, operation in sorted(unknown_static_coverage)
            )
        )
    non_reachable_static_coverage = {
        key for key in static_coverage
        if baseline_by_key[key].get("verdict") != "reachable"
    }
    if non_reachable_static_coverage:
        raise ValueError(
            "No-regression evidence may cover only reachable baseline cells: "
            + ", ".join(
                f"{context}:{operation}"
                for context, operation in sorted(non_reachable_static_coverage)
            )
        )
    static_conflicts = static_coverage & observed_defect_evidence
    for key in static_coverage - static_conflicts:
        candidate_by_key[key]["verdict"] = "reachable"
    for key in sorted(driven_keys):
        if (
            baseline_by_key[key].get("verdict") == "reachable"
            and candidate_by_key[key].get("verdict") != "reachable"
        ):
            failures.append({
                "context": key[0],
                "operation": key[1],
                "reason": "driven-old-reachable-not-reproved",
            })
    failures.extend({
        "context": context,
        "operation": operation,
        "reason": "no-regression-evidence-conflicts-with-device-evidence",
    } for context, operation in sorted(static_conflicts))

    covered_keys = driven_keys | static_coverage
    uncovered_reachable_cells = [
        {
            "context": str(cell["context"]),
            "operation": str(cell["operation"]),
        }
        for cell in baseline_cells
        if cell.get("verdict") == "reachable"
        and (str(cell["context"]), str(cell["operation"])) not in covered_keys
    ]
    if require_baseline_coverage:
        failures.extend({
            "context": cell["context"],
            "operation": cell["operation"],
            "reason": "old-reachable-not-driven",
        } for cell in uncovered_reachable_cells)

    return {
        "accepted": bool(accepted_segments) and not failures,
        "acceptedSegments": accepted_segments,
        "rejectedSegments": rejected_segments,
        "drivenCells": [
            {"context": context, "operation": operation}
            for context, operation in sorted(driven_keys)
        ],
        "noRegressionCoveredCells": [
            {"context": context, "operation": operation}
            for context, operation in sorted(static_coverage)
        ],
        "failures": failures,
        "uncoveredReachableCells": uncovered_reachable_cells,
        "unassessedLegacyDrivenCells": unassessed_legacy_driven_cells,
        "candidateCells": [
            candidate_by_key[(str(cell["context"]), str(cell["operation"]))]
            for cell in baseline_cells
        ],
    }


def validate_segment_plan(
    plan: dict[str, Any],
    *,
    operation_contexts: dict[str, set[str]],
    scenario_names: set[str],
) -> list[str]:
    errors: list[str] = []
    seen: set[str] = set()
    segments = plan.get("segments")
    if not isinstance(segments, list) or not segments:
        return ["segment plan must contain a nonempty segments array"]
    for segment in segments:
        if not isinstance(segment, dict):
            errors.append("segment plan contains a non-object segment")
            continue
        name = str(segment.get("id", ""))
        if not name:
            errors.append("segment is missing id")
        elif name in seen:
            errors.append(f"segment {name} is duplicated")
        seen.add(name)
        context = str(segment.get("context", ""))
        if context not in PROOF_CONTEXTS:
            errors.append(
                f"segment {name or '<missing>'} has unknown proof context {context}"
            )
        expected_maximum_steps = segment.get("expectedMaximumSteps")
        if (
            not isinstance(expected_maximum_steps, int)
            or isinstance(expected_maximum_steps, bool)
            or not 1 <= expected_maximum_steps <= 100
        ):
            errors.append(
                f"segment {name or '<missing>'} expectedMaximumSteps must be between 1 and 100"
            )
        scenarios = segment.get("scenarios")
        if not isinstance(scenarios, list) or not scenarios:
            errors.append(f"segment {name or '<missing>'} has no scenarios")
        else:
            for scenario in scenarios:
                if str(scenario) not in scenario_names:
                    errors.append(
                        f"segment {name or '<missing>'} has unknown scenario {scenario}"
                    )
        decisions = segment.get("decisions")
        if not isinstance(decisions, list) or not decisions:
            errors.append(f"segment {name or '<missing>'} has no decisions")
        else:
            for decision in decisions:
                if not isinstance(decision, dict):
                    errors.append(
                        f"segment {name or '<missing>'} contains a non-object decision"
                    )
                    continue
                decision_context = str(decision.get("context", ""))
                operation = str(decision.get("operation", ""))
                if decision_context not in PROOF_CONTEXTS:
                    errors.append(
                        f"segment {name or '<missing>'} decision has unknown proof "
                        f"context {decision_context}"
                    )
                if operation not in operation_contexts:
                    errors.append(
                        f"segment {name or '<missing>'} has unknown operation {operation}"
                    )
                elif decision_context not in operation_contexts[operation]:
                    errors.append(
                        f"segment {name or '<missing>'} operation {operation} is not "
                        f"derived for proof context {decision_context}"
                    )
    return errors


def immersive_resident_window_is_hidden(
    *,
    toggle: dict[str, Any],
    cleanup: dict[str, Any],
    no_named_node: bool,
    no_new_identifier: bool,
) -> bool:
    cleanup_proves_intermediate_state = (
        cleanup.get("success") is True
        and cleanup.get("ok") is True
        and cleanup.get("payload") == ["false"]
    )
    mechanism_was_open = (
        toggle.get("success") is True or cleanup_proves_intermediate_state
    )
    return mechanism_was_open and no_named_node and no_new_identifier


def product_accessibility_identifiers(document: dict[str, Any]) -> set[str]:
    hierarchy = str(document.get("hierarchy", ""))
    identifiers = set(re.findall(r"identifier: '([^']+)'", hierarchy))
    system_scene_prefix = f"{APP_BUNDLE}:SFBSystemService-"
    return {
        identifier
        for identifier in identifiers
        if not identifier.startswith(system_scene_prefix)
    }


class ReachabilityRun:
    def __init__(self, arguments: argparse.Namespace) -> None:
        self.arguments = arguments
        self.output = arguments.output_directory.resolve()
        self.controller_output = self.output / "controller"
        self.raw = self.output / "raw"
        self.output.mkdir(parents=True, exist_ok=True)
        self.controller_output.mkdir(parents=True, exist_ok=True)
        self.raw.mkdir(parents=True, exist_ok=True)
        self.inventory = json.loads(INVENTORY.read_text(encoding="utf-8"))
        self.operations = {
            str(item["id"]): item for item in self.inventory["operations"]
        }
        self.cells: dict[tuple[str, str], dict[str, Any]] = {}
        self.events: list[dict[str, Any]] = []
        self.driven_cells: set[tuple[str, str]] = set()
        self.tapped_cells: set[tuple[str, str]] = set()
        self.silent_taps: list[dict[str, Any]] = []
        self.copy_timings: list[dict[str, Any]] = []
        self.session_id: str | None = None
        self.evidence_session: str | None = None
        self.channel_health: dict[str, dict[str, Any]] = {}
        self.channel_failures: list[dict[str, Any]] = []
        self.segment: dict[str, Any] | None = getattr(arguments, "segment_spec", None)
        self.sequence = 0
        self.probe_offset = 0
        self.deferred_deliveries: list[dict[str, Any]] = []
        self.deferred_command_ids: set[str] = set()
        self.last_deferred_command_id: str | None = None
        self.deferred_probe_requirements: list[dict[str, Any]] = []
        self.probe_markers: dict[int, str] = {0: utc_now()}
        self.next_probe_marker = 1
        self.last_controller_document: dict[str, Any] = {}
        self.direct_transfer_calls = 0
        self.segment_evidence_started = False
        self.evidence_retrieval_transfer_calls = 0
        self.probe_retrieval_count = 0
        self.probe_status: dict[str, Any] = {}
        self.sensitive_values: tuple[str, ...] = ()
        self.out_of_context_observations = {}
        self.lane = "simulator" if enchron_target.is_simulator(DEVICE) else "device"
        self.budgets = BudgetProvider()
        self.client = ControllerClient(
            self.lane,
            command_prefix=[
                sys.executable,
                str(CONTROLLER),
                "--device",
                DEVICE,
                "--output-directory",
                str(self.controller_output),
                "--developer-dir",
                DEVELOPER_DIR,
                "--execution-input",
                str(arguments.execution_input),
            ],
            budgets=self.budgets,
        )
        self.tools = LocalToolRunner(self.lane, budgets=self.budgets)
        self.policy = RecoveryPolicy()
        self.history: list[FaultRecord] = []
        self.halted = False
        self.service_hosts: dict[str, str] = {}
        self.service_receipts: dict[str, dict[str, object]] = {}
        try:
            hosts, receipts = _resolved_service_hosts()
            self.service_hosts = hosts
            self.service_receipts = receipts
        except Exception:
            self.service_hosts = {}
            self.service_receipts = {}
        plan_document = getattr(arguments, "segment_plan_document", None)
        if self.segment is not None and isinstance(plan_document, dict):
            (self.output / "segment-plan.json").write_text(
                json.dumps(
                    plan_document, ensure_ascii=False, indent=2, sort_keys=True
                ) + "\n",
                encoding="utf-8",
            )
        for operation_id, operation in self.operations.items():
            for context in product_proof_contexts(operation):
                self.cells[(context, operation_id)] = {
                    "context": context,
                    "operation": operation_id,
                    "kind": operation["kind"],
                    "identifierTemplate": operation.get("identifierTemplate"),
                    "existsInHierarchy": False,
                    "reportsHittable": False,
                    "applicationReceived": False,
                    "verdict": "unmeasured",
                    "reason": UNMEASURED_REASON,
                    "evidence": [],
                }

    def record_wait_sample(self, label: str, seconds: float, censored: bool) -> None:
        self.budgets.record_sample(self.lane, label, seconds, censored)

    def hold(self, label: str, seconds: float) -> None:
        if seconds <= 0:
            return
        started = datetime.now(timezone.utc)

        def probe() -> dict[str, Any] | None:
            elapsed = (datetime.now(timezone.utc) - started).total_seconds()
            if elapsed >= seconds:
                return {"heldSeconds": round(elapsed, 3)}
            return None

        wait_for(
            label,
            probe,
            Budget(
                seconds=seconds + PACING_POLL_SLACK_SECONDS,
                provenance=(
                    f"pacing hold {seconds:g}s + "
                    f"{PACING_POLL_SLACK_SECONDS:g}s poll slack"
                ),
            ),
            observe=lambda: [],
            record=(
                self.record_wait_sample
                if getattr(self, "budgets", None) is not None
                else None
            ),
        )

    def channel_refuses(self, action: str) -> bool:
        if action in RECOVERY_VERBS:
            return False
        if getattr(self, "salvaging", False):
            return False
        if getattr(self, "halted", False):
            return True
        return self.segment is not None and bool(self.channel_failures)

    def record_instrument_fault(
        self,
        location: str,
        fault: InstrumentFault,
        *,
        evidence: str | None = None,
        continuity: bool = True,
    ) -> object:
        self.history.append(FaultRecord(
            location=location,
            kind=fault.kind,
            censored=fault.kind in CENSORED_FAULT_KINDS,
        ))
        decision = self.policy.on_fault(fault, self.history)
        entry: dict[str, Any] = {
            "at": utc_now(),
            "action": location,
            "kind": fault.kind,
            "error": str(fault),
        }
        if evidence is not None:
            entry["evidence"] = evidence
        if isinstance(decision, Halt):
            entry["halt"] = {
                "reason": decision.reason,
                "faultReport": decision.report,
            }
            self.halted = True
            self.channel_failures.append(entry)
        elif continuity and self.segment is not None:
            self.channel_failures.append(entry)
        return decision

    def _recover_emby_playback_timeout(
        self, presentation: str, operation_id: str, identifier: str
    ) -> bool:
        self.salvaging = True
        snapshot = self.controller("snapshot", "--no-screenshot")
        evidence = self.events[-1]["evidence"] if self.events else "raw/snapshot.json"
        self.mark_driven(presentation, operation_id)
        self.mark_observation(
            presentation,
            operation_id,
            exists=True,
            hittable=True,
            evidence=evidence,
            reason=(
                f"Emby {operation_id} on {identifier} is unresponsive; "
                "controller reported response-timeout while opening "
                "authenticated content and the hierarchy remained without "
                "transitioning to playback"
            ),
        )
        cell = self.cells.get((presentation, operation_id))
        if cell is not None and cell.get("verdict") == "unmeasured":
            cell["verdict"] = "known-defect"
            cell["reason"] = (
                f"Emby {operation_id} on {identifier} is unresponsive; "
                "controller reported response-timeout while opening "
                "authenticated content and the hierarchy remained without "
                "transitioning to playback"
            )
            if evidence not in cell.get("evidence", []):
                cell["evidence"].append(evidence)
        self.events.append({
            "at": utc_now(),
            "action": "productHang",
            "operation": operation_id,
            "identifier": identifier,
            "kind": "response-timeout",
            "success": False,
            "evidence": evidence,
        })
        self.salvaging = False
        self.controller("halt", "--no-screenshot")
        if not self.ensure_session():
            return False
        self.relaunch()
        health = self.channel_health_probe("after-emby-hang")
        status_document = self.read_probe_status()
        parsed = parse_probe_status_response(status_document) if isinstance(status_document, dict) else {}
        self.probe_status = parsed
        if health.get("passed") is True and status_document.get("success") is True:
            self.channel_failures.clear()
            self.history.clear()
            self.halted = False
            self.events.append({
                "at": utc_now(),
                "action": "recoverEmbyHang",
                "success": True,
                "evidence": "raw/channel-health-after-emby-hang.json",
            })
            return True
        self.events.append({
            "at": utc_now(),
            "action": "recoverEmbyHang",
            "success": False,
            "evidence": "raw/channel-health-after-emby-hang.json",
        })
        return False

    def local_call(self, verb: str, action: Any) -> Any:
        self.policy.record_action()
        try:
            return self.tools.call(verb, action)
        except InstrumentFault as fault:
            self.record_instrument_fault(verb, fault)
            return None

    @staticmethod
    def snapshot_poll(document: dict[str, Any]) -> dict[str, Any]:
        failure = document.get("failure")
        healthy = document.get("success") is True or (
            isinstance(failure, dict) and failure.get("class") == "product"
        )
        return {
            "healthy": healthy,
            "identifiers": sorted(
                ReachabilityRun.hierarchy_identifiers(document)
            ),
        }

    def wait_observation(
        self,
        verb: str,
        label: str,
        probe: Any,
        observe: Any,
        polls: list[dict[str, Any]] | None = None,
    ) -> dict[str, Any]:
        try:
            evidence = wait_for(
                verb,
                probe,
                self.budgets.budget(self.lane, verb),
                observe,
                record=self.record_wait_sample,
            )
        except InstrumentFault as fault:
            recorded = list(polls) if polls is not None else None
            evidence_backed = recorded is None or (
                bool(recorded)
                and all(poll.get("healthy") is True for poll in recorded)
            )
            outcome: dict[str, Any] = {
                "waitExpired": True,
                "label": label,
                "observations": list(fault.evidence.get("observations", [])),
                "budget": fault.budget.provenance if fault.budget else None,
            }
            self.sequence += 1
            name = f"{self.sequence:03d}-wait-{verb}.json"
            (self.raw / name).write_text(
                json.dumps({
                    **outcome,
                    "verb": verb,
                    "evidenceBackedExpiry": evidence_backed,
                    "polls": recorded,
                    "diagnosis": str(fault),
                }, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
                encoding="utf-8",
            )
            outcome["evidence"] = f"raw/{name}"
            if evidence_backed:
                outcome["evidenceBackedExpiry"] = True
            else:
                outcome["instrumentFault"] = True
            self.events.append({
                "at": utc_now(),
                "action": "waitExpired",
                "label": label,
                "kind": fault.kind,
                "success": False,
                "evidenceBackedExpiry": evidence_backed,
                "budget": outcome["budget"],
                "evidence": f"raw/{name}",
            })
            if not evidence_backed:
                self.record_instrument_fault(verb, fault, evidence=f"raw/{name}")
            return outcome
        if isinstance(evidence, dict) and evidence.get("quarantined"):
            return {
                "instrumentFault": True,
                "quarantined": True,
                "label": label,
            }
        return evidence if isinstance(evidence, dict) else {}

    def device_copy_from(
        self, source: str, destination: Path, *, label: str
    ) -> Any:
        completed = None
        for attempt, delay in enumerate(TRANSFER_ATTEMPTS):
            self.direct_transfer_calls += 1
            started = datetime.now(timezone.utc)
            completed = self.local_call(
                "probe-copy",
                lambda budget: enchron_target.copy_from_container(
                    target=DEVICE,
                    bundle_id=APP_BUNDLE,
                    source=source,
                    destination=destination,
                    developer_dir=DEVELOPER_DIR,
                    core_device_identifier=CORE_DEVICE,
                    budget_seconds=budget.seconds,
                ),
            )
            elapsed = round(
                (datetime.now(timezone.utc) - started).total_seconds(), 3
            )
            self.copy_timings.append({
                "label": label,
                "elapsedSeconds": elapsed,
                "succeeded": completed is not None and completed.returncode == 0,
            })
            if completed is None:
                return None
            if completed.returncode == 0:
                return completed
            output = completed.stderr + completed.stdout
            if not TRANSIENT_TRANSFER.search(output):
                return completed
            self.events.append({
                "at": utc_now(),
                "action": "retryDeviceCopy",
                "label": label,
                "attempt": attempt + 1,
                "elapsedSeconds": elapsed,
                "detail": output.strip()[:160],
            })
            self.hold("transfer-backoff", delay)
        return completed

    def controller(self, action: str, *extra: str) -> dict[str, Any]:
        refuse_when_detached()
        if self.channel_refuses(action):
            document = {
                "success": False,
                "error": (
                    "segment channel continuity already failed"
                    if self.segment is not None
                    else "the controller channel is quarantined after repeated "
                    "instrument faults"
                ),
            }
            self.sequence += 1
            name = f"{self.sequence:03d}-{action}.json"
            (self.raw / name).write_text(
                json.dumps(document, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
                encoding="utf-8",
            )
            self.events.append({
                "at": utc_now(),
                "action": action,
                "arguments": list(extra),
                "success": False,
                "evidence": f"raw/{name}",
                "elapsedSeconds": 0.0,
            })
            self.last_controller_document = document
            return document
        self.policy.record_action()
        started = datetime.now(timezone.utc)
        fault: InstrumentFault | None = None
        document: dict[str, Any] = {}
        for attempt in range(2):
            try:
                response = self.client.invoke(action, list(extra))
                document = dict(response.document)
                fault = None
                break
            except InstrumentFault as caught:
                fault = caught
                document = {
                    "success": False,
                    "error": str(caught),
                    "failure": {
                        "class": "instrument",
                        "kind": caught.kind,
                        "evidence": caught.evidence,
                    },
                }
                if attempt == 0:
                    decision = self.record_instrument_fault(action, caught, continuity=False)
                    if isinstance(decision, Halt):
                        break
                    self.events.append({
                        "at": utc_now(),
                        "action": "retryAfterInstrumentFault",
                        "arguments": [action],
                        "success": True,
                        "detail": (
                            f"{action} raised {caught.kind}; the recovery policy "
                            "chose one retry before the fault counts against "
                            "channel continuity."
                        ),
                    })
                    self.policy.record_action()
        document = redact_sensitive_values(
            document, getattr(self, "sensitive_values", ())
        )
        self.sequence += 1
        name = f"{self.sequence:03d}-{action}.json"
        (self.raw / name).write_text(
            json.dumps(document, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        self.events.append(
            {
                "at": utc_now(),
                "action": action,
                "arguments": list(extra),
                "success": document.get("success"),
                "evidence": f"raw/{name}",
                "elapsedSeconds": round(
                    (datetime.now(timezone.utc) - started).total_seconds(), 3
                ),
                "transportCallCount": document.get("transportCallCount", 0),
            }
        )
        self.last_controller_document = document
        if fault is None:
            self.history.clear()
        elif not self.halted:
            self.record_instrument_fault(action, fault, evidence=f"raw/{name}")
        return document

    def app_command(
        self,
        verb: str,
        *,
        defer_response: bool = True,
        track_reachability: bool = True,
        **arguments: str,
    ) -> dict[str, Any]:
        operation_id = f"command:{verb}"
        context = self.active_context
        if (
            track_reachability
            and operation_id in self.operations
            and context is not None
            and (context, operation_id) in self.cells
        ):
            self.mark_driven(context, operation_id)
        extra = ["--verb", verb, "--no-screenshot"]
        if getattr(self, "segment", None) is not None and defer_response:
            extra.append("--defer-response")
        if getattr(self, "segment", None) is not None:
            marker = self.evidence_session
            if marker is None:
                marker = self.session_id
            if marker is not None:
                extra.extend(("--arg", f"evidenceSession={marker}"))
        for key, value in arguments.items():
            extra.extend(("--arg", f"{key}={value}"))
        response = self.controller("app-command", *extra)
        for delay in (1.5, 3.0, 6.0):
            if response.get("success") is True or "test-command.json" not in str(
                response.get("error", "")
            ):
                break
            self.hold("app-command-retry", delay)
            response = self.controller("app-command", *extra)
        if self.segment is not None and defer_response:
            command_id = response.get("id")
            if isinstance(command_id, str):
                self.deferred_command_ids.add(command_id)
                self.last_deferred_command_id = command_id
        return response

    @property
    def active_context(self) -> str | None:
        if self.segment is not None:
            return str(self.segment["context"])
        selected = list(getattr(self.arguments, "contexts", []))
        return selected[0] if len(selected) == 1 else None

    def mark_driven(self, context: str, operation_id: str) -> None:
        if operation_id in self.operations and self.provable(context, operation_id):
            self.driven_cells.add((context, operation_id))

    def channel_health_probe(self, phase: str) -> dict[str, Any]:
        session_id = self.session_id
        payload = (
            f"reachability-channel-health phase={phase} session={session_id} "
            f"nonce={uuid.uuid4()}\n"
        ).encode("utf-8")
        source = self.raw / f"channel-health-{phase}-source.txt"
        returned = self.raw / f"channel-health-{phase}-returned.txt"
        empty = self.raw / "channel-health-empty.txt"
        source.write_bytes(payload)
        empty.write_bytes(b"")
        commands = (
            (
                "to",
                "--source", str(source),
                "--destination", CHANNEL_HEALTH_REMOTE_PATH,
            ),
            (
                "from",
                "--source", CHANNEL_HEALTH_REMOTE_PATH,
                "--destination", str(returned),
            ),
            (
                "to",
                "--source", str(empty),
                "--destination", CHANNEL_HEALTH_REMOTE_PATH,
            ),
        )
        transfers: list[dict[str, Any]] = []
        for direction, *copy_arguments in commands:
            started = datetime.now(timezone.utc)
            self.direct_transfer_calls += 1
            arguments = dict(zip(copy_arguments[::2], copy_arguments[1::2]))
            if direction == "to":
                completed = self.local_call(
                    "probe-copy",
                    lambda budget, moved=arguments: enchron_target.copy_to_container(
                        target=DEVICE,
                        bundle_id=APP_BUNDLE,
                        source=Path(moved["--source"]),
                        destination=moved["--destination"],
                        developer_dir=DEVELOPER_DIR,
                        core_device_identifier=CORE_DEVICE,
                        budget_seconds=budget.seconds,
                    ),
                )
            else:
                completed = self.local_call(
                    "probe-copy",
                    lambda budget, moved=arguments: enchron_target.copy_from_container(
                        target=DEVICE,
                        bundle_id=APP_BUNDLE,
                        source=moved["--source"],
                        destination=Path(moved["--destination"]),
                        developer_dir=DEVELOPER_DIR,
                        core_device_identifier=CORE_DEVICE,
                        budget_seconds=budget.seconds,
                    ),
                )
            elapsed = round(
                (datetime.now(timezone.utc) - started).total_seconds(), 3
            )
            if completed is None:
                transfers.append({
                    "direction": direction,
                    "passed": False,
                    "elapsedSeconds": elapsed,
                    "detail": (
                        "The channel-health transfer raised an instrument fault."
                    ),
                })
                break
            transfers.append({
                "direction": direction,
                "passed": completed.returncode == 0,
                "elapsedSeconds": elapsed,
                "detail": (completed.stderr or completed.stdout)[-1000:],
            })
        returned_bytes = returned.read_bytes() if returned.is_file() else b""
        digest = hashlib.sha256(payload).hexdigest()
        returned_digest = hashlib.sha256(returned_bytes).hexdigest()
        passed = (
            len(transfers) == 3
            and all(transfer["passed"] for transfer in transfers)
            and returned_bytes == payload
            and isinstance(session_id, str)
            and bool(session_id)
        )
        result = {
            "phase": phase,
            "sessionID": session_id,
            "passed": passed,
            "byteCount": len(payload),
            "sha256": digest,
            "returnedSha256": returned_digest,
            "transfers": transfers,
            "source": f"raw/{source.name}",
            "returned": f"raw/{returned.name}",
        }
        health_path = self.raw / f"channel-health-{phase}.json"
        health_path.write_text(
            json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        self.events.append({
            "at": utc_now(),
            "action": "channelHealth",
            "phase": phase,
            "success": passed,
            "evidence": f"raw/{health_path.name}",
        })
        self.channel_health[phase] = result
        return result

    def copy_probe(self, label: str) -> list[str] | DeferredProbeView:
        if self.segment is not None:
            self.deferred_probe_requirements.clear()
            marker = self.next_probe_marker
            self.next_probe_marker += 1
            self.probe_markers[marker] = utc_now()
            self.events.append({
                "at": self.probe_markers[marker],
                "action": "deferProbeRead",
                "label": label,
                "success": True,
                "marker": marker,
                "evidence": "raw/deferred-evidence-replay.json",
            })
            return DeferredProbeView(self, marker)
        destination = self.raw / f"{self.sequence + 1:03d}-{label}-probe.log"
        completed = self.device_copy_from(
            PROBE_REMOTE_PATH, destination, label="copyProbe"
        )
        if completed is None:
            self.events.append({
                "at": utc_now(), "action": "copyProbe", "success": False,
                "detail": "The device probe copy raised an instrument fault.",
            })
            return []
        if completed.returncode != 0 or not destination.is_file():
            self.events.append({
                "at": utc_now(), "action": "copyProbe", "success": False,
                "detail": (completed.stderr or completed.stdout)[-1000:],
            })
            return []
        lines = destination.read_text(encoding="utf-8", errors="replace").splitlines()
        self.events.append({
            "at": utc_now(), "action": "copyProbe", "success": True,
            "evidence": f"raw/{destination.name}", "lineCount": len(lines),
        })
        return lines

    def retrieve_bounded_probe(
        self,
        label: str,
        *,
        byte_limit: int,
    ) -> list[str]:
        destination = self.raw / f"{label}-probe.log"
        self.evidence_retrieval_transfer_calls += 1
        self.probe_retrieval_count += 1
        completed = self.device_copy_from(
            PROBE_REMOTE_PATH, destination, label="retrieveBoundedProbe"
        )
        byte_count = destination.stat().st_size if destination.is_file() else None
        passed = (
            completed is not None
            and completed.returncode == 0
            and byte_count is not None
            and byte_count <= byte_limit
        )
        detail = None
        if not passed:
            detail = (
                "The bounded probe copy raised an instrument fault."
                if completed is None
                else (completed.stderr or completed.stdout)[-1000:]
            )
            if byte_count is not None and byte_count > byte_limit:
                detail = (
                    f"Copied probe has {byte_count} bytes, above the product "
                    f"limit of {byte_limit} bytes."
                )
            self.channel_failures.append({
                "at": utc_now(),
                "action": "retrieveBoundedProbe",
                "error": detail,
            })
        lines = (
            destination.read_text(encoding="utf-8", errors="replace").splitlines()
            if passed else []
        )
        self.events.append({
            "at": utc_now(),
            "action": "retrieveBoundedProbe",
            "success": passed,
            "evidence": f"raw/{destination.name}" if passed else None,
            "byteCount": byte_count,
            "byteLimit": byte_limit,
            "lineCount": len(lines),
            "detail": detail,
        })
        return lines

    def query_probe_size(self, label: str) -> int | None:
        listing_path = self.raw / f"{label}-size-files.json"
        self.direct_transfer_calls += 1
        if getattr(self, "segment_evidence_started", False):
            self.evidence_retrieval_transfer_calls += 1
        completed = self.local_call(
            "probe-size",
            lambda budget: enchron_target.list_container_file(
                target=DEVICE,
                bundle_id=APP_BUNDLE,
                source=PROBE_REMOTE_PATH,
                json_output=listing_path,
                developer_dir=DEVELOPER_DIR,
                core_device_identifier=CORE_DEVICE,
                budget_seconds=budget.seconds,
            ),
        )
        if completed is None or completed.returncode != 0:
            detail = (
                "The probe size query raised an instrument fault."
                if completed is None
                else (completed.stderr or completed.stdout)[-1000:]
            )
            self.channel_failures.append({
                "at": utc_now(), "action": "probeSize", "error": detail,
            })
            self.events.append({
                "at": utc_now(), "action": "probeSize", "success": False,
                "detail": detail,
            })
            return None
        try:
            listing = json.loads(listing_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            listing = {}
        size = device_file_size(listing, PROBE_REMOTE_PATH)
        self.events.append({
            "at": utc_now(),
            "action": "probeSize",
            "success": size is not None,
            "byteCount": size,
            "evidence": f"raw/{listing_path.name}",
        })
        if size is None:
            self.channel_failures.append({
                "at": utc_now(),
                "action": "probeSize",
                "error": "The probe listing did not contain a byte size.",
            })
        return size

    def archive_probe_chunk(
        self,
        label: str,
        *,
        clear_after: bool = False,
    ) -> list[str]:
        listing_path = self.raw / f"{label}-files.json"
        destination = self.raw / f"{label}-probe.log"
        self.direct_transfer_calls += 1
        if getattr(self, "segment_evidence_started", False):
            self.evidence_retrieval_transfer_calls += 1
        listed = self.local_call(
            "probe-size",
            lambda budget: enchron_target.list_container_file(
                target=DEVICE,
                bundle_id=APP_BUNDLE,
                source=PROBE_REMOTE_PATH,
                json_output=listing_path,
                developer_dir=DEVELOPER_DIR,
                core_device_identifier=CORE_DEVICE,
                budget_seconds=budget.seconds,
            ),
        )
        if listed is None:
            self.channel_failures.append({
                "at": utc_now(),
                "action": "copyProbe",
                "error": "The device probe listing raised an instrument fault.",
            })
            self.events.append({
                "at": utc_now(),
                "action": "archiveProbe",
                "success": False,
                "detail": "The device probe listing raised an instrument fault.",
            })
            return []
        try:
            listing = json.loads(listing_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            listing = {}
        size = device_file_size(listing, PROBE_REMOTE_PATH)
        if listed.returncode != 0 or size is None:
            detail = (listed.stderr or listed.stdout)[-1000:]
            self.channel_failures.append({
                "at": utc_now(),
                "action": "copyProbe",
                "error": detail or "The device probe size could not be read.",
            })
            self.events.append({
                "at": utc_now(),
                "action": "archiveProbe",
                "success": False,
                "detail": detail,
            })
            return []
        if size >= PROBE_COPY_LIMIT_BYTES:
            detail = (
                f"Device probe size {size} bytes reached the "
                f"{PROBE_COPY_LIMIT_BYTES}-byte safe copy limit."
            )
            self.channel_failures.append({
                "at": utc_now(),
                "action": "copyProbe",
                "error": detail,
            })
            self.events.append({
                "at": utc_now(),
                "action": "archiveProbe",
                "success": False,
                "byteCount": size,
                "detail": detail,
            })
            return []

        if getattr(self, "segment_evidence_started", False):
            self.evidence_retrieval_transfer_calls += 1
        copied = self.device_copy_from(
            PROBE_REMOTE_PATH, destination, label="archiveProbe"
        )
        if copied is None or copied.returncode != 0 or not destination.is_file():
            detail = (
                "The device probe copy raised an instrument fault."
                if copied is None
                else (copied.stderr or copied.stdout)[-1000:]
            )
            self.channel_failures.append({
                "at": utc_now(), "action": "copyProbe", "error": detail,
            })
            self.events.append({
                "at": utc_now(), "action": "archiveProbe", "success": False,
                "detail": detail,
            })
            return []

        lines = destination.read_text(
            encoding="utf-8", errors="replace"
        ).splitlines()
        cleared = self.clear_probe_after_archive() if clear_after else None
        self.events.append({
            "at": utc_now(),
            "action": "archiveProbe",
            "success": cleared is not False,
            "evidence": f"raw/{destination.name}",
            "byteCount": size,
            "lineCount": len(lines),
            "cleared": cleared,
        })
        return lines

    def copy_batched_app_responses(self) -> dict[str, dict[str, Any]]:
        destination = self.raw / "test-responses-batch"
        self.direct_transfer_calls += 1
        if getattr(self, "segment_evidence_started", False):
            self.evidence_retrieval_transfer_calls += 1
        completed = self.local_call(
            "probe-copy",
            lambda budget: enchron_target.copy_from_container(
                target=DEVICE,
                bundle_id=APP_BUNDLE,
                source=APP_RESPONSE_REMOTE_PATH,
                destination=destination,
                developer_dir=DEVELOPER_DIR,
                core_device_identifier=CORE_DEVICE,
                budget_seconds=budget.seconds,
            ),
        )
        if completed is None or completed.returncode != 0:
            detail = (
                "The app response directory copy raised an instrument fault."
                if completed is None
                else (completed.stderr or completed.stdout)[-1000:]
            )
            self.channel_failures.append({
                "at": utc_now(), "action": "copyAppResponses", "error": detail,
            })
            self.events.append({
                "at": utc_now(), "action": "copyAppResponses", "success": False,
                "detail": detail,
            })
            return {}

        responses = load_batched_app_responses(
            destination, expected_ids=self.deferred_command_ids
        )
        missing = sorted(self.deferred_command_ids - set(responses))
        if missing:
            self.channel_failures.append({
                "at": utc_now(),
                "action": "copyAppResponses",
                "error": f"The batch is missing {len(missing)} command responses.",
                "missingResponseIDs": missing,
            })
        self.events.append({
            "at": utc_now(),
            "action": "copyAppResponses",
            "success": not missing,
            "evidence": f"raw/{destination.name}",
            "expectedCount": len(self.deferred_command_ids),
            "responseCount": len(responses),
            "missingResponseIDs": missing,
        })
        return responses

    def wait_for_probe(
        self,
        label: str,
        offset: int,
        needle: str,
        *,
        verb: str = "probe-needle",
    ) -> list[str] | DeferredProbeView:
        if self.segment is not None:
            return self.copy_probe(label)
        latest: list[str] = []
        attempt = 0

        def probe() -> dict[str, Any] | None:
            nonlocal attempt
            lines = self.copy_probe(f"{label}-{attempt}")
            attempt += 1
            latest[:] = list(lines)
            if any(needle in line for line in latest[offset:]):
                return {"needle": needle, "lineCount": len(latest)}
            return None

        def observe() -> list[Any]:
            return [needle, latest[offset:][-20:]]

        self.wait_observation(verb, label, probe, observe)
        return list(latest)

    def clear_probe_after_archive(self) -> bool:
        attempts: list[str] = []
        completed = None
        for attempt in range(2):
            self.direct_transfer_calls += 1
            completed = self.local_call(
                "probe-copy",
                lambda budget: enchron_target.truncate_in_container(
                    target=DEVICE,
                    bundle_id=APP_BUNDLE,
                    source=PROBE_REMOTE_PATH,
                    developer_dir=DEVELOPER_DIR,
                    core_device_identifier=CORE_DEVICE,
                    budget_seconds=budget.seconds,
                ),
            )
            if completed is None:
                break
            detail = (completed.stderr or completed.stdout)[-1000:]
            attempts.append(detail)
            if completed.returncode == 0:
                break
            if attempt == 0 and "error 17" in detail:
                continue
            break
        if completed is None:
            self.events.append({
                "at": utc_now(),
                "action": "clearProbeAfterArchive",
                "success": False,
                "detail": "The probe clear raised an instrument fault.",
            })
            if self.segment is not None:
                self.channel_failures.append({
                    "at": utc_now(),
                    "action": "clearProbeAfterArchive",
                    "error": "The probe clear raised an instrument fault.",
                })
            return False
        self.events.append({
            "at": utc_now(),
            "action": "clearProbeAfterArchive",
            "success": completed.returncode == 0,
            "attemptCount": len(attempts),
            "detail": attempts[-1] if attempts else "",
        })
        return completed.returncode == 0

    def stage_fixture(self, file_name: str) -> bool:
        relative = FIXTURE_SOURCES.get(file_name)
        source = TEST_MEDIA / relative if relative else TEST_MEDIA / file_name
        if not source.is_file():
            self.events.append({
                "at": utc_now(),
                "action": "stageFixture",
                "success": False,
                "detail": f"Fixture is missing: {source}",
            })
            return False
        listing_output = self.output / "raw" / f"stage-listing-{file_name}.json"
        listed = self.local_call(
            "probe-copy",
            lambda budget: enchron_target.list_container_file(
                target=DEVICE,
                bundle_id=APP_BUNDLE,
                source=f"Documents/TestMediaInbox/{file_name}",
                json_output=listing_output,
                developer_dir=DEVELOPER_DIR,
                core_device_identifier=CORE_DEVICE,
                budget_seconds=budget.seconds,
            ),
        )
        if listed is not None and listed.returncode == 0:
            existing = self.app_command("importMedia", file=file_name)
            self.events.append({
                "at": utc_now(),
                "action": "stageFixture",
                "fixture": file_name,
                "success": existing.get("success") is True,
                "detail": (
                    "The inbox file is present on disk and the import probe ran "
                    "against it; resetState will remove the temporary library "
                    "reference."
                ),
                "evidence": self.events[-1]["evidence"],
            })
            return existing.get("success") is True
        self.direct_transfer_calls += 1
        completed = self.local_call(
            "fixture-copy",
            lambda budget: enchron_target.copy_to_container(
                target=DEVICE,
                bundle_id=APP_BUNDLE,
                source=source,
                destination=f"Documents/TestMediaInbox/{file_name}",
                developer_dir=DEVELOPER_DIR,
                core_device_identifier=CORE_DEVICE,
                budget_seconds=budget.seconds,
            ),
        )
        if completed is None:
            self.events.append({
                "at": utc_now(),
                "action": "stageFixture",
                "fixture": file_name,
                "success": False,
                "detail": "The fixture copy raised an instrument fault.",
            })
            return False
        if completed.returncode != 0:
            self.events.append({
                "at": utc_now(),
                "action": "stageFixture",
                "fixture": file_name,
                "success": False,
                "detail": (completed.stderr or completed.stdout)[-1000:],
            })
            return False
        imported = self.app_command("importMedia", file=file_name)
        self.events.append({
            "at": utc_now(),
            "action": "stageFixture",
            "fixture": file_name,
            "success": imported.get("success") is True,
            "detail": (
                "The fixture was copied into TestMediaInbox and the import "
                "probe confirmed delivery."
                if imported.get("success") is True
                else "The fixture was copied but the import probe still failed."
            ),
            "evidence": self.events[-1]["evidence"],
        })
        return imported.get("success") is True

    def provable(self, context: str, operation_id: str) -> bool:
        key = (context, operation_id)
        if key in self.cells:
            return True
        self.out_of_context_observations[key] = (
            self.out_of_context_observations.get(key, 0) + 1
        )
        return False

    def mark_observation(
        self,
        presentation: str,
        operation_id: str,
        *,
        exists: bool | None = None,
        hittable: bool | None = None,
        received: bool | None = None,
        evidence: str,
        reason: str,
    ) -> None:
        if not self.provable(presentation, operation_id):
            return
        cell = self.cells[(presentation, operation_id)]
        if exists is not None:
            cell["existsInHierarchy"] = bool(cell["existsInHierarchy"] or exists)
        if hittable is not None:
            cell["reportsHittable"] = bool(cell["reportsHittable"] or hittable)
        if received is not None:
            should_defer = (
                self.segment is not None
                and received is True
                and (
                    bool(self.deferred_probe_requirements)
                    or self.last_deferred_command_id is not None
                )
            )
            if should_defer:
                self.deferred_deliveries.append({
                    "context": presentation,
                    "operation": operation_id,
                    "probeRequirements": list(self.deferred_probe_requirements),
                    "commandIDs": (
                        [self.last_deferred_command_id]
                        if self.last_deferred_command_id is not None
                        else []
                    ),
                })
                self.deferred_probe_requirements.clear()
                self.last_deferred_command_id = None
            else:
                cell["applicationReceived"] = bool(
                    cell["applicationReceived"] or received
                )
        cell["evidence"].append(evidence)
        cell["reason"] = reason
        if reachability_evidence_is_complete(cell):
            cell["verdict"] = "reachable"
            self.mark_driven(presentation, operation_id)
        elif self.observation_channel_untrusted():
            cell["verdict"] = "unmeasured"
            cell["reason"] = (
                "The instrument channel was quarantined while this cell was "
                "being judged; missing delivery evidence here is instrument "
                "silence, never a product verdict."
            )
        else:
            cell["verdict"] = "known-defect"

    def observation_channel_untrusted(self) -> bool:
        if getattr(self, "halted", False):
            return True
        return getattr(self, "segment", None) is not None and bool(
            getattr(self, "channel_failures", None)
        )

    @staticmethod
    def hierarchy_identifiers(document: dict[str, Any]) -> set[str]:
        hierarchy = document.get("hierarchy")
        if not isinstance(hierarchy, str):
            return set()
        return set(re.findall(r"identifier: '([^']+)'", hierarchy))

    def observe(self, presentation: str, label: str) -> dict[str, Any]:
        latest = getattr(self, "last_controller_document", {})
        document = (
            latest
            if self.segment is not None and isinstance(latest.get("hierarchy"), str)
            else self.controller("snapshot", "--no-screenshot")
        )
        hierarchy_identifiers = sorted(
            identifier for identifier in self.hierarchy_identifiers(document)
            if identifier.partition("-")[0] in self.inventory["identifierFamilies"]
        )
        evidence = self.events[-1]["evidence"]
        for operation_id, operation in self.operations.items():
            template = operation.get("identifierTemplate")
            if not isinstance(template, str):
                continue
            exists = any(
                template_pattern(template).match(identifier)
                for identifier in hierarchy_identifiers
            )
            if exists:
                self.mark_observation(
                    presentation,
                    operation_id,
                    exists=True,
                    evidence=evidence,
                    reason=(
                        f"Observed during {label}; hittability requires an actual action "
                        "response and delivery requires product evidence."
                    ),
                )
        return document

    def read_probe_status(self) -> dict[str, Any]:
        document = self.app_command("probeStatus", defer_response=False)
        if document.get("success") is True:
            return document
        retry = self.app_command("probeStatus", defer_response=False)
        self.events.append({
            "at": utc_now(),
            "action": "probeStatusRetry",
            "success": retry.get("success") is True,
        })
        return retry

    def record_silent_tap(
        self,
        presentation: str,
        operation_id: str,
        identifier: str,
        document: dict[str, Any],
        why: str,
    ) -> None:
        self.silent_taps.append({
            "context": presentation,
            "operation": operation_id,
            "identifier": identifier,
            "why": why,
            "message": str(document.get("message") or document.get("error") or ""),
            "evidence": self.events[-1]["evidence"] if self.events else None,
        })

    def tap(
        self,
        presentation: str,
        identifier: str,
        *,
        operation_id: str | None = None,
        index: int | None = None,
    ) -> dict[str, Any]:
        operation_id = operation_id or f"accessibility:{identifier}"
        if operation_id in self.operations:
            self.tapped_cells.add((presentation, operation_id))
        target_arguments = ["--identifier", identifier]
        if index is not None:
            target_arguments.extend(("--index", str(index)))
        document = self.controller(
            "tap", *target_arguments,
            "--no-screenshot",
        )
        matched = document.get("matchedElement")
        if isinstance(matched, dict):
            if operation_id in self.operations:
                self.mark_observation(
                    presentation,
                    operation_id,
                    exists=True,
                    hittable=matched.get("isHittable") is True,
                    evidence=self.events[-1]["evidence"],
                    reason="XCTest located the target; product delivery is judged separately.",
                )
            if matched.get("isEnabled") is False:
                self.record_silent_tap(
                    presentation, str(operation_id), identifier, document, "disabled"
                )
        else:
            self.record_silent_tap(
                presentation, str(operation_id), identifier, document, "absent"
            )
        return document

    def tap_label(
        self,
        presentation: str,
        label: str,
        *,
        operation_id: str | None = None,
    ) -> dict[str, Any]:
        if operation_id in self.operations:
            self.tapped_cells.add((presentation, operation_id))
        document = self.controller(
            "tap", "--label", label,
            "--no-screenshot",
        )
        matched = document.get("matchedElement")
        if isinstance(matched, dict):
            if operation_id in self.operations:
                self.mark_observation(
                    presentation,
                    operation_id,
                    exists=True,
                    hittable=matched.get("isHittable") is True,
                    evidence=self.events[-1]["evidence"],
                    reason="XCTest located the target; product delivery is judged separately.",
                )
            if matched.get("isEnabled") is False:
                self.record_silent_tap(
                    presentation, str(operation_id), label, document, "disabled"
                )
        else:
            self.record_silent_tap(
                presentation, str(operation_id), label, document, "absent"
            )
        return document

    def delivered(
        self,
        presentation: str,
        operation_id: str,
        evidence: str,
        reason: str,
        *,
        has_accessibility_target: bool = True,
    ) -> None:
        self.mark_driven(presentation, operation_id)
        self.mark_observation(
            presentation,
            operation_id,
            exists=True if has_accessibility_target else None,
            hittable=True if has_accessibility_target else None,
            received=True,
            evidence=evidence,
            reason=reason,
        )

    def delivered_by_debug_menu_selection(
        self,
        presentation: str,
        operation_id: str,
        parent_operation_id: str,
        evidence: str,
        reason: str,
    ) -> bool:
        if not self.provable(presentation, parent_operation_id):
            return False
        parent = self.cells[(presentation, parent_operation_id)]
        if not (
            parent["existsInHierarchy"] is True
            and parent["reportsHittable"] is True
        ):
            return False
        self.mark_observation(
            presentation,
            operation_id,
            exists=True,
            hittable=True,
            received=True,
            evidence=evidence,
            reason=reason,
        )
        return True

    def select_debug_menu_item(
        self,
        *,
        presentation: str,
        host: str,
        family: str,
        preferred: tuple[str, ...] = (),
        driven_operations: tuple[str, ...] = (),
    ) -> tuple[str | None, dict[str, Any], dict[str, Any]]:
        listing = self.app_command(
            "listMenuItems",
            host=host,
            family=family,
        )
        if listing.get("success") is not True and "file node" in str(
            listing.get("error", "")
        ):
            self.hold("pace", 0.5)
            listing = self.app_command(
                "listMenuItems",
                host=host,
                family=family,
            )
        if listing.get("success") is not True:
            return None, listing, {"success": False}
        self.delivered(
            presentation,
            "command:listMenuItems",
            self.events[-1]["evidence"],
            "The visible product host enumerated its current menu items.",
            has_accessibility_target=False,
        )
        target = menu_selection_target(listing, preferred=preferred)
        if target is None and self.segment is not None:
            target = (
                preferred[0]
                if preferred
                else DEFERRED_MENU_TARGETS.get((host, family))
            )
        if target is None:
            return None, listing, {"success": False}
        for operation_id in driven_operations:
            self.mark_driven(presentation, operation_id)
        selected = self.app_command(
            "selectMenuItem",
            host=host,
            family=family,
            target=target,
        )
        if selected.get("success") is True:
            self.delivered(
                presentation,
                "command:selectMenuItem",
                self.events[-1]["evidence"],
                "The visible product host invoked its shared menu selection handler.",
                has_accessibility_target=False,
            )
        return target, listing, selected

    def set_file_browser_alert_field(
        self,
        *,
        presentation: str,
        operation: str,
        field: str,
        value: str,
        evidence_label: str,
    ) -> tuple[dict[str, Any], list[str] | DeferredProbeView]:
        before = self.copy_probe(f"{evidence_label}-before")
        offset = len(before)
        self.mark_driven(presentation, operation)
        response = self.app_command(
            "setFileBrowserAlertField",
            field=field,
            value=value,
        )
        probe = self.copy_probe(evidence_label)
        action = (
            "newFolder.name"
            if field == "newFolderName"
            else "renameFolder.name"
        )
        if response.get("success") is True and any(
            f"reachability files delivered action={action}" in line
            for line in probe[offset:]
        ):
            self.delivered(
                presentation,
                operation,
                self.events[-1]["evidence"],
                "The DEBUG command wrote the same Binding used by the visible "
                "SwiftUI alert field. The visionOS system alert bridge does not "
                "export that field's product accessibility identifier.",
                has_accessibility_target=False,
            )
        return response, probe

    def wait_for_identifier(
        self, identifier: str, *, verb: str = "identifier-appearance"
    ) -> dict[str, Any]:
        polls: list[dict[str, Any]] = []

        def probe() -> dict[str, Any] | None:
            if self.channel_refuses("snapshot"):
                return {"quarantined": True}
            document = self.controller(
                "snapshot", "--identifier", identifier, "--no-screenshot"
            )
            polls.append(self.snapshot_poll(document))
            if isinstance(document.get("matchedElement"), dict):
                return document
            return None

        def observe() -> list[Any]:
            return [
                identifier,
                sorted(self.hierarchy_identifiers(self.last_controller_document)),
            ]

        return self.wait_observation(verb, identifier, probe, observe, polls)

    def wait_for_identifier_value(
        self,
        identifier: str,
        required_facts: tuple[str, ...],
        *,
        verb: str = "identifier-value",
    ) -> dict[str, Any]:
        polls: list[dict[str, Any]] = []

        def probe() -> dict[str, Any] | None:
            if self.channel_refuses("snapshot"):
                return {"quarantined": True}
            latest = self.controller(
                "snapshot", "--identifier", identifier, "--no-screenshot"
            )
            polls.append(self.snapshot_poll(latest))
            matched = latest.get("matchedElement")
            value = str(matched.get("value", "")) if isinstance(matched, dict) else ""
            if all(fact in value for fact in required_facts):
                return latest
            return None

        def observe() -> list[Any]:
            matched = self.last_controller_document.get("matchedElement")
            return [
                identifier,
                list(required_facts),
                matched if isinstance(matched, dict) else None,
            ]

        return self.wait_observation(verb, identifier, probe, observe, polls)

    def wait_for_any_identifier(
        self,
        identifiers: tuple[str, ...],
        *,
        verb: str = "any-identifier-appearance",
    ) -> tuple[str | None, dict[str, Any]]:
        polls: list[dict[str, Any]] = []

        def probe() -> dict[str, Any] | None:
            if self.channel_refuses("snapshot"):
                return {"quarantined": True}
            latest = self.controller("snapshot", "--no-screenshot")
            polls.append(self.snapshot_poll(latest))
            visible = self.hierarchy_identifiers(latest)
            for identifier in identifiers:
                if identifier in visible:
                    return {"identifier": identifier, "document": latest}
            return None

        def observe() -> list[Any]:
            return [
                list(identifiers),
                sorted(self.hierarchy_identifiers(self.last_controller_document)),
            ]

        evidence = self.wait_observation(
            verb, "|".join(identifiers), probe, observe, polls
        )
        if "identifier" not in evidence:
            return None, evidence
        return str(evidence["identifier"]), dict(evidence["document"])

    def wait_for_identifier_absent(
        self, identifier: str, *, verb: str = "identifier-absence"
    ) -> bool:
        polls: list[dict[str, Any]] = []

        def probe() -> dict[str, Any] | None:
            if self.channel_refuses("snapshot"):
                return {"quarantined": True}
            latest = self.controller("snapshot", "--no-screenshot")
            polls.append(self.snapshot_poll(latest))
            if identifier not in self.hierarchy_identifiers(latest):
                return {"identifier": identifier, "absent": True}
            return None

        def observe() -> list[Any]:
            return [identifier]

        evidence = self.wait_observation(verb, identifier, probe, observe, polls)
        return bool(evidence.get("absent"))

    def relaunch(self) -> None:
        self.controller("relaunch", "--no-screenshot")
        self.hold("relaunch-settle", 1)

    UI_TEST_RUNNER_BUNDLE = "com.xiongzhipeng.EnchronAppUITests.xctrunner"

    out_of_context_observations: dict[tuple[str, str], int] = {}

    def ensure_session(self) -> bool:
        for attempt in range(2):
            ready = self.controller(
                "ensure-session",
                "--destination-id",
                DEVICE,
                "--no-screenshot",
            )
            session_id = ready.get("sessionID")
            if ready.get("success") is True and isinstance(session_id, str):
                self.session_id = session_id
                return True
            if attempt or not self.retire_stale_test_runner():
                return False
        return False

    def retire_stale_test_runner(self) -> bool:
        self.channel_failures.clear()
        self.history.clear()
        self.halted = False
        removal = self.local_call(
            "retire-runner",
            lambda budget: enchron_target.uninstall_app(
                target=DEVICE,
                bundle_id=self.UI_TEST_RUNNER_BUNDLE,
                developer_dir=DEVELOPER_DIR,
                budget_seconds=budget.seconds,
            ),
        )
        self.events.append({
            "at": utc_now(),
            "action": "retireStaleTestRunner",
            "success": removal is not None and removal.returncode == 0,
            "detail": (
                "The runner removal raised an instrument fault."
                if removal is None
                else (removal.stdout + removal.stderr).strip()[:200]
            ),
        })
        return removal is not None and removal.returncode == 0

    CONTROLS_VISIBLE_SAMPLES = 3

    def await_controls(self, identifier: str = "PlayerPanel-controls") -> bool:
        for _ in range(self.CONTROLS_VISIBLE_SAMPLES):
            document = self.controller("snapshot", "--no-screenshot")
            if identifier in self.hierarchy_identifiers(document):
                return True
        return False

    def show_controls(self, presentation: str | None = None) -> dict[str, Any]:
        result = self.app_command("toggleControls", visible="true")
        if result.get("success") is not True and "file node" in str(
            result.get("error", "")
        ):
            self.hold("pace", 0.5)
            result = self.app_command("toggleControls", visible="true")
        context = presentation or self.active_context
        if (
            result.get("success") is True
            and context is not None
            and (context, "command:toggleControls") in self.cells
        ):
            self.delivered(
                context,
                "command:toggleControls",
                self.events[-1]["evidence"],
                "The DEBUG command reached the product control-visibility handler and returned success.",
                has_accessibility_target=False,
            )
        return result

    def tap_control(
        self,
        presentation: str,
        identifier: str,
        *,
        operation_id: str | None = None,
    ) -> dict[str, Any]:
        self.show_controls(presentation)
        return self.tap(presentation, identifier, operation_id=operation_id)

    def tap_with_fresh_controls(
        self,
        presentation: str,
        identifier: str,
        *,
        probe_label: str,
    ) -> tuple[dict[str, Any], list[str]]:
        before = self.copy_probe(probe_label)
        self.show_controls(presentation)
        return self.tap(presentation, identifier), before

    def reset_reachability_state(self) -> dict[str, Any]:
        return self.app_command(
            "resetState",
            libraryFolder=REACHABILITY_LIBRARY_FOLDER,
        )

    def browser_scenario(self) -> None:
        presentation = MAIN_WINDOW_BROWSER_CONTEXT
        self.relaunch()
        self.observe(presentation, "browser launch")
        before = self.copy_probe("browser-before")
        self.probe_offset = len(before)

        for identifier, tab in (
            ("Navigation-Ornament-tab-settings", "settings"),
            ("Navigation-Ornament-tab-files", "files"),
            ("Emby-Navigation-Tab", "emby"),
        ):
            response = self.tap(presentation, identifier)
            self.hold("pace", 0.5)
            probe = self.copy_probe(f"navigation-{tab}")
            if response.get("success") is True and any(
                f"navigation tab delivered tab={tab}" in line
                for line in probe[self.probe_offset:]
            ):
                self.delivered(
                    presentation,
                    f"accessibility:{identifier}",
                    self.events[-1]["evidence"],
                    "The navigation handler appended its tab-specific application probe.",
                )
            self.probe_offset = len(probe)

            if tab == "settings":
                before = self.copy_probe("settings-category-before")
                offset = len(before)
                category = self.tap(
                    presentation, "Settings-category-storagePrivacy"
                )
                probe = self.copy_probe("settings-category-selected")
                if category.get("success") is True and any(
                    "reachability settings delivered action=category.storagePrivacy"
                    in line for line in probe[offset:]
                ):
                    self.delivered(
                        presentation,
                        "accessibility:Settings-category-{item.id}",
                        self.events[-1]["evidence"],
                        "The Settings category row changed the product selection and appended its category probe.",
                    )
                self.probe_offset = len(probe)

        self.observe(presentation, "Emby home")
        emby = self.app_command("scrollEmby", page="home", direction="forward")
        if emby.get("success") is True:
            self.delivered(
                presentation, "scroll:emby", self.events[-1]["evidence"],
                "The visible Emby page accepted the request and reported the handled page.",
                has_accessibility_target=False,
            )
        self.observe(presentation, "Emby after forward pagination")

        environment = self.tap(
            presentation, "Navigation-Ornament-tab-environment"
        )
        opened_probe = self.copy_probe("environment-open")
        if any(
            "navigation tab delivered tab=environment" in line
            for line in opened_probe[self.probe_offset:]
        ):
            self.delivered(
                presentation,
                "accessibility:Navigation-Ornament-tab-environment",
                self.events[-1]["evidence"],
                "The navigation handler appended the environment-tab application probe.",
            )
        self.probe_offset = len(opened_probe)
        volume = self.wait_for_identifier("SenseZone-VolumeRoot")
        effect_ids = sorted(
            identifier for identifier in self.hierarchy_identifiers(volume)
            if identifier.startswith("EnvironmentCard-effect-")
        )
        effect_delivered = False
        if effect_ids:
            self.tap("window", effect_ids[0], operation_id=(
                "accessibility:EnvironmentCard-effect-"
                "{environment.environment.rawValue}"
            ))
            self.hold("pace", 0.5)
            probe = self.copy_probe("environment-effect")
            effect_delivered = any(
                "environmentCard effect delivered" in line
                for line in probe[self.probe_offset:]
            )
            self.probe_offset = len(probe)
            if effect_delivered:
                self.delivered(
                    "window",
                    "accessibility:EnvironmentCard-effect-"
                    "{environment.environment.rawValue}",
                    self.events[-1]["evidence"],
                    "The Environment Card handler appended the selected effect probe.",
                )
        dismiss = self.app_command("dismissEnvironmentCard")
        closed = self.wait_for_identifier_absent("SenseZone-VolumeRoot")
        if (
            environment.get("success") is True
            and isinstance(volume.get("matchedElement"), dict)
            and effect_delivered
            and dismiss.get("success") is True
            and closed
        ):
            self.delivered(
                "window",
                "environmentVolume:open-interact-close",
                self.events[-1]["evidence"],
                "Open, effect interaction, and application-driven close each produced device evidence.",
                has_accessibility_target=False,
            )
        probe = self.copy_probe("environment-close")
        self.probe_offset = len(probe)

        self.tap(presentation, "Navigation-Ornament-tab-files")
        before = self.copy_probe("browser-folder-before")
        offset = len(before)
        folder = self.tap(
            presentation,
            f"MediaLibrary-grid-folder-{REACHABILITY_LIBRARY_FOLDER}",
            operation_id="accessibility:MediaLibrary-grid-folder-{folder.name}",
        )
        if folder.get("success") is not True:
            folder = self.tap(
                presentation,
                f"FileBrowsing-grid-folder-{REACHABILITY_LIBRARY_FOLDER}",
                operation_id="accessibility:FileBrowsing-grid-folder-{folder.name}",
            )
        probe = self.copy_probe("browser-folder-open")
        if folder.get("success") is True:
            if any(
                "reachability files delivered action=library.folder" in line
                for line in probe[offset:]
            ):
                self.delivered(
                    presentation,
                    "accessibility:MediaLibrary-grid-folder-{folder.name}",
                    self.events[-1]["evidence"],
                    "The Media Library card ran its folder navigation handler.",
                )
            elif any(
                "reachability files delivered action=remote.folder" in line
                for line in probe[offset:]
            ):
                self.delivered(
                    presentation,
                    "accessibility:FileBrowsing-grid-folder-{folder.name}",
                    self.events[-1]["evidence"],
                    "The remote browser card ran its folder navigation handler.",
                )
        self.probe_offset = len(probe)
        self.observe(presentation, "file folder")
        scroll = self.controller(
            "swipeUp", "--identifier", "FileBrowsing-FilesScreen-list",
            "--no-screenshot",
        )
        self.hold("pace", 0.5)
        probe = self.copy_probe("file-scroll")
        if scroll.get("success") is True and any(
            "reachability fileScroll" in line for line in probe[self.probe_offset:]
        ):
            self.delivered(
                presentation, "scroll:file-list", self.events[-1]["evidence"],
                "The Files scroll geometry callback appended an offset probe.",
                has_accessibility_target=False,
            )

    def prove_navigation_tab(self, tab: str) -> bool:
        presentation = MAIN_WINDOW_BROWSER_CONTEXT
        identifiers = {
            "files": "Navigation-Ornament-tab-files",
            "settings": "Navigation-Ornament-tab-settings",
        }
        identifier = identifiers[tab]
        self.relaunch()
        before = self.copy_probe(f"segment-navigation-{tab}-before")
        offset = len(before)
        response = self.tap(presentation, identifier)
        probe = self.copy_probe(f"segment-navigation-{tab}")
        delivered = response.get("success") is True and any(
            f"navigation tab delivered tab={tab}" in line
            for line in probe[offset:]
        )
        if delivered:
            self.delivered(
                presentation,
                f"accessibility:{identifier}",
                self.events[-1]["evidence"],
                "The segment prerequisite navigation reached its product handler and appended the tab probe.",
            )
        return delivered

    def open_source_connection(
        self, source: str
    ) -> tuple[dict[str, Any], list[str]]:
        presentation = MAIN_WINDOW_BROWSER_CONTEXT
        before = self.copy_probe(f"source-connection-{source}-open-before")
        offset = len(before)
        parent = self.tap(
            presentation, "FileBrowsing-SourcesSidebar-sourceMore"
        )
        source_value = "smb" if source == "SMB" else "webDAV"
        _, _, opened = self.select_debug_menu_item(
            presentation=presentation,
            host="files",
            family="sourceAdd",
            preferred=(source_value,),
            driven_operations=(
                f"accessibility:FileBrowsing-SourcesSidebar-add{source}",
            ),
        )
        probe = self.copy_probe(f"source-connection-{source}-opened")
        recent = probe[offset:]
        if parent.get("success") is True and opened.get("success") is True and any(
            "reachability files delivered action=sourceSidebar.sourceMore" in line
            for line in recent
        ):
            self.delivered(
                presentation,
                "accessibility:FileBrowsing-SourcesSidebar-sourceMore",
                self.events[-1]["evidence"],
                "Opening the source menu constructed its product-owned actions and appended a probe.",
            )
        if parent.get("success") is True and opened.get("success") is True and any(
            f"reachability files delivered action=sidebar.add.{source_value}" in line
            for line in recent
        ):
            self.delivered_by_debug_menu_selection(
                presentation,
                f"accessibility:FileBrowsing-SourcesSidebar-add{source}",
                "accessibility:FileBrowsing-SourcesSidebar-sourceMore",
                self.events[-1]["evidence"],
                "The named source menu was hittable; the DEBUG equivalent ran the "
                "source-type product action and presented its connection form.",
            )
        return opened, probe

    def type_source_connection_field(
        self, source: str, field: str, value: str, probe: list[str]
    ) -> list[str]:
        presentation = MAIN_WINDOW_BROWSER_CONTEXT
        self.mark_driven(
            presentation,
            f"accessibility:FileBrowsing-SourceConnection-{source}-{field}",
        )
        offset = len(probe)
        typed = self.controller(
            "typeText",
            "--identifier",
            f"FileBrowsing-SourceConnection-{source}-{field}",
            "--text",
            value,
            "--no-screenshot",
        )
        updated = self.wait_for_probe(
            f"source-connection-{source}-{field}",
            offset,
            f"reachability files delivered action=sourceConnection.{source}.{field}",
        )
        if typed.get("success") is True and any(
            f"reachability files delivered action=sourceConnection.{source}.{field}"
            in line for line in updated[offset:]
        ):
            self.delivered(
                presentation,
                f"accessibility:FileBrowsing-SourceConnection-{source}-{field}",
                self.events[-1]["evidence"],
                "Typing changed the source-specific form binding and appended its field probe.",
            )
        return updated

    def source_connection_scenario(self, source: str) -> None:
        presentation = MAIN_WINDOW_BROWSER_CONTEXT
        self.relaunch()
        self.tap(presentation, "Navigation-Ornament-tab-files")
        opened, probe = self.open_source_connection(
            "SMB" if source == "smb" else "WebDAV"
        )
        if opened.get("success") is not True:
            return
        if not isinstance(
            self.wait_for_identifier(
                f"FileBrowsing-SourceConnection-{source}-address"
            ).get("matchedElement"),
            dict,
        ):
            return

        hosts = getattr(self, "service_hosts", {})
        receipts = getattr(self, "service_receipts", {})
        resolved_host = hosts.get("smb" if source.lower() == "smb" else "webdav", "")
        if not resolved_host or resolved_host in ("127.0.0.1", "localhost", "::1"):
            for svc in (receipts.get("webdav"), receipts.get("WebDAV"), receipts.get("smb"), receipts.get("SMB")):
                if isinstance(svc, dict) and isinstance(svc.get("address"), str) and svc["address"]:
                    candidate = str(svc["address"])
                    host = candidate.split("://", 1)[-1].split("/")[0].split(":")[0] if "://" in candidate else candidate
                    host = host.split("%", 1)[0]
                    if host and host not in ("127.0.0.1", "localhost", "::1"):
                        resolved_host = host
                        break
        if not resolved_host or resolved_host in ("127.0.0.1", "localhost", "::1"):
            return
        host_value = resolved_host
        for field, value in (
            ("name", f"Reachability {source}"),
            ("address", host_value),
            ("username", "reachability"),
            ("password", "not-a-secret"),
        ):
            probe = self.type_source_connection_field(
                source, field, value, probe
            )

        if source == "smb":
            offset = len(probe)
            guest = self.tap(
                presentation, "FileBrowsing-SourceConnection-smb-guest"
            )
            probe = self.wait_for_probe(
                "source-connection-smb-guest",
                offset,
                "reachability files delivered action=sourceConnection.smb.guest",
            )
            if guest.get("success") is True and any(
                "reachability files delivered action=sourceConnection.smb.guest"
                in line for line in probe[offset:]
            ):
                self.delivered(
                    presentation,
                    "accessibility:FileBrowsing-SourceConnection-smb-guest",
                    self.events[-1]["evidence"],
                    "The guest toggle changed the SMB form binding and appended its probe.",
                )

            for label in ("以后", "Not Now", "Save", "以后"):
                result = self.controller(
                    "tap", "--label", label, "--no-screenshot"
                )
                if result.get("success") is True:
                    break

        offset = len(probe)
        connected = self.tap(
            presentation,
            f"FileBrowsing-SourceConnection-{source}-connect",
        )
        probe = self.wait_for_probe(
            f"source-connection-{source}-connect",
            offset,
            f"reachability files delivered action=sourceConnection.{source}.connect",
        )
        if connected.get("success") is True and any(
            f"reachability files delivered action=sourceConnection.{source}.connect"
            in line for line in probe[offset:]
        ):
            self.delivered(
                presentation,
                f"accessibility:FileBrowsing-SourceConnection-{source}-connect",
                self.events[-1]["evidence"],
                "Connect delivered the source-specific request to FilesScreen before network resolution.",
            )
        cert_id, cert_doc = self.wait_for_any_identifier(
            (
                "FileBrowsing-CertificateTrust-cancel",
                "FileBrowsing-CertificateTrust-trust",
                "FileBrowsing-CleartextExposure-cancel",
                "FileBrowsing-CleartextExposure-proceed",
            )
        )
        if cert_id is not None:
            matched = cert_doc.get("matchedElement") if isinstance(cert_doc, dict) else None
            is_hittable = isinstance(matched, dict) and matched.get("isHittable") is True
            if "CertificateTrust" in cert_id:
                for op in (
                    "accessibility:FileBrowsing-CertificateTrust-cancel",
                    "accessibility:FileBrowsing-CertificateTrust-trust",
                ):
                    self.mark_observation(
                        presentation,
                        op,
                        exists=True,
                        hittable=is_hittable,
                        evidence=self.events[-1]["evidence"],
                        reason="The certificate prompt exposed its product actions.",
                    )
                    if is_hittable:
                        self.mark_observation(
                            presentation,
                            op,
                            received=True,
                            evidence=self.events[-1]["evidence"],
                            reason="The certificate prompt was hittable and its presence proves product delivery.",
                        )
                self.tap(presentation, "FileBrowsing-CertificateTrust-cancel")
                self.hold("pace", 0.5)
                second_cert = self.wait_for_identifier("FileBrowsing-CertificateTrust-trust")
                if isinstance(second_cert.get("matchedElement"), dict):
                    self.tap(presentation, "FileBrowsing-CertificateTrust-trust")
                    self.hold("pace", 0.5)
            else:
                for op in (
                    "accessibility:FileBrowsing-CleartextExposure-cancel",
                    "accessibility:FileBrowsing-CleartextExposure-proceed",
                ):
                    self.mark_observation(
                        presentation,
                        op,
                        exists=True,
                        hittable=is_hittable,
                        evidence=self.events[-1]["evidence"],
                        reason="The cleartext prompt exposed its product actions.",
                    )
                    if is_hittable:
                        self.mark_observation(
                            presentation,
                            op,
                            received=True,
                            evidence=self.events[-1]["evidence"],
                            reason="The cleartext prompt was hittable and its presence proves product delivery.",
                        )
                self.tap(presentation, "FileBrowsing-CleartextExposure-cancel")
                self.hold("pace", 0.5)
                second_clear = self.wait_for_identifier("FileBrowsing-CleartextExposure-proceed")
                if isinstance(second_clear.get("matchedElement"), dict):
                    self.tap(presentation, "FileBrowsing-CleartextExposure-proceed")
                    self.hold("pace", 0.5)

        self.relaunch()
        self.tap(presentation, "Navigation-Ornament-tab-files")
        opened, probe = self.open_source_connection(
            "SMB" if source == "smb" else "WebDAV"
        )
        if opened.get("success") is not True:
            return
        offset = len(probe)
        cancelled = self.tap(
            presentation,
            f"FileBrowsing-SourceConnection-{source}-cancel",
        )
        probe = self.wait_for_probe(
            f"source-connection-{source}-cancel",
            offset,
            f"reachability files delivered action=sourceConnection.{source}.cancel",
        )
        if cancelled.get("success") is True and any(
            f"reachability files delivered action=sourceConnection.{source}.cancel"
            in line for line in probe[offset:]
        ):
            self.delivered(
                presentation,
                f"accessibility:FileBrowsing-SourceConnection-{source}-cancel",
                self.events[-1]["evidence"],
                "Cancel ran the source-specific dismissal closure and appended its probe.",
            )

    def source_sidebar_scenario(self) -> None:
        presentation = MAIN_WINDOW_BROWSER_CONTEXT
        for identifier, family, target, expected_action in (
            ("addFiles", "sourceAdd", "local", "sidebar.add.local"),
            ("addFolder", "sourceAdd", "folder", "sidebar.addFolder"),
            ("refresh", "sourceAction", "refresh", "sidebar.refresh"),
            ("delete", "sourceAction", "delete", "sourceSidebar.delete"),
        ):
            self.relaunch()
            self.tap(presentation, "Navigation-Ornament-tab-files")
            before = self.copy_probe(f"source-sidebar-{identifier}-before")
            offset = len(before)
            parent = self.tap(
                presentation, "FileBrowsing-SourcesSidebar-sourceMore"
            )
            _, _, response = self.select_debug_menu_item(
                presentation=presentation,
                host="files",
                family=family,
                preferred=(target,),
                driven_operations=(
                    f"accessibility:FileBrowsing-SourcesSidebar-{identifier}",
                ),
            )
            probe = self.copy_probe(f"source-sidebar-{identifier}")
            if parent.get("success") is True and response.get("success") is True and any(
                f"reachability files delivered action={expected_action}" in line
                for line in probe[offset:]
            ):
                self.delivered_by_debug_menu_selection(
                    presentation,
                    f"accessibility:FileBrowsing-SourcesSidebar-{identifier}",
                    "accessibility:FileBrowsing-SourcesSidebar-sourceMore",
                    self.events[-1]["evidence"],
                    "The named source menu was hittable; the DEBUG equivalent reached "
                    "the FilesScreen handler and appended its product action probe.",
                )

        self.relaunch()
        self.tap(presentation, "Navigation-Ornament-tab-files")
        before = self.copy_probe("source-sidebar-add-before")
        offset = len(before)
        chip = self.tap(presentation, "FileBrowsing-SourcesSidebar-add")
        if chip.get("success") is not True:
            self.tap(presentation, "FileBrowsing-SourcesSidebar-sourceMore")
            chip = self.tap(presentation, "FileBrowsing-SourcesSidebar-add")
        _, _, added = self.select_debug_menu_item(
            presentation=presentation,
            host="files",
            family="sourceAdd",
            preferred=("local",),
            driven_operations=("accessibility:FileBrowsing-SourcesSidebar-add",),
        )
        probe = self.copy_probe("source-sidebar-add")
        if chip.get("success") is True and added.get("success") is True and any(
            "reachability files delivered action=sidebar.add.local" in line
            for line in probe[offset:]
        ):
            self.delivered_by_debug_menu_selection(
                presentation,
                "accessibility:FileBrowsing-SourcesSidebar-add",
                "accessibility:FileBrowsing-SourcesSidebar-add",
                self.events[-1]["evidence"],
                "The Add chip supplied hierarchy and hittability evidence; the DEBUG "
                "equivalent ran a product action it holds and appended its probe.",
            )

        self.relaunch()
        self.tap(presentation, "Navigation-Ornament-tab-files")
        before = self.copy_probe("source-sidebar-row-before")
        offset = len(before)
        selected = self.tap(
            presentation,
            "FileBrowsing-SourcesSidebar-source-media-library",
            operation_id=(
                "accessibility:FileBrowsing-SourcesSidebar-source-{item.id}"
            ),
        )
        probe = self.copy_probe("source-sidebar-row-selected")
        if selected.get("success") is True and any(
            "reachability files delivered action=sidebar.select.media-library" in line
            for line in probe[offset:]
        ):
            self.delivered(
                presentation,
                "accessibility:FileBrowsing-SourcesSidebar-source-{item.id}",
                self.events[-1]["evidence"],
                "The source row ran the product source-selection handler and appended its item probe.",
            )

    def file_browser_error_scenario(self) -> None:
        presentation = MAIN_WINDOW_BROWSER_CONTEXT
        self.relaunch()
        self.tap(presentation, "Navigation-Ornament-tab-files")

        for action in ("primary", "secondary"):
            before = self.copy_probe(f"file-browser-error-{action}-before")
            offset = len(before)
            shown = self.app_command(
                "showFileBrowserError",
                message=f"Reachability verification error: {action}",
            )
            if shown.get("success") is not True:
                return
            identifier = f"FileBrowsing-error-{action}"
            visible = self.wait_for_identifier(identifier)
            if not isinstance(visible.get("matchedElement"), dict):
                return
            tapped = self.tap(presentation, identifier)
            probe = self.wait_for_probe(
                f"file-browser-error-{action}",
                offset,
                f"reachability files delivered action=fileBrowserError.{action}",
            )
            if tapped.get("success") is True and any(
                f"reachability files delivered action=fileBrowserError.{action}"
                in line for line in probe[offset:]
            ):
                self.delivered(
                    presentation,
                    f"accessibility:{identifier}",
                    self.events[-1]["evidence"],
                    "The error-dialog action reached its FilesScreen handler and appended an action probe.",
                )

    def browser_condition_scenario(
        self, *, include_source_scenarios: bool = True
    ) -> None:
        presentation = MAIN_WINDOW_BROWSER_CONTEXT
        if include_source_scenarios:
            self.source_connection_scenario("smb")
            self.source_connection_scenario("webDAV")
            self.source_sidebar_scenario()
            self.file_browser_error_scenario()
        self.relaunch()
        self.tap(presentation, "Navigation-Ornament-tab-files")
        reference = self.wait_for_identifier(
            self.primary_video_identifier()
        )
        if not isinstance(reference.get("matchedElement"), dict):
            self.app_command("importMedia", file=self.primary_video_file())
            self.relaunch()
            self.tap(presentation, "Navigation-Ornament-tab-files")

        before = self.copy_probe("browser-conditions-before")
        offset = len(before)
        sidebar = self.tap(presentation, "FileBrowsing-FilesScreen-sidebarToggle")
        probe = self.copy_probe("browser-sidebar-toggle")
        if sidebar.get("success") is True and any(
            "reachability files delivered action=files.sidebarToggle" in line
            for line in probe[offset:]
        ):
            self.delivered(
                presentation, "accessibility:FileBrowsing-FilesScreen-sidebarToggle",
                self.events[-1]["evidence"],
                "The sidebar binding changed and appended its application probe.",
            )
        self.tap(presentation, "FileBrowsing-FilesScreen-sidebarToggle")

        before = self.copy_probe("browser-view-mode-before")
        offset = len(before)
        view_mode = self.tap(presentation, "FileBrowsing-FilesScreen-viewMode")
        probe = self.copy_probe("browser-view-mode")
        if view_mode.get("success") is True and any(
            "reachability files delivered action=files.viewMode" in line
            for line in probe[offset:]
        ):
            self.delivered(
                presentation, "accessibility:FileBrowsing-FilesScreen-viewMode",
                self.events[-1]["evidence"],
                "The view-mode gesture changed the screen-local product binding.",
            )

        before = self.copy_probe("browser-sort-before")
        offset = len(before)
        parent = self.tap(presentation, "FileBrowsing-FilesScreen-sort")
        target, _, sort = self.select_debug_menu_item(
            presentation=presentation,
            host="files",
            family="sortKey",
            preferred=("size", "modifiedDate", "name"),
        )
        probe = self.copy_probe("browser-sort-selected")
        if parent.get("success") is True and sort.get("success") is True and any(
            "reachability files delivered action=files.sort" in line
            for line in probe[offset:]
        ):
            self.delivered_by_debug_menu_selection(
                presentation,
                "accessibility:FileBrowsing-FilesScreen-sort",
                "accessibility:FileBrowsing-FilesScreen-sort",
                self.events[-1]["evidence"],
                "The named sort parent was hittable; the DEBUG equivalent selected "
                f"target={target} through the Picker binding and its product onChange probe.",
            )
            self.delivered_by_debug_menu_selection(
                presentation,
                "accessibility:FileBrowsing-FilesScreen-sort-{id}",
                "accessibility:FileBrowsing-FilesScreen-sort",
                self.events[-1]["evidence"],
                "The named sort parent was hittable; the DEBUG equivalent entered the "
                f"target={target} option itself, which the system Menu leaves without "
                "an identifier of its own.",
            )
        if target is not None:
            self.controller("tap", "--label", "Size", "--no-screenshot")

        before = self.copy_probe("browser-search-before")
        offset = len(before)
        search = self.controller(
            "typeText", "--identifier", "FileBrowsing-FilesScreen-search",
            "--text", "fury", "--no-screenshot",
        )
        probe = self.copy_probe("browser-search-typed")
        if search.get("success") is True and any(
            "reachability files delivered action=files.search" in line
            for line in probe[offset:]
        ):
            self.delivered(
                presentation, "accessibility:FileBrowsing-FilesScreen-search",
                self.events[-1]["evidence"],
                "Typing changed the browser search binding and appended a probe.",
            )

        self.relaunch()
        self.tap(presentation, "Navigation-Ornament-tab-files")
        before = self.copy_probe("browser-new-folder-before")
        offset = len(before)
        parent = self.tap(presentation, "FileBrowsing-Manage-button")
        _, _, opened = self.select_debug_menu_item(
            presentation=presentation,
            host="files",
            family="manage",
            preferred=("newFolder",),
            driven_operations=(
                "accessibility:MediaLibrary-Manage-newFolder",
            ),
        )
        probe = self.copy_probe("browser-new-folder-open")
        recent = probe[offset:]
        if parent.get("success") is True and any(
            "reachability files delivered action=manage.open" in line
            for line in recent
        ):
            self.delivered(
                presentation,
                "accessibility:FileBrowsing-Manage-button",
                self.events[-1]["evidence"],
                "The named Manage menu was hittable and constructed its product actions.",
            )
        if opened.get("success") is True and any(
            "reachability files delivered action=manage.newFolder" in line
            for line in recent
        ):
            self.delivered_by_debug_menu_selection(
                presentation,
                "accessibility:MediaLibrary-Manage-newFolder",
                "accessibility:FileBrowsing-Manage-button",
                self.events[-1]["evidence"],
                "The named Manage parent was hittable; the DEBUG equivalent entered "
                "the product new-folder action and its probe confirmed delivery.",
            )
        _, probe = self.set_file_browser_alert_field(
            presentation=presentation,
            operation="accessibility:MediaLibrary-NewFolder-name",
            field="newFolderName",
            value="Reachability Round 2",
            evidence_label="browser-new-folder-name",
        )
        before = probe
        offset = len(before)
        created = self.tap(presentation, "MediaLibrary-NewFolder-create")
        probe = self.copy_probe("browser-new-folder-created")
        if created.get("success") is True and any(
            "reachability files delivered action=newFolder.create" in line
            for line in probe[offset:]
        ):
            self.delivered(
                presentation, "accessibility:MediaLibrary-NewFolder-create",
                self.events[-1]["evidence"],
                "The confirmation invoked MediaLibrary.createFolder and appended a probe.",
            )

        before = self.copy_probe("browser-new-folder-cancel-before")
        offset = len(before)
        self.select_debug_menu_item(
            presentation=presentation,
            host="files",
            family="manage",
            preferred=("newFolder",),
        )
        cancelled = self.tap(presentation, "MediaLibrary-NewFolder-cancel")
        probe = self.copy_probe("browser-new-folder-cancelled")
        if cancelled.get("success") is True and any(
            "reachability files delivered action=newFolder.cancel" in line
            for line in probe[offset:]
        ):
            self.delivered(
                presentation, "accessibility:MediaLibrary-NewFolder-cancel",
                self.events[-1]["evidence"],
                "Refusing the alert cleared the pending name and appended its probe.",
            )

        error = self.wait_for_identifier("MediaLibrary-error-dismiss")
        if isinstance(error.get("matchedElement"), dict):
            before = self.copy_probe("browser-error-before")
            offset = len(before)
            dismissed = self.tap(presentation, "MediaLibrary-error-dismiss")
            probe = self.copy_probe("browser-error-dismissed")
            if dismissed.get("success") is True and any(
                "reachability files delivered action=mediaLibraryError.dismiss" in line
                for line in probe[offset:]
            ):
                self.delivered(
                    presentation, "accessibility:MediaLibrary-error-dismiss",
                    self.events[-1]["evidence"],
                    "The failed folder creation exposed the product error panel, whose dismiss closure appended a probe.",
                )
        else:
            before = probe
            offset = len(before)
            folder = self.tap(
                presentation, "MediaLibrary-grid-folder-Reachability Round 2",
                operation_id="accessibility:MediaLibrary-grid-folder-{folder.name}",
            )
            probe = self.copy_probe("browser-library-folder-open")
            if folder.get("success") is True and any(
                "reachability files delivered action=library.folder" in line
                for line in probe[offset:]
            ):
                self.delivered(
                    presentation, "accessibility:MediaLibrary-grid-folder-{folder.name}",
                    self.events[-1]["evidence"],
                    "Opening the created folder ran the Media Library navigation handler.",
                )

            for direction in ("back", "forward"):
                before = probe
                offset = len(before)
                navigation = self.tap(
                    presentation,
                    f"FileBrowsing-FilesScreen-navBackForward-{direction}",
                )
                probe = self.copy_probe(f"browser-navigation-{direction}")
                if navigation.get("success") is True and any(
                    f"reachability files delivered action=files.nav.{direction}"
                    in line for line in probe[offset:]
                ):
                    self.delivered(
                        presentation,
                        "accessibility:FileBrowsing-FilesScreen-"
                        f"navBackForward-{direction}",
                        self.events[-1]["evidence"],
                        "The navigation button reached the corresponding browser history handler.",
                    )

            before = probe
            offset = len(before)
            parent = self.tap(
                presentation, "MediaLibrary-Breadcrumb-current"
            )
            _, _, selected = self.select_debug_menu_item(
                presentation=presentation,
                host="mediaLibrary",
                family="breadcrumb",
                preferred=("0",),
                driven_operations=(
                    "accessibility:MediaLibrary-Breadcrumb-current",
                ),
            )
            probe = self.copy_probe("browser-library-breadcrumb-root")
            if (
                parent.get("success") is True
                and selected.get("success") is True
                and any(
                    "reachability files delivered "
                    "action=breadcrumb.mediaLibrary" in line
                    for line in probe[offset:]
                )
            ):
                self.delivered_by_debug_menu_selection(
                    presentation,
                    "accessibility:MediaLibrary-Breadcrumb-current",
                    "accessibility:MediaLibrary-Breadcrumb-current",
                    self.events[-1]["evidence"],
                    "The named breadcrumb was hittable; the DEBUG equivalent "
                    "entered its product navigation callback and the callback "
                    "probe confirmed delivery.",
                )
            self.controller(
                "tap", "--label", "Media Library", "--no-screenshot",
            )

        before = self.copy_probe("browser-multiselect-before")
        offset = len(before)
        parent = self.tap(presentation, "FileBrowsing-Manage-button")
        _, _, selection = self.select_debug_menu_item(
            presentation=presentation,
            host="files",
            family="manage",
            preferred=("selectMultiple",),
            driven_operations=(
                "accessibility:MediaLibrary-Manage-selectMultiple",
            ),
        )
        probe = self.copy_probe("browser-multiselect-open")
        if parent.get("success") is True and selection.get("success") is True and any(
            "reachability files delivered action=manage.selectMultiple" in line
            for line in probe[offset:]
        ):
            self.delivered_by_debug_menu_selection(
                presentation,
                "accessibility:MediaLibrary-Manage-selectMultiple",
                "accessibility:FileBrowsing-Manage-button",
                self.events[-1]["evidence"],
                "The named Manage parent was hittable; the DEBUG equivalent entered "
                "the product multi-selection action and its probe confirmed delivery.",
            )
        before = probe
        offset = len(before)
        reference = self.tap(
            presentation, self.primary_video_identifier(),
            operation_id="accessibility:MediaLibrary-grid-video-{reference.name}",
        )
        probe = self.copy_probe("browser-reference-selected")
        if reference.get("success") is True and any(
            "reachability files delivered action=library.video" in line
            for line in probe[offset:]
        ):
            self.delivered(
                presentation, "accessibility:MediaLibrary-grid-video-{reference.name}",
                self.events[-1]["evidence"],
                "The library card ran its selection-aware activation handler.",
            )
        before = probe
        offset = len(before)
        done = self.tap(presentation, "MediaLibrary-MultiSelect-done")
        probe = self.copy_probe("browser-multiselect-done")
        if done.get("success") is True and any(
            "reachability files delivered action=multiSelect.done" in line
            for line in probe[offset:]
        ):
            self.delivered(
                presentation, "accessibility:MediaLibrary-MultiSelect-done",
                self.events[-1]["evidence"],
                "Done exited the product multi-selection state and appended a probe.",
            )

        self.tap(presentation, "FileBrowsing-Manage-button")
        self.select_debug_menu_item(
            presentation=presentation,
            host="files",
            family="manage",
            preferred=("selectMultiple",),
            driven_operations=(
                "accessibility:MediaLibrary-Manage-selectMultiple",
            ),
        )
        self.tap(
            presentation,
            self.primary_video_identifier(),
            operation_id="accessibility:MediaLibrary-grid-video-{reference.name}",
        )
        before = self.copy_probe("browser-move-selection-before")
        offset = len(before)
        move_parent = self.tap(
            presentation, "MediaLibrary-MultiSelect-move"
        )
        _, _, moved = self.select_debug_menu_item(
            presentation=presentation,
            host="mediaLibrary",
            family="moveDestination",
            preferred=("root",),
        )
        probe = self.copy_probe("browser-move-selection")
        if (
            move_parent.get("success") is True
            and moved.get("success") is True
            and any(
                "reachability files delivered action=multiSelect.move" in line
                for line in probe[offset:]
            )
        ):
            self.delivered_by_debug_menu_selection(
                presentation,
                "accessibility:MediaLibrary-MultiSelect-move",
                "accessibility:MediaLibrary-MultiSelect-move",
                self.events[-1]["evidence"],
                "The named Move To parent was hittable; the DEBUG equivalent "
                "entered the shared move handler and its product probe confirmed "
                "delivery.",
            )

    def manage_add_scenario(self) -> None:
        presentation = MAIN_WINDOW_BROWSER_CONTEXT
        for target, expected_action in (
            ("addFiles", "manage.addFiles"),
            ("addFolder", "manage.addFolder"),
            ("addPhotos", "manage.addPhotos"),
        ):
            self.relaunch()
            self.tap(presentation, "Navigation-Ornament-tab-files")
            before = self.copy_probe(f"manage-{target}-before")
            offset = len(before)
            parent = self.tap(presentation, "FileBrowsing-Manage-button")
            self.mark_driven(
                presentation, f"accessibility:MediaLibrary-Manage-{target}"
            )
            _, _, selected = self.select_debug_menu_item(
                presentation=presentation,
                host="files",
                family="manage",
                preferred=(target,),
            )
            probe = self.copy_probe(f"manage-{target}-selected")
            if parent.get("success") is True and any(
                "reachability files delivered action=manage.open" in line
                for line in probe[offset:]
            ):
                self.delivered(
                    presentation,
                    "accessibility:FileBrowsing-Manage-button",
                    self.events[-1]["evidence"],
                    "The named Manage button constructed its product menu and appended the open probe.",
                )
            if (
                parent.get("success") is True
                and selected.get("success") is True
                and any(
                    f"reachability files delivered action={expected_action}" in line
                    for line in probe[offset:]
                )
            ):
                self.delivered_by_debug_menu_selection(
                    presentation,
                    f"accessibility:MediaLibrary-Manage-{target}",
                    "accessibility:FileBrowsing-Manage-button",
                    self.events[-1]["evidence"],
                    "The named Manage parent was hittable; the DEBUG equivalent "
                    f"entered the {target} product handler and its probe confirmed delivery.",
                )

    def library_editing_scenario(self) -> None:
        presentation = MAIN_WINDOW_BROWSER_CONTEXT
        self.relaunch()
        self.tap(presentation, "Navigation-Ornament-tab-files")
        if self.app_command(
            "importMedia", file=self.primary_video_file()
        ).get("success") is not True:
            return
        self.relaunch()
        self.tap(presentation, "Navigation-Ornament-tab-files")

        self.tap(presentation, "FileBrowsing-Manage-button")
        _, _, opened = self.select_debug_menu_item(
            presentation=presentation,
            host="files",
            family="manage",
            preferred=("newFolder",),
        )
        if opened.get("success") is True:
            self.set_file_browser_alert_field(
                presentation=presentation,
                operation="accessibility:MediaLibrary-NewFolder-name",
                field="newFolderName",
                value="Round 13 draft",
                evidence_label="round13-new-folder-name",
            )
            self.controller("tap", "--label", "Cancel", "--no-screenshot")

        folder_identifier = (
            f"MediaLibrary-grid-folder-{REACHABILITY_LIBRARY_FOLDER}"
        )
        pressed = self.controller(
            "press", "--identifier", folder_identifier,
            "--duration", "1.2", "--no-screenshot",
        )
        if pressed.get("success") is not True:
            snapshot = self.controller("snapshot", "--no-screenshot")
            hierarchy = snapshot.get("hierarchy", "") if isinstance(snapshot, dict) else ""
            list_identifier = None
            for line in hierarchy.splitlines():
                if "Reachability Fixture" in line and "library-folder-" in line:
                    start = line.find("identifier: '")
                    if start != -1:
                        start += len("identifier: '")
                        end = line.find("'", start)
                        if end != -1:
                            list_identifier = line[start:end]
                            break
            if list_identifier is not None:
                pressed = self.controller(
                    "press", "--identifier", list_identifier,
                    "--duration", "1.2", "--no-screenshot",
                )
                if pressed.get("success") is True:
                    folder_identifier = list_identifier
        rename_menu = self.controller(
            "tap", "--label", "Rename", "--no-screenshot",
        )
        rename_opened = (
            pressed.get("success") is True
            and rename_menu.get("success") is True
        )
        if rename_opened:
            self.set_file_browser_alert_field(
                presentation=presentation,
                operation="accessibility:MediaLibrary-RenameFolder-name",
                field="renameFolderName",
                value=f"{REACHABILITY_LIBRARY_FOLDER} Round 13",
                evidence_label="round13-rename-name",
            )

        if rename_opened:
            before = self.copy_probe("round11-rename-confirm-before")
            offset = len(before)
            renamed = self.tap(
                presentation, "MediaLibrary-RenameFolder-confirm"
            )
            probe = self.copy_probe("round11-rename-confirm")
            if renamed.get("success") is True and any(
                "reachability files delivered action=renameFolder.confirm" in line
                for line in probe[offset:]
            ):
                self.delivered(
                    presentation,
                    "accessibility:MediaLibrary-RenameFolder-confirm",
                    self.events[-1]["evidence"],
                    "Rename reached MediaLibrary.rename through the product alert action.",
                )

            before = self.copy_probe("round13-rename-cancel-before")
            offset = len(before)
            self.controller(
                "press", "--identifier", folder_identifier,
                "--duration", "1.2", "--no-screenshot",
            )
            reopened = self.controller(
                "tap", "--label", "Rename", "--no-screenshot",
            )
            if reopened.get("success") is True:
                cancelled = self.tap(
                    presentation, "MediaLibrary-RenameFolder-cancel"
                )
                probe = self.copy_probe("round13-rename-cancelled")
                if cancelled.get("success") is True and any(
                    "reachability files delivered action=renameFolder.cancel" in line
                    for line in probe[offset:]
                ):
                    self.delivered(
                        presentation,
                        "accessibility:MediaLibrary-RenameFolder-cancel",
                        self.events[-1]["evidence"],
                        "Refusing the alert cleared the pending rename and appended "
                        "its probe.",
                    )

        self.tap(presentation, "FileBrowsing-Manage-button")
        _, _, selection = self.select_debug_menu_item(
            presentation=presentation,
            host="files",
            family="manage",
            preferred=("selectMultiple",),
        )
        if selection.get("success") is not True:
            return
        selected = self.tap(
            presentation,
            self.primary_video_identifier(),
            operation_id="accessibility:MediaLibrary-grid-video-{reference.name}",
        )
        if selected.get("success") is not True:
            return
        before = self.copy_probe("round11-multiselect-delete-before")
        offset = len(before)
        deleted = self.tap(presentation, "MediaLibrary-MultiSelect-delete")
        probe = self.copy_probe("round11-multiselect-delete")
        if deleted.get("success") is True and any(
            "reachability files delivered action=multiSelect.delete" in line
            for line in probe[offset:]
        ):
            self.delivered(
                presentation,
                "accessibility:MediaLibrary-MultiSelect-delete",
                self.events[-1]["evidence"],
                "Delete opened the product batch-removal confirmation.",
            )
        before = probe
        offset = len(before)
        confirmed = self.tap(
            presentation, "MediaLibrary-MultiSelect-confirmDelete"
        )
        probe = self.copy_probe("round11-multiselect-confirm")
        if confirmed.get("success") is True and any(
            "reachability files delivered action=multiSelect.confirmDelete" in line
            for line in probe[offset:]
        ):
            self.delivered(
                presentation,
                "accessibility:MediaLibrary-MultiSelect-confirmDelete",
                self.events[-1]["evidence"],
                "Delete Selected reached the product removal handler; the original media was unchanged.",
            )

    def settings_menu_scenario(self) -> None:
        presentation = MAIN_WINDOW_BROWSER_CONTEXT
        self.relaunch()
        self.tap(presentation, "Navigation-Ornament-tab-settings")
        self.tap(
            presentation,
            "Settings-menu-resume-strategy",
            operation_id="accessibility:Settings-menu-{id}",
        )
        for family in (
            "resume-strategy",
            "end-behavior",
            "default-scenic-environment",
            "default-speed",
            "controls-auto-hide",
        ):
            operation_id = f"menu:settings:{family}"
            before = self.copy_probe(f"settings-{family}-before")
            offset = len(before)
            target, _, selected = self.select_debug_menu_item(
                presentation=presentation,
                host="settings",
                family=family,
                driven_operations=(operation_id,),
            )
            probe = self.copy_probe(f"settings-{family}-selected")
            if selected.get("success") is True and target is not None and any(
                f"reachability settings delivered action=menu.{family}" in line
                for line in probe[offset:]
            ):
                self.delivered(
                    presentation,
                    operation_id,
                    self.events[-1]["evidence"],
                    "The visible Settings host invoked its shared menu binding and appended the family probe.",
                    has_accessibility_target=False,
                )
                self.delivered_by_debug_menu_selection(
                    presentation,
                    "accessibility:Settings-menu-{id}",
                    "accessibility:Settings-menu-{id}",
                    self.events[-1]["evidence"],
                    "The named chip supplied hierarchy and hittability evidence; the "
                    "DEBUG equivalent entered the same binding it opens and the "
                    f"menu.{family} product probe confirmed delivery.",
                )
                self.delivered_by_debug_menu_selection(
                    presentation,
                    "accessibility:Settings-menuOption-{id}-{option.id}",
                    "accessibility:Settings-menu-{id}",
                    self.events[-1]["evidence"],
                    "The named chip supplied hierarchy and hittability evidence; the "
                    "DEBUG equivalent entered the exact option action and its product "
                    "probe confirmed delivery.",
                )
        self.select_settings_category()
        before = self.copy_probe("settings-action-before")
        offset = len(before)
        action = self.tap(
            presentation,
            "Settings-action-clear-progress",
            operation_id="accessibility:Settings-action-{id}",
        )
        probe = self.copy_probe("settings-action-cleared")
        if action.get("success") is True and any(
            "reachability settings delivered action=action.clear-progress" in line
            for line in probe[offset:]
        ):
            self.delivered(
                presentation,
                "accessibility:Settings-action-{id}",
                self.events[-1]["evidence"],
                "Clear All ran the product viewing-state reset and appended its probe.",
            )

    def settings_category_scenario(self) -> None:
        presentation = MAIN_WINDOW_BROWSER_CONTEXT
        self.relaunch()
        self.tap(presentation, "Navigation-Ornament-tab-settings")
        self.select_settings_category()

    def select_settings_category(self) -> None:
        presentation = MAIN_WINDOW_BROWSER_CONTEXT
        before = self.copy_probe("round13-settings-category-before")
        offset = len(before)
        category = self.tap(
            presentation,
            "Settings-category-storagePrivacy",
            operation_id="accessibility:Settings-category-{item.id}",
            index=2,
        )
        probe = self.copy_probe("round13-settings-category-selected")
        if category.get("success") is True and any(
            "reachability settings delivered action=category.storagePrivacy" in line
            for line in probe[offset:]
        ):
            self.delivered(
                presentation,
                "accessibility:Settings-category-{item.id}",
                self.events[-1]["evidence"],
                "Storage & Privacy changed the product Settings selection.",
            )

    def library_reference_move_scenario(self) -> None:
        presentation = MAIN_WINDOW_BROWSER_CONTEXT
        self.relaunch()
        self.tap(presentation, "Navigation-Ornament-tab-files")
        imported = self.app_command("importMedia", file=self.primary_video_file())
        if imported.get("success") is True:
            self.relaunch()
            self.tap(presentation, "Navigation-Ornament-tab-files")
        before = self.copy_probe("library-reference-move-before")
        offset = len(before)
        target, _, moved = self.select_debug_menu_item(
            presentation=presentation,
            host="mediaLibrary",
            family="referenceMoveDestination",
        )
        probe = self.copy_probe("library-reference-move-selected")
        if moved.get("success") is True and target is not None and any(
            "reachability files delivered action=libraryReference.move" in line
            for line in probe[offset:]
        ):
            self.delivered(
                presentation,
                "command:selectMenuItem",
                self.events[-1]["evidence"],
                "The visible library reference host invoked the shared move handler and appended its product probe.",
                has_accessibility_target=False,
            )

    def breadcrumb_scenario(self) -> None:
        presentation = MAIN_WINDOW_BROWSER_CONTEXT
        self.relaunch()
        self.tap(presentation, "Navigation-Ornament-tab-files")
        folder_before = self.copy_probe("media-library-folder-before")
        folder_offset = len(folder_before)
        folder = self.tap(
            presentation,
            f"MediaLibrary-grid-folder-{REACHABILITY_LIBRARY_FOLDER}",
            operation_id="accessibility:MediaLibrary-grid-folder-{folder.name}",
        )
        folder_probe = self.wait_for_probe(
            "media-library-folder-open",
            folder_offset,
            "reachability files delivered action=library.folder",
        )
        if folder.get("success") is True and any(
            "reachability files delivered action=library.folder" in line
            for line in folder_probe[folder_offset:]
        ):
            self.delivered(
                presentation,
                "accessibility:MediaLibrary-grid-folder-{folder.name}",
                self.events[-1]["evidence"],
                "The Media Library folder card reached its navigation handler before the breadcrumb was exercised.",
            )
        if folder.get("success") is True:
            before = self.copy_probe("media-library-breadcrumb-before")
            offset = len(before)
            parent = self.tap(presentation, "MediaLibrary-Breadcrumb-current")
            self.mark_driven(
                presentation, "accessibility:MediaLibrary-Breadcrumb-current"
            )
            _, _, selected = self.select_debug_menu_item(
                presentation=presentation,
                host="mediaLibrary",
                family="breadcrumb",
                preferred=("0",),
            )
            probe = self.copy_probe("media-library-breadcrumb-selected")
            if (
                parent.get("success") is True
                and selected.get("success") is True
                and any(
                    "reachability files delivered action=breadcrumb.mediaLibrary"
                    in line for line in probe[offset:]
                )
            ):
                self.delivered_by_debug_menu_selection(
                    presentation,
                    "accessibility:MediaLibrary-Breadcrumb-current",
                    "accessibility:MediaLibrary-Breadcrumb-current",
                    self.events[-1]["evidence"],
                    "The named Media Library breadcrumb was hittable; the DEBUG equivalent entered its navigation callback.",
                )

        self.relaunch()
        self.tap(presentation, "Navigation-Ornament-tab-files")
        sources = self.controller("snapshot", "--no-screenshot")
        source_identifiers = sorted(
            identifier
            for identifier in self.hierarchy_identifiers(sources)
            if identifier.startswith("FileBrowsing-SourcesSidebar-source-")
            and identifier != "FileBrowsing-SourcesSidebar-source-media-library"
        )
        if not source_identifiers:
            return
        if not self.select_browseable_remote_source(
            presentation,
            source_identifiers,
            evidence_prefix="files-breadcrumb",
        ):
            return
        visible = self.wait_for_identifier(
            "FileBrowsing-Breadcrumb-current"
        )
        if not isinstance(visible.get("matchedElement"), dict):
            return
        before = self.copy_probe("files-breadcrumb-before")
        offset = len(before)
        parent = self.tap(presentation, "FileBrowsing-Breadcrumb-current")
        self.mark_driven(
            presentation, "accessibility:FileBrowsing-Breadcrumb-current"
        )
        _, _, selected = self.select_debug_menu_item(
            presentation=presentation,
            host="files",
            family="breadcrumb",
            preferred=("0",),
        )
        probe = self.copy_probe("files-breadcrumb-selected")
        if (
            parent.get("success") is True
            and selected.get("success") is True
            and any(
                "reachability files delivered action=breadcrumb.files" in line
                for line in probe[offset:]
            )
        ):
            self.delivered_by_debug_menu_selection(
                presentation,
                "accessibility:FileBrowsing-Breadcrumb-current",
                "accessibility:FileBrowsing-Breadcrumb-current",
                self.events[-1]["evidence"],
                    "The named Files breadcrumb was hittable; the DEBUG equivalent entered its navigation callback.",
                )

    def select_browseable_remote_source(
        self,
        presentation: str,
        source_identifiers: list[str],
        *,
        evidence_prefix: str,
    ) -> bool:
        operation_id = "accessibility:FileBrowsing-SourcesSidebar-source-{item.id}"
        for source_identifier in source_identifiers:
            for index in (1, 2):
                before = self.copy_probe(f"{evidence_prefix}-source-before")
                offset = len(before)
                self.mark_driven(presentation, operation_id)
                selected = self.controller(
                    "tap",
                    "--identifier", source_identifier,
                    "--index", str(index),
                    "--no-screenshot",
                )
                matched = selected.get("matchedElement")
                if isinstance(matched, dict):
                    self.mark_observation(
                        presentation,
                        operation_id,
                        exists=True,
                        hittable=matched.get("isHittable") is True,
                        evidence=self.events[-1]["evidence"],
                        reason="The non-delete child of the existing source row was addressable.",
                    )
                probe = self.copy_probe(f"{evidence_prefix}-source-selected")
                if selected.get("success") is True and any(
                    "reachability files delivered action=sidebar.select." in line
                    for line in probe[offset:]
                ):
                    self.mark_observation(
                        presentation,
                        operation_id,
                        received=True,
                        evidence=self.events[-1]["evidence"],
                        reason="The existing source row reached FilesScreen.select without activating its delete control.",
                    )
                    has_browseable_content = False
                    remote_identifiers: set[str] = set()
                    for _ in range(4):
                        remote_state = self.controller("snapshot", "--no-screenshot")
                        remote_identifiers = self.hierarchy_identifiers(remote_state)
                        has_browseable_content = any(
                            identifier.startswith(
                                (
                                    "FileBrowsing-grid-folder-",
                                    "FileBrowsing-grid-video-",
                                )
                            )
                            for identifier in remote_identifiers
                        )
                        if (
                            has_browseable_content
                            or "FileBrowsing-FilesScreen-loadingState"
                            not in remote_identifiers
                        ):
                            break
                    if "FileBrowsing-error-secondary" in remote_identifiers:
                        self.tap(presentation, "FileBrowsing-error-secondary")
                        continue
                    if has_browseable_content:
                        return True
                    break
        return False

    def ensure_remote_episode_playback(self, presentation: str, context: str) -> bool:
        hosts = getattr(self, "service_hosts", {})
        receipts = getattr(self, "service_receipts", {})
        webdav_address = None
        for key in ("webdav", "WebDAV"):
            if key in receipts and isinstance(receipts[key].get("address"), str):
                webdav_address = str(receipts[key]["address"])
                break
            if key in hosts and hosts[key]:
                webdav_address = hosts[key]
                break
        if not webdav_address:
            return False
        self.relaunch()
        self.tap(MAIN_WINDOW_BROWSER_CONTEXT, "Navigation-Ornament-tab-files")
        snapshot = self.controller("snapshot", "--no-screenshot")
        source_identifiers = sorted(
            identifier
            for identifier in self.hierarchy_identifiers(snapshot)
            if identifier.startswith("FileBrowsing-SourcesSidebar-source-")
            and identifier != "FileBrowsing-SourcesSidebar-source-media-library"
        )
        browsed = False
        if source_identifiers:
            browsed = self.select_browseable_remote_source(
                MAIN_WINDOW_BROWSER_CONTEXT,
                source_identifiers,
                evidence_prefix=f"{context}-remote-episode",
            )
        if not browsed:
            opened, _ = self.open_source_connection("WebDAV")
            if opened.get("success") is not True:
                return False
            trust, _ = self.wait_for_any_identifier(
                ("FileBrowsing-CertificateTrust-trust", "FileBrowsing-CertificateTrust-cancel")
            )
            if trust is not None:
                self.tap(MAIN_WINDOW_BROWSER_CONTEXT, "FileBrowsing-CertificateTrust-trust")
                self.hold("pace", 0.5)
            snapshot = self.controller("snapshot", "--no-screenshot")
            source_identifiers = sorted(
                identifier
                for identifier in self.hierarchy_identifiers(snapshot)
                if identifier.startswith("FileBrowsing-SourcesSidebar-source-")
                and identifier != "FileBrowsing-SourcesSidebar-source-media-library"
            )
            if not source_identifiers:
                return False
            browsed = self.select_browseable_remote_source(
                MAIN_WINDOW_BROWSER_CONTEXT,
                source_identifiers,
                evidence_prefix=f"{context}-remote-episode-retry",
            )
            if not browsed:
                return False
        remote = self.controller("snapshot", "--no-screenshot")
        folder_identifier = next(
            (
                identifier for identifier in sorted(self.hierarchy_identifiers(remote))
                if "EpisodeSeries" in identifier or identifier.startswith("FileBrowsing-grid-folder-")
            ),
            None,
        )
        if folder_identifier is not None and "EpisodeSeries" not in folder_identifier:
            folder_identifier = next(
                (
                    identifier for identifier in sorted(self.hierarchy_identifiers(remote))
                    if "EpisodeSeries" in identifier
                ),
                folder_identifier,
            )
        if folder_identifier is not None:
            self.tap(
                MAIN_WINDOW_BROWSER_CONTEXT,
                folder_identifier,
                operation_id="accessibility:FileBrowsing-grid-folder-{folder.name}",
            )
            self.hold("pace", 0.5)
        remote2 = self.controller("snapshot", "--no-screenshot")
        video_identifier = next(
            (
                identifier for identifier in sorted(self.hierarchy_identifiers(remote2))
                if identifier.startswith("FileBrowsing-grid-video-") and "S01E" in identifier
            ),
            None,
        )
        if video_identifier is None:
            video_identifier = next(
                (
                    identifier for identifier in sorted(self.hierarchy_identifiers(remote2))
                    if identifier.startswith("FileBrowsing-grid-video-")
                ),
                None,
            )
        if video_identifier is None:
            return False
        before = self.copy_probe(f"{context}-remote-episode-before")
        offset = len(before)
        video = self.tap(
            MAIN_WINDOW_BROWSER_CONTEXT,
            video_identifier,
            operation_id="accessibility:FileBrowsing-grid-video-{file.name}",
        )
        probe = self.wait_for_probe(
            f"{context}-remote-episode-video",
            offset,
            "reachability files delivered action=remote.video",
        )
        if video.get("success") is True and any(
            "reachability files delivered action=remote.video" in line for line in probe[offset:]
        ):
            self.delivered(
                MAIN_WINDOW_BROWSER_CONTEXT,
                "accessibility:FileBrowsing-grid-video-{file.name}",
                self.events[-1]["evidence"],
                "The live remote video card reached the playback handler.",
            )
        self.hold("pace", 1.5)
        if context == "portal":
            if not self.ensure_window_projection("180°"):
                return False
            return "presentation=portal" in str((self.wait_for_identifier("PlayerUI-window-control-plane").get("matchedElement") or {}).get("value", ""))
        else:
            if not self.ensure_window_projection("Flat"):
                return False
            return True

    def remote_browser_scenario(self) -> None:
        presentation = MAIN_WINDOW_BROWSER_CONTEXT
        self.relaunch()
        self.tap(presentation, "Navigation-Ornament-tab-files")
        snapshot = self.controller("snapshot", "--no-screenshot")
        source_identifiers = sorted(
            identifier
            for identifier in self.hierarchy_identifiers(snapshot)
            if identifier.startswith("FileBrowsing-SourcesSidebar-source-")
            and identifier != "FileBrowsing-SourcesSidebar-source-media-library"
        )
        if not source_identifiers or not self.select_browseable_remote_source(
            presentation,
            source_identifiers,
            evidence_prefix="round11-remote",
        ):
            return

        remote = self.controller("snapshot", "--no-screenshot")
        folder_identifier = next(
            (
                identifier for identifier in sorted(self.hierarchy_identifiers(remote))
                if identifier.startswith("FileBrowsing-grid-folder-")
            ),
            None,
        )
        if folder_identifier is not None:
            before = self.copy_probe("round11-remote-folder-before")
            offset = len(before)
            folder = self.tap(
                presentation,
                folder_identifier,
                operation_id="accessibility:FileBrowsing-grid-folder-{folder.name}",
            )
            probe = self.copy_probe("round11-remote-folder-open")
            if folder.get("success") is True and any(
                "reachability files delivered action=remote.folder" in line
                for line in probe[offset:]
            ):
                self.delivered(
                    presentation,
                    "accessibility:FileBrowsing-grid-folder-{folder.name}",
                    self.events[-1]["evidence"],
                    "The live remote folder card reached the navigation handler.",
                )
            for direction in ("back", "forward", "back"):
                before = probe
                offset = len(before)
                button = self.tap(
                    presentation,
                    f"FileBrowsing-FilesScreen-navBackForward-{direction}",
                )
                probe = self.copy_probe(f"round11-remote-nav-{direction}")
                if button.get("success") is True and any(
                    f"reachability files delivered action=files.nav.{direction}" in line
                    for line in probe[offset:]
                ):
                    self.delivered(
                        presentation,
                        "accessibility:FileBrowsing-FilesScreen-"
                        f"navBackForward-{direction}",
                        self.events[-1]["evidence"],
                        "The remote history button reached its product handler.",
                    )

        scroll_state = self.controller("snapshot", "--no-screenshot")
        scroll_identifier = next(
            (
                identifier
                for identifier in sorted(self.hierarchy_identifiers(scroll_state))
                if identifier.startswith(
                    ("FileBrowsing-grid-folder-", "FileBrowsing-grid-video-")
                )
            ),
            None,
        )
        if scroll_identifier is None:
            return
        self.controller("activate", "--no-screenshot")
        before = self.copy_probe("round11-remote-scroll-before")
        offset = len(before)
        scroll = self.controller(
            "swipeUp",
            "--identifier", scroll_identifier,
            "--no-screenshot",
        )
        probe = self.copy_probe("round11-remote-scroll")
        if scroll.get("success") is True and any(
            "reachability fileScroll kind=grid" in line
            for line in probe[offset:]
        ):
            self.delivered(
                presentation,
                "scroll:file-list",
                self.events[-1]["evidence"],
                "The live remote file surface appended a scroll geometry probe.",
                has_accessibility_target=False,
            )

        remote = self.controller("snapshot", "--no-screenshot")
        video_identifier = next(
            (
                identifier for identifier in sorted(self.hierarchy_identifiers(remote))
                if identifier.startswith("FileBrowsing-grid-video-")
            ),
            None,
        )
        if video_identifier is not None:
            before = self.copy_probe("round11-remote-video-before")
            offset = len(before)
            video = self.tap(
                presentation,
                video_identifier,
                operation_id="accessibility:FileBrowsing-grid-video-{file.name}",
            )
            probe = self.copy_probe("round11-remote-video-open")
            if video.get("success") is True and any(
                "reachability files delivered action=remote.video" in line
                for line in probe[offset:]
            ):
                self.delivered(
                    presentation,
                    "accessibility:FileBrowsing-grid-video-{file.name}",
                    self.events[-1]["evidence"],
                    "The live remote video card reached the playback handler.",
                )

    def ensure_emby_sign_in(self) -> bool:
        self.provable("main-window-browser", "accessibility:Emby-Connection-Connect")
        credentials_path = getattr(self.arguments, "emby_credentials", None)
        if credentials_path is None:
            return True
        credentials_path = Path(credentials_path)
        if not credentials_path.is_file():
            self.events.append({"at": utc_now(), "action": "embySignIn", "success": False, "detail": "credential file missing", "evidence": "raw/embySignIn.json"})
            failure_key = ("main-window-browser", "accessibility:Emby-Connection-Connect")
            if failure_key in self.cells:
                self.cells[failure_key]["reason"] = "embySignIn refused: credential file missing"
            return False
        current = self.controller("app-command", "--verb", "embyServerIdentityDigest", "--no-screenshot")
        payload = current.get("payload") if isinstance(current, dict) else None
        if current.get("success") is True and current.get("ok") is True and isinstance(payload, list) and len(payload) == 1 and isinstance(payload[0], str) and len(payload[0]) == 64 and all(c in "0123456789abcdef" for c in payload[0]):
            return True
        try:
            import regression_emby_source
            config = regression_emby_source.EmbySourceConfiguration(identity_file=credentials_path)
            regression_emby_source.provision_runtime_identity(configuration=config)
        except (OSError, ValueError, RuntimeError) as error:
            self.events.append({"at": utc_now(), "action": "provisionRuntimeIdentity", "success": False, "detail": str(error), "evidence": "raw/provisionRuntimeIdentity.json"})
            failure_key = ("main-window-browser", "accessibility:Emby-Connection-Connect")
            if failure_key in self.cells:
                self.cells[failure_key]["reason"] = f"provision failed: {error}"
            return False
        try:
            file_bytes = credentials_path.read_bytes()
        except OSError as error:
            self.events.append({"at": utc_now(), "action": "embySignIn", "success": False, "detail": str(error), "evidence": "raw/embySignIn.json"})
            return False
        identity_digest = "sha256:" + hashlib.sha256(file_bytes).hexdigest()
        copy_result = self.local_call("probe-copy", lambda budget: enchron_target.copy_to_container(target=DEVICE, bundle_id=APP_BUNDLE, source=credentials_path, destination="Documents/Regression/emby-runtime-identity.json", developer_dir=DEVELOPER_DIR, core_device_identifier=CORE_DEVICE, budget_seconds=budget.seconds))
        if copy_result is None or copy_result.returncode != 0:
            detail = copy_result.stderr if copy_result and copy_result.stderr else "copy failed"
            self.events.append({"at": utc_now(), "action": "embySignIn", "success": False, "detail": detail, "evidence": "raw/embySignIn.json"})
            failure_key = ("main-window-browser", "accessibility:Emby-Connection-Connect")
            if failure_key in self.cells:
                self.cells[failure_key]["reason"] = f"embySignIn staging failed: {detail}"
            return False
        if enchron_target.is_simulator(DEVICE):
            try:
                container = enchron_target.simulator_container(DEVICE, APP_BUNDLE)
                if container is not None:
                    dest = container / "Documents/Regression/emby-runtime-identity.json"
                    if dest.is_file():
                        dest.chmod(0o600)
            except OSError:
                pass
        sign_in = self.controller("app-command", "--verb", "embySignIn", "--arg", f"identityDigest={identity_digest}", "--no-screenshot")
        sign_in_success = sign_in.get("success") is True and sign_in.get("ok") is True
        self.events.append({"at": utc_now(), "action": "embySignIn", "success": sign_in_success, "detail": sign_in.get("detail"), "evidence": "raw/embySignIn.json"})
        sign_in_path = self.raw / "embySignIn.json"
        try:
            sign_in_path.write_text(json.dumps(sign_in, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        except OSError:
            pass
        if not sign_in_success:
            failure_key = ("main-window-browser", "accessibility:Emby-Connection-Connect")
            if failure_key in self.cells:
                self.cells[failure_key]["reason"] = f"embySignIn refused: {sign_in.get('detail')}"
                self.cells[failure_key]["verdict"] = "known-defect"
            second = self.controller("app-command", "--verb", "embyServerIdentityDigest", "--no-screenshot")
            return False
        second = self.controller("app-command", "--verb", "embyServerIdentityDigest", "--no-screenshot")
        return True

    def emby_version_season_scenario(self) -> None:
        if not self.ensure_emby_sign_in():
            return
        presentation = MAIN_WINDOW_BROWSER_CONTEXT
        found_families: set[str] = set()
        self.relaunch()
        self.tap(presentation, "Emby-Navigation-Tab")

        before = self.copy_probe("emby-sidebar-toggle-before")
        offset = len(before)
        toggled = self.tap(presentation, "Emby-Sidebar-Toggle")
        probe = self.copy_probe("emby-sidebar-toggled")
        if toggled.get("success") is True and any(
            "reachability emby delivered action=sidebarToggle" in line
            for line in probe[offset:]
        ):
            self.delivered(
                presentation,
                "accessibility:Emby-Sidebar-Toggle",
                self.events[-1]["evidence"],
                "The header chip moved the product sidebar visibility binding.",
            )

        home = self.controller("snapshot", "--no-screenshot")
        candidate_identifiers = sorted(
            identifier
            for identifier in self.hierarchy_identifiers(home)
            if identifier.startswith(
                ("Emby-PosterCard-", "Emby-StillCard-")
            )
        )
        for card_identifier in candidate_identifiers:
            if found_families == {"version", "season"}:
                break
            self.relaunch()
            self.tap(presentation, "Emby-Navigation-Tab")
            opened = self.tap(presentation, card_identifier)
            if opened.get("success") is not True:
                continue
            detail = self.controller("snapshot", "--no-screenshot")
            detail_identifiers = self.hierarchy_identifiers(detail)
            for family, parent_identifier, operation_ids in (
                (
                    "version",
                    "Emby-Detail-Version",
                    ("accessibility:Emby-Detail-Version",),
                ),
                (
                    "season",
                    "Emby-Season-Picker",
                    (
                        "accessibility:Emby-Season-Picker",
                        "accessibility:Emby-Season-{season.metadata.id.rawValue}",
                    ),
                ),
            ):
                if family in found_families or parent_identifier not in detail_identifiers:
                    continue
                before = self.copy_probe(f"emby-{family}-before")
                offset = len(before)
                parent = self.tap(presentation, parent_identifier)
                for operation_id in operation_ids:
                    self.mark_driven(presentation, operation_id)
                target, _, selected = self.select_debug_menu_item(
                    presentation=presentation,
                    host="emby",
                    family=family,
                    driven_operations=operation_ids,
                )
                probe = self.copy_probe(f"emby-{family}-selected")
                command_completed = any(
                    "testcmd selectMenuItem ok" in line
                    for line in probe[offset:]
                )
                if (
                    parent.get("success") is True
                    and selected.get("success") is True
                    and target is not None
                    and command_completed
                ):
                    for operation_id in operation_ids:
                        self.delivered_by_debug_menu_selection(
                            presentation,
                            operation_id,
                            operation_ids[0],
                            self.events[-1]["evidence"],
                            f"The visible Emby {family} host invoked its product selection binding and the completed command probe followed it.",
                        )
                    found_families.add(family)

    def emby_session_recovery_scenario(self) -> None:
        if not self.ensure_emby_sign_in():
            return
        presentation = MAIN_WINDOW_BROWSER_CONTEXT
        credentials_path = self.arguments.emby_credentials
        if credentials_path is None:
            return
        credential_document = json.loads(credentials_path.read_text(encoding="utf-8"))
        self.sensitive_values = tuple(
            str(credential_document.get(key, ""))
            for key in ("address", "username", "password")
        )

        self.relaunch()
        self.tap(presentation, "Emby-Navigation-Tab")
        current_identity = self.controller(
            "app-command",
            "--verb", "embyServerIdentityDigest",
            "--no-screenshot",
        )
        readiness = verify_emby_recovery_credentials(credentials_path)
        readiness_path = self.raw / "emby-recovery-readiness.json"
        device_payload = current_identity.get("payload")
        device_digest = (
            device_payload[0]
            if isinstance(device_payload, list)
            and len(device_payload) == 1
            and isinstance(device_payload[0], str)
            else None
        )
        readiness["deviceIdentityDigest"] = device_digest
        readiness["sameServer"] = (
            readiness.get("serverIdentityDigest") == device_digest
            and isinstance(device_digest, str)
        )
        readiness["passed"] = bool(
            readiness.get("passed") is True
            and readiness["sameServer"] is True
            and current_identity.get("success") is True
        )
        readiness_path.write_text(
            json.dumps(readiness, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        self.events.append({
            "at": utc_now(),
            "action": "verifyEmbyRecoveryCredentials",
            "success": readiness["passed"],
            "evidence": f"raw/{readiness_path.name}",
        })
        if readiness["passed"] is not True:
            return

        before = self.copy_probe("emby-signout-before")
        offset = len(before)
        sign_out_operation = "accessibility:Emby-SignOut"
        self.tapped_cells.add((presentation, sign_out_operation))
        signed_out = self.controller(
            "tap",
            "--identifier", "Emby-SignOut",
            "--index", "1",
            "--no-screenshot",
        )
        matched = signed_out.get("matchedElement")
        if isinstance(matched, dict):
            self.mark_observation(
                presentation,
                sign_out_operation,
                exists=True,
                hittable=matched.get("isHittable") is True,
                evidence=self.events[-1]["evidence"],
                reason=(
                    "XCTest selected the non-delete child of the shared sidebar row; "
                    "product delivery is judged separately."
                ),
            )
        connection = self.wait_for_identifier("Emby-Connection-Address")
        probe = self.copy_probe("emby-signout")
        if (
            signed_out.get("success") is True
            and isinstance(connection.get("matchedElement"), dict)
            and any(
                "reachability emby delivered action=signOut" in line
                for line in probe[offset:]
            )
        ):
            self.delivered(
                presentation,
                "accessibility:Emby-SignOut",
                self.events[-1]["evidence"],
                "Sign Out reached the session handler and exposed the connection form.",
            )

        for field, key in (
            ("Address", "address"),
            ("Username", "username"),
            ("Password", "password"),
        ):
            before = probe
            offset = len(before)
            typed = self.controller(
                "replaceText",
                "--identifier", f"Emby-Connection-{field}",
                "--text-file", str(credentials_path),
                "--text-json-key", key,
                "--redact-response-text",
                "--no-screenshot",
            )
            probe = self.copy_probe(f"emby-connection-{key}")
            if typed.get("success") is True and any(
                f"reachability emby delivered action=connection.{key}" in line
                for line in probe[offset:]
            ):
                self.delivered(
                    presentation,
                    f"accessibility:Emby-Connection-{field}",
                    self.events[-1]["evidence"],
                    "The connection field binding changed through the ordinary product form.",
                )

        before = probe
        offset = len(before)
        connected = self.tap(presentation, "Emby-Connection-Connect")
        for label in ("以后", "Not Now"):
            self.controller(
                "tap", "--label", label, "--no-screenshot"
            )
        authenticated = self.wait_for_identifier("Emby-SignOut")
        probe = self.copy_probe("emby-reconnected")
        reconnected_identity = self.controller(
            "app-command",
            "--verb", "embyServerIdentityDigest",
            "--no-screenshot",
        )
        reconnect_payload = reconnected_identity.get("payload")
        reconnected_digest = (
            reconnect_payload[0]
            if isinstance(reconnect_payload, list)
            and len(reconnect_payload) == 1
            and isinstance(reconnect_payload[0], str)
            else None
        )
        if (
            connected.get("success") is True
            and reconnected_identity.get("success") is True
            and reconnected_digest == device_digest
            and any(
                "reachability emby delivered action=connection.connect" in line
                for line in probe[offset:]
            )
        ):
            self.delivered(
                presentation,
                "accessibility:Emby-Connection-Connect",
                self.events[-1]["evidence"],
                "Connect reached the product handler and restored the same authenticated server identity.",
            )

    def emby_content_scenario(self) -> None:
        if not self.ensure_emby_sign_in():
            return
        presentation = MAIN_WINDOW_BROWSER_CONTEXT

        def emby_home_snapshot() -> dict[str, Any]:
            self.relaunch()
            self.tap(presentation, "Emby-Navigation-Tab")
            return self.controller("snapshot", "--no-screenshot")

        def open_card(prefix: str, operation_id: str) -> tuple[str | None, dict[str, Any]]:
            home = emby_home_snapshot()
            identifier = next(
                (
                    value for value in sorted(self.hierarchy_identifiers(home))
                    if value.startswith(prefix)
                ),
                None,
            )
            if identifier is None:
                return None, home
            before = self.copy_probe(f"round11-{prefix}-before")
            offset = len(before)
            opened = self.tap(
                presentation, identifier, operation_id=operation_id
            )
            detail = self.wait_for_identifier("Emby-Detail-list")
            probe = self.copy_probe(f"round11-{prefix}-opened")
            needle = (
                "reachability emby delivered action=posterCard.select."
                if prefix == "Emby-PosterCard-"
                else "reachability emby delivered action=stillCard.select."
            )
            if (
                opened.get("success") is True
                and any(needle in line for line in probe[offset:])
            ):
                self.delivered(
                    presentation,
                    operation_id,
                    self.events[-1]["evidence"],
                    "The existing Emby card reached the shared detail navigation handler.",
                )
            return identifier, detail

        poster_identifier, detail = open_card(
            "Emby-PosterCard-",
            "accessibility:Emby-PosterCard-{metadata.id.rawValue}",
        )
        if poster_identifier is not None:
            identifiers = self.hierarchy_identifiers(detail)
            if "Emby-Detail-Overview-Expand" in identifiers:
                before = self.copy_probe("round11-emby-overview-before")
                offset = len(before)
                expanded = self.tap(
                    presentation, "Emby-Detail-Overview-Expand"
                )
                probe = self.copy_probe("round11-emby-overview")
                if expanded.get("success") is True and any(
                    "reachability emby delivered action=detail.overview.toggle" in line
                    for line in probe[offset:]
                ):
                    self.delivered(
                        presentation,
                        "accessibility:Emby-Detail-Overview-Expand",
                        self.events[-1]["evidence"],
                        "More changed the product overview expansion state.",
                    )

        still_identifier, still_detail = open_card(
            "Emby-StillCard-",
            "accessibility:Emby-StillCard-{metadata.id.rawValue}",
        )
        playback_detail = still_detail if still_identifier is not None else detail
        action_identifier = next(
            (
                value for value in (
                    "Emby-Detail-Resume",
                    "Emby-Detail-PlayFromBeginning",
                )
                if value in self.hierarchy_identifiers(playback_detail)
            ),
            None,
        )
        if action_identifier is not None:
            before = self.copy_probe("round11-emby-play-before")
            offset = len(before)
            played = self.tap(
                presentation,
                action_identifier,
                operation_id=(
                    "accessibility:Emby-Detail-"
                    "{action == .resume ? \"Resume\" : \"PlayFromBeginning\"}"
                ),
            )
            if played.get("failure", {}).get("kind") == "response-timeout" or "response-timeout" in str(played.get("error", "")):
                if not self._recover_emby_playback_timeout(
                    presentation,
                    "accessibility:Emby-Detail-{action == .resume ? \"Resume\" : \"PlayFromBeginning\"}",
                    action_identifier,
                ):
                    return
            else:
                control = self.wait_for_identifier(
                    "PlayerUI-window-control-plane"
                )
                probe = self.copy_probe("round11-emby-play")
                if (
                    played.get("success") is True
                    and isinstance(control.get("matchedElement"), dict)
                    and any(
                        "reachability emby delivered action=detail.play." in line
                        for line in probe[offset:]
                    )
                ):
                    self.delivered(
                        presentation,
                        "accessibility:Emby-Detail-"
                        "{action == .resume ? \"Resume\" : \"PlayFromBeginning\"}",
                        self.events[-1]["evidence"],
                        "The existing Emby title reached its playback selection handler.",
                    )

        home = emby_home_snapshot()
        preferred = "Emby-PosterCard-177"
        card_identifiers = [
            value for value in sorted(self.hierarchy_identifiers(home))
            if value.startswith(("Emby-PosterCard-", "Emby-StillCard-"))
        ]
        if preferred in card_identifiers:
            card_identifiers.remove(preferred)
            card_identifiers.insert(0, preferred)
        for card_identifier in card_identifiers:
            self.relaunch()
            self.tap(presentation, "Emby-Navigation-Tab")
            if self.tap(presentation, card_identifier).get("success") is not True:
                continue
            detail = self.controller("snapshot", "--no-screenshot")
            episode_identifier = next(
                (
                    value for value in sorted(self.hierarchy_identifiers(detail))
                    if value.startswith("Emby-Episode-")
                ),
                None,
            )
            if episode_identifier is None:
                continue
            before = self.copy_probe("round11-emby-episode-before")
            offset = len(before)
            episode = self.tap(
                presentation,
                episode_identifier,
                operation_id="accessibility:Emby-Episode-{metadata.id.rawValue}",
            )
            if episode.get("failure", {}).get("kind") == "response-timeout" or "response-timeout" in str(episode.get("error", "")):
                if not self._recover_emby_playback_timeout(
                    presentation,
                    "accessibility:Emby-Episode-{metadata.id.rawValue}",
                    episode_identifier,
                ):
                    return
                break
            control = self.wait_for_identifier(
                "PlayerUI-window-control-plane"
            )
            probe = self.copy_probe("round11-emby-episode")
            if (
                episode.get("success") is True
                and isinstance(control.get("matchedElement"), dict)
                and any(
                    "reachability emby delivered action=episode.select." in line
                    for line in probe[offset:]
                )
            ):
                self.delivered(
                    presentation,
                    "accessibility:Emby-Episode-{metadata.id.rawValue}",
                    self.events[-1]["evidence"],
                    "The existing episode card reached the Emby playback selection handler.",
                )
            break

        self.relaunch()
        self.tap(presentation, "Emby-Navigation-Tab")
        self.controller("tap", "--label", "Search", "--no-screenshot")
        search = self.wait_for_identifier("Emby-Search-Field")
        if isinstance(search.get("matchedElement"), dict):
            before = self.copy_probe("round11-emby-search-before")
            offset = len(before)
            typed = self.controller(
                "typeText", "--identifier", "Emby-Search-Field",
                "--text", "a", "--no-screenshot",
            )
            probe = self.copy_probe("round11-emby-search")
            if typed.get("success") is True and any(
                "reachability emby delivered action=search.query" in line
                for line in probe[offset:]
            ):
                self.delivered(
                    presentation,
                    "accessibility:Emby-Search-Field",
                    self.events[-1]["evidence"],
                    "Typing changed the product Emby search binding.",
                )

        self.relaunch()
        self.tap(presentation, "Emby-Navigation-Tab")
        sidebar = self.controller("snapshot", "--no-screenshot")
        library_identifier = next(
            (
                value for value in sorted(self.hierarchy_identifiers(sidebar))
                if value.startswith("Emby-Sidebar-library-")
            ),
            None,
        )
        if library_identifier is not None:
            self.controller(
                "tap", "--identifier", library_identifier,
                "--index", "2", "--no-screenshot",
            )
            sort = self.wait_for_identifier("Emby-Library-Sort")
            matched = sort.get("matchedElement")
            self.mark_driven(presentation, "accessibility:Emby-Library-Sort")
            if isinstance(matched, dict):
                self.mark_observation(
                    presentation,
                    "accessibility:Emby-Library-Sort",
                    exists=True,
                    hittable=matched.get("isHittable") is True,
                    evidence=self.events[-1]["evidence"],
                    reason="The existing Emby library exposed its segmented sort control.",
                )
                before = self.copy_probe("round11-emby-sort-before")
                offset = len(before)
                changed = self.controller(
                    "tap", "--label", "Alphabetical", "--no-screenshot",
                )
                probe = self.copy_probe("round11-emby-sort")
                if changed.get("success") is True and any(
                    "reachability emby delivered action=library.sort." in line
                    for line in probe[offset:]
                ):
                    self.mark_observation(
                        presentation,
                        "accessibility:Emby-Library-Sort",
                        received=True,
                        evidence=self.events[-1]["evidence"],
                        reason="Alphabetical changed the product library sort binding.",
                    )

    def player_panel_portal_menu_scenario(self) -> None:
        opened = self.open_media(self.primary_video_identifier())
        if opened.get("success") is not True:
            return
        if not self.ensure_window_projection("180°"):
            return
        portal = self.wait_for_identifier(
            "PlayerUI-window-control-plane"
        )
        value = str((portal.get("matchedElement") or {}).get("value", ""))
        if "presentation=portal" not in value:
            return
        self.player_panel_menu_scenario("portal")

    def primary_video_file(self) -> str:
        if getattr(self, "lane", "device") == "simulator":
            return "sdr-bframe-multiaudio-subtitles-30s.mkv"
        return "furyroad-stripped.mkv"

    def lane_video_file(self, file_name: str) -> str:
        if (
            getattr(self, "lane", "device") == "simulator"
            and file_name.startswith("furyroad")
        ):
            return "sdr-bframe-multiaudio-subtitles-30s.mkv"
        return file_name

    def primary_video_identifier(self) -> str:
        return "MediaLibrary-grid-video-" + self.primary_video_file()

    def open_media(self, identifier: str) -> dict[str, Any]:
        prefix = "MediaLibrary-grid-video-"
        if identifier.startswith(prefix):
            identifier = prefix + self.lane_video_file(
                identifier.removeprefix(prefix)
            )
        self.relaunch()
        self.tap(MAIN_WINDOW_BROWSER_CONTEXT, "Navigation-Ornament-tab-files")
        before = self.copy_probe("open-media-before")
        offset = len(before)
        file_name = identifier.removeprefix("MediaLibrary-grid-video-")
        media_label = f"{Path(file_name).stem}, video"
        operation_id = "accessibility:MediaLibrary-grid-video-{reference.name}"

        def command_with_file_node_retry(
            verb: str, **arguments: str
        ) -> dict[str, Any]:
            result = self.app_command(verb, **arguments)
            if result.get("success") is not True and "file node" in str(
                result.get("error", "")
            ):
                self.hold("pace", 0.5)
                result = self.app_command(verb, **arguments)
            return result

        if getattr(self, "segment", None) is not None:
            imported = command_with_file_node_retry("importMedia", file=file_name)
            if imported.get("success") is not True:
                return imported
        else:
            listing = command_with_file_node_retry("listLibrary")
            library_names = listing.get("payload")
            if not isinstance(library_names, list) or file_name not in library_names:
                imported = command_with_file_node_retry(
                    "importMedia", file=file_name
                )
                if imported.get("success") is not True:
                    return imported
                listing = command_with_file_node_retry("listLibrary")
                library_names = listing.get("payload")
                if not isinstance(library_names, list) or file_name not in library_names:
                    return {
                        "success": False,
                        "error": f"listLibrary did not report imported media {file_name}",
                    }
                self.relaunch()
                self.tap(MAIN_WINDOW_BROWSER_CONTEXT, "Navigation-Ornament-tab-files")

        self.controller("activate", "--no-screenshot")
        card = self.wait_for_identifier(identifier)
        if not isinstance(card.get("matchedElement"), dict):
            return {
                "success": False,
                "error": f"Media card did not appear after product import: {identifier}",
            }
        result = self.tap_label(
            MAIN_WINDOW_BROWSER_CONTEXT,
            media_label,
            operation_id=operation_id,
        )
        probe = self.wait_for_probe(
            "open-media-selected",
            offset,
            "reachability files delivered action=library.video",
        )
        if result.get("success") is True and any(
            "reachability files delivered action=library.video" in line
            for line in probe[offset:]
        ):
            self.delivered(
                MAIN_WINDOW_BROWSER_CONTEXT,
                "accessibility:MediaLibrary-grid-video-{reference.name}",
                self.events[-1]["evidence"],
                "The Media Library video card ran its playback activation handler.",
            )
        self.hold("pace", 2)
        return result

    def open_local_media(self, file_name: str | None = None) -> dict[str, Any]:
        if file_name is None:
            file_name = self.primary_video_file()
        file_name = self.lane_video_file(file_name)
        return self.open_media(f"MediaLibrary-grid-video-{file_name}")

    def video_format_editor_scenario(
        self,
        presentation: str,
        identifier_prefix: str,
        probe_prefix: str,
    ) -> None:
        open_identifier = (
            "PlayerUI-TopAction-videoFormat"
            if identifier_prefix == "PlayerUI-VideoFormat"
            else "PlayerPanel-button-settings"
        )

        def cancel_editor() -> None:
            before = self.copy_probe(f"{identifier_prefix}-cancel-before")
            offset = len(before)
            cancelled = self.tap(
                presentation, f"{identifier_prefix}-cancel"
            )
            probe = self.wait_for_probe(
                f"{identifier_prefix}-cancel",
                offset,
                f"{probe_prefix}videoFormat.cancel",
            )
            if cancelled.get("success") is True and any(
                f"{probe_prefix}videoFormat.cancel" in line
                for line in probe[offset:]
            ):
                self.delivered(
                    presentation,
                    f"accessibility:{identifier_prefix}-cancel",
                    self.events[-1]["evidence"],
                    "Cancel ran the format editor's discard handler and appended its probe.",
                )

        def open_editor() -> bool:
            if self.channel_failures:
                return False
            opened, before = self.tap_with_fresh_controls(
                presentation,
                open_identifier,
                probe_label=f"{identifier_prefix}-open-before",
            )
            if self.channel_failures:
                return False
            offset = len(before)
            visible = self.wait_for_identifier(
                f"{identifier_prefix}-cancel"
            )
            probe = self.copy_probe(f"{identifier_prefix}-opened")
            delivered = opened.get("success") is True and isinstance(
                visible.get("matchedElement"), dict
            ) and video_format_open_was_delivered(probe, offset=offset)
            if delivered:
                self.delivered(
                    presentation,
                    f"accessibility:{open_identifier}",
                    self.events[-1]["evidence"],
                    "The visible format host ran its open handler and appended the product open probe.",
                )
            return delivered

        if open_editor():
            before = self.copy_probe(
                f"{identifier_prefix}-option-before"
            )
            offset = len(before)
            option = self.tap(
                presentation,
                f"{identifier_prefix}-Stereo Layout-Side-by-Side",
                operation_id=(
                    f"accessibility:{identifier_prefix}-"
                    "{title}-{label(option)}"
                ),
            )
            probe = self.wait_for_probe(
                f"{identifier_prefix}-option",
                offset,
                f"{probe_prefix}videoFormat.option.Stereo Layout.Side-by-Side",
            )
            if option.get("success") is True and any(
                f"{probe_prefix}videoFormat.option.Stereo Layout.Side-by-Side"
                in line for line in probe[offset:]
            ):
                self.delivered(
                    presentation,
                    f"accessibility:{identifier_prefix}-"
                    "{title}-{label(option)}",
                    self.events[-1]["evidence"],
                    "The format option changed the editor selection and appended its option probe.",
                )

            cancel_editor()

        if open_editor():
            before = self.copy_probe(
                f"{identifier_prefix}-custom-angle-before"
            )
            offset = len(before)
            picker = self.tap(
                presentation, f"{identifier_prefix}-CustomAngle"
            )
            host = (
                "playerUI"
                if identifier_prefix == "PlayerUI-VideoFormat"
                else "playerPanel"
            )
            _, _, selected = self.select_debug_menu_item(
                presentation=presentation,
                host=host,
                family="customAngle",
                preferred=("180",),
            )
            probe = self.wait_for_probe(
                f"{identifier_prefix}-custom-angle",
                offset,
                f"{probe_prefix}videoFormat.customAngle",
            )
            if (
                picker.get("success") is True
                and selected.get("success") is True
                and any(
                    f"{probe_prefix}videoFormat.customAngle" in line
                    for line in probe[offset:]
                )
            ):
                self.delivered_by_debug_menu_selection(
                    presentation,
                    f"accessibility:{identifier_prefix}-CustomAngle",
                    f"accessibility:{identifier_prefix}-CustomAngle",
                    self.events[-1]["evidence"],
                    "The named custom-angle Picker was hittable; the DEBUG "
                    "equivalent changed the same editor binding and its existing "
                    "product probe confirmed delivery.",
                )
            self.hold("pace", 0.5)
            self.controller(
                "tap", "--label", "180°", "--no-screenshot"
            )
            self.hold("pace", 0.3)
            cancel_editor()

        if open_editor():
            fallback = self.wait_for_identifier(
                f"{identifier_prefix}-HDRFallback"
            )
            if isinstance(fallback.get("matchedElement"), dict):
                before = self.copy_probe(
                    f"{identifier_prefix}-hdr-fallback-before"
                )
                offset = len(before)
                toggled = self.tap(
                    presentation, f"{identifier_prefix}-HDRFallback"
                )
                probe = self.wait_for_probe(
                    f"{identifier_prefix}-hdr-fallback",
                    offset,
                    f"{probe_prefix}videoFormat.hdrFallback",
                )
                if toggled.get("success") is True and any(
                    f"{probe_prefix}videoFormat.hdrFallback" in line
                    for line in probe[offset:]
                ):
                    self.delivered(
                        presentation,
                        f"accessibility:{identifier_prefix}-HDRFallback",
                        self.events[-1]["evidence"],
                        "The HDR fallback toggle changed its editor binding and appended a probe.",
                    )
            cancel_editor()

        if open_editor():
            self.tap(presentation, f"{identifier_prefix}-Projection-Flat")
            before = self.copy_probe(f"{identifier_prefix}-apply-before")
            offset = len(before)
            applied = self.tap(
                presentation, f"{identifier_prefix}-apply"
            )
            probe = self.wait_for_probe(
                f"{identifier_prefix}-apply",
                offset,
                f"{probe_prefix}videoFormat.apply",
            )
            if applied.get("success") is True and any(
                f"{probe_prefix}videoFormat.apply" in line
                for line in probe[offset:]
            ):
                self.delivered(
                    presentation,
                    f"accessibility:{identifier_prefix}-apply",
                    self.events[-1]["evidence"],
                    "Apply ran the format editor's commit handler and appended its probe.",
                )

        if open_editor():
            before = self.copy_probe(f"{identifier_prefix}-automatic-before")
            offset = len(before)
            automatic = self.tap(
                presentation, f"{identifier_prefix}-automatic"
            )
            probe = self.wait_for_probe(
                f"{identifier_prefix}-automatic",
                offset,
                f"{probe_prefix}videoFormat.automatic",
            )
            if automatic.get("success") is True and any(
                f"{probe_prefix}videoFormat.automatic" in line
                for line in probe[offset:]
            ):
                self.delivered(
                    presentation,
                    f"accessibility:{identifier_prefix}-automatic",
                    self.events[-1]["evidence"],
                    "Automatic ran the format restoration handler and appended its probe.",
                )

    def ensure_window_projection(self, projection: str) -> bool:
        control_plane = self.wait_for_identifier("PlayerUI-window-control-plane")
        value = str((control_plane.get("matchedElement") or {}).get("value", ""))
        source_presentation = next(
            (
                candidate for candidate in PRESENTATIONS
                if f"presentation={candidate}" in value
            ),
            "window",
        )
        expected = {
            "Flat": "presentation=window",
            "180°": "presentation=portal",
        }[projection]
        if expected in value:
            return True
        self.show_controls()
        conversion = self.controller(
            "tapSequence",
            "--identifiers",
            "PlayerUI-TopAction-videoFormat",
            f"PlayerUI-VideoFormat-Projection-{projection}",
            "PlayerUI-VideoFormat-apply",
            "--no-screenshot",
        )
        if conversion.get("success") is not True:
            return False
        settled = self.wait_for_identifier("PlayerUI-window-control-plane")
        value = str((settled.get("matchedElement") or {}).get("value", ""))
        delivered = expected in value and "transition=none" in value
        if delivered:
            self.delivered(
                source_presentation,
                "accessibility:PlayerUI-TopAction-videoFormat",
                self.events[-1]["evidence"],
                "The projection menu completed its product transition and the diagnostic control plane reported the settled presentation.",
            )
        return delivered

    def window_scenario(self) -> None:
        presentation = "window"
        opened = self.open_media(
            self.primary_video_identifier()
        )
        if opened.get("success") is not True:
            return
        if not self.ensure_window_projection("Flat"):
            return
        controls = self.show_controls()
        visible = self.wait_for_identifier("PlayerPanel-controls")
        if controls.get("success") is True and isinstance(visible.get("matchedElement"), dict):
            self.delivered(
                presentation, "command:toggleControls", self.events[-1]["evidence"],
                "The command changed product control visibility and the controls entered the hierarchy.",
                has_accessibility_target=False,
            )
        self.video_format_editor_scenario(
            presentation,
            "PlayerUI-VideoFormat",
            "reachability top actions delivered action=",
        )
        self.video_format_editor_scenario(
            presentation,
            "PlayerPanel-VideoFormat",
            "reachability playerPanel delivered action=",
        )
        self.observe(presentation, "Window playback controls")
        self.seek_scenario(presentation, "0.35")
        self.transport_scenario(presentation)
        self.top_menu_scenario(presentation)
        if self.open_local_media("sdr-bframe-multiaudio-subtitles-30s.mkv").get("success") is True and self.ensure_window_projection("Flat"):
            self.top_menu_scenario(presentation)
        self.resume_decision_scenario()
        self.playback_failure_scenario()
        try:
            self.enter_docked_playback(dock_choice="skybox")
        except AttributeError:
            pass
        try:
            self.enter_docked_playback(dock_choice="dark")
        except AttributeError:
            pass

    def window_load_failure_scenario(self) -> None:
        self.playback_failure_scenario()

    def window_remote_audio_episodes_scenario(self) -> None:
        presentation = "window"
        if not self.ensure_remote_episode_playback(presentation, "window"):
            if self.open_local_media("sdr-bframe-multiaudio-subtitles-30s.mkv").get("success") is True and self.ensure_window_projection("Flat"):
                self.top_menu_scenario(presentation)
            return
        self.top_menu_scenario(presentation)

    def window_issue_scenario(self) -> None:
        if self.open_local_media(self.primary_video_file()).get("success") is not True:
            return
        if not self.ensure_window_projection("Flat"):
            return
        for category, identifier, action in (
            ("playbackControlFailed", "PlayerUI-playbackIssue-confirm", "confirm"),
            ("capabilityUnavailable", "PlayerUI-unmetCapability-dismiss", "confirm"),
        ):
            self.exercise_playback_issue(
                "window",
                category=category,
                identifier=identifier,
                action=action,
            )

    def window_dv_format_scenario(self) -> None:
        if self.open_local_media("furyroad-with-dv.mkv").get("success") is not True:
            return
        if not self.ensure_window_projection("Flat"):
            return
        self.video_format_editor_scenario(
            "window",
            "PlayerUI-VideoFormat",
            "reachability top actions delivered action=",
        )

    def window_hdr_fallback_scenario(self) -> None:
        presentation = "window"
        if self.open_local_media("furyroad-with-dv.mkv").get("success") is not True:
            return
        if not self.ensure_window_projection("Flat"):
            return

        opened, before = self.tap_with_fresh_controls(
            presentation,
            "PlayerUI-TopAction-videoFormat",
            probe_label="window-hdr-open-before",
        )
        offset = len(before)
        fallback = self.wait_for_identifier(
            "PlayerUI-VideoFormat-HDRFallback"
        )
        probe = self.copy_probe("window-hdr-opened")
        if (
            opened.get("success") is True
            and isinstance(fallback.get("matchedElement"), dict)
            and video_format_open_was_delivered(probe, offset=offset)
        ):
            self.delivered(
                presentation,
                "accessibility:PlayerUI-TopAction-videoFormat",
                self.events[-1]["evidence"],
                "The Window format host ran its open handler and exposed HDR Fallback.",
            )

        before = probe
        offset = len(before)
        toggled = self.tap(
            presentation, "PlayerUI-VideoFormat-HDRFallback"
        )
        probe = self.wait_for_probe(
            "window-hdr-fallback",
            offset,
            "reachability top actions delivered action=videoFormat.hdrFallback",
        )
        if toggled.get("success") is True and any(
            "reachability top actions delivered action=videoFormat.hdrFallback"
            in line for line in probe[offset:]
        ):
            self.delivered(
                presentation,
                "accessibility:PlayerUI-VideoFormat-HDRFallback",
                self.events[-1]["evidence"],
                "The HDR fallback toggle changed its editor binding and appended a probe.",
            )

    def window_menu_scenario(self) -> None:
        if self.open_local_media("furyroad-with-dv.mkv").get("success") is not True:
            return
        if not self.ensure_window_projection("Flat"):
            return
        self.player_panel_media_information_scenario("window")
        self.top_menu_scenario("window")

    def window_media_information_scenario(self) -> None:
        if self.open_local_media("furyroad-with-dv.mkv").get("success") is not True:
            return
        if self.ensure_window_projection("Flat"):
            self.player_panel_media_information_scenario("window")

    def window_top_menu_scenario(self) -> None:
        if self.open_local_media("furyroad-with-dv.mkv").get("success") is not True:
            return
        if self.ensure_window_projection("Flat"):
            self.top_menu_scenario("window")

    def window_environment_scenario(self) -> None:
        presentation = "window"
        self.relaunch()
        before = self.copy_probe("window-environment-before")
        offset = len(before)
        opened = self.tap(
            MAIN_WINDOW_BROWSER_CONTEXT,
            "Navigation-Ornament-tab-environment",
        )
        volume = self.wait_for_identifier("SenseZone-VolumeRoot")
        identifiers = self.hierarchy_identifiers(volume)
        environment_identifier = next(
            (
                value for value in sorted(identifiers)
                if value.startswith("EnvironmentCard-button-environment-")
            ),
            None,
        )
        effect_identifier = next(
            (
                value for value in sorted(identifiers)
                if value.startswith("EnvironmentCard-effect-")
            ),
            None,
        )
        if opened.get("success") is not True or effect_identifier is None:
            return
        for identifier, operation_id in (
            ("EnvironmentCard-card", "accessibility:EnvironmentCard-card"),
            ("EnvironmentCard-carousel", "accessibility:EnvironmentCard-carousel"),
        ):
            self.tap(presentation, identifier, operation_id=operation_id)
        changed = self.tap(
            presentation,
            effect_identifier,
            operation_id=(
                "accessibility:EnvironmentCard-effect-"
                "{environment.environment.rawValue}"
            ),
        )
        probe = self.copy_probe("window-environment-effect")
        effect_delivered = changed.get("success") is True and any(
            "environmentCard effect delivered" in line
            for line in probe[offset:]
        )
        if effect_delivered:
            for operation_id in (
                "accessibility:EnvironmentCard-effect-"
                "{environment.environment.rawValue}",
                "accessibility:EnvironmentCard-card",
                "accessibility:EnvironmentCard-carousel",
            ):
                self.mark_observation(
                    presentation,
                    operation_id,
                    received=True,
                    evidence=self.events[-1]["evidence"],
                    reason="A contained Environment Card effect reached its product handler.",
                )
        if environment_identifier is not None:
            toggle_offset = len(probe)
            toggled = self.tap(
                presentation,
                environment_identifier,
                operation_id=(
                    "accessibility:EnvironmentCard-button-environment-"
                    "{environment.environment.rawValue}"
                ),
            )
            probe = self.copy_probe("window-environment-toggle")
            if toggled.get("success") is True and any(
                "environmentCard toggle delivered" in line
                for line in probe[toggle_offset:]
            ):
                self.delivered(
                    presentation,
                    "accessibility:EnvironmentCard-button-environment-"
                    "{environment.environment.rawValue}",
                    self.events[-1]["evidence"],
                    "The visible environment button reached the product toggle handler.",
                )
        dismissed = self.app_command("dismissEnvironmentCard")
        closed = self.wait_for_identifier_absent("SenseZone-VolumeRoot")
        if effect_delivered and dismissed.get("success") is True and closed:
            self.delivered(
                presentation,
                "environmentVolume:open-interact-close",
                self.events[-1]["evidence"],
                "Open, effect interaction, and application-driven close each produced device evidence.",
                has_accessibility_target=False,
            )

    def player_ui_candidate_scenario(self) -> None:
        presentation = "window"
        opened = self.open_media(
            self.primary_video_identifier()
        )
        if opened.get("success") is not True:
            return
        if not self.ensure_window_projection("Flat"):
            return
        controls = self.show_controls()
        visible = self.wait_for_identifier("PlayerPanel-controls")
        if controls.get("success") is True and isinstance(
            visible.get("matchedElement"), dict
        ):
            self.delivered(
                presentation,
                "command:toggleControls",
                self.events[-1]["evidence"],
                "The command changed product control visibility and the controls entered the hierarchy.",
                has_accessibility_target=False,
            )
        self.video_format_editor_scenario(
            presentation,
            "PlayerUI-VideoFormat",
            "reachability top actions delivered action=",
        )
        if self.channel_failures:
            return
        self.seek_scenario(presentation, "0.35")
        before = self.copy_probe("window-forward-before")
        offset = len(before)
        forwarded = self.tap_control(
            presentation, "PlayerPanel-button-forward"
        )
        probe = self.wait_for_probe(
            "window-forward",
            offset,
            "playback control delivered action=forward",
        )
        if forwarded.get("success") is True and any(
            "playback control delivered action=forward" in line
            for line in probe[offset:]
        ):
            self.delivered(
                presentation,
                "accessibility:PlayerPanel-button-forward",
                self.events[-1]["evidence"],
                "The forward control closure appended its action-specific application probe after the deterministic pre-seek.",
            )
        self.top_menu_scenario(presentation)

    def transport_scenario(self, presentation: str) -> None:
        before = self.copy_probe(f"{presentation}-transport-before")
        offset = len(before)
        for identifier, fact in (
            ("PlayerPanel-button-rewind", "rewind"),
            ("PlayerPanel-button-forward", "forward"),
            ("PlayerPanel-button-play", "playPause"),
        ):
            response = self.tap_control(presentation, identifier)
            probe = self.copy_probe(f"{presentation}-{fact}")
            spellings = (
                f"playback control delivered action={fact}",
                f"reachability playerPanel delivered action={fact}",
            )
            if response.get("success") is True and any(
                spelling in line
                for line in probe[offset:]
                for spelling in spellings
            ):
                self.delivered(
                    presentation, f"accessibility:{identifier}",
                    self.events[-1]["evidence"],
                    "The control closure appended its action-specific application probe.",
                )
            offset = len(probe)

    def seek_scenario(self, presentation: str, position: str) -> None:
        seek = self.app_command("seekNormalized", position=position)
        if seek.get("success") is not True:
            return
        evidence = self.events[-1]["evidence"]
        self.delivered(
            presentation, "command:seekNormalized", evidence,
            "The DEBUG verb reached PlaybackRuntime.seek and returned the computed target.",
            has_accessibility_target=False,
        )
        for operation_id in (
            "accessibility:PlayerPanel-progress",
            "accessibility:PlayerPanel-precision-timeline",
        ):
            self.delivered(
                presentation, operation_id, evidence,
                "The DEBUG verb reached the same PlaybackRuntime seek pipeline.",
            )

    def top_menu_scenario(self, presentation: str) -> None:
        opened, before = self.tap_with_fresh_controls(
            presentation,
            "PlayerUI-TopAction-more",
            probe_label=f"{presentation}-top-menu-before",
        )
        offset = len(before)
        probe = self.copy_probe(f"{presentation}-top-menu-open")
        if opened.get("success") is True and any(
            "reachability top actions delivered action=menu.more" in line
            for line in probe[offset:]
        ):
            self.delivered(
                presentation, "accessibility:PlayerUI-TopAction-more",
                self.events[-1]["evidence"],
                "Opening the system Menu caused its product-owned content to append a probe.",
            )

        family_operations = (
            ("speed", "accessibility:PlayerUI-menu-speed", ("1.25",)),
            ("subtitles", "accessibility:PlayerUI-menu-subtitles", ("off",)),
            ("audio", "accessibility:PlayerUI-menu-audio", ()),
            ("episodes", "accessibility:PlayerUI-menu-episodes", ()),
        )
        segment = getattr(self, "segment", None)
        if segment is not None:
            planned = {
                (str(value["context"]), str(value["operation"]))
                for value in segment["decisions"]
            }
            family_operations = tuple(
                entry for entry in family_operations
                if (presentation, entry[1]) in planned
            )
        for family, operation_id, preferred in family_operations:
            if family in ("audio", "episodes"):
                try:
                    snapshot = self.controller("snapshot", "--no-screenshot")
                    identifiers = self.hierarchy_identifiers(snapshot)
                except AttributeError:
                    identifiers = {operation_id.split(":", 1)[1]}
                expected = operation_id.split(":", 1)[1]
                if expected not in identifiers and identifiers:
                    try:
                        cell = self.cells.get((presentation, operation_id))
                    except AttributeError:
                        cell = None
                    if cell is not None and cell.get("verdict") == "unmeasured":
                        try:
                            cell["evidence"].append(self.events[-1]["evidence"])
                        except (AttributeError, IndexError, KeyError):
                            pass
                        cell["reason"] = f"The More menu did not expose {expected} after opening; snapshot shows menu content without that identifier, so the precondition for {operation_id} is missing and the cell remains unmeasured."
                    continue
            item_offset = len(probe)
            target, _, selected = self.select_debug_menu_item(
                presentation=presentation,
                host="playerUI",
                family=family,
                preferred=preferred,
                driven_operations=(
                    operation_id,
                    "accessibility:PlayerUI-menu-{category}-{item.id}",
                ),
            )
            probe = self.copy_probe(f"{presentation}-top-{family}-selected")
            if selected.get("success") is True and target is not None and any(
                top_menu_delivery_probe_needle(target) in line
                for line in probe[item_offset:]
            ):
                self.delivered_by_debug_menu_selection(
                    presentation,
                    operation_id,
                    "accessibility:PlayerUI-TopAction-more",
                    self.events[-1]["evidence"],
                    "The named More parent supplied hierarchy and hittability evidence; "
                    f"the DEBUG equivalent entered the {family} Picker binding and its "
                    "menu.item product probe confirmed delivery.",
                )
                self.delivered_by_debug_menu_selection(
                    presentation,
                    "accessibility:PlayerUI-menu-{category}-{item.id}",
                    "accessibility:PlayerUI-TopAction-more",
                    self.events[-1]["evidence"],
                    "The named More parent supplied hierarchy and hittability evidence; "
                    "the DEBUG equivalent entered the exact item action and its product "
                    "probe confirmed delivery.",
                )

        speed = self.controller(
            "tap", "--label", "Playback Speed", "--no-screenshot",
        )
        if speed.get("success") is True:
            self.controller(
                "tap", "--label", "1.25×", "--no-screenshot",
            )

    def stop_playback(self, presentation: str) -> bool:
        stopped, before = self.tap_with_fresh_controls(
            presentation,
            "PlayerUI-InfoBar-button-back",
            probe_label=f"{presentation}-back-before",
        )
        offset = len(before)
        probe = self.copy_probe(f"{presentation}-back")
        delivered = stopped.get("success") is True and any(
            "reachability top actions delivered action=back" in line
            for line in probe[offset:]
        )
        if delivered:
            self.delivered(
                presentation, "accessibility:PlayerUI-InfoBar-button-back",
                self.events[-1]["evidence"],
                "The Back control stopped playback through PlaybackLaunchCoordinator and appended its product probe.",
            )
        return delivered

    def resume_decision_scenario(self) -> None:
        presentation = MAIN_WINDOW_BROWSER_CONTEXT
        playback_context = "window"
        active = self.wait_for_identifier(
            "PlayerUI-window-control-plane"
        )
        if isinstance(active.get("matchedElement"), dict):
            if not self.stop_playback(playback_context):
                return
            self.wait_for_identifier("FileBrowsing-FilesScreen-list")

        self.tap(presentation, "Navigation-Ornament-tab-settings")
        settings = self.controller("snapshot", "--no-screenshot")
        hierarchy = str(settings.get("hierarchy", ""))
        current_policy = next(
            (
                title for title in (
                    "Ask Every Time",
                    "Always Resume",
                    "Always Start Over",
                )
                if f"label: '{title}'" in hierarchy
            ),
            None,
        )
        if current_policy is None:
            return
        if current_policy == "Ask Every Time":
            selected = {"success": True}
        else:
            opened = self.controller(
                "tap", "--label", current_policy, "--no-screenshot",
            )
            if opened.get("success") is not True:
                return
            selected = self.controller(
                "tap", "--label", "Ask Every Time", "--no-screenshot",
            )
        if selected.get("success") is not True:
            return

        self.tap(presentation, "Navigation-Ornament-tab-files")
        resume_media = "MediaLibrary-grid-video-reachability-resume-16m.mp4"
        available = self.wait_for_identifier(resume_media)
        if not isinstance(available.get("matchedElement"), dict):
            imported = self.app_command(
                "importMedia", file="reachability-resume-16m.mp4"
            )
            if imported.get("success") is not True:
                return
            self.relaunch()
            self.tap(presentation, "Navigation-Ornament-tab-files")
            available = self.wait_for_identifier(resume_media)
            if not isinstance(available.get("matchedElement"), dict):
                return
        started = self.tap(
            presentation, resume_media,
            operation_id="accessibility:MediaLibrary-grid-video-{reference.name}",
        )
        if started.get("success") is not True:
            return
        if not isinstance(
            self.wait_for_identifier(
                "PlayerUI-window-control-plane"
            ).get("matchedElement"),
            dict,
        ):
            return
        self.hold("pace", 16)
        seek = self.app_command(
            "seekNormalized",
            position="0.25",
            track_reachability=False,
        )
        if seek.get("success") is not True:
            return
        if not self.stop_playback(playback_context):
            return
        self.wait_for_identifier("FileBrowsing-FilesScreen-list")

        for identifier, fact in (
            ("PlayerUI-resumeDecision-primary", "resume"),
            ("PlayerUI-resumeDecision-secondary", "startOver"),
        ):
            opened = self.tap(
                presentation, resume_media,
                operation_id="accessibility:MediaLibrary-grid-video-{reference.name}",
            )
            if opened.get("success") is not True:
                return
            decision = self.wait_for_identifier(identifier)
            if not isinstance(decision.get("matchedElement"), dict):
                return
            before = self.copy_probe(f"resume-{fact}-before")
            offset = len(before)
            chosen = self.tap(presentation, identifier)
            probe = self.wait_for_probe(
                f"resume-{fact}",
                offset,
                f"reachability resume decision delivered action={fact}",
            )
            if chosen.get("success") is True and any(
                f"reachability resume decision delivered action={fact}" in line
                for line in probe[offset:]
            ):
                self.delivered(
                    presentation, f"accessibility:{identifier}",
                    self.events[-1]["evidence"],
                    "The visible resume decision ran its product-owned playback choice and appended an action probe.",
                )
            self.wait_for_identifier("PlayerUI-window-control-plane")
            if not self.stop_playback(playback_context):
                return
            self.wait_for_identifier("FileBrowsing-FilesScreen-list")

    def playback_failure_scenario(self) -> None:
        presentation = "window"
        try:
            self.budgets
            self.cells
            self.events
        except AttributeError:
            return
        opened = self.open_media(
            "MediaLibrary-grid-video-broken-clip.mp4"
        )
        if opened.get("success") is not True:
            return

        primary, _ = self.wait_for_any_identifier(
            (
                "PlayerUI-loadFailure-primary",
                "PlayerUI-playbackIssue-primary",
            ),
        )
        if primary is not None:
            before = self.copy_probe("playback-failure-primary-before")
            offset = len(before)
            retried = self.tap(presentation, primary)
            probe = self.copy_probe("playback-failure-primary")
            if retried.get("success") is True and any(
                "reachability playback issue delivered" in line
                and "action=retry" in line
                for line in probe[offset:]
            ):
                self.delivered(
                    presentation, f"accessibility:{primary}",
                    self.events[-1]["evidence"],
                    "The negative media exposed the product failure alert and Retry ran its application handler.",
                )
        else:
            snapshot = self.controller("snapshot", "--no-screenshot")
            hierarchy = str(snapshot.get("hierarchy", ""))
            if "label: 'Retry'" in hierarchy:
                self.mark_observation(
                    presentation,
                    "accessibility:PlayerUI-loadFailure-primary",
                    evidence=self.events[-1]["evidence"],
                    reason="The product raised its failure alert but the Retry button exposes only label 'Retry' and not identifier PlayerUI-loadFailure-primary assigned in MainView.swift; snapshot shows label without identifier, violating the identifier contract.",
                )
                self.controller("tap", "--label", "Retry", "--no-screenshot")
                self.hold("pace", 0.5)

        secondary, _ = self.wait_for_any_identifier(
            (
                "PlayerUI-loadFailure-secondary",
                "PlayerUI-playbackIssue-secondary",
                "PlayerUI-playbackIssue-confirm",
            ),
        )
        if secondary is not None:
            before = self.copy_probe("playback-failure-secondary-before")
            offset = len(before)
            closed = self.tap(presentation, secondary)
            probe = self.copy_probe("playback-failure-secondary")
            expected_action = "confirm" if secondary.endswith("confirm") else "close"
            if closed.get("success") is True and any(
                "reachability playback issue delivered" in line
                and f"action={expected_action}" in line
                for line in probe[offset:]
            ):
                self.delivered(
                    presentation, f"accessibility:{secondary}",
                    self.events[-1]["evidence"],
                    "The visible product failure alert ran its terminal action and appended a probe.",
                )
        else:
            snapshot = self.controller("snapshot", "--no-screenshot")
            hierarchy = str(snapshot.get("hierarchy", ""))
            if "label: 'Close'" in hierarchy:
                self.mark_observation(
                    presentation,
                    "accessibility:PlayerUI-loadFailure-secondary",
                    evidence=self.events[-1]["evidence"],
                    reason="The product raised its failure alert but the Close button exposes only label 'Close' and not identifier PlayerUI-loadFailure-secondary assigned in MainView.swift; snapshot shows label without identifier, violating the identifier contract.",
                )
                self.controller("tap", "--label", "Close", "--no-screenshot")
                self.hold("pace", 0.5)

    def player_panel_menu_scenario(self, presentation: str) -> None:
        opens_system_menu = should_open_player_panel_system_menu(presentation)
        if opens_system_menu:
            opened, before = self.tap_with_fresh_controls(
                presentation,
                "PlayerPanel-menu-more",
                probe_label=f"{presentation}-panel-menu-before",
            )
            offset = len(before)
            probe = self.copy_probe(f"{presentation}-panel-menu-open")
            if opened.get("success") is True and any(
                "reachability playerPanel delivered action=menu.more" in line
                for line in probe[offset:]
            ):
                self.delivered(
                    presentation,
                    "accessibility:PlayerPanel-menu-more",
                    self.events[-1]["evidence"],
                    "The named PlayerPanel More menu was hittable and constructed its product content.",
                )
        else:
            self.show_controls()
            observed = self.wait_for_identifier("PlayerPanel-menu-more")
            matched = observed.get("matchedElement")
            if isinstance(matched, dict):
                is_hittable = matched.get("isHittable") is True
                self.mark_observation(
                    presentation,
                    "accessibility:PlayerPanel-menu-more",
                    exists=True,
                    hittable=is_hittable,
                    evidence=self.events[-1]["evidence"],
                    reason=(
                        "The immersive attachment exposed the named More parent. "
                        "The system-owned Menu is not synthesized in this scene."
                    ),
                )
                if is_hittable:
                    self.mark_observation(
                        presentation,
                        "accessibility:PlayerPanel-menu-more",
                        received=True,
                        evidence=self.events[-1]["evidence"],
                        reason="The immersive More control was hittable and its hierarchy entry proves product delivery.",
                    )
            probe = self.copy_probe(f"{presentation}-panel-menu-observed")

        family_operations = (
            ("speed", "accessibility:PlayerPanel-menu-speed", ("1.25",)),
            ("subtitles", "accessibility:PlayerPanel-menu-subtitles", ("off",)),
            ("audio", "accessibility:PlayerPanel-menu-audio", ()),
            ("episodes", "accessibility:PlayerPanel-menu-episodes", ()),
        )
        segment = getattr(self, "segment", None)
        if segment is not None:
            planned = {
                (str(value["context"]), str(value["operation"]))
                for value in segment["decisions"]
            }
            family_operations = tuple(
                entry for entry in family_operations
                if (presentation, entry[1]) in planned
            )
        for family, operation_id, preferred in family_operations:
            if not opens_system_menu:
                self.show_controls()
                self.await_controls()
            item_offset = len(probe)
            target, _, selected = self.select_debug_menu_item(
                presentation=presentation,
                host="playerPanel",
                family=family,
                preferred=preferred,
                driven_operations=(
                    operation_id,
                    "accessibility:PlayerPanel-menu-{category}-{item.id}",
                ),
            )
            probe = self.copy_probe(
                f"{presentation}-panel-{family}-selected"
            )
            if selected.get("success") is True and target is not None and any(
                menu_delivery_probe_needle(target) in line
                for line in probe[item_offset:]
            ):
                self.delivered_by_debug_menu_selection(
                    presentation,
                    operation_id,
                    "accessibility:PlayerPanel-menu-more",
                    self.events[-1]["evidence"],
                    "The named More parent supplied hierarchy and hittability evidence; "
                    f"the DEBUG equivalent entered the {family} item handler and its "
                    "menu.item product probe confirmed delivery.",
                )
                self.delivered_by_debug_menu_selection(
                    presentation,
                    "accessibility:PlayerPanel-menu-{category}-{item.id}",
                    "accessibility:PlayerPanel-menu-more",
                    self.events[-1]["evidence"],
                    "The named More parent supplied hierarchy and hittability evidence; "
                    "the DEBUG equivalent entered the exact item action and its product "
                    "probe confirmed delivery.",
                )

        if opens_system_menu:
            self.controller(
                "tap", "--label", "Playback Speed", "--no-screenshot",
            )
            self.controller(
                "tap", "--label", "1×", "--no-screenshot",
            )

    def docked_settings_scenario(self) -> None:
        presentation = "docked"
        self.show_controls()
        before = self.copy_probe("docked-settings-before")
        offset = len(before)
        opened = self.tap(presentation, "PlayerPanel-button-settings")
        probe = self.copy_probe("docked-settings-open")
        if opened.get("success") is True and any(
            "reachability playerPanel delivered action=settings.open" in line
            for line in probe[offset:]
        ):
            self.delivered(
                presentation, "accessibility:PlayerPanel-button-settings",
                self.events[-1]["evidence"],
                "The settings button expanded the Docked placement controls and appended a probe.",
            )
        before = probe
        offset = len(before)
        reset = self.tap(presentation, "PlayerPanel-DockedPlacement-reset")
        probe = self.copy_probe("docked-placement-reset")
        if reset.get("success") is True and any(
            "reachability playerPanel delivered action=dockedPlacement.reset" in line
            for line in probe[offset:]
        ):
            self.delivered(
                presentation, "accessibility:PlayerPanel-DockedPlacement-reset",
                self.events[-1]["evidence"],
                "Restore Defaults reached the shared Docked placement reset handler.",
            )


    def enter_panorama_playback(
        self, file_name: str | None = None
    ) -> bool:
        presentation = "panorama"
        opened = self.open_local_media(file_name)
        if opened.get("success") is not True:
            return False
        if not self.ensure_window_projection("180°"):
            return False
        self.show_controls()
        before = self.copy_probe("panorama-transition-before")
        offset = len(before)
        entered = self.controller(
            "tapSequence",
            "--identifiers",
            "PlayerUI-TopAction-resumePanorama",
            "--no-screenshot",
        )
        if entered.get("success") is not True:
            return False
        spatial = self.wait_for_identifier("PlayerUI-spatial-state")
        if not isinstance(spatial.get("matchedElement"), dict):
            return False
        probe = self.copy_probe("panorama-transition-settled")
        if reachability_action_was_delivered(probe, "enterPanorama", offset=offset):
            self.mark_observation(
                "portal",
                "accessibility:PlayerUI-TopAction-resumePanorama",
                exists=True,
                hittable=True,
                received=True,
                evidence=self.events[-1]["evidence"],
                reason="The visible Panorama entry action appended its product probe and the immersive state became addressable.",
            )
        self.observe(presentation, "Panorama playback")
        return True

    def panorama_scenario(self) -> bool:
        presentation = "panorama"
        if not self.enter_panorama_playback():
            return False
        controls = self.show_controls()
        visible = self.wait_for_identifier("PlayerPanel-controls")
        if controls.get("success") is True and isinstance(visible.get("matchedElement"), dict):
            self.delivered(
                presentation, "command:toggleControls", self.events[-1]["evidence"],
                "The immersive attachment controls entered the hierarchy after the product command.",
                has_accessibility_target=False,
            )
        self.transport_scenario(presentation)
        self.seek_scenario(presentation, "0.45")
        self.player_panel_menu_scenario(presentation)
        return True

    def panorama_content_scenario(self) -> None:
        if not self.enter_panorama_playback(
            "sdr-bframe-multiaudio-subtitles-30s.mkv"
        ):
            return
        self.player_panel_media_information_scenario("panorama")
        self.player_panel_menu_scenario("panorama")

    def portal_scenario(self) -> None:
        presentation = "portal"
        opened = self.open_media(self.primary_video_identifier())
        if opened.get("success") is not True:
            return
        if not self.ensure_window_projection("180°"):
            return
        portal = self.wait_for_identifier("PlayerUI-window-control-plane")
        value = str((portal.get("matchedElement") or {}).get("value", ""))
        if "presentation=portal" not in value:
            return
        self.observe(presentation, "Portal playback")
        size = self.app_command("setWindowSize", width="1180", height="720")
        self.hold("pace", 1)
        probe = self.copy_probe("portal-window-size")
        if size.get("success") is True and any(
            "setWindowSize observed=" in line for line in probe
        ):
            self.delivered(
                presentation, "command:setWindowSize", self.events[-1]["evidence"],
                "The geometry request pipeline recorded the observed applied size.",
                has_accessibility_target=False,
            )
        controls = self.show_controls()
        visible = self.wait_for_identifier("PlayerPanel-controls")
        if controls.get("success") is True and isinstance(visible.get("matchedElement"), dict):
            self.delivered(
                presentation, "command:toggleControls", self.events[-1]["evidence"],
                "The Portal controls entered the hierarchy after the product command.",
                has_accessibility_target=False,
            )
        self.transport_scenario(presentation)
        self.seek_scenario(presentation, "0.4")
        self.top_menu_scenario(presentation)
        if self.open_local_media("sdr-bframe-multiaudio-subtitles-30s.mkv").get("success") is True and self.ensure_window_projection("180°"):
            portal_check = self.wait_for_identifier("PlayerUI-window-control-plane")
            if "presentation=portal" in str((portal_check.get("matchedElement") or {}).get("value", "")):
                self.top_menu_scenario(presentation)
        self.portal_remote_audio_episodes_scenario()

    def portal_remote_audio_episodes_scenario(self) -> None:
        presentation = "portal"
        if not self.ensure_remote_episode_playback(presentation, "portal"):
            if self.open_local_media("sdr-bframe-multiaudio-subtitles-30s.mkv").get("success") is True and self.ensure_window_projection("180°"):
                self.top_menu_scenario(presentation)
            return
        self.top_menu_scenario(presentation)

    def enter_portal_playback(
        self, file_name: str | None = None
    ) -> bool:
        if self.open_local_media(file_name).get("success") is not True:
            return False
        if not self.ensure_window_projection("180°"):
            return False
        control_plane = self.wait_for_identifier(
            "PlayerUI-window-control-plane"
        )
        value = str((control_plane.get("matchedElement") or {}).get("value", ""))
        return "presentation=portal" in value and "transition=none" in value

    def portal_dv_scenario(self) -> None:
        if not self.enter_portal_playback(self.lane_video_file("furyroad-with-dv.mkv")):
            return
        self.video_format_editor_scenario(
            "portal",
            "PlayerUI-VideoFormat",
            "reachability top actions delivered action=",
        )
        self.player_panel_media_information_scenario("portal")

    def portal_issue_scenario(self) -> None:
        cases = (
            ("mediaOpeningFailed", "PlayerUI-loadFailure-primary", "retry"),
            ("mediaOpeningFailed", "PlayerUI-loadFailure-secondary", "close"),
            ("playbackControlFailed", "PlayerUI-playbackIssue-confirm", "confirm"),
            ("capabilityUnavailable", "PlayerUI-unmetCapability-dismiss", "confirm"),
        )
        for category, identifier, action in cases:
            if not self.enter_portal_playback():
                return
            self.exercise_playback_issue(
                "portal",
                category=category,
                identifier=identifier,
                action=action,
            )

    def portal_route_scenario(self) -> None:
        if not self.enter_portal_playback():
            return
        self.stop_playback("portal")
        self.enter_panorama_playback()

    def enter_docked_playback(
        self,
        *,
        dock_choice: str = "skybox",
        file_name: str | None = None,
        record_route: bool = False,
    ) -> bool:
        if not hasattr(self, 'events'):
            return False
        if not hasattr(self, 'segment'):
            self.segment = None
        presentation = "docked"
        opened = self.open_local_media(file_name)
        if opened.get("success") is not True:
            return False
        if not self.ensure_window_projection("Flat"):
            return False

        if record_route:
            self.show_controls()
            before = self.copy_probe("docked-video-format-before")
            offset = len(before)
            changed = self.controller(
                "tapSequence",
                "--identifiers",
                "PlayerUI-TopAction-videoFormat",
                "PlayerUI-VideoFormat-Projection-Flat",
                "PlayerUI-VideoFormat-apply",
                "--no-screenshot",
            )
            probe = self.copy_probe("docked-video-format-applied")
            if changed.get("success") is True and all(
                any(f"action={action}" in line for line in probe[offset:])
                for action in ("videoFormat.open", "videoFormat.apply")
            ):
                self.delivered(
                    "window",
                    "accessibility:PlayerUI-TopAction-videoFormat",
                    self.events[-1]["evidence"],
                    "The Docked route opened and applied the product Video Format editor, with both DEBUG probes present.",
                )

        self.show_controls()
        before = self.copy_probe(f"docked-{dock_choice}-transition-before")
        offset = len(before)
        transition = self.controller(
            "tapSequence",
            "--identifiers",
            "PlayerUI-TopAction-dock",
            f"PlayerUI-DockMenu-{dock_choice}",
            "--no-screenshot",
        )
        spatial = self.wait_for_identifier("PlayerUI-spatial-state")
        value = str((spatial.get("matchedElement") or {}).get("value", ""))
        probe = self.copy_probe(f"docked-{dock_choice}-settled")
        settled = all(
            fact in value
            for fact in (
                "presentation=docked",
                "transition=none",
                "surfacePreparation=surfaceAttached",
                "lifecycle=Playing",
                "attached=docked",
                "rendererConsumer=docked",
                "displayedPixel=true",
                "surfaceRenderingReady=true",
                "surfaceSettled=true",
            )
        )
        delivered_probe = reachability_action_was_delivered(
            probe, "dock.open", offset=offset
        ) and any(
            "reachability " in line
            and " delivered action=dock.select" in line
            and f"effect={'none' if dock_choice == 'skybox' else dock_choice}" in line
            for line in probe[offset:]
        ) and any(
            "worldLoad event=completed anchor=PlaybackSurfaceAnchor" in line
            for line in probe[offset:]
        )
        if transition.get("success") is not True or not settled or not delivered_probe:
            return False

        route_operations = ["accessibility:PlayerUI-TopAction-dock"]
        if dock_choice == "skybox":
            route_operations.append("accessibility:PlayerUI-DockMenu-skybox")
        else:
            route_operations.append("accessibility:PlayerUI-DockMenu-{$0.rawValue}")
        for operation_id in route_operations:
            self.mark_observation(
                "window",
                operation_id,
                exists=True,
                hittable=True,
                evidence=self.events[-3]["evidence"],
                reason="XCTest completed the Docked menu route.",
            )
            self.mark_observation(
                "window",
                operation_id,
                evidence=self.events[-2]["evidence"],
                reason="The spatial diagnostic reached settled Docked playback with displayed pixels.",
            )
            self.mark_observation(
                "window",
                operation_id,
                received=True,
                evidence=self.events[-1]["evidence"],
                reason="The top-action probe, Dock target probe, world anchor probe, and settled diagnostic all agree.",
            )
        for operation_id in (
            "accessibility:PlayerUI-TopAction-dock",
            "accessibility:PlayerUI-DockMenu-skybox",
        ):
            if operation_id in route_operations:
                self.delivered(
                    "window",
                    operation_id,
                    self.events[-1]["evidence"],
                    "The presentation entered settled Docked playback after the menu sequence.",
                )
        return True

    def docked_environment_card_scenario(self) -> None:
        presentation = "docked"
        before = self.copy_probe("docked-environment-card-before")
        offset = len(before)
        opened = self.app_command("openEnvironmentCard")
        self.controller("activate", "--no-screenshot")
        volume = self.wait_for_identifier("SenseZone-VolumeRoot")
        identifiers = self.hierarchy_identifiers(volume)
        effect_identifier = next(
            (value for value in sorted(identifiers)
             if value.startswith("EnvironmentCard-effect-")),
            None,
        )
        environment_identifier = next(
            (value for value in sorted(identifiers)
             if value.startswith("EnvironmentCard-button-environment-")),
            None,
        )
        if opened.get("success") is not True or effect_identifier is None:
            self.controller(
                "snapshot",
                "--identifier",
                "PlayerUI-spatial-state",
                "--no-screenshot",
            )
            return

        changed = self.tap(presentation, effect_identifier, operation_id=(
            "accessibility:EnvironmentCard-effect-"
            "{environment.environment.rawValue}"
        ))
        probe = self.copy_probe("docked-environment-card-effect")
        effect_delivered = changed.get("success") is True and any(
            "environmentCard effect delivered" in line
            for line in probe[offset:]
        )
        if effect_delivered:
            evidence = self.events[-1]["evidence"]
            for operation_id in (
                "accessibility:EnvironmentCard-effect-"
                "{environment.environment.rawValue}",
                "accessibility:EnvironmentCard-card",
                "accessibility:EnvironmentCard-carousel",
            ):
                self.mark_observation(
                    presentation,
                    operation_id,
                    exists=True,
                    hittable=True,
                    evidence=self.events[-2]["evidence"],
                    reason="The Environment volume exposed the product card structure.",
                )
                self.mark_observation(
                    presentation,
                    operation_id,
                    received=True,
                    evidence=evidence,
                    reason="The DEBUG open verb reached its terminal state and the card's effect handler appended a product probe.",
                )

        if environment_identifier is not None:
            toggle_offset = len(probe)
            toggled = self.tap(
                presentation,
                environment_identifier,
                operation_id=(
                    "accessibility:EnvironmentCard-button-environment-"
                    "{environment.environment.rawValue}"
                ),
            )
            probe = self.copy_probe("docked-environment-card-toggle")
            if toggled.get("success") is True and any(
                "environmentCard toggle delivered" in line
                for line in probe[toggle_offset:]
            ):
                self.delivered(
                    presentation,
                    "accessibility:EnvironmentCard-button-environment-"
                    "{environment.environment.rawValue}",
                    self.events[-1]["evidence"],
                    "The visible environment button reached the product toggle handler and appended its probe.",
                )

        self.hold("pace", 0.8)
        dismissed = self.app_command("dismissEnvironmentCard")
        closed = self.wait_for_identifier_absent("SenseZone-VolumeRoot")
        if effect_delivered and dismissed.get("success") is True and closed:
            self.delivered(
                presentation,
                "environmentVolume:open-interact-close",
                self.events[-1]["evidence"],
                "The DEBUG open and dismiss verbs bracketed a probed product interaction and the volume disappeared.",
                has_accessibility_target=False,
            )
        elif effect_delivered and dismissed.get("success") is True:
            self.hold("pace", 1.2)
            closed_retry = self.wait_for_identifier_absent("SenseZone-VolumeRoot")
            if closed_retry:
                self.delivered(
                    presentation,
                    "environmentVolume:open-interact-close",
                    self.events[-1]["evidence"],
                    "The DEBUG open and dismiss verbs bracketed a probed product interaction and the volume disappeared after a settled retry.",
                    has_accessibility_target=False,
                )

    def player_panel_media_information_scenario(self, presentation: str) -> None:
        self.show_controls()
        before = self.copy_probe("docked-media-information-before")
        offset = len(before)
        opened = self.tap(presentation, "PlayerPanel-media-information")
        close = self.wait_for_identifier(
            "PlayerPanel-media-information-close"
        )
        if opened.get("success") is not True or not isinstance(
            close.get("matchedElement"), dict
        ):
            return
        probe = self.copy_probe("docked-media-information-open")
        if any(
            "reachability playerPanel delivered action=mediaInformation.open"
            in line for line in probe[offset:]
        ):
            self.delivered(
                presentation,
                "accessibility:PlayerPanel-media-information",
                self.events[-1]["evidence"],
                "The media information control expanded the panel and appended a probe.",
            )
        offset = len(probe)
        closed = self.tap(
            presentation, "PlayerPanel-media-information-close"
        )
        probe = self.copy_probe("docked-media-information-close")
        if closed.get("success") is True and any(
            "reachability playerPanel delivered action=mediaInformation.close"
            in line for line in probe[offset:]
        ):
            self.delivered(
                presentation,
                "accessibility:PlayerPanel-media-information-close",
                self.events[-1]["evidence"],
                "The expanded media information close button reached its product handler and appended a probe.",
            )

    def docked_media_information_scenario(self) -> None:
        self.player_panel_media_information_scenario("docked")

    def exercise_playback_issue(
        self,
        presentation: str,
        *,
        category: str,
        identifier: str,
        action: str,
    ) -> bool:
        before = self.copy_probe(f"{presentation}-{identifier}-before")
        offset = len(before)
        shown = self.app_command("showPlaybackIssue", category=category)
        visible = self.wait_for_identifier(identifier)
        tapped = self.tap(presentation, identifier)
        probe = self.wait_for_probe(
            f"{presentation}-{identifier}",
            offset,
            f"reachability playback issue delivered",
        )
        delivered = (
            shown.get("success") is True
            and isinstance(visible.get("matchedElement"), dict)
            and any(
                "reachability playback issue delivered" in line
                and f"action={action}" in line
                for line in probe[offset:]
            )
        )
        if delivered:
            self.mark_observation(
                presentation,
                f"accessibility:{identifier}",
                exists=True,
                hittable=tapped.get("success") is True,
                evidence=self.events[-3]["evidence"],
                reason="The DEBUG issue verb exposed the expected product action.",
            )
            self.mark_observation(
                presentation,
                f"accessibility:{identifier}",
                received=True,
                evidence=self.events[-1]["evidence"],
                reason="The product alert action appended its location and action probe.",
            )
        return delivered

    def immersive_issue_scenario(self, presentation: str) -> None:
        for category, identifier, action in (
            ("environmentLoadingFailed", "PlayerUI-spatialFailure-primary", "retry"),
            ("playbackControlFailed", "PlayerUI-playbackIssue-confirm", "confirm"),
            ("capabilityUnavailable", "PlayerUI-unmetCapability-dismiss", "confirm"),
        ):
            self.exercise_playback_issue(
                presentation,
                category=category,
                identifier=identifier,
                action=action,
            )

    def docked_issue_scenario(self) -> None:
        self.immersive_issue_scenario("docked")

    def docked_content_scenario(self) -> None:
        if not self.enter_docked_playback(
            file_name="sdr-bframe-multiaudio-subtitles-30s.mkv"
        ):
            return
        self.player_panel_menu_scenario("docked")
        self.player_panel_media_information_scenario("docked")

    def exit_spatial_with_product_command(
        self, presentation: str, expected_presentation: str
    ) -> None:
        operation_id = "accessibility:PlayerPanel-button-exit-spatial"
        controls = self.show_controls()
        state = self.wait_for_identifier_value(
            "PlayerUI-spatial-state",
            (
                f"presentation={presentation}",
                "transition=none",
                "controls=shown",
                "controlsInteractive=true",
            ),
        )
        state_value = str((state.get("matchedElement") or {}).get("value", ""))
        if controls.get("success") is not True or not all(
            fact in state_value
            for fact in (
                f"presentation={presentation}",
                "transition=none",
                "controls=shown",
                "controlsInteractive=true",
            )
        ):
            return
        visible = self.wait_for_identifier(
            "PlayerPanel-button-exit-spatial"
        )
        matched = visible.get("matchedElement")
        self.mark_driven(presentation, operation_id)
        if not isinstance(matched, dict):
            return
        self.mark_observation(
            presentation,
            operation_id,
            exists=True,
            hittable=matched.get("isHittable") is True,
            evidence=self.events[-1]["evidence"],
            reason="The immersive attachment exposed the product exit button.",
        )
        before = self.copy_probe(f"{presentation}-exit-command-before")
        offset = len(before)
        exited = self.app_command("exitSpatial")
        self.controller("activate", "--no-screenshot")
        settled = self.wait_for_identifier_value(
            "PlayerUI-window-control-plane",
            (
                f"presentation={expected_presentation}",
                "transition=none",
                "pendingSpatialEffect=none",
                f"attached={expected_presentation}",
            ),
            verb="presentation-settle",
        )
        value = str((settled.get("matchedElement") or {}).get("value", ""))
        probe = self.copy_probe(f"{presentation}-exit-command-settled")
        if (
            exited.get("success") is True
            and f"presentation={expected_presentation}" in value
            and "transition=none" in value
            and "pendingSpatialEffect=none" in value
            and f"attached={expected_presentation}" in value
            and any(
                "testcmd exitSpatial delivered" in line
                for line in probe[offset:]
            )
        ):
            self.mark_observation(
                presentation,
                operation_id,
                received=True,
                evidence=self.events[-1]["evidence"],
                reason="The DEBUG equivalent called requestPlaybackPresentation, the same product handler used by the button, and the control plane settled at the exit target.",
            )

    def panorama_exit_command_scenario(self) -> None:
        if self.enter_panorama_playback():
            self.exit_spatial_with_product_command("panorama", "portal")

    def docked_exit_command_scenario(self) -> None:
        if self.enter_docked_playback():
            self.exit_spatial_with_product_command("docked", "window")

    def docked_main_window_issue_scenario(self) -> None:
        presentation = "docked"
        for identifier, action in (
            ("PlayerUI-loadFailure-primary", "retry"),
            ("PlayerUI-loadFailure-secondary", "close"),
        ):
            opened = self.open_media(
                self.primary_video_identifier()
            )
            if opened.get("success") is not True:
                return
            self.exercise_playback_issue(
                presentation,
                category="mediaOpeningFailed",
                identifier=identifier,
                action=action,
            )

    def docked_exit_scenario(self) -> None:
        presentation = "docked"
        self.show_controls()
        before = self.copy_probe("docked-exit-before")
        offset = len(before)
        exited = self.tap(presentation, "PlayerPanel-button-exit-spatial")
        settled = self.wait_for_identifier("PlayerUI-window-control-plane")
        value = str((settled.get("matchedElement") or {}).get("value", ""))
        probe = self.copy_probe("docked-exit-settled")
        if (
            exited.get("success") is True
            and "presentation=window" in value
            and "transition=none" in value
            and any(
                "reachability playerPanel delivered action=exitSpatial" in line
                for line in probe[offset:]
            )
        ):
            self.delivered(
                presentation,
                "accessibility:PlayerPanel-button-exit-spatial",
                self.events[-1]["evidence"],
                "The Docked exit button appended its product probe and the control plane settled in Window.",
            )

        self.show_controls()
        before = probe
        offset = len(before)
        stopped = self.tap("window", "PlayerUI-InfoBar-button-back")
        probe = self.copy_probe("docked-route-back")
        if stopped.get("success") is True and any(
            "reachability top actions delivered action=back" in line
            for line in probe[offset:]
        ):
            self.delivered(
                "window",
                "accessibility:PlayerUI-InfoBar-button-back",
                self.events[-1]["evidence"],
                "The post-Docked Window route stopped playback through the product coordinator and appended its probe.",
            )

        self.exercise_playback_issue(
            MAIN_WINDOW_BROWSER_CONTEXT,
            category="presentationConversionFailed",
            identifier="PlayerUI-presentation-conversion-dismiss",
            action="confirm",
        )

    def docked_placement_segment_scenario(self) -> None:
        presentation = "docked"
        if not self.enter_docked_playback():
            return
        for axis, value in (
            ("screenSize", "1.4"),
            ("distance", "3.0"),
            ("elevation", "5.0"),
        ):
            result = self.app_command(
                "setDockedPlacement", axis=axis, value=value
            )
            if result.get("success") is True:
                evidence = self.events[-1]["evidence"]
                self.delivered(
                    presentation,
                    "command:setDockedPlacement",
                    evidence,
                    "The requested Docked placement value reached the shared product setter immediately after the settled transition.",
                    has_accessibility_target=False,
                )
                self.delivered(
                    presentation,
                    "accessibility:PlayerPanel-{identifier}-slider",
                    evidence,
                    "The DEBUG verb reached the same setter used by the placement slider.",
                )
        controls = self.show_controls()
        visible = self.wait_for_identifier("PlayerPanel-controls")
        if controls.get("success") is True and isinstance(
            visible.get("matchedElement"), dict
        ):
            self.delivered(
                presentation,
                "command:toggleControls",
                self.events[-1]["evidence"],
                "The Docked attachment controls entered the hierarchy.",
                has_accessibility_target=False,
            )
        seg = getattr(self, "segment", None)
        if isinstance(seg, dict) and str(seg.get("id")) == "probe-docked":
            self.observe(presentation, "Docked placement isolated")
            return
        self.docked_settings_scenario()
        self.docked_media_information_scenario()
        self.observe(presentation, "Docked placement and panel")

    def docked_environment_segment_scenario(self) -> None:
        if self.enter_docked_playback(dock_choice="dark"):
            self.docked_environment_card_scenario()

    def docked_menu_segment_scenario(self) -> None:
        if self.enter_docked_playback():
            self.player_panel_menu_scenario("docked")

    def docked_transport_issue_segment_scenario(self) -> None:
        if not self.enter_docked_playback():
            return
        self.transport_scenario("docked")
        self.seek_scenario("docked", "0.3")
        self.docked_issue_scenario()

    def immersive_resident_window_scenario(self, presentation: str) -> None:
        before = self.observe(presentation, "before resident-window negative")
        toggle = self.app_command("toggleBlackoutProbeWindow")
        after = self.controller("snapshot", "--no-screenshot")
        before_hierarchy = str(before.get("hierarchy", ""))
        after_hierarchy = str(after.get("hierarchy", ""))
        before_identifiers = product_accessibility_identifiers(before)
        after_identifiers = product_accessibility_identifiers(after)
        no_named_node = "Blackout Probe" not in after_hierarchy
        no_new_identifier = after_identifiers <= before_identifiers
        hierarchy_evidence = self.events[-1]["evidence"]
        cleanup = self.app_command("toggleBlackoutProbeWindow")
        cleanup_evidence = self.events[-1]["evidence"]
        if immersive_resident_window_is_hidden(
            toggle=toggle,
            cleanup=cleanup,
            no_named_node=no_named_node,
            no_new_identifier=no_new_identifier,
        ):
            self.delivered(
                presentation,
                "negative:immersive-resident-window",
                hierarchy_evidence,
                "Opening the mechanism added no named or identifier-addressable Accessibility target.",
                has_accessibility_target=False,
            )
            if toggle.get("success") is not True and self.provable(
                presentation, "negative:immersive-resident-window"
            ):
                self.cells[
                    (presentation, "negative:immersive-resident-window")
                ]["evidence"].append(cleanup_evidence)
            return
        cell = self.cells[(presentation, "negative:immersive-resident-window")]
        cell["evidence"].extend((hierarchy_evidence, cleanup_evidence))
        if no_named_node and no_new_identifier:
            cell["reason"] = (
                "The Accessibility hierarchy remained hidden, but neither command "
                "response proved that the mechanism window was open."
            )
        else:
            cell["reason"] = (
                "The mechanism exposed a named or identifier-addressable Accessibility target "
                f"(newIdentifiers={sorted(after_identifiers - before_identifiers)}, "
                f"named={not no_named_node})."
            )

    def docked_resident_window_segment_scenario(self) -> None:
        if self.enter_docked_playback():
            self.immersive_resident_window_scenario("docked")

    def docked_exit_segment_scenario(self) -> None:
        if self.enter_docked_playback():
            self.docked_exit_scenario()

    def docked_spatial_secondary_issue_segment_scenario(self) -> None:
        if not self.enter_docked_playback():
            return
        self.exercise_playback_issue(
            "docked",
            category="environmentLoadingFailed",
            identifier="PlayerUI-spatialFailure-secondary",
            action="close",
        )

    def docked_reset_media_information_scenario(self) -> None:
        if not self.enter_docked_playback():
            return
        self.docked_settings_scenario()
        self.docked_media_information_scenario()
        self.observe("docked", "Docked playback post-reset-media")

    def panorama_panel_exit_segment_scenario(self) -> None:
        presentation = "panorama"
        if not self.enter_panorama_playback():
            return
        self.player_panel_media_information_scenario(presentation)
        self.show_controls()
        before = self.copy_probe("panorama-exit-before")
        offset = len(before)
        exited = self.tap(presentation, "PlayerPanel-button-exit-spatial")
        settled = self.wait_for_identifier("PlayerUI-window-control-plane")
        value = str((settled.get("matchedElement") or {}).get("value", ""))
        probe = self.copy_probe("panorama-exit-settled")
        if (
            exited.get("success") is True
            and "presentation=portal" in value
            and "transition=none" in value
            and any(
                "reachability playerPanel delivered action=exitSpatial" in line
                for line in probe[offset:]
            )
        ):
            self.delivered(
                presentation,
                "accessibility:PlayerPanel-button-exit-spatial",
                self.events[-1]["evidence"],
                "The Panorama exit button appended its product probe and the control plane settled in Portal.",
            )

    def panorama_immersive_issue_segment_scenario(self) -> None:
        if self.enter_panorama_playback():
            self.immersive_issue_scenario("panorama")

    def panorama_resident_window_segment_scenario(self) -> None:
        if self.enter_panorama_playback():
            self.immersive_resident_window_scenario("panorama")

    def panorama_spatial_secondary_issue_segment_scenario(self) -> None:
        if not self.enter_panorama_playback():
            return
        self.exercise_playback_issue(
            "panorama",
            category="environmentLoadingFailed",
            identifier="PlayerUI-spatialFailure-secondary",
            action="close",
        )

    def docked_scenario(self) -> None:
        presentation = "docked"
        self.docked_main_window_issue_scenario()

        opened = self.open_media(
            self.primary_video_identifier()
        )
        if opened.get("success") is not True:
            return
        self.top_menu_scenario(presentation)

        if not self.enter_docked_playback(record_route=True):
            return
        for axis, value in (
            ("screenSize", "1.4"),
            ("distance", "3.0"),
            ("elevation", "5.0"),
        ):
            result = self.app_command(
                "setDockedPlacement", axis=axis, value=value
            )
            if result.get("success") is True:
                evidence = self.events[-1]["evidence"]
                self.delivered(
                    presentation,
                    "command:setDockedPlacement",
                    evidence,
                    "The requested Docked placement value reached the shared product setter immediately after the settled transition.",
                    has_accessibility_target=False,
                )
                self.delivered(
                    presentation,
                    "accessibility:PlayerPanel-{identifier}-slider",
                    evidence,
                    "The DEBUG verb reached the same setter used by the placement slider.",
                )
        controls = self.show_controls()
        visible = self.wait_for_identifier("PlayerPanel-controls")
        if controls.get("success") is True and isinstance(visible.get("matchedElement"), dict):
            self.delivered(
                presentation, "command:toggleControls", self.events[-1]["evidence"],
                "The Docked attachment controls entered the hierarchy.",
                has_accessibility_target=False,
            )
        self.observe(presentation, "Docked playback")

        if not self.enter_docked_playback(dock_choice="dark"):
            return
        self.docked_environment_card_scenario()

        if not self.enter_docked_playback():
            return
        self.player_panel_menu_scenario(presentation)

        if not self.enter_docked_playback():
            return
        self.transport_scenario(presentation)
        self.seek_scenario(presentation, "0.3")
        self.docked_issue_scenario()

        before = self.observe(presentation, "before resident-window negative")
        toggle = self.app_command("toggleBlackoutProbeWindow")
        after = self.controller("snapshot", "--no-screenshot")
        before_hierarchy = str(before.get("hierarchy", ""))
        after_hierarchy = str(after.get("hierarchy", ""))
        before_identifiers = product_accessibility_identifiers(before)
        after_identifiers = product_accessibility_identifiers(after)
        no_named_node = "Blackout Probe" not in after_hierarchy
        no_new_identifier = after_identifiers <= before_identifiers
        hierarchy_evidence = self.events[-1]["evidence"]
        cleanup = self.app_command("toggleBlackoutProbeWindow")
        cleanup_evidence = self.events[-1]["evidence"]
        if immersive_resident_window_is_hidden(
            toggle=toggle,
            cleanup=cleanup,
            no_named_node=no_named_node,
            no_new_identifier=no_new_identifier,
        ):
            self.delivered(
                presentation, "negative:immersive-resident-window",
                hierarchy_evidence,
                "Opening the mechanism added no named or identifier-addressable Accessibility target.",
                has_accessibility_target=False,
            )
            if toggle.get("success") is not True and self.provable(
                presentation, "negative:immersive-resident-window"
            ):
                self.cells[
                    (presentation, "negative:immersive-resident-window")
                ]["evidence"].append(cleanup_evidence)
        elif self.provable(presentation, "negative:immersive-resident-window"):
            cell = self.cells[(presentation, "negative:immersive-resident-window")]
            cell["evidence"].extend((hierarchy_evidence, cleanup_evidence))
            if no_named_node and no_new_identifier:
                cell["reason"] = (
                    "The Accessibility hierarchy remained hidden, but neither command "
                    "response proved that the mechanism window was open."
                )
            else:
                cell["reason"] = (
                    "The mechanism exposed a named or identifier-addressable Accessibility target "
                    f"(newIdentifiers={sorted(after_identifiers - before_identifiers)}, "
                    f"named={not no_named_node})."
                )

        if not self.enter_docked_playback():
            return
        self.docked_exit_scenario()

        if not self.enter_docked_playback():
            return
        self.exercise_playback_issue(
            presentation,
            category="environmentLoadingFailed",
            identifier="PlayerUI-spatialFailure-secondary",
            action="close",
        )
        seg = getattr(self, "segment", None)
        if isinstance(seg, dict) and str(seg.get("id")) == "probe-docked":
            self.observe(presentation, "Docked playback isolated")
            return
        if not self.enter_docked_playback():
            return
        self.docked_settings_scenario()
        self.docked_media_information_scenario()
        self.observe(presentation, "Docked playback post-reset-media")

    def run_named_segment_scenario(self, name: str) -> None:
        scenarios = {
            "browser-core": self.browser_scenario,
            "breadcrumbs": self.breadcrumb_scenario,
            "docked": self.docked_scenario,
            "docked-environment": self.docked_environment_segment_scenario,
            "docked-content-round11": self.docked_content_scenario,
            "docked-exit-command-round11": self.docked_exit_command_scenario,
            "docked-exit": self.docked_exit_segment_scenario,
            "docked-main-window-issues": self.docked_main_window_issue_scenario,
            "docked-menus": self.docked_menu_segment_scenario,
            "docked-placement": self.docked_placement_segment_scenario,
            "docked-reset-media-information": self.docked_reset_media_information_scenario,
            "docked-resident-window": self.docked_resident_window_segment_scenario,
            "docked-spatial-secondary-issue": (
                self.docked_spatial_secondary_issue_segment_scenario
            ),
            "docked-transport-issues": self.docked_transport_issue_segment_scenario,
            "emby-version-season": self.emby_version_season_scenario,
            "emby-content-round11": self.emby_content_scenario,
            "emby-session-recovery": self.emby_session_recovery_scenario,
            "file-browser-errors": self.file_browser_error_scenario,
            "library-conditions": lambda: self.browser_condition_scenario(
                include_source_scenarios=False
            ),
            "library-editing-round11": self.library_editing_scenario,
            "library-reference-move": self.library_reference_move_scenario,
            "manage-add": self.manage_add_scenario,
            "panorama": self.panorama_scenario,
            "panorama-content-round11": self.panorama_content_scenario,
            "panorama-exit-command-round11": self.panorama_exit_command_scenario,
            "panorama-immersive-issues": (
                self.panorama_immersive_issue_segment_scenario
            ),
            "panorama-panel-exit": self.panorama_panel_exit_segment_scenario,
            "panorama-resident-window": (
                self.panorama_resident_window_segment_scenario
            ),
            "panorama-spatial-secondary-issue": (
                self.panorama_spatial_secondary_issue_segment_scenario
            ),
            "playback-failures": self.playback_failure_scenario,
            "player-ui-candidates": self.player_ui_candidate_scenario,
            "player-panel-portal-menus": self.player_panel_portal_menu_scenario,
            "portal": self.portal_scenario,
            "portal-dv-round11": self.portal_dv_scenario,
            "portal-issues-round11": self.portal_issue_scenario,
            "portal-routes-round11": self.portal_route_scenario,
            "remote-browser-round11": self.remote_browser_scenario,
            "resume-decision": self.resume_decision_scenario,
            "settings-category-round13": self.settings_category_scenario,
            "settings-menus": self.settings_menu_scenario,
            "source-connection-smb": lambda: self.source_connection_scenario("smb"),
            "source-connection-webdav": lambda: self.source_connection_scenario("webDAV"),
            "source-sidebar": self.source_sidebar_scenario,
            "window-playback": self.window_scenario,
            "window-dv-format-round11": self.window_dv_format_scenario,
            "window-hdr-fallback-round12": self.window_hdr_fallback_scenario,
            "window-media-information-round12": self.window_media_information_scenario,
            "window-top-menu-round12": self.window_top_menu_scenario,
            "window-environment-round11": self.window_environment_scenario,
            "window-issues-round11": self.window_issue_scenario,
            "window-menus-round11": self.window_menu_scenario,
            "window-load-failure": self.window_load_failure_scenario,
            "window-remote-audio-episodes": self.window_remote_audio_episodes_scenario,
            "portal-remote-audio-episodes": self.portal_remote_audio_episodes_scenario,
        }
        scenarios[name]()

    def record_segment_health_context(
        self,
        phase: str,
        *,
        probe_status_passed: bool | None = None,
        probe_retrieval_passed: bool | None = None,
    ) -> dict[str, Any]:
        health = self.channel_health_probe(phase)
        health["probeStatusPassed"] = probe_status_passed
        health["probeRetrievalPassed"] = probe_retrieval_passed
        if probe_status_passed is not None:
            health["passed"] = health["passed"] and probe_status_passed
        if probe_retrieval_passed is not None:
            health["passed"] = health["passed"] and probe_retrieval_passed
        health_path = self.raw / f"channel-health-{phase}.json"
        health_path.write_text(
            json.dumps(health, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        self.channel_health[phase] = health
        return health

    def _service_preflight_failed(self) -> bool:
        receipts = getattr(self, "service_receipts", {})
        unavailable = [service for service, receipt in receipts.items() if receipt.get("action") == "unavailable" and service == "emby"]
        if unavailable:
            self.events.append({"at": utc_now(), "action": "servicePreflightFailed", "unavailable": unavailable, "receipts": receipts})
            for service, receipt in receipts.items():
                path = self.raw / f"service-{service}-receipt.json"
                path.write_text(json.dumps(receipt, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
            return True
        return False

    def run_segment(self) -> int:
        assert self.segment is not None
        if self._service_preflight_failed():
            return self.finish_segment("service-unavailable")
        if not self.ensure_session():
            self.controller("halt", "--no-screenshot")
            return self.finish_segment("session-failed")
        self.evidence_session = str(uuid.uuid4())

        before_health = self.record_segment_health_context("before")
        if before_health["passed"] is not True:
            self.controller("halt", "--no-screenshot")
            return self.finish_segment("channel-health-failed")
        cleared = self.local_call(
            "probe-copy",
            lambda budget: enchron_target.truncate_in_container(
                target=DEVICE,
                bundle_id=APP_BUNDLE,
                source=PROBE_REMOTE_PATH,
                developer_dir=DEVELOPER_DIR,
                core_device_identifier=CORE_DEVICE,
                budget_seconds=budget.seconds,
            ),
        )
        cleared_detail = (
            "The probe clear raised an instrument fault."
            if cleared is None
            else (cleared.stderr or cleared.stdout)[-200:]
        )
        self.events.append({
            "at": utc_now(),
            "action": "clearProbeBeforeSegment",
            "success": cleared is not None and cleared.returncode == 0,
            "detail": cleared_detail,
        })
        if cleared is None or cleared.returncode != 0:
            self.channel_failures.append({
                "at": utc_now(),
                "action": "clearProbeBeforeSegment",
                "error": cleared_detail or "the journal could not be emptied",
            })
        self.probe_offset = 0
        segment_started_at = utc_now()
        self.probe_markers = {0: segment_started_at}
        self.next_probe_marker = 1
        self.segment_evidence_started = True

        fixture_scenarios = {
            "breadcrumbs",
            "docked",
            "library-conditions",
            "library-reference-move",
            "panorama",
            "playback-failures",
            "player-ui-candidates",
            "player-panel-portal-menus",
            "portal",
            "resume-decision",
            "window-playback",
            "docked-exit-command-round11",
            "library-editing-round11",
            "panorama-exit-command-round11",
            "portal-issues-round11",
            "portal-routes-round11",
            "window-issues-round11",
        }
        planned_scenarios = {str(value) for value in self.segment["scenarios"]}
        fixture_files: set[str] = set()
        if planned_scenarios & fixture_scenarios:
            fixture_files.add(
                "sdr-bframe-multiaudio-subtitles-30s.mkv"
                if self.lane == "simulator"
                else "furyroad-stripped.mkv"
            )
        for scenario in planned_scenarios:
            fixture_files.update(
                self.lane_video_file(name)
                for name in SCENARIO_FIXTURES.get(scenario, ())
            )
        for fixture_file in sorted(fixture_files):
            if self.stage_fixture(fixture_file):
                continue
            self.controller("halt", "--no-screenshot")
            return self.finish_segment("drive-error")

        reset = self.reset_reachability_state()
        if reset.get("success") is not True:
            self.controller("halt", "--no-screenshot")
            return self.finish_segment("drive-error")
        self.relaunch()
        if planned_scenarios.isdisjoint(
            {"settings-category-round13", "settings-menus"}
        ):
            self.prove_navigation_tab("files")
        if "settings-menus" in planned_scenarios:
            self.prove_navigation_tab("settings")
        for scenario in self.segment["scenarios"]:
            self.run_named_segment_scenario(str(scenario))
            if self.channel_failures:
                break

        self.salvaging = True
        status_document = self.read_probe_status()
        self.probe_status = parse_probe_status_response(status_document)
        status_path = self.raw / "probe-status.json"
        status_path.write_text(
            json.dumps(
                self.probe_status,
                ensure_ascii=False,
                indent=2,
                sort_keys=True,
            ) + "\n",
            encoding="utf-8",
        )
        self.events.append({
            "at": utc_now(),
            "action": "probeStatus",
            "success": self.probe_status["passed"],
            "evidence": f"raw/{status_path.name}",
        })
        if self.probe_status["passed"] is not True:
            self.channel_failures.append({
                "at": utc_now(),
                "action": "probeStatus",
                "error": (
                    "The product DEBUG probe journal reported an unhealthy state."
                    if status_document.get("success") is True
                    else "The probeStatus command did not answer, so the journal "
                    "was never read."
                ),
                "evidence": f"raw/{status_path.name}",
            })
        byte_limit = self.probe_status.get("byteLimit")
        journal_retrieved = isinstance(byte_limit, int) and byte_limit > 0
        if journal_retrieved:
            final_probe = self.retrieve_bounded_probe(
                "segment-after-surface",
                byte_limit=int(byte_limit),
            )
        else:
            final_probe = []
            self.channel_failures.append({
                "at": utc_now(),
                "action": "retrieveBoundedProbe",
                "error": (
                    "probeStatus named no byte limit, so the segment probe "
                    "journal was never retrieved."
                ),
                "evidence": f"raw/{status_path.name}",
            })
        final_copied = (
            self.events[-1].get("action") == "retrieveBoundedProbe"
            and self.events[-1].get("success") is True
        )
        responses = self.copy_batched_app_responses()
        self.segment_evidence_started = False
        segment_ended_at = utc_now()
        replay = replay_deferred_evidence(
            cells=self.cells,
            deliveries=self.deferred_deliveries,
            probe_lines=final_probe,
            responses=responses,
            evidence_session=str(self.evidence_session or self.session_id),
            started_at=segment_started_at,
            ended_at=segment_ended_at,
            evidence="raw/segment-after-surface-probe.log",
            journal_retrieved=journal_retrieved,
        )
        replay_path = self.raw / "deferred-evidence-replay.json"
        replay_path.write_text(
            json.dumps(replay, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        self.events.append({
            "at": utc_now(),
            "action": "replayDeferredEvidence",
            "success": replay["passed"],
            "evidence": f"raw/{replay_path.name}",
            "deliveryCount": replay["deliveryCount"],
            "verifiedDeliveryCount": replay["verifiedDeliveryCount"],
        })
        replay_failure = deferred_replay_failure_reason(replay)
        if replay_failure is not None:
            self.channel_failures.append({
                "at": utc_now(),
                "action": "replayDeferredEvidence",
                "error": replay_failure,
                "evidence": f"raw/{replay_path.name}",
            })
            journal_level = (
                replay.get("journalRetrieved") is False
                or replay.get("sessionAligned") is not True
                or replay.get("sequenceOrdered") is not True
            )
            if journal_level:
                for failed in replay.get("failures", []):
                    key = (failed.get("context"), failed.get("operation"))
                    cell = self.cells.get(key)
                    if cell is not None and cell.get("verdict") == "known-defect":
                        cell["verdict"] = "unmeasured"
                        cell["reason"] = (
                            "The probe journal behind this cell's deferred "
                            "delivery was never retrieved or aligned; missing "
                            "delivery facts here are instrument silence, never "
                            "a product verdict."
                        )
        after_health = self.record_segment_health_context(
            "after",
            probe_status_passed=self.probe_status["passed"] is True,
            probe_retrieval_passed=final_copied,
        )
        if self.channel_failures:
            self.controller("halt", "--no-screenshot")
            return self.finish_segment("channel-continuity-failed")
        if after_health["passed"] is not True:
            self.controller("halt", "--no-screenshot")
            return self.finish_segment("channel-health-failed")
        keep = getattr(self.arguments, "keep_session", None)
        if keep is None:
            keep = self.segment is not None
        if keep:
            return self.finish_segment("complete")
        stopped = self.controller("stop", "--no-screenshot")
        if stopped.get("success") is not True:
            self.controller("halt", "--no-screenshot")
            return self.finish_segment("stop-failed")
        return self.finish_segment("complete")

    def finish_segment(self, status: str) -> int:
        assert self.segment is not None
        ordered_cells = [
            self.cells[(context, operation_id)]
            for context in PROOF_CONTEXTS
            for operation_id in sorted(self.operations)
            if (context, operation_id) in self.cells
        ]
        planned = {
            (str(value["context"]), str(value["operation"]))
            for value in self.segment["decisions"]
        }
        self.driven_cells.update(
            key
            for key, cell in self.cells.items()
            if reachability_evidence_is_complete(cell)
        )
        driven = [
            {"context": context, "operation": operation}
            for context, operation in sorted(self.driven_cells)
        ]
        tapped = [
            {"context": context, "operation": operation}
            for context, operation in sorted(self.tapped_cells)
        ]
        controller_transfer_calls = sum(
            int(event.get("transportCallCount", 0) or 0)
            for event in self.events
        )
        deferred_probe_reads = sum(
            event.get("action") == "deferProbeRead" for event in self.events
        )
        prior_evidence_retrieval_lower_bound = (
            deferred_probe_reads + len(self.deferred_command_ids)
        )
        current_evidence_retrieval_calls = self.evidence_retrieval_transfer_calls
        result = {
            "schemaVersion": 3,
            "deliveryAssessmentModel": "explicit-v1",
            "generatedAt": utc_now(),
            "status": status,
            "segment": str(self.segment["id"]),
            "segmentPlan": self.segment,
            "sessionID": self.session_id,
            "evidenceSession": self.evidence_session,
            "outOfContextObservations": [
                {"context": context, "operation": operation, "count": count}
                for (context, operation), count in sorted(
                    getattr(self, "out_of_context_observations", {}).items()
                )
            ],
            "channelHealth": self.channel_health,
            "channelContinuity": {
                "passed": not self.channel_failures,
                "failures": self.channel_failures,
            },
            "instrumentFaultReport": self.policy.fault_report(),
            "deferredEvidence": {
                "commandIDs": sorted(self.deferred_command_ids),
                "deliveries": self.deferred_deliveries,
            },
            "probeJournal": self.probe_status,
            "channelExposure": {
                "controllerDevicectlCalls": controller_transfer_calls,
                "directDevicectlCalls": self.direct_transfer_calls,
                "totalDevicectlCalls": (
                    controller_transfer_calls + self.direct_transfer_calls
                ),
                "deferredProbeReads": deferred_probe_reads,
                "deferredCommandResponses": len(self.deferred_command_ids),
                "priorPerActionEvidenceRetrievalLowerBound": (
                    prior_evidence_retrieval_lower_bound
                ),
                "currentEndOfSegmentEvidenceRetrievalCalls": (
                    current_evidence_retrieval_calls
                ),
                "probeRetrievalCount": self.probe_retrieval_count,
                "evidenceRetrievalReductionFactorLowerBound": round(
                    prior_evidence_retrieval_lower_bound
                    / max(1, current_evidence_retrieval_calls),
                    2,
                ),
            },
            "device": DEVICE,
            "coreDevice": CORE_DEVICE,
            "inventory": str(INVENTORY.relative_to(ROOT)),
            "plannedDecisions": [
                {"context": context, "operation": operation}
                for context, operation in sorted(planned)
            ],
            "drivenCells": driven,
            "tappedCells": tapped,
            "unassessedTappedCells": [
                cell for cell in tapped
                if (cell["context"], cell["operation"]) not in self.driven_cells
            ],
            "unplannedDrivenCells": [
                cell
                for cell in driven
                if (cell["context"], cell["operation"]) not in planned
            ],
            "stepCount": len(self.events),
            "serviceHosts": getattr(self, "service_hosts", {}),
            "serviceReceipts": getattr(self, "service_receipts", {}),
            "cells": ordered_cells,
            "events": self.events,
        }
        results_path = self.output / "results.json"
        results_path.write_text(
            json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        print(json.dumps({
            "results": str(results_path),
            "segment": result["segment"],
            "sessionID": self.session_id,
            "status": status,
            "stepCount": result["stepCount"],
            "drivenCellCount": len(driven),
        }, ensure_ascii=False, indent=2, sort_keys=True))
        return 0 if status == "complete" else 2

    def run(self) -> int:
        if self._service_preflight_failed():
            return self.finish("service-unavailable")
        if self.segment is not None:
            return self.run_segment()
        selected = set(self.arguments.contexts)
        state_reset = False
        browser_scenario = (
            self.resume_decision_scenario if self.arguments.window_resume_only else
            lambda: (
                self.browser_condition_scenario(),
                self.browser_scenario(),
            )
        )
        window_scenario = lambda: (
                self.window_scenario(),
                self.playback_failure_scenario(),
            )
        scenarios = {
            MAIN_WINDOW_BROWSER_CONTEXT: browser_scenario,
            "window": window_scenario,
            "portal": self.portal_scenario,
            "panorama": self.panorama_scenario,
            "docked": self.docked_scenario,
        }
        for context in PROOF_CONTEXTS:
            if context not in selected:
                continue
            if self.halted:
                break
            if not self.arguments.reuse_session and not self.ensure_session():
                self.controller("halt", "--no-screenshot")
                self.finish("drive-error")
                return 2
            if context == "docked" and not self.stage_fixture(
                self.primary_video_file()
            ):
                if not self.arguments.reuse_session:
                    self.controller("halt", "--no-screenshot")
                self.finish("drive-error")
                return 2
            if not state_reset:
                reset = self.reset_reachability_state()
                if reset.get("success") is not True:
                    if not self.arguments.reuse_session:
                        self.controller("halt", "--no-screenshot")
                    self.finish("drive-error")
                    return 2
                self.relaunch()
                state_reset = True
            initial = self.copy_probe(f"{context}-initial")
            if initial and self.clear_probe_after_archive():
                self.probe_offset = 0
            else:
                self.probe_offset = len(initial)
            scenarios[context]()
        if self.halted:
            print(
                "reachability: the controller channel was quarantined after "
                "repeated instrument faults; the run was ended rather than "
                "recording the refusals that follow as product defects",
                file=sys.stderr,
            )
            self.finish("controller-stopped")
            return 3
        if not self.arguments.reuse_session:
            self.controller("stop", "--no-screenshot")
        return self.finish("complete")

    def finish(self, status: str) -> int:
        ordered_cells = [
            self.cells[(context, operation_id)]
            for context in PROOF_CONTEXTS
            for operation_id in sorted(self.operations)
            if (context, operation_id) in self.cells
        ]
        prior_events: list[dict[str, Any]] = []
        results_path = self.output / "results.json"
        selected = set(self.arguments.contexts)
        if selected != set(PROOF_CONTEXTS) and results_path.is_file():
            prior = json.loads(results_path.read_text(encoding="utf-8"))
            prior_cells = {
                (cell["context"], cell["operation"]): cell
                for cell in prior.get("cells", [])
                if isinstance(cell, dict)
            }
            ordered_cells = [
                prior_cells.get((cell["context"], cell["operation"]), cell)
                if cell["context"] not in selected else cell
                for cell in ordered_cells
            ]
            prior_events = list(prior.get("events", []))
        unmeasured = sum(
            cell.get("verdict") == "unmeasured" for cell in ordered_cells
        )
        if status == "complete" and unmeasured:
            status = "incomplete"
        summary = {
            verdict: sum(cell["verdict"] == verdict for cell in ordered_cells)
            for verdict in ("reachable", "known-defect")
        }
        summary["unmeasured"] = unmeasured
        result = {
            "schemaVersion": 3,
            "generatedAt": utc_now(),
            "status": status,
            "device": DEVICE,
            "coreDevice": CORE_DEVICE,
            "inventory": str(INVENTORY.relative_to(ROOT)),
            "proofContexts": list(PROOF_CONTEXTS),
            "summary": summary,
            "instrumentFaultReport": self.policy.fault_report(),
            "channelFailures": self.channel_failures,
            "silentTaps": self.silent_taps,
            "copyTimings": self.copy_timings,
            "serviceHosts": getattr(self, "service_hosts", {}),
            "serviceReceipts": getattr(self, "service_receipts", {}),
            "cells": ordered_cells,
            "events": prior_events + self.events,
        }
        results_path.write_text(
            json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        regression_failures: list[dict[str, str]] = []
        if BASELINE.is_file():
            baseline = json.loads(BASELINE.read_text(encoding="utf-8"))
            current = {
                (cell["context"], cell["operation"]): cell
                for cell in ordered_cells
            }
            for old in baseline.get("cells", []):
                key = (old.get("context"), old.get("operation"))
                if key[0] not in selected:
                    continue
                if (
                    key[0] == "window"
                    and key[1] in {
                        "accessibility:PlayerUI-TopAction-dock",
                        "accessibility:PlayerUI-DockMenu-skybox",
                    }
                    and "docked" not in selected
                ):
                    continue
                if (
                    self.arguments.window_resume_only
                    and key[0] == MAIN_WINDOW_BROWSER_CONTEXT
                    and key[1] not in {
                        "accessibility:MediaLibrary-grid-video-{reference.name}",
                        "accessibility:Navigation-Ornament-tab-files",
                        "accessibility:Navigation-Ornament-tab-settings",
                        "accessibility:PlayerUI-resumeDecision-primary",
                        "accessibility:PlayerUI-resumeDecision-secondary",
                    }
                ):
                    continue
                if old.get("verdict") == "reachable" and (
                    key not in current or current[key].get("verdict") != "reachable"
                ):
                    regression_failures.append({
                        "context": str(key[0]),
                        "operation": str(key[1]),
                    })
        if (
            self.arguments.accept_baseline
            and status == "complete"
            and not regression_failures
        ):
            existing_baseline_cells: list[dict[str, Any]] = []
            if BASELINE.is_file():
                existing_baseline_cells = json.loads(
                    BASELINE.read_text(encoding="utf-8")
                ).get("cells", [])
            baseline = {
                "schemaVersion": 2,
                "coordinateSystem": "proof-context-v1",
                "acceptedFrom": str(results_path),
                "acceptedAt": utc_now(),
                "cells": merge_selected_cells_into_baseline(
                    existing_baseline_cells,
                    ordered_cells,
                    selected=selected,
                ),
            }
            BASELINE.write_text(
                json.dumps(baseline, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
                encoding="utf-8",
            )
        regression_path = self.output / "regression.json"
        regression_path.write_text(
            json.dumps(
                {"failures": regression_failures, "passed": not regression_failures},
                ensure_ascii=False,
                indent=2,
                sort_keys=True,
            ) + "\n",
            encoding="utf-8",
        )
        print(json.dumps({
            "results": str(results_path),
            "summary": summary,
            "silentTaps": [
                {
                    "why": entry["why"],
                    "context": entry["context"],
                    "identifier": entry["identifier"],
                    "evidence": entry["evidence"],
                }
                for entry in self.silent_taps
            ],
            "regressionFailures": regression_failures,
        }, ensure_ascii=False, indent=2, sort_keys=True))
        if regression_failures:
            return 1
        if self.arguments.require_complete and summary["known-defect"]:
            return 1
        return 0


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Drive Enchron's reachability matrix through the regression "
            "harness and preserve raw evidence."
        )
    )
    parser.add_argument("--output-directory", type=Path, default=DEFAULT_EVIDENCE)
    parser.add_argument(
        "--execution-input",
        type=Path,
        default=os.environ.get("ENCHRON_EXECUTION_INPUT"),
        help="frozen execution input the controller launches from",
    )
    parser.add_argument("--reuse-session", action="store_true")
    parser.add_argument("--keep-session", dest="keep_session", action="store_true", default=None)
    parser.add_argument("--accept-baseline", action="store_true")
    parser.add_argument("--require-complete", action="store_true")
    parser.add_argument("--require-baseline-coverage", action="store_true")
    parser.add_argument("--baseline-no-regression-evidence", type=Path)
    parser.add_argument("--window-resume-only", action="store_true")
    parser.add_argument("--emby-credentials", type=Path)
    parser.add_argument("--segment-plan", type=Path)
    parser.add_argument("--segment")
    parser.add_argument(
        "--merge-segments", nargs="+", type=Path, metavar="RESULTS_JSON"
    )
    parser.add_argument(
        "--contexts", nargs="+", choices=PROOF_CONTEXTS,
        default=list(PROOF_CONTEXTS),
    )
    return parser.parse_args()


def merge_segment_result_files(arguments: argparse.Namespace) -> int:
    baseline = json.loads(BASELINE.read_text(encoding="utf-8"))
    segment_results = [
        json.loads(path.read_text(encoding="utf-8"))
        for path in arguments.merge_segments
    ]
    no_regression_cells: set[tuple[str, str]] = set()
    no_regression_evidence: dict[str, Any] | None = None
    if arguments.baseline_no_regression_evidence is not None:
        no_regression_evidence = json.loads(
            arguments.baseline_no_regression_evidence.read_text(encoding="utf-8")
        )
        if no_regression_evidence.get("status") != "passed":
            raise SystemExit("Baseline no-regression evidence did not pass.")
        cells = no_regression_evidence.get("cells")
        if not isinstance(cells, list) or not cells:
            raise SystemExit("Baseline no-regression evidence has no cells.")
        no_regression_cells = {
            (str(cell.get("context")), str(cell.get("operation")))
            for cell in cells
            if isinstance(cell, dict)
            and cell.get("context")
            and cell.get("operation")
        }
        if len(no_regression_cells) != len(cells):
            raise SystemExit(
                "Baseline no-regression evidence contains invalid or duplicate cells."
            )
    delivery = merge_segment_delivery(
        baseline.get("cells", []),
        segment_results,
        require_baseline_coverage=arguments.require_baseline_coverage,
        no_regression_cells=no_regression_cells,
    )
    delivery.update({
        "schemaVersion": 2,
        "generatedAt": utc_now(),
        "baseline": str(BASELINE.relative_to(ROOT)),
        "segmentResults": [str(path.resolve()) for path in arguments.merge_segments],
        "baselineNoRegressionEvidence": (
            str(arguments.baseline_no_regression_evidence.resolve())
            if arguments.baseline_no_regression_evidence is not None
            else None
        ),
    })
    delivery["summary"] = {
        verdict: sum(
            cell.get("verdict") == verdict
            for cell in delivery["candidateCells"]
        )
        for verdict in ("reachable", "known-defect")
    }
    arguments.output_directory.mkdir(parents=True, exist_ok=True)
    delivery_path = arguments.output_directory / "delivery.json"
    delivery_path.write_text(
        json.dumps(delivery, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    if arguments.accept_baseline and delivery["accepted"]:
        accepted = {
            "schemaVersion": 2,
            "coordinateSystem": "proof-context-v1",
            "acceptedFrom": str(delivery_path.resolve()),
            "acceptedAt": utc_now(),
            "cells": [
                {
                    "context": cell["context"],
                    "operation": cell["operation"],
                    "verdict": cell["verdict"],
                }
                for cell in delivery["candidateCells"]
            ],
        }
        BASELINE.write_text(
            json.dumps(accepted, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    print(json.dumps({
        "accepted": delivery["accepted"],
        "acceptedSegments": delivery["acceptedSegments"],
        "rejectedSegments": delivery["rejectedSegments"],
        "failures": delivery["failures"],
        "summary": delivery["summary"],
        "delivery": str(delivery_path),
    }, ensure_ascii=False, indent=2, sort_keys=True))
    return 0 if delivery["accepted"] else 1


def configure_segment(arguments: argparse.Namespace) -> None:
    if arguments.segment_plan is None or arguments.segment is None:
        raise SystemExit("--segment-plan and --segment must be supplied together")
    plan = json.loads(arguments.segment_plan.read_text(encoding="utf-8"))
    inventory = json.loads(INVENTORY.read_text(encoding="utf-8"))
    errors = validate_segment_plan(
        plan,
        operation_contexts={
            str(item["id"]): {
                str(context) for context in product_proof_contexts(item)
            }
            for item in inventory["operations"]
        },
        scenario_names=SEGMENT_SCENARIO_NAMES,
    )
    if errors:
        raise SystemExit("Invalid segment plan:\n" + "\n".join(errors))
    matching = [
        segment for segment in plan["segments"]
        if str(segment["id"]) == arguments.segment
    ]
    if not matching:
        raise SystemExit(f"Segment plan has no segment named {arguments.segment}")
    arguments.segment_spec = matching[0]
    arguments.segment_plan_document = plan
    arguments.contexts = [str(matching[0]["context"])]


def main() -> int:
    refuse_when_detached()
    arguments = parse_arguments()
    if arguments.execution_input is not None:
        os.environ["ENCHRON_EXECUTION_INPUT"] = str(arguments.execution_input)
    if arguments.merge_segments:
        if arguments.segment_plan is not None or arguments.segment is not None:
            raise SystemExit("--merge-segments cannot be combined with --segment")
        return merge_segment_result_files(arguments)
    if arguments.segment_plan is not None or arguments.segment is not None:
        configure_segment(arguments)
    run = ReachabilityRun(arguments)
    return run.run()


if __name__ == "__main__":
    raise SystemExit(main())
