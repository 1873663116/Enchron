#!/usr/bin/env python3

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
import hashlib
import ipaddress
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import sys
import time
from datetime import datetime, timezone
from types import MappingProxyType
from typing import Callable, Mapping, Protocol
from urllib.parse import urlsplit, urlunsplit

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
VERIFICATION_DIRECTORY = REPOSITORY_ROOT / "Scripts/verification"
INVENTORY_PATH = REPOSITORY_ROOT / "Config/reachability_operation_inventory.json"
REMOTE_SOURCE_PATH = REPOSITORY_ROOT / "Scripts/verification/regression_remote_source.py"
REMOTE_PREFLIGHT_PATH = (
    REPOSITORY_ROOT / "Scripts/verification/regression_environment_preflight.py"
)
SMB_SOURCE_PATH = REPOSITORY_ROOT / "Scripts/verification/regression_smb_source.py"
SYSTEM_IMPORT_PATH = REPOSITORY_ROOT / "Scripts/verification/regression_system_import.py"
DEVICE_HUB_CANVAS_PATH = REPOSITORY_ROOT / "Scripts/verification/device_hub_canvas.py"
RULES_DIRECTORY = REPOSITORY_ROOT / "Scripts/rules"
if str(REPOSITORY_ROOT) not in sys.path:
    sys.path.insert(0, str(REPOSITORY_ROOT))
if str(VERIFICATION_DIRECTORY) not in sys.path:
    sys.path.insert(0, str(VERIFICATION_DIRECTORY))
if str(RULES_DIRECTORY) not in sys.path:
    sys.path.insert(0, str(RULES_DIRECTORY))

import enchron_target
from harness import Budget, BudgetProvider, ControllerClient, FaultRecord, Halt, InstrumentFault, LocalToolRunner, RecoveryPolicy, wait_for

import regression_environment_preflight as _remote_preflight
import regression_emby_source as _emby_source
import regression_smb_source as _smb_source
import regression_system_import as _system_import

REMOTE_RUNTIME_FILE = _remote_preflight.remote.DEFAULT_RUNTIME_ROOT / "runtime.json"
REMOTE_PREFLIGHT_CHECKS = frozenset(_remote_preflight.CHECKS)
SMB_RUNTIME_FILE = _smb_source.DEFAULT_RUNTIME_ROOT / "runtime.json"
@dataclass
class _HarnessInstruments:
    device: str
    core_device: str
    developer_dir: str
    lane: str
    budgets: BudgetProvider
    controller: ControllerClient
    tools: LocalToolRunner
    policy: RecoveryPolicy
    history: list[FaultRecord] = field(default_factory=list)

    def record_wait_sample(self, label, seconds, censored):
        self.budgets.record_sample(self.lane, label, seconds, censored)

    def tool_env(self):
        return {**os.environ, "DEVELOPER_DIR": self.developer_dir}


def _harness_recovered(instruments, location, action):
    while True:
        instruments.policy.record_action()
        try:
            return action()
        except InstrumentFault as fault:
            instruments.history.append(FaultRecord(location=location, kind=fault.kind, censored=fault.kind in ("transport-timeout", "wait-expired")))
            decision = instruments.policy.on_fault(fault, instruments.history)
            if isinstance(decision, Halt):
                fault.evidence["halt"] = {"reason": decision.reason, "faultReport": decision.report}
                raise


def _hold_via_wait(lane, budgets, label, seconds):
    if seconds <= 0:
        return
    started = datetime.now(timezone.utc)
    def probe():
        elapsed = (datetime.now(timezone.utc) - started).total_seconds()
        if elapsed >= seconds:
            return {"heldSeconds": round(elapsed, 3)}
        return None
    wait_for(label, probe, Budget(seconds=seconds + 5.0, provenance=label + " hold"), observe=lambda: [], record=lambda l, s, c: budgets.record_sample(lane, l, s, c))



def _source_identity(path: Path) -> Mapping[str, str]:
    return MappingProxyType(
        {
            "path": path.relative_to(REPOSITORY_ROOT).as_posix(),
            "digest": "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest(),
        }
    )


def _screenshot_digest(response: Mapping[str, object]) -> str | None:
    path_value = next(
        (
            response.get(field)
            for field in ("localScreenshotPath", "screenshotPath", "screenshot")
            if isinstance(response.get(field), str) and response.get(field)
        ),
        None,
    )
    if not isinstance(path_value, str):
        return None
    path = Path(path_value)
    if path.is_symlink() or not path.is_file():
        return None
    return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()


REMOTE_IMPLEMENTATION_IDENTITIES = MappingProxyType(
    {
        "remote-source-service": _source_identity(REMOTE_SOURCE_PATH),
        "remote-environment-preflight": _source_identity(REMOTE_PREFLIGHT_PATH),
    }
)
SMB_IMPLEMENTATION_IDENTITIES = MappingProxyType(
    {"smb-source-preflight": _source_identity(SMB_SOURCE_PATH)}
)
SYSTEM_IMPORT_IMPLEMENTATION_IDENTITIES = MappingProxyType(
    {
        "system-import-preflight": _source_identity(SYSTEM_IMPORT_PATH),
        "device-hub-driver": _source_identity(DEVICE_HUB_CANVAS_PATH),
    }
)


class OperationAdapterError(ValueError):
    pass


class ValueKind(Enum):
    BOOLEAN = "boolean"
    INTEGER = "integer"
    STRING = "string"
    STRING_LIST = "string-list"


@dataclass(frozen=True)
class Field:
    name: str
    kind: ValueKind
    required: bool = True
    choices: frozenset[object] = frozenset()
    minimum: int | None = None
    maximum: int | None = None
    nonempty: bool = True

    def validate(self, value: object, location: str) -> None:
        if self.kind is ValueKind.BOOLEAN:
            valid = type(value) is bool
        elif self.kind is ValueKind.INTEGER:
            valid = type(value) is int
        elif self.kind is ValueKind.STRING:
            valid = isinstance(value, str)
        elif self.name == "relatedResults":
            valid = isinstance(value, list)
        else:
            valid = isinstance(value, list) and all(
                isinstance(item, str) for item in value
            )
        if not valid:
            raise OperationAdapterError(f"{location} must be {self.kind.value}")
        if self.nonempty and (
            isinstance(value, str) and not value
            or isinstance(value, list) and not value
        ):
            raise OperationAdapterError(f"{location} must not be empty")
        if self.choices and value not in self.choices:
            allowed = ", ".join(sorted(str(item) for item in self.choices))
            raise OperationAdapterError(f"{location} must be one of {allowed}")
        if isinstance(value, int) and not isinstance(value, bool):
            if self.minimum is not None and value < self.minimum:
                raise OperationAdapterError(f"{location} must be >= {self.minimum}")
            if self.maximum is not None and value > self.maximum:
                raise OperationAdapterError(f"{location} must be <= {self.maximum}")


CrossValidator = Callable[[Mapping[str, object]], None]


@dataclass(frozen=True)
class ArgumentRule:
    kind: str
    fields: tuple[str, ...] = ()
    groups: tuple[tuple[str, ...], ...] = ()
    discriminator: str | None = None
    cases: tuple[tuple[str, tuple[str, ...], tuple[str, ...]], ...] = ()

    def validate(self, arguments: Mapping[str, object], location: str) -> None:
        present = set(arguments)
        if self.kind == "at-least-one":
            if not present.intersection(self.fields):
                requirement = (
                    "identifier or label"
                    if self.fields == ("identifiers", "labels")
                    else "one of " + ", ".join(self.fields)
                )
                raise OperationAdapterError(
                    f"{location} requires {requirement}"
                )
            return
        if self.kind == "all-or-none":
            matched = present.intersection(self.fields)
            if matched and matched != set(self.fields):
                raise OperationAdapterError(
                    f"{location} requires all or none of {', '.join(self.fields)}"
                )
            return
        if self.kind == "exactly-one-group":
            complete = [group for group in self.groups if set(group) <= present]
            mentioned = {
                field
                for group in self.groups
                for field in group
                if field in present
            }
            if len(complete) != 1 or mentioned != set(complete[0]):
                rendered = " or ".join("+".join(group) for group in self.groups)
                raise OperationAdapterError(
                    f"{location} requires exactly one complete group: {rendered}"
                )
            return
        if self.kind == "when-equals":
            assert self.discriminator is not None
            value = arguments.get(self.discriminator)
            matched = next((case for case in self.cases if case[0] == value), None)
            if matched is None:
                return
            _, required, forbidden = matched
            missing = [field for field in required if field not in present]
            rejected = [field for field in forbidden if field in present]
            if missing or rejected:
                details = []
                if missing:
                    details.append("requires " + ", ".join(missing))
                if rejected:
                    details.append("forbids " + ", ".join(rejected))
                raise OperationAdapterError(
                    f"{location} with {self.discriminator}={value} "
                    + " and ".join(details)
                )
            return
        raise OperationAdapterError(f"{location} has an unknown argument rule")

    def canonical(self) -> dict[str, object]:
        if self.kind in ("at-least-one", "all-or-none"):
            return {"kind": self.kind, "fields": list(self.fields)}
        if self.kind == "exactly-one-group":
            return {
                "kind": self.kind,
                "groups": [list(group) for group in self.groups],
            }
        assert self.kind == "when-equals" and self.discriminator is not None
        return {
            "kind": self.kind,
            "discriminator": self.discriminator,
            "cases": [
                {
                    "value": value,
                    "required": list(required),
                    "forbidden": list(forbidden),
                }
                for value, required, forbidden in self.cases
            ],
        }


@dataclass(frozen=True)
class OperationSpec:
    identifier: str
    lanes: frozenset[str]
    fields: tuple[Field, ...]
    outputs: tuple[tuple[str, str], ...]
    cross_validate: CrossValidator | None = None
    argument_rules: tuple[ArgumentRule, ...] = ()

    def validate(self, lane: str, arguments: object) -> Mapping[str, object]:
        if lane not in self.lanes:
            raise OperationAdapterError(
                f"{self.identifier} is unavailable on lane {lane}"
            )
        if not isinstance(arguments, dict):
            raise OperationAdapterError("operation arguments must be a JSON object")
        fields = {field.name: field for field in self.fields}
        unknown = sorted(set(arguments) - set(fields))
        if unknown:
            raise OperationAdapterError(
                f"{self.identifier} rejects unknown fields: {', '.join(unknown)}"
            )
        missing = sorted(
            field.name
            for field in self.fields
            if field.required and field.name not in arguments
        )
        if missing:
            raise OperationAdapterError(
                f"{self.identifier} requires fields: {', '.join(missing)}"
            )
        for name, value in arguments.items():
            location = f"{self.identifier}.{name}"
            try:
                fields[name].validate(value, location)
            except OperationAdapterError:
                if name not in GRANT_ARGUMENT_FIELDS or not _is_thawed_grant(
                    name, value, fields[name]
                ):
                    raise
        for rule in self.argument_rules:
            rule.validate(arguments, self.identifier)
        if self.cross_validate is not None:
            self.cross_validate(arguments)
        return MappingProxyType(dict(arguments))


@dataclass(frozen=True)
class OperationContext:
    lane: str
    target: str
    attempt_root: Path
    controller_directory: Path
    bundle_id: str = "com.xiongzhipeng.XrPlayer"

    def __post_init__(self) -> None:
        if self.lane not in ("simulator", "device"):
            raise OperationAdapterError("context lane must be simulator or device")
        if not self.target:
            raise OperationAdapterError("context target must not be empty")
        if not self.attempt_root.is_absolute() or not self.controller_directory.is_absolute():
            raise OperationAdapterError("attempt paths must be absolute")


@dataclass(frozen=True)
class _LeaseBoundFixtureTransport:
    lane: str
    target: str
    bundle_id: str
    developer_dir: str
    delegate: object

    def copy_to_container(self, source: Path, destination: str) -> None:
        if self.lane == "simulator":
            copy = getattr(self.delegate, "copy_to_container")
            copy(source, destination)
            return
        budgets = BudgetProvider()
        tools = LocalToolRunner(self.lane, budgets=budgets)
        completed = tools.call("fixture-copy", lambda budget: enchron_target.copy_to_container(target=self.target, bundle_id=self.bundle_id, source=source, destination=destination, developer_dir=self.developer_dir, core_device_identifier=self.target, **{"timeout": budget.seconds}))
        if completed.returncode != 0:
            detail = (completed.stderr or completed.stdout)[-500:]
            raise InstrumentFault("fixture-copy-failed", {"destination": destination, "stderr": detail})

    def copy_from_container(self, source: str, destination: Path) -> None:
        copy = getattr(self.delegate, "copy_from_container")
        copy(source, destination)


class OperationBackend(Protocol):
    def execute(
        self,
        operation_id: str,
        arguments: Mapping[str, object],
        context: OperationContext,
    ) -> Mapping[str, object]: ...


@dataclass(frozen=True)
class Invocation:
    operation_id: str
    outputs: tuple[tuple[str, str], ...]
    result: Mapping[str, object]


def _choices(*values: object) -> frozenset[object]:
    return frozenset(values)


LANES = frozenset(("simulator", "device"))
SIMULATOR = frozenset(("simulator",))
DEVICE = frozenset(("device",))
CONTEXTS = _choices("main-window-browser", "window", "portal", "panorama", "docked")


def _field(
    name: str,
    kind: ValueKind,
    *,
    required: bool = True,
    choices: frozenset[object] = frozenset(),
    minimum: int | None = None,
    maximum: int | None = None,
    nonempty: bool = True,
) -> Field:
    return Field(name, kind, required, choices, minimum, maximum, nonempty)


def _deadline() -> Field:
    return _field("deadlineSeconds", ValueKind.INTEGER, minimum=1, maximum=90)


def _index(required: bool = False) -> Field:
    return _field("index", ValueKind.INTEGER, required=required, minimum=0)


def _capture_frames(arguments: Mapping[str, object]) -> None:
    expectation = arguments.get("remoteExpectation")
    generation = arguments.get("remoteGenerationToken")
    receipt = arguments.get("remoteReceiptID")
    restored_generation = arguments.get("restoredGenerationToken")
    product_binding = arguments.get("productBindingDigest")
    artwork_expectation = arguments.get("artworkExpectation")
    include_hdr_fallback = arguments.get("includeHDRFallback")
    related_manifests = arguments.get("relatedFrameManifests", [])
    assert isinstance(related_manifests, list)
    for manifest in related_manifests:
        if manifest.startswith("result://"):
            if re.fullmatch(
                r"result://call:[a-z0-9:-]+/frameManifest", manifest
            ) is None:
                raise OperationAdapterError(
                    "relatedFrameManifests must select /frameManifest"
                )
            continue
        try:
            decoded = json.loads(manifest)
        except json.JSONDecodeError as error:
            raise OperationAdapterError(
                "relatedFrameManifests must contain canonical capture manifests"
            ) from error
        if not isinstance(decoded, dict) or set(decoded) != {"context", "frames"}:
            raise OperationAdapterError(
                "relatedFrameManifests contain the wrong closed shape"
            )
    if include_hdr_fallback is not None and include_hdr_fallback is not True:
        raise OperationAdapterError("includeHDRFallback may only request true")
    artwork_key = arguments.get("artworkKey")
    if artwork_key is not None and artwork_expectation is None:
        raise OperationAdapterError(
            "artworkKey only names the store an artwork exit capture reads"
        )
    if artwork_expectation is not None:
        if (
            artwork_expectation != "exit-replaces-current-frame"
            or arguments.get("count") != 4
            or arguments.get("minimumIntervalMillis") != 0
            or arguments.get("context") != "window"
            or expectation is not None
            or generation is not None
            or product_binding is not None
            or include_hdr_fallback is not None
        ):
            raise OperationAdapterError(
                "artwork exit capture requires the exact four-frame local variant"
            )
        # After the exit the runtime has no current launch request, so the probe
        # can only reach the store the pre-exit capture named. An exact key is
        # therefore the sole way to read the artwork the exit wrote.
        if artwork_key is not None:
            reference = str(artwork_key)
            pattern = (
                r"result://call:[a-z0-9:-]+/artworkKey"
                if reference.startswith("result://")
                else r"media-[0-9a-f]{64}"
            )
            if re.fullmatch(pattern, reference) is None:
                raise OperationAdapterError(
                    "artworkKey must be one exact media artwork key or the "
                    "artworkKey field of an earlier capture"
                )
        return
    if expectation is None:
        if any(
            value is not None
            for value in (
                generation,
                receipt,
                restored_generation,
                product_binding,
            )
        ):
            raise OperationAdapterError(
                "frame remote bindings require one closed remoteExpectation"
            )
        return
    if expectation not in (
        "webdav-playback-range",
        "buffer-absorbed-interruption",
    ):
        raise OperationAdapterError(
            "frame capture remoteExpectation is not supported"
        )
    if not isinstance(product_binding, str):
        raise OperationAdapterError(
            "remote frame capture requires a product binding"
        )
    if expectation == "webdav-playback-range":
        if (
            not isinstance(generation, str)
            or receipt is not None
            or restored_generation is not None
        ):
            raise OperationAdapterError(
                "healthy frame capture requires only a generation token"
            )
        if generation.startswith("result://") and re.fullmatch(
            r"result://call:[a-z0-9:-]+/(?:generationToken|restoredGenerationToken)",
            generation,
        ) is None:
            raise OperationAdapterError(
                "remoteGenerationToken must select a generation result"
            )
    else:
        if (
            generation is not None
            or not isinstance(receipt, str)
            or not isinstance(restored_generation, str)
        ):
            raise OperationAdapterError(
                "fault frame capture requires receipt and restoration bindings"
            )
        _literal_or_result_reference(arguments, "remoteReceiptID", "receiptID")
        _literal_or_result_reference(
            arguments,
            "restoredGenerationToken",
            "restoredGenerationToken",
        )
    _sha256_or_result_reference(
        arguments, "productBindingDigest", "bindingDigest"
    )


def _accessibility_activate(arguments: Mapping[str, object]) -> None:
    identifiers = arguments.get("identifiers", [])
    labels = arguments.get("labels", [])
    gesture = arguments.get("gesture", "tap")
    duration = arguments.get("durationMillis")
    assert isinstance(identifiers, list)
    assert isinstance(labels, list)
    settle_delay = arguments.get("settleDelayMillis")
    if settle_delay is not None and settle_delay <= 0:
        raise OperationAdapterError("settleDelayMillis must be positive")
    if not identifiers and not labels:
        raise OperationAdapterError(
            "accessibility activate requires at least one identifier or label"
        )
    if len(identifiers) != len(set(identifiers)):
        raise OperationAdapterError("accessibility identifiers must be unique")
    if len(labels) != len(set(labels)):
        raise OperationAdapterError("accessibility labels must be unique")
    if any(not label or label.strip() != label for label in labels):
        raise OperationAdapterError("accessibility labels must be exact nonempty strings")
    if len(identifiers) != 1 and "index" in arguments:
        raise OperationAdapterError("index is allowed only with one identifier")
    if gesture == "press":
        if len(identifiers) != 1 or labels or not isinstance(duration, int):
            raise OperationAdapterError(
                "press requires one identifier, durationMillis, and no labels"
            )
    elif duration is not None:
        raise OperationAdapterError(
            "durationMillis is allowed only for the press gesture"
        )
    if identifiers:
        _validate_identifiers(identifiers)
    assert_absent = arguments.get("assertAbsent", [])
    assert isinstance(assert_absent, list)
    if assert_absent:
        if len(assert_absent) != len(set(assert_absent)):
            raise OperationAdapterError("assertAbsent identifiers must be unique")
        if gesture == "press":
            raise OperationAdapterError(
                "assertAbsent is not allowed with the press gesture"
            )
        if not identifiers:
            raise OperationAdapterError("assertAbsent requires identifiers")
        _validate_identifiers(assert_absent)
    also_inspect = arguments.get("alsoInspect", [])
    assert isinstance(also_inspect, list)
    if also_inspect:
        if len(also_inspect) != len(set(also_inspect)):
            raise OperationAdapterError("alsoInspect identifiers must be unique")
        if gesture == "press":
            raise OperationAdapterError(
                "alsoInspect is not allowed with the press gesture"
            )
        if len(labels) > 1:
            raise OperationAdapterError("alsoInspect allows at most one label")
        _validate_identifiers(also_inspect)
    if arguments.get("summonControls") is not None and arguments.get("summonControls") is not True:
        raise OperationAdapterError("summonControls may only request true")
    if arguments.get("dismissControls") is not None and arguments.get("dismissControls") is not True:
        raise OperationAdapterError("dismissControls may only request true")
    if arguments.get("summonControls") is True and arguments.get("dismissControls") is True:
        raise OperationAdapterError(
            "summonControls and dismissControls are mutually exclusive"
        )
    _related_results(arguments)


GRANT_ARGUMENT_FIELDS = frozenset(
    ("hostShares", "priorSnapshot", "relatedResults")
)
_RESULT_REFERENCE = re.compile(r"result://call:[a-z0-9:-]+/[A-Za-z][A-Za-z0-9]*")


def _is_json_value(value: object) -> bool:
    if value is None or isinstance(value, (str, int, float, bool)):
        return True
    if isinstance(value, list):
        return all(_is_json_value(item) for item in value)
    if isinstance(value, Mapping):
        return all(
            isinstance(key, str) and _is_json_value(item)
            for key, item in value.items()
        )
    return False


def _is_thawed_grant(name: str, value: object, field: Field) -> bool:
    if field.nonempty and isinstance(value, list) and not value:
        return False
    if name == "relatedResults":
        return isinstance(value, list) and all(_is_json_value(item) for item in value)
    if name == "priorSnapshot":
        return isinstance(value, Mapping)
    if name == "hostShares":
        return (
            isinstance(value, list)
            and bool(value)
            and all(
                isinstance(item, str) and item and item.strip() == item
                for item in value
            )
        )
    return False


def _related_results(arguments: Mapping[str, object]) -> None:
    related_results = arguments.get("relatedResults", [])
    assert isinstance(related_results, list)
    for result in related_results:
        if isinstance(result, str):
            if result.startswith("result://") and _RESULT_REFERENCE.fullmatch(
                result
            ) is None:
                raise OperationAdapterError(
                    "relatedResults must contain top-level result references"
                )
            continue
        if not _is_json_value(result):
            raise OperationAdapterError(
                "relatedResults must contain top-level result references"
            )


def _inlined_viewing_storage_snapshots(
    arguments: Mapping[str, object],
) -> list[Mapping[str, object]]:
    snapshots: list[Mapping[str, object]] = []
    for item in arguments.get("relatedResults", ()):
        if not isinstance(item, Mapping):
            continue
        if item.get("schema") != "enchron.regression.viewing-storage-observation@1":
            continue
        snapshot = item.get("snapshot")
        if isinstance(snapshot, Mapping):
            snapshots.append(snapshot)
    return snapshots


def _inlined_certificate_before_state(
    arguments: Mapping[str, object],
) -> dict[str, str] | None:
    for item in arguments.get("relatedResults", ()):
        if not isinstance(item, Mapping):
            continue
        nested = item.get("fields")
        if isinstance(nested, Mapping) and nested:
            return {str(key): str(value) for key, value in nested.items()}
        if any(key in item for key in ("lifecycle", "error", "active")):
            return {
                str(key): str(value)
                for key, value in item.items()
                if isinstance(value, (str, int, bool))
            }
    return None


def _accessibility_single(arguments: Mapping[str, object]) -> None:
    _validate_identifiers([str(arguments["identifier"])])
    _related_results(arguments)


def _browse_hierarchy_bound_name(value: object, label: str) -> None:
    if not isinstance(value, str) or not value or value.strip() != value:
        raise OperationAdapterError(
            f"browse hierarchy {label} must be exact nonempty text"
        )
    if value.startswith("result://"):
        return
    if value in (".", "..") or "/" in value:
        raise OperationAdapterError(
            f"browse hierarchy {label} must be an exact direct-child name"
        )


def _browse_hierarchy(arguments: Mapping[str, object]) -> None:
    source_label = str(arguments["sourceLabel"])
    if not source_label.strip() or source_label.strip() != source_label:
        raise OperationAdapterError(
            "browse hierarchy sourceLabel must be exact nonempty text"
        )
    components = arguments["pathComponents"]
    assert isinstance(components, list)
    identifiers: list[str] = []
    for component in components:
        if (
            not component
            or component.strip() != component
            or component in (".", "..")
            or "/" in component
        ):
            raise OperationAdapterError(
                "browse hierarchy pathComponents must be exact direct-child names"
            )
        identifiers.append(f"FileBrowsing-grid-folder-{component}")
    _validate_identifiers(identifiers)
    source_receipt = arguments.get("sourceReceipt")
    if source_receipt is not None and re.fullmatch(
        r"result://call:[a-z0-9:-]+/report", str(source_receipt)
    ) is None:
        raise OperationAdapterError(
            "browse hierarchy sourceReceipt must select a host preflight /report"
        )
    host_share = arguments.get("hostShareName")
    if host_share is not None:
        _browse_hierarchy_bound_name(host_share, "hostShareName")
        if not str(host_share).startswith("result://") and host_share != components[0]:
            raise OperationAdapterError(
                "browse hierarchy hostShareName must equal the first path component"
            )
    expected_video = arguments.get("expectedVideoName")
    if expected_video is not None:
        _browse_hierarchy_bound_name(expected_video, "expectedVideoName")
    host_shares = arguments.get("hostShares")
    if host_shares is None:
        pass
    elif isinstance(host_shares, str):
        if re.fullmatch(r"result://call:[a-z0-9:-]+/hostShares", host_shares) is None:
            raise OperationAdapterError(
                "browse hierarchy hostShares must select a host preflight /hostShares"
            )
    elif not (
        isinstance(host_shares, list)
        and host_shares
        and all(
            isinstance(item, str) and item and item.strip() == item
            for item in host_shares
        )
    ):
        raise OperationAdapterError(
            "browse hierarchy hostShares must select a host preflight /hostShares"
        )


def _accessibility_type(arguments: Mapping[str, object]) -> None:
    named = ("identifier" in arguments, "label" in arguments)
    if named[0] == named[1]:
        raise OperationAdapterError(
            "accessibility.type requires exactly one identifier or label"
        )
    if named[0]:
        _validate_identifiers([str(arguments["identifier"])])
    else:
        label = str(arguments["label"])
        if not label or label.strip() != label:
            raise OperationAdapterError(
                "accessibility.type label must be exact nonempty text"
            )
    _related_results(arguments)
    direct = "text" in arguments
    file_pair = "textFile" in arguments or "textJSONKey" in arguments
    if direct == file_pair:
        raise OperationAdapterError(
            "accessibility.type requires text or the textFile/textJSONKey pair"
        )
    if file_pair and not ("textFile" in arguments and "textJSONKey" in arguments):
        raise OperationAdapterError("textFile and textJSONKey must appear together")
    if arguments["secret"] is True and not file_pair:
        raise OperationAdapterError("secret text must use a file and JSON key")
    if file_pair:
        text_file = str(arguments["textFile"])
        if text_file.startswith("result://"):
            if re.fullmatch(
                r"result://call:[a-z0-9:-]+/runtimePath", text_file
            ) is None:
                raise OperationAdapterError(
                    "textFile result reference must select /runtimePath"
                )
        elif not Path(text_file).is_absolute():
            raise OperationAdapterError(
                "textFile must be one absolute runtime artifact path"
            )


def _host_preflight(arguments: Mapping[str, object]) -> None:
    phase = str(arguments.get("phase", "ensure"))
    check = str(arguments["check"])
    recipe = arguments.get("recipe")
    receipt_id = arguments.get("receiptID")
    if phase == "ensure":
        if recipe is not None or receipt_id is not None:
            raise OperationAdapterError(
                "host preflight ensure rejects recipe and receiptID"
            )
        return
    if check != "remote-faults":
        raise OperationAdapterError(
            "remote recipe actuation requires check=remote-faults"
        )
    if phase == "activate":
        if recipe not in _remote_preflight.remote.RECIPE_NAMES or receipt_id is not None:
            raise OperationAdapterError(
                "remote recipe activate requires one exact closed recipe"
            )
        return
    if phase == "restore":
        if recipe is not None or not isinstance(receipt_id, str):
            raise OperationAdapterError(
                "remote recipe restore requires one receiptID"
            )
        if receipt_id.startswith("result://"):
            if re.fullmatch(
                r"result://call:[a-z0-9:-]+/receiptID", receipt_id
            ) is None:
                raise OperationAdapterError(
                    "remote restore result reference must select /receiptID"
                )
        elif re.fullmatch(
            r"receipt:g-[0-9]{6}:[a-z][a-z-]*", receipt_id
        ) is None:
            raise OperationAdapterError("remote restore receiptID is invalid")
        return
    raise OperationAdapterError("unknown host preflight phase")


REMOTE_EXPECTATIONS = frozenset(
    (
        "webdav-connection",
        "webdav-playback-range",
        "certificate-trust-boundary",
        "recoverable-read",
        "finite-backoff",
        "certificate-change",
        "buffer-absorbed-interruption",
    )
)
REMOTE_HEALTHY_EXPECTATIONS = frozenset(
    ("webdav-connection", "webdav-playback-range", "certificate-trust-boundary")
)
REMOTE_FAULT_EXPECTATIONS = REMOTE_EXPECTATIONS - REMOTE_HEALTHY_EXPECTATIONS
PROGRESS_SEEK_TAP_LIMIT = 5
"""The progress track maps a tap location through a thumb-inset affine, so the
first offset lands close and each correction removes the residual; five taps is
far past convergence and bounds a track that refuses to move."""
PROGRESS_SEEK_DEADLINE_SECONDS = 60
PROGRESS_SEEK_PROBE_LINE = (
    "reachability playerPanel delivered action=progress.seekToTrack"
)
"""PlaybackPanel.seekToTrack records this line, so an absent line is a tap the
product never received rather than a controller that reported success."""
ISSUE_INDUCE_RECIPES = MappingProxyType(
    {
        "source-file-missing": "missing-object",
        "source-access-denied": "access-denied",
        "connection-interrupted": "transport-interrupted",
        "media-data-corrupt": "corrupt-media",
        "server-certificate-changed": "certificate-rotation",
    }
)
ISSUE_SLOT_POLICY = MappingProxyType(
    {
        "source-file-missing": ("Playback Error", True, True, False),
        "source-access-denied": ("Playback Error", True, True, False),
        "connection-interrupted": ("Playback Error", True, True, False),
        "media-data-corrupt": ("Playback Error", True, True, False),
        "server-certificate-changed": (
            "Server Certificate Changed",
            False,
            True,
            False,
        ),
    }
)
ISSUE_FIXTURE_SOURCE_LABEL = "Enchron Regression WebDAV"
ISSUE_FIXTURE_MEDIA_IDENTIFIER = (
    "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv"
)
REMOTE_PLAYBACK_EXPECTATIONS = frozenset(
    (
        "webdav-playback-range",
        "recoverable-read",
        "finite-backoff",
        "buffer-absorbed-interruption",
    )
)
PLAYBACK_EXPECTATIONS = frozenset(
    ("webdav-loopback", "recoverable-read", "finite-reconnect")
)
CONTAINER_INDEX_EXPECTATIONS = frozenset(
    (
        "baseline-empty",
        "local-active-empty",
        "local-after-empty",
        "remote-positive-control",
    )
)
PLAYBACK_TOPOLOGY_FIELDS = (
    "sourceIdentity",
    "contentRevision",
    "providerProjectionKind",
    "sampleProjectionKind",
    "rendererProjectionKind",
    "rendererViewPackingKind",
    "hasAudio",
)


def _sha256(value: object, location: str) -> str:
    if not isinstance(value, str) or re.fullmatch(r"sha256:[0-9a-f]{64}", value) is None:
        raise OperationAdapterError(f"{location} must be one SHA-256 identity")
    return value


def playback_topology_digest(fields: Mapping[str, object]) -> str:
    topology: dict[str, str] = {}
    for field in PLAYBACK_TOPOLOGY_FIELDS:
        value = fields.get(field)
        if not isinstance(value, str) or not value or value == "none":
            raise OperationAdapterError(
                f"playback-state probe omitted topology field {field}"
            )
        topology[field] = value
    encoded = json.dumps(
        topology,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return "sha256:" + hashlib.sha256(encoded).hexdigest()


def certificate_boundary_observation(lines: list[str]) -> dict[str, object]:
    requested = [
        (index, line)
        for index, line in enumerate(lines)
        if "certificateBoundary promptRequested" in line
    ]
    dismissed = [
        index
        for index, line in enumerate(lines)
        if "certificateBoundary modalDismissed id=source-connection" in line
    ]
    presented = [
        (index, line)
        for index, line in enumerate(lines)
        if "certificateBoundary promptPresented" in line
    ]
    decisions = [
        (index, line)
        for index, line in enumerate(lines)
        if "certificateBoundary decision" in line
    ]
    parsed_decisions: list[bool | None] = []
    fingerprints: list[str | None] = []
    ordered_attempts: list[bool] = []
    connection_phases: list[bool] = []
    validity_boundaries: list[bool] = []
    complete_attempts = min(
        len(requested), len(dismissed), len(presented), len(decisions)
    )
    for attempt in range(complete_attempts):
        request_index, request_line = requested[attempt]
        presented_index, presented_line = presented[attempt]
        decision_index, decision_line = decisions[attempt]
        ordered_attempts.append(
            request_index
            < dismissed[attempt]
            < presented_index
            < decision_index
        )
        connection_phases.append("phase=connection" in request_line)
        validity_boundaries.append(
            "validFrom=" in presented_line and "validUntil=" in presented_line
        )
        decision_match = re.search(r"\bapproved=(true|false)\b", decision_line)
        fingerprint_match = re.search(r"\bfingerprint=([^ ]+)", presented_line)
        parsed_decisions.append(
            None if decision_match is None else decision_match.group(1) == "true"
        )
        fingerprints.append(
            None if fingerprint_match is None else fingerprint_match.group(1)
        )
    playback_prompt_count = sum(
        "phase=playback" in line for _, line in requested
    )
    one_stable_fingerprint = (
        len(fingerprints) == 2
        and all(fingerprint is not None for fingerprint in fingerprints)
        and len(set(fingerprints)) == 1
    )
    return {
        "schema": "enchron.regression.certificate-boundary-observation@1",
        "decisions": parsed_decisions,
        "fingerprints": fingerprints,
        "promptCount": len(requested),
        "dismissCount": len(dismissed),
        "presentedCount": len(presented),
        "decisionCount": len(decisions),
        "playbackPromptCount": playback_prompt_count,
        "orderedAttempts": ordered_attempts,
        "connectionPhases": connection_phases,
        "validityBoundaries": validity_boundaries,
        "oneStableFingerprint": one_stable_fingerprint,
        "events": {
            "requested": [line for _, line in requested],
            "dismissedIndices": dismissed,
            "presented": [line for _, line in presented],
            "decisions": [line for _, line in decisions],
        },
        "expectationObservation": {
            "expected": {
                "promptCount": 2,
                "dismissCount": 2,
                "presentedCount": 2,
                "decisionCount": 2,
                "playbackPromptCount": 0,
                "decisions": [False, True],
                "oneStableFingerprint": True,
                "orderedAttempts": [True, True],
                "connectionPhases": [True, True],
                "validityBoundaries": [True, True],
            },
            "observed": {
                "promptCount": len(requested),
                "dismissCount": len(dismissed),
                "presentedCount": len(presented),
                "decisionCount": len(decisions),
                "playbackPromptCount": playback_prompt_count,
                "decisions": parsed_decisions,
                "fingerprints": fingerprints,
                "oneStableFingerprint": one_stable_fingerprint,
                "orderedAttempts": ordered_attempts,
                "connectionPhases": connection_phases,
                "validityBoundaries": validity_boundaries,
            },
        },
    }


def _certificate_fingerprint(value: object, location: str) -> str:
    if not isinstance(value, str):
        raise OperationAdapterError(f"{location} is not a certificate fingerprint")
    hex_value = value.removeprefix("sha256:").replace(":", "").lower()
    if re.fullmatch(r"[0-9a-f]{64}", hex_value) is None:
        raise OperationAdapterError(f"{location} is not a certificate fingerprint")
    return "sha256:" + hex_value


def certificate_change_observation(
    lines: list[str],
    remote: Mapping[str, object],
    interruption: Mapping[str, object],
) -> dict[str, object]:
    changed = [
        line for line in lines if "certificateBoundary changed previous=" in line
    ]
    prompts = [
        line
        for line in lines
        if "certificateBoundary promptRequested" in line
        or "certificateBoundary promptPresented" in line
        or "certificateBoundary decision" in line
    ]
    closes = [
        line
        for line in lines
        if "reachability playback issue delivered" in line
        and "action=close" in line
    ]
    match = (
        re.search(
            r"certificateBoundary changed previous=([^ ]+) new=([^ ]+)",
            changed[0],
        )
        if changed
        else None
    )

    def fingerprint_or_none(value: object) -> str | None:
        try:
            return _certificate_fingerprint(value, "certificate observation")
        except OperationAdapterError:
            return None

    previous = fingerprint_or_none(match.group(1)) if match is not None else None
    current = fingerprint_or_none(match.group(2)) if match is not None else None
    remote_previous = fingerprint_or_none(
        remote.get("priorCertificateFingerprint")
    )
    remote_current = fingerprint_or_none(remote.get("certificateFingerprint"))
    before = interruption.get("before")
    after = interruption.get("after")
    trust = interruption.get("trust")
    before_state = dict(before) if isinstance(before, Mapping) else None
    after_state = dict(after) if isinstance(after, Mapping) else None
    trust_state = dict(trust) if isinstance(trust, Mapping) else None
    stored_after = (
        fingerprint_or_none(trust_state.get("storedFingerprint"))
        if trust_state is not None
        else None
    )
    trust_previous = (
        fingerprint_or_none(trust_state.get("previousFingerprint"))
        if trust_state is not None
        else None
    )
    trust_current = (
        fingerprint_or_none(trust_state.get("currentFingerprint"))
        if trust_state is not None
        else None
    )
    trusted_after = (
        trust_state.get("currentFingerprintTrusted")
        if trust_state is not None
        else None
    )
    return {
        "schema": "enchron.regression.certificate-change-observation@1",
        "previousFingerprint": previous,
        "currentFingerprint": current,
        "remotePreviousFingerprint": remote_previous,
        "remoteCurrentFingerprint": remote_current,
        "issueCategory": "server-certificate-changed",
        "deliveredChangeEvents": changed,
        "deliveredCloseEvents": closes,
        "playbackPromptEvents": prompts,
        "beforeClose": before_state,
        "afterClose": after_state,
        "storedFingerprintAfterClose": stored_after,
        "trustPreviousFingerprint": trust_previous,
        "trustCurrentFingerprint": trust_current,
        "currentFingerprintTrustedAfterClose": trusted_after,
        "interruption": dict(interruption),
        "expectationObservation": {
            "expected": {
                "changeEventCount": 1,
                "deliveredFingerprintPair": [remote_previous, remote_current],
                "closeEventCount": 1,
                "playbackPromptCount": 0,
                "beforeClose": {
                    "active": "true",
                    "lifecycle": "Paused",
                    "error": "server-certificate-changed",
                    "transition": "none",
                    "presentation": ["window", "portal"],
                },
                "afterClose": {
                    "active": "false",
                    "lifecycle": "Idle",
                    "error": "none",
                    "session": "none",
                    "transition": "none",
                },
                "storedFingerprintAfterClose": remote_previous,
                "trustPreviousFingerprint": remote_previous,
                "trustCurrentFingerprint": remote_current,
                "currentFingerprintTrustedAfterClose": "false",
            },
            "observed": {
                "changeEventCount": len(changed),
                "deliveredFingerprintPair": [previous, current],
                "closeEventCount": len(closes),
                "playbackPromptCount": len(prompts),
                "beforeClose": before_state,
                "afterClose": after_state,
                "storedFingerprintAfterClose": stored_after,
                "trustPreviousFingerprint": trust_previous,
                "trustCurrentFingerprint": trust_current,
                "currentFingerprintTrustedAfterClose": trusted_after,
            },
        },
    }


def _exact_object(
    value: object,
    fields: frozenset[str],
    location: str,
) -> Mapping[str, object]:
    if not isinstance(value, dict):
        raise OperationAdapterError(f"{location} must be a JSON object")
    actual = frozenset(value)
    if actual != fields:
        missing = ", ".join(sorted(fields - actual)) or "none"
        extra = ", ".join(sorted(actual - fields)) or "none"
        raise OperationAdapterError(
            f"{location} has the wrong fields; missing: {missing}; extra: {extra}"
        )
    return value


def _nonempty_text(value: object, location: str) -> str:
    if not isinstance(value, str) or not value or value.strip() != value:
        raise OperationAdapterError(f"{location} must be exact nonempty text")
    return value


def _lowercase_uuid(value: object, location: str) -> str:
    text = _nonempty_text(value, location)
    if re.fullmatch(
        r"[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}",
        text,
    ) is None:
        raise OperationAdapterError(f"{location} must be one lowercase UUID")
    return text


def _nonnegative_integer(value: object, location: str) -> int:
    if type(value) is not int or value < 0:
        raise OperationAdapterError(f"{location} must be a non-negative integer")
    return value


def validate_library_snapshot(value: object) -> Mapping[str, object]:
    snapshot = _exact_object(
        value,
        frozenset(("folders", "references", "stagedFiles")),
        "librarySnapshot",
    )
    folders = snapshot["folders"]
    references = snapshot["references"]
    staged_files = snapshot["stagedFiles"]
    for field, collection in (
        ("folders", folders),
        ("references", references),
        ("stagedFiles", staged_files),
    ):
        if not isinstance(collection, list):
            raise OperationAdapterError(f"librarySnapshot.{field} must be an array")

    folder_ids: list[str] = []
    parent_ids: list[str | None] = []
    for index, item in enumerate(folders):
        location = f"librarySnapshot.folders[{index}]"
        folder = _exact_object(
            item,
            frozenset(("id", "parentID", "name")),
            location,
        )
        folder_id = _lowercase_uuid(folder["id"], f"{location}.id")
        parent = folder["parentID"]
        parent_id = (
            None
            if parent is None
            else _lowercase_uuid(parent, f"{location}.parentID")
        )
        _nonempty_text(folder["name"], f"{location}.name")
        if parent_id == folder_id:
            raise OperationAdapterError(f"{location}.parentID cannot equal its id")
        folder_ids.append(folder_id)
        parent_ids.append(parent_id)
    if folder_ids != sorted(folder_ids) or len(folder_ids) != len(set(folder_ids)):
        raise OperationAdapterError(
            "librarySnapshot.folders must have unique IDs in ascending order"
        )
    folder_id_set = set(folder_ids)
    if any(parent is not None and parent not in folder_id_set for parent in parent_ids):
        raise OperationAdapterError(
            "librarySnapshot folder parentID must identify a folder in the snapshot"
        )

    reference_ids: list[str] = []
    for index, item in enumerate(references):
        location = f"librarySnapshot.references[{index}]"
        reference = _exact_object(
            item,
            frozenset(
                (
                    "id",
                    "folderID",
                    "name",
                    "locatorKind",
                    "sourceIdentity",
                    "sourcePath",
                    "sourceExists",
                    "sourceDigest",
                    "sizeInBytes",
                )
            ),
            location,
        )
        reference_id = _lowercase_uuid(reference["id"], f"{location}.id")
        folder_id_value = reference["folderID"]
        folder_id = (
            None
            if folder_id_value is None
            else _lowercase_uuid(folder_id_value, f"{location}.folderID")
        )
        if folder_id is not None and folder_id not in folder_id_set:
            raise OperationAdapterError(
                f"{location}.folderID must identify a folder in the snapshot"
            )
        _nonempty_text(reference["name"], f"{location}.name")
        locator_kind = reference["locatorKind"]
        if locator_kind not in ("file", "sourceItem"):
            raise OperationAdapterError(
                f"{location}.locatorKind must be file or sourceItem"
            )
        _sha256(reference["sourceIdentity"], f"{location}.sourceIdentity")
        source_path = _nonempty_text(reference["sourcePath"], f"{location}.sourcePath")
        _nonnegative_integer(reference["sizeInBytes"], f"{location}.sizeInBytes")
        source_exists = reference["sourceExists"]
        source_digest = reference["sourceDigest"]
        if locator_kind == "sourceItem":
            if source_exists is not None or source_digest is not None:
                raise OperationAdapterError(
                    f"{location} must not invent local integrity for a sourceItem"
                )
        else:
            if source_exists is not None and type(source_exists) is not bool:
                raise OperationAdapterError(
                    f"{location}.sourceExists must be Boolean or null"
                )
            if source_digest is not None:
                _sha256(source_digest, f"{location}.sourceDigest")
                if source_exists is not True:
                    raise OperationAdapterError(
                        f"{location}.sourceDigest requires sourceExists=true"
                    )
            if source_path == "unresolved" and (
                source_exists is not None or source_digest is not None
            ):
                raise OperationAdapterError(
                    f"{location} cannot attach integrity to an unresolved source"
                )
        reference_ids.append(reference_id)
    if reference_ids != sorted(reference_ids) or len(reference_ids) != len(
        set(reference_ids)
    ):
        raise OperationAdapterError(
            "librarySnapshot.references must have unique IDs in ascending order"
        )

    staged_names: list[str] = []
    for index, item in enumerate(staged_files):
        location = f"librarySnapshot.stagedFiles[{index}]"
        staged = _exact_object(
            item,
            frozenset(("name", "sizeInBytes", "digest")),
            location,
        )
        staged_names.append(_nonempty_text(staged["name"], f"{location}.name"))
        _nonnegative_integer(staged["sizeInBytes"], f"{location}.sizeInBytes")
        _sha256(staged["digest"], f"{location}.digest")
    if staged_names != sorted(staged_names) or len(staged_names) != len(
        set(staged_names)
    ):
        raise OperationAdapterError(
            "librarySnapshot.stagedFiles must have unique names in ascending order"
        )
    return snapshot


def validate_directory_media_import_receipt(
    value: object,
    arguments: Mapping[str, object] | None = None,
) -> Mapping[str, object]:
    receipt = _exact_object(
        value,
        frozenset(
            (
                "schema",
                "directoryName",
                "mediaFileName",
                "memberFileNames",
                "referenceID",
                "bookmarkRootPath",
                "bookmarkRootIsDirectory",
                "mediaRelativePath",
                "mediaSourcePath",
            )
        ),
        "directoryMediaImportReceipt",
    )
    if receipt["schema"] != "enchron.regression.directory-media-import@1":
        raise OperationAdapterError(
            "directoryMediaImportReceipt.schema is not the reviewed version"
        )
    directory_name = _nonempty_text(
        receipt["directoryName"],
        "directoryMediaImportReceipt.directoryName",
    )
    media_name = _nonempty_text(
        receipt["mediaFileName"],
        "directoryMediaImportReceipt.mediaFileName",
    )
    members = receipt["memberFileNames"]
    if not isinstance(members, list) or not members or any(
        not isinstance(item, str) or not item for item in members
    ):
        raise OperationAdapterError(
            "directoryMediaImportReceipt.memberFileNames must be a nonempty string array"
        )
    if members != sorted(members) or len(members) != len(set(members)):
        raise OperationAdapterError(
            "directoryMediaImportReceipt.memberFileNames must be unique and sorted"
        )
    _lowercase_uuid(
        receipt["referenceID"],
        "directoryMediaImportReceipt.referenceID",
    )
    if receipt["bookmarkRootIsDirectory"] is not True:
        raise OperationAdapterError(
            "directoryMediaImportReceipt must prove a directory bookmark root"
        )
    relative_path = _nonempty_text(
        receipt["mediaRelativePath"],
        "directoryMediaImportReceipt.mediaRelativePath",
    )
    if relative_path != media_name:
        raise OperationAdapterError(
            "directoryMediaImportReceipt media relative path must name the requested media"
        )
    root_path_text = _nonempty_text(
        receipt["bookmarkRootPath"],
        "directoryMediaImportReceipt.bookmarkRootPath",
    )
    source_path_text = _nonempty_text(
        receipt["mediaSourcePath"],
        "directoryMediaImportReceipt.mediaSourcePath",
    )
    root_path = PurePosixPath(root_path_text)
    if (
        not root_path.is_absolute()
        or ".." in root_path.parts
        or root_path.name != directory_name
    ):
        raise OperationAdapterError(
            "directoryMediaImportReceipt bookmark root must be the requested absolute directory"
        )
    if source_path_text != str(root_path / media_name):
        raise OperationAdapterError(
            "directoryMediaImportReceipt media source must descend from its bookmark root"
        )
    if arguments is not None:
        if directory_name != arguments["directoryName"]:
            raise OperationAdapterError(
                "directoryMediaImportReceipt changed the requested directory name"
            )
        if media_name != arguments["mediaFileName"]:
            raise OperationAdapterError(
                "directoryMediaImportReceipt changed the requested media file name"
            )
        expected_members = sorted(str(item) for item in arguments["memberFileNames"])
        if members != expected_members:
            raise OperationAdapterError(
                "directoryMediaImportReceipt changed the requested directory members"
            )
    return receipt


def validate_system_import_delivery_snapshot(
    value: object,
) -> Mapping[str, object]:
    def closed_object(
        candidate: object,
        required: frozenset[str],
        optional: frozenset[str],
        location: str,
    ) -> Mapping[str, object]:
        if not isinstance(candidate, dict):
            raise OperationAdapterError(f"{location} must be a JSON object")
        actual = frozenset(candidate)
        if not required.issubset(actual) or not actual.issubset(required | optional):
            raise OperationAdapterError(
                f"{location} does not match its closed product schema"
            )
        return candidate

    snapshot = closed_object(
        value,
        frozenset(
            (
                "schema",
                "requestID",
                "routeIdentity",
                "deliveryDomain",
                "items",
                "persistentLibraryDelivery",
            )
        ),
        frozenset(),
        "systemImportDeliverySnapshot",
    )
    if snapshot["schema"] != "enchron.regression.system-import-delivery@1":
        raise OperationAdapterError(
            "systemImportDeliverySnapshot has the wrong schema"
        )
    request_id = _lowercase_uuid(
        snapshot["requestID"], "systemImportDeliverySnapshot.requestID"
    )
    delivery_domain = snapshot["deliveryDomain"]
    if delivery_domain not in {
        "files-provider-security-scope",
        "app-managed-photo-transfer",
    }:
        raise OperationAdapterError(
            "systemImportDeliverySnapshot has an unknown delivery domain"
        )
    if snapshot["routeIdentity"] != f"{delivery_domain}:{request_id}":
        raise OperationAdapterError(
            "systemImportDeliverySnapshot route identity is inconsistent"
        )
    items = snapshot["items"]
    if not isinstance(items, list) or not items:
        raise OperationAdapterError(
            "systemImportDeliverySnapshot must contain delivered items"
        )
    expected_identity_kind = {
        "files-provider-security-scope": "files-provider-url",
        "app-managed-photo-transfer": "photos-asset",
    }[str(delivery_domain)]
    for index, value_item in enumerate(items):
        location = f"systemImportDeliverySnapshot.items[{index}]"
        item = closed_object(
            value_item,
            frozenset(("returnedIdentityKind", "deliveredName")),
            frozenset(("returnedIdentity", "byteCount", "sha256")),
            location,
        )
        if item["returnedIdentityKind"] != expected_identity_kind:
            raise OperationAdapterError(
                f"{location}.returnedIdentityKind disagrees with its route"
            )
        _direct_filename({"fileName": _nonempty_text(item["deliveredName"], location)})
        if "returnedIdentity" in item:
            _nonempty_text(item["returnedIdentity"], f"{location}.returnedIdentity")
        if "byteCount" in item:
            _nonnegative_integer(item["byteCount"], f"{location}.byteCount")
        if "sha256" in item:
            _sha256(item["sha256"], f"{location}.sha256")

    persistence = closed_object(
        snapshot["persistentLibraryDelivery"],
        frozenset(("outcome", "references")),
        frozenset(("errorDescription",)),
        "systemImportDeliverySnapshot.persistentLibraryDelivery",
    )
    outcome = persistence["outcome"]
    if outcome not in {"persisted", "rejected"}:
        raise OperationAdapterError(
            "systemImportDeliverySnapshot has an unknown persistence outcome"
        )
    references = persistence["references"]
    if not isinstance(references, list):
        raise OperationAdapterError(
            "systemImportDeliverySnapshot persistent references must be an array"
        )
    reference_ids: set[str] = set()
    for index, value_reference in enumerate(references):
        location = (
            "systemImportDeliverySnapshot.persistentLibraryDelivery"
            f".references[{index}]"
        )
        reference = _exact_object(
            value_reference,
            frozenset(("id", "name", "locatorKind", "sizeInBytes")),
            location,
        )
        reference_id = _lowercase_uuid(reference["id"], f"{location}.id")
        if reference_id in reference_ids:
            raise OperationAdapterError(
                "systemImportDeliverySnapshot repeats a persistent reference"
            )
        reference_ids.add(reference_id)
        _direct_filename(
            {"fileName": _nonempty_text(reference["name"], f"{location}.name")}
        )
        if reference["locatorKind"] not in {"file", "sourceItem"}:
            raise OperationAdapterError(
                f"{location}.locatorKind is not a library locator kind"
            )
        _nonnegative_integer(reference["sizeInBytes"], f"{location}.sizeInBytes")
    error_description = persistence.get("errorDescription")
    if outcome == "persisted" and error_description is not None:
        raise OperationAdapterError(
            "persisted system import unexpectedly contains an error"
        )
    if outcome == "rejected":
        _nonempty_text(error_description, "system import rejection errorDescription")
    _reject_secret_result(snapshot, "systemImportDeliverySnapshot")
    return snapshot


def validate_product_state_reset_receipt(value: object) -> Mapping[str, object]:
    receipt = _exact_object(
        value,
        frozenset(
            (
                "schema",
                "removedReferenceCount",
                "removedFolderCount",
                "removedManagedDefaultKeys",
                "remainingReferenceCount",
                "remainingFolderCount",
                "remainingManagedDefaultKeys",
                "createdFolderNames",
            )
        ),
        "productStateResetReceipt",
    )
    if receipt["schema"] != "enchron.regression.product-state-reset@1":
        raise OperationAdapterError("product reset receipt has the wrong schema")
    for field in (
        "removedReferenceCount",
        "removedFolderCount",
        "remainingReferenceCount",
        "remainingFolderCount",
    ):
        _nonnegative_integer(receipt[field], f"productStateResetReceipt.{field}")
    for field in (
        "removedManagedDefaultKeys",
        "remainingManagedDefaultKeys",
        "createdFolderNames",
    ):
        values = receipt[field]
        if (
            not isinstance(values, list)
            or any(not isinstance(item, str) or not item for item in values)
            or values != sorted(values)
            or len(values) != len(set(values))
        ):
            raise OperationAdapterError(
                f"productStateResetReceipt.{field} must be sorted unique strings"
            )
    if receipt["remainingManagedDefaultKeys"]:
        raise OperationAdapterError("product reset left managed defaults behind")
    return receipt


def _remote_check_payload(
    check: str, report: Mapping[str, object]
) -> Mapping[str, object]:
    if report.get("schema") != "enchron.regression.environment-preflight@1":
        raise OperationAdapterError("remote preflight returned the wrong report schema")
    if report.get("ready") is not True:
        raise OperationAdapterError(f"remote preflight {check} did not report ready")
    checks = report.get("checks")
    if not isinstance(checks, list) or len(checks) != 1 or not isinstance(checks[0], dict):
        raise OperationAdapterError("remote preflight must return one exact fixed check")
    result = checks[0]
    if result.get("check") != check or result.get("ready") is not True:
        raise OperationAdapterError("remote preflight result does not match its fixed check")
    return result


def _triggered_requests_from_log(log_path: object) -> list[dict[str, object]]:
    if not isinstance(log_path, str) or not Path(log_path).is_file():
        return []
    try:
        entries = [
            json.loads(line)
            for line in Path(log_path).read_text(encoding="utf-8").splitlines()
            if line
        ]
    except (OSError, json.JSONDecodeError) as error:
        raise OperationAdapterError(
            "activation request log is unreadable"
        ) from error
    _reject_secret_result(entries, "triggeredRequests")
    return [
        item
        for item in entries
        if isinstance(item, dict) and item.get("triggered") is True
    ]


def _reject_secret_result(value: object, location: str = "report") -> None:
    if isinstance(value, Mapping):
        for key, item in value.items():
            folded = str(key).casefold().replace("_", "").replace("-", "")
            if folded in {"password", "authorization", "accesstoken", "secretbytes"}:
                raise OperationAdapterError(
                    f"remote preflight leaked a secret field at {location}.{key}"
                )
            _reject_secret_result(item, f"{location}.{key}")
    elif isinstance(value, list):
        for index, item in enumerate(value):
            _reject_secret_result(item, f"{location}[{index}]")


def _manifest_hashes(value: object, location: str) -> None:
    if not isinstance(value, dict) or not value:
        raise OperationAdapterError(f"{location} omitted object manifest hashes")
    for fixture_id, digest in value.items():
        if not isinstance(fixture_id, str) or not fixture_id:
            raise OperationAdapterError(f"{location} returned an invalid fixture ID")
        _sha256(digest, f"{location}.{fixture_id}")


def validate_remote_preflight_report(
    check: str, report: Mapping[str, object]
) -> None:
    if check not in REMOTE_PREFLIGHT_CHECKS:
        raise OperationAdapterError(f"not a remote fixed preflight: {check}")
    _reject_secret_result(report)
    result = _remote_check_payload(check, report)
    service_id = result.get("serviceID")
    if not isinstance(service_id, str) or not service_id.startswith("remote-source:"):
        raise OperationAdapterError("remote preflight omitted its service identity")
    if check == "webdav-regression":
        generation = result.get("generation")
        if not isinstance(generation, int) or isinstance(generation, bool) or generation < 1:
            raise OperationAdapterError("webdav-regression omitted its generation")
        for key in (
            "endpointDigest",
            "certificateFingerprint",
            "requestLogDigest",
            "rangeDigest",
            "expectedRangeDigest",
        ):
            _sha256(result.get(key), f"webdav-regression.{key}")
        for key in ("requestLogPath",):
            value = result.get(key)
            if not isinstance(value, str) or not Path(value).is_absolute():
                raise OperationAdapterError(
                    f"webdav-regression.{key} must be one absolute artifact path"
                )
        _manifest_hashes(
            result.get("objectManifestHashes"),
            "webdav-regression.objectManifestHashes",
        )
        if (
            result.get("propfindStatus") != 207
            or result.get("rangeStatus") != 206
            or result.get("rangeDigest") != result.get("expectedRangeDigest")
        ):
            raise OperationAdapterError(
                "webdav-regression did not prove DAV and ranged fixture bytes"
            )
        return

    recipes = result.get("recipes")
    if not isinstance(recipes, list) or tuple(
        item.get("recipe") if isinstance(item, dict) else None for item in recipes
    ) != _remote_preflight.remote.RECIPE_NAMES:
        raise OperationAdapterError("remote-faults did not verify the exact closed recipes")
    for item in recipes:
        assert isinstance(item, dict)
        recipe = str(item["recipe"])
        receipt = item.get("receipt")
        if item.get("verified") is not True or not isinstance(receipt, dict):
            raise OperationAdapterError(f"remote-faults did not verify {recipe}")
        if (
            receipt.get("schema")
            != "enchron.regression.remote-source-receipt@1"
            or receipt.get("recipe") != recipe
        ):
            raise OperationAdapterError(f"remote-faults returned a mismatched {recipe} receipt")
        receipt_id = receipt.get("receiptID")
        generation = receipt.get("generation")
        activation_time = receipt.get("activationTime")
        if not isinstance(receipt_id, str) or not receipt_id:
            raise OperationAdapterError(f"remote-faults.{recipe} omitted its receipt ID")
        if not isinstance(generation, int) or isinstance(generation, bool) or generation < 1:
            raise OperationAdapterError(f"remote-faults.{recipe} omitted its generation")
        if not isinstance(activation_time, str) or not activation_time.endswith("Z"):
            raise OperationAdapterError(
                f"remote-faults.{recipe} omitted its activation time"
            )
        for key in (
            "endpointDigest",
            "priorStateDigest",
            "terminalStateDigest",
            "priorCertificateFingerprint",
            "certificateFingerprint",
        ):
            _sha256(receipt.get(key), f"remote-faults.{recipe}.{key}")
        _sha256(receipt.get("restoredStateDigest"), f"remote-faults.{recipe}.restored")
        _sha256(receipt.get("logDigest"), f"remote-faults.{recipe}.logDigest")
        _manifest_hashes(
            receipt.get("objectManifestHashes"),
            f"remote-faults.{recipe}.objectManifestHashes",
        )
        log_path = receipt.get("logPath")
        if not isinstance(log_path, str) or not Path(log_path).is_absolute():
            raise OperationAdapterError(
                f"remote-faults.{recipe}.logPath must be one absolute artifact path"
            )
    terminal = result.get("terminalState")
    if not isinstance(terminal, dict) or terminal.get("recipe") != "healthy":
        raise OperationAdapterError("remote-faults did not restore the service to healthy")
    generation = terminal.get("generation")
    if not isinstance(generation, int) or isinstance(generation, bool) or generation < 1:
        raise OperationAdapterError("remote-faults terminal state omitted its generation")
    _sha256(terminal.get("endpointDigest"), "remote-faults.terminal.endpointDigest")
    _sha256(
        terminal.get("certificateFingerprint"),
        "remote-faults.terminal.certificateFingerprint",
    )


def validate_remote_activation_receipt(
    receipt: object,
    recipe: str,
) -> Mapping[str, object]:
    required = frozenset(
        (
            "schema",
            "receiptID",
            "recipe",
            "generation",
            "endpointDigest",
            "activationTime",
            "priorStateDigest",
            "terminalStateDigest",
            "restoredStateDigest",
            "logPath",
            "logDigest",
            "objectManifestHashes",
            "priorCertificateFingerprint",
            "certificateFingerprint",
        )
    )
    value = _exact_object(receipt, required, "activationReceipt")
    _reject_secret_result(value, "activationReceipt")
    if (
        value.get("schema") != "enchron.regression.remote-source-receipt@1"
        or value.get("recipe") != recipe
        or value.get("restoredStateDigest") is not None
    ):
        raise OperationAdapterError("remote activation receipt identity drifted")
    receipt_id = value.get("receiptID")
    generation = value.get("generation")
    if (
        not isinstance(receipt_id, str)
        or re.fullmatch(
            rf"receipt:g-([0-9]{{6}}):{re.escape(recipe)}", receipt_id
        )
        is None
        or not isinstance(generation, int)
        or isinstance(generation, bool)
        or receipt_id != f"receipt:g-{generation:06d}:{recipe}"
    ):
        raise OperationAdapterError("remote activation receipt is not generation bound")
    if not isinstance(value.get("activationTime"), str) or not str(
        value["activationTime"]
    ).endswith("Z"):
        raise OperationAdapterError("remote activation receipt omitted activation time")
    for field in (
        "endpointDigest",
        "priorStateDigest",
        "terminalStateDigest",
        "logDigest",
        "priorCertificateFingerprint",
        "certificateFingerprint",
    ):
        _sha256(value.get(field), f"activationReceipt.{field}")
    _manifest_hashes(
        value.get("objectManifestHashes"),
        "activationReceipt.objectManifestHashes",
    )
    log_path = value.get("logPath")
    if not isinstance(log_path, str) or not Path(log_path).is_absolute():
        raise OperationAdapterError("activationReceipt.logPath must be absolute")
    return value


def validate_remote_restoration_receipt(
    receipt: object,
    activation_receipt_id: str,
) -> Mapping[str, object]:
    required = frozenset(
        (
            "schema",
            "receiptID",
            "activationReceiptID",
            "activationRecipe",
            "activationGeneration",
            "activationEndpointDigest",
            "activationLogPath",
            "activationLogDigest",
            "restoredAt",
            "restoredRecipe",
            "restoredGeneration",
            "restoredStateDigest",
            "restoredEndpointDigest",
            "restoredCertificateFingerprint",
            "restoredRequestLogPath",
            "restoredRequestLogDigest",
            "objectManifestHashes",
            "propfindStatus",
            "rangeStatus",
            "range",
            "rangeDigest",
            "expectedRangeDigest",
            "verified",
            "receiptPath",
            "receiptDigest",
        )
    )
    value = _exact_object(receipt, required, "restorationReceipt")
    _reject_secret_result(value, "restorationReceipt")
    if (
        value.get("schema")
        != "enchron.regression.remote-source-restoration@1"
        or value.get("activationReceiptID") != activation_receipt_id
        or value.get("restoredRecipe") != "healthy"
        or value.get("verified") is not True
        or value.get("propfindStatus") != 207
        or value.get("rangeStatus") != 206
        or value.get("rangeDigest") != value.get("expectedRangeDigest")
    ):
        raise OperationAdapterError("remote restoration receipt is not verified healthy")
    activation_generation = value.get("activationGeneration")
    restored_generation = value.get("restoredGeneration")
    if (
        not isinstance(activation_generation, int)
        or isinstance(activation_generation, bool)
        or not isinstance(restored_generation, int)
        or isinstance(restored_generation, bool)
        or restored_generation <= activation_generation
    ):
        raise OperationAdapterError("remote restoration generations are invalid")
    for field in (
        "activationEndpointDigest",
        "activationLogDigest",
        "restoredStateDigest",
        "restoredEndpointDigest",
        "restoredCertificateFingerprint",
        "restoredRequestLogDigest",
        "rangeDigest",
        "expectedRangeDigest",
        "receiptDigest",
    ):
        _sha256(value.get(field), f"restorationReceipt.{field}")
    _manifest_hashes(
        value.get("objectManifestHashes"),
        "restorationReceipt.objectManifestHashes",
    )
    for field in (
        "activationLogPath",
        "restoredRequestLogPath",
        "receiptPath",
    ):
        path = value.get(field)
        if not isinstance(path, str) or not Path(path).is_absolute():
            raise OperationAdapterError(f"restorationReceipt.{field} must be absolute")
    return value


def validate_smb_preflight_report(
    report: object, runtime_file: Path = SMB_RUNTIME_FILE
) -> None:
    try:
        _smb_source.validate_preflight_report(report, runtime_file)
    except _smb_source.SMBSourceError as error:
        raise OperationAdapterError(str(error)) from error


def _smb_aggregate_video_name(report: Mapping[str, object]) -> str:
    paths = report.get("aggregatePaths")
    if not isinstance(paths, list):
        raise OperationAdapterError("SMB aggregate omitted its paths")
    names = [
        PurePosixPath(path).name
        for path in paths
        if isinstance(path, str) and PurePosixPath(path).suffix.casefold() == ".mkv"
    ]
    if len(names) != 1 or not names[0]:
        raise OperationAdapterError("SMB aggregate did not name one video")
    return names[0]


def _runtime_identity(path: Path) -> tuple[Mapping[str, object], Mapping[str, object]]:
    try:
        information = path.lstat()
        runtime = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise OperationAdapterError("remote runtime identity is unreadable") from error
    if (
        not stat.S_ISREG(information.st_mode)
        or information.st_uid != os.getuid()
        or stat.S_IMODE(information.st_mode) != 0o600
    ):
        raise OperationAdapterError(
            "remote runtime identity must be an owner-only 0600 regular file"
        )
    if (
        not isinstance(runtime, dict)
        or set(runtime) != _remote_preflight.remote.RUNTIME_DOCUMENT_KEYS
    ):
        raise OperationAdapterError("remote runtime identity schema drifted")
    if not all(
        isinstance(runtime.get(key), str) and runtime[key]
        for key in ("address", "user", "password", "serviceID")
    ):
        raise OperationAdapterError("remote runtime identity omitted an exact UI input")
    metadata: Mapping[str, object] = MappingProxyType(
        {
            "path": str(path),
            "mode": "0600",
            "serviceID": runtime["serviceID"],
            "generation": runtime["generation"],
            "requestLogPath": runtime["requestLogPath"],
            "manifestPath": runtime["manifestPath"],
            "certificateFingerprint": runtime["certificateFingerprint"],
        }
    )
    return MappingProxyType(runtime), metadata


def _literal_lan_address() -> str:
    from Scripts.verification import journey_preflight

    candidate = journey_preflight.host_address()
    try:
        address = ipaddress.ip_address(candidate)
    except ValueError as error:
        raise OperationAdapterError("remote preflight found no literal LAN address") from error
    if (
        address.version != 4
        or address.is_loopback
        or address.is_unspecified
        or address.is_multicast
        or not (address.is_private or address.is_link_local)
    ):
        raise OperationAdapterError("remote preflight requires one literal IPv4 LAN address")
    return candidate


def _cursor(arguments: Mapping[str, object]) -> None:
    _related_results(arguments)
    token = arguments.get("cursorToken")
    if token is not None and not (
        re.fullmatch(r"(?:-1|[0-9]+):[0-9]+", str(token))
        or re.fullmatch(r"result://call:[a-z0-9:-]+/[A-Za-z][A-Za-z0-9]*", str(token))
    ):
        raise OperationAdapterError("cursorToken is not a direct or result cursor token")
    expectation = arguments.get("remoteExpectation")
    generation = arguments.get("remoteGenerationToken")
    receipt = arguments.get("remoteReceiptID")
    restored_generation = arguments.get("restoredGenerationToken")
    product_binding = arguments.get("productBindingDigest")
    container_expectation = arguments.get("containerIndexExpectation")
    container_fields = {
        "expectedBaselineDigest": arguments.get("expectedBaselineDigest"),
        "expectedLocalActiveDigest": arguments.get("expectedLocalActiveDigest"),
        "expectedLocalAfterDigest": arguments.get("expectedLocalAfterDigest"),
    }
    include_viewing_storage = arguments.get("includeViewingStorage")
    prior_viewing_digests = arguments.get("priorViewingStorageDigests")
    await_empty_stores = arguments.get("awaitEmptyStores")
    deadline_seconds = arguments.get("deadlineSeconds")
    remote_request_cursor = arguments.get("remoteRequestCursor")
    viewing_storage_options = (
        prior_viewing_digests,
        await_empty_stores,
        deadline_seconds,
        remote_request_cursor,
    )
    omit_playback_state = arguments.get("omitPlaybackState")
    emby_progress_readback = arguments.get("embyProgressReadback")
    if omit_playback_state is not None and omit_playback_state is not True:
        raise OperationAdapterError("omitPlaybackState may only request true")
    if (
        emby_progress_readback is not None
        and emby_progress_readback is not True
    ):
        raise OperationAdapterError("embyProgressReadback may only request true")
    if omit_playback_state is True and expectation not in (
        "finite-backoff",
        "recoverable-read",
    ):
        raise OperationAdapterError(
            "omitPlaybackState requires a finite-backoff or recoverable-read remoteExpectation"
        )
    if include_viewing_storage is not None and include_viewing_storage is not True:
        raise OperationAdapterError("includeViewingStorage may only request true")
    if any(value is not None for value in viewing_storage_options) and (
        include_viewing_storage is not True
    ):
        raise OperationAdapterError(
            "viewing-storage options require includeViewingStorage=true"
        )
    if prior_viewing_digests is not None:
        if len(prior_viewing_digests) != len(set(prior_viewing_digests)):
            raise OperationAdapterError(
                "priorViewingStorageDigests must not repeat a binding"
            )
        for value in prior_viewing_digests:
            if not (
                re.fullmatch(r"sha256:[0-9a-f]{64}", value)
                or re.fullmatch(
                    r"result://call:[a-z0-9:-]+/viewingStorageDigest",
                    value,
                )
            ):
                raise OperationAdapterError(
                    "priorViewingStorageDigests must bind prior surface-probe results"
                )
    if await_empty_stores is not None:
        allowed_stores = {"viewing-state", "container-index", "artwork"}
        if (
            await_empty_stores != sorted(set(await_empty_stores))
            or not set(await_empty_stores).issubset(allowed_stores)
            or deadline_seconds is None
        ):
            raise OperationAdapterError(
                "awaitEmptyStores requires a canonical store set and deadlineSeconds"
            )
    elif deadline_seconds is not None:
        raise OperationAdapterError(
            "deadlineSeconds is reserved for awaitEmptyStores"
        )
    if remote_request_cursor is not None:
        if expectation != "webdav-playback-range" or not (
            re.fullmatch(r"0|[1-9][0-9]*", str(remote_request_cursor))
            or re.fullmatch(
                r"result://call:[a-z0-9:-]+/remoteRequestCursor",
                str(remote_request_cursor),
            )
        ):
            raise OperationAdapterError(
                "remoteRequestCursor requires a WebDAV playback observation cursor"
            )
    if container_expectation is not None:
        if (
            container_expectation not in CONTAINER_INDEX_EXPECTATIONS
            or token is not None
            or expectation is not None
            or any(
                value is not None
                for value in (
                    generation,
                    receipt,
                    restored_generation,
                    product_binding,
                )
            )
        ):
            raise OperationAdapterError(
                "container index observation is one closed non-remote probe"
            )
        required = {
            "baseline-empty": frozenset(),
            "local-active-empty": frozenset(("expectedBaselineDigest",)),
            "local-after-empty": frozenset(("expectedBaselineDigest",)),
            "remote-positive-control": frozenset(
                (
                    "expectedBaselineDigest",
                    "expectedLocalActiveDigest",
                    "expectedLocalAfterDigest",
                )
            ),
        }[str(container_expectation)]
        present = frozenset(
            name for name, value in container_fields.items() if value is not None
        )
        if present != required:
            raise OperationAdapterError(
                f"{container_expectation} requires exact prior index digest bindings"
            )
        for field in required:
            _sha256_or_result_reference(arguments, field, "containerIndexDigest")
        return
    if any(value is not None for value in container_fields.values()):
        raise OperationAdapterError(
            "container index digest bindings require containerIndexExpectation"
        )
    if expectation is None:
        if any(
            value is not None
            for value in (
                generation,
                receipt,
                restored_generation,
                product_binding,
            )
        ):
            raise OperationAdapterError(
                "remote surface bindings require one closed remoteExpectation"
            )
        return
    if expectation not in REMOTE_EXPECTATIONS:
        raise OperationAdapterError("surface remoteExpectation is not closed")
    if expectation == "certificate-change" and token is None:
        raise OperationAdapterError(
            "certificate change observation requires a pre-rotation cursorToken"
        )
    if expectation in REMOTE_HEALTHY_EXPECTATIONS:
        if not isinstance(generation, str) or receipt is not None or restored_generation is not None:
            raise OperationAdapterError(
                "healthy remote observation requires only remoteGenerationToken"
            )
        _literal_or_result_reference(
            arguments, "remoteGenerationToken", "generationToken"
        )
    else:
        if (
            not isinstance(receipt, str)
            or not isinstance(restored_generation, str)
            or generation is not None
        ):
            raise OperationAdapterError(
                "fault observation requires receiptID and restoredGenerationToken"
            )
        _literal_or_result_reference(arguments, "remoteReceiptID", "receiptID")
        _literal_or_result_reference(
            arguments, "restoredGenerationToken", "restoredGenerationToken"
        )
    if expectation in REMOTE_PLAYBACK_EXPECTATIONS:
        if not isinstance(product_binding, str):
            raise OperationAdapterError(
                "remote playback observation requires productBindingDigest"
            )
        _sha256_or_result_reference(
            arguments, "productBindingDigest", "bindingDigest"
        )
    elif product_binding is not None:
        raise OperationAdapterError(
            "productBindingDigest is allowed only for a remote playback expectation"
        )


def _stage_fixture(arguments: Mapping[str, object]) -> None:
    root = Path(str(arguments["sourceRoot"]))
    if not root.is_absolute():
        raise OperationAdapterError("sourceRoot must be absolute")


def _direct_child_name(value: object, location: str) -> str:
    text = str(value)
    path = PurePosixPath(text)
    if (
        not text
        or text.strip() != text
        or path.is_absolute()
        or len(path.parts) != 1
        or path.name in ("", ".", "..")
    ):
        raise OperationAdapterError(f"{location} must be one direct-child basename")
    return text


def _direct_filename(arguments: Mapping[str, object]) -> None:
    _direct_child_name(arguments["fileName"], "fileName")


def _directory_subtitle_source(arguments: Mapping[str, object]) -> None:
    directory_name = _direct_child_name(
        arguments["directoryName"], "directoryName"
    )
    media_name = _direct_child_name(arguments["mediaFileName"], "mediaFileName")
    members_value = arguments["memberFileNames"]
    assert isinstance(members_value, list)
    members = [
        _direct_child_name(item, "memberFileNames") for item in members_value
    ]
    if len(members) != len(set(members)):
        raise OperationAdapterError("memberFileNames must contain unique basenames")
    if media_name not in members:
        raise OperationAdapterError("memberFileNames must include mediaFileName")
    if directory_name in members:
        raise OperationAdapterError(
            "directoryName must not collide with one staged member file"
        )
    media_stem = PurePosixPath(media_name).stem
    associated_sidecars = [
        name
        for name in members
        if PurePosixPath(name).suffix.lower() in (".srt", ".vtt", ".ass", ".ssa")
        and (
            PurePosixPath(name).stem == media_stem
            or PurePosixPath(name).stem.startswith(media_stem + ".")
        )
    ]
    if not associated_sidecars:
        raise OperationAdapterError(
            "memberFileNames must include a same-basename external subtitle"
        )


def _media_open(arguments: Mapping[str, object]) -> None:
    identifier = str(arguments["identifier"])
    allowed = identifier in ("Emby-Detail-Resume", "Emby-Detail-PlayFromBeginning") or any(
        identifier.startswith(prefix)
        for prefix in (
            "MediaLibrary-grid-video-",
            "FileBrowsing-grid-video-",
            "Emby-Episode-",
        )
    )
    if not allowed:
        raise OperationAdapterError("identifier is not a playback-start identifier")
    _validate_identifiers([identifier])
    _related_results(arguments)
    if (
        "expectedIssueCategory" in arguments
        and arguments["expectedLanding"] not in ("window", "either-main-window")
    ):
        raise OperationAdapterError(
            "an expected media-open issue must remain on a main-window landing"
        )


def _unsigned_token(arguments: Mapping[str, object]) -> None:
    token = str(arguments["generationToken"])
    if not (
        re.fullmatch(r"0|[1-9][0-9]*", token)
        or re.fullmatch(r"result://call:[a-z0-9:-]+/generationToken", token)
    ):
        raise OperationAdapterError("generationToken must be canonical unsigned decimal")


def _literal_or_result_reference(
    arguments: Mapping[str, object], argument_name: str, result_field: str
) -> None:
    value = arguments.get(argument_name)
    if value is None:
        return
    text = str(value)
    if text == "none":
        raise OperationAdapterError(f"{argument_name} must identify a concrete value")
    if text.startswith("result://") and re.fullmatch(
        rf"result://call:[a-z0-9:-]+/{re.escape(result_field)}", text
    ) is None:
        raise OperationAdapterError(
            f"{argument_name} must be a literal or a /{result_field} result reference"
        )


def _sha256_or_result_reference(
    arguments: Mapping[str, object], argument_name: str, result_field: str
) -> None:
    value = arguments.get(argument_name)
    if value is None:
        return
    text = str(value)
    if text.startswith("result://"):
        if re.fullmatch(
            rf"result://call:[a-z0-9:-]+/{re.escape(result_field)}", text
        ) is None:
            raise OperationAdapterError(
                f"{argument_name} must select /{result_field}"
            )
        return
    _sha256(text, argument_name)


def _playback_state(arguments: Mapping[str, object]) -> None:
    _related_results(arguments)
    expectation = arguments.get("expectation")
    bound_names = frozenset(
        (
            "expectedSession",
            "expectedSourceIdentity",
            "expectedContentRevision",
            "expectedTopologyDigest",
            "minimumPositionMillis",
            "minimumReconnects",
        )
    )
    present = frozenset(arguments) - {"expectation", "relatedResults"}
    if expectation is None:
        if present:
            raise OperationAdapterError(
                "playback-state bindings require one closed expectation"
            )
        return
    if expectation not in PLAYBACK_EXPECTATIONS:
        raise OperationAdapterError("playback-state expectation is not closed")
    if expectation == "webdav-loopback":
        if present != {"minimumPositionMillis"}:
            raise OperationAdapterError(
                "webdav-loopback requires only minimumPositionMillis"
            )
        return
    required = bound_names
    if present != required:
        raise OperationAdapterError(
            f"{expectation} requires exact identity, topology, position, and reconnect bindings"
        )
    _literal_or_result_reference(arguments, "expectedSession", "session")
    _sha256_or_result_reference(
        arguments, "expectedSourceIdentity", "sourceIdentity"
    )
    _sha256_or_result_reference(
        arguments, "expectedContentRevision", "contentRevision"
    )
    _sha256_or_result_reference(
        arguments, "expectedTopologyDigest", "topologyDigest"
    )
    required_reconnects = 1 if expectation == "recoverable-read" else 3
    if arguments.get("minimumReconnects") != required_reconnects:
        raise OperationAdapterError(
            f"{expectation} requires minimumReconnects={required_reconnects}"
        )


def _wait_position(arguments: Mapping[str, object]) -> None:
    _literal_or_result_reference(arguments, "expectedMediaName", "mediaName")
    _literal_or_result_reference(arguments, "differentSessionFrom", "session")


def _playback_seek(arguments: Mapping[str, object]) -> None:
    if arguments.get("summonControls") is not None and arguments.get("summonControls") is not True:
        raise OperationAdapterError("summonControls may only request true")


def _summon_controls_only_true(arguments: Mapping[str, object]) -> None:
    if arguments.get("summonControls") is not None and arguments.get("summonControls") is not True:
        raise OperationAdapterError("summonControls may only request true")


def _format_apply(arguments: Mapping[str, object]) -> None:
    _summon_controls_only_true(arguments)
    projection = arguments["projection"]
    coverage = arguments.get("horizontalCoverageDegrees")
    if projection == "customAngle":
        if coverage is None:
            raise OperationAdapterError(
                "customAngle requires horizontalCoverageDegrees"
            )
        assert isinstance(coverage, int) and not isinstance(coverage, bool)
        if (coverage - 180) % 10 != 0:
            raise OperationAdapterError(
                "horizontalCoverageDegrees must use the exact 180...360 step-10 set"
            )
    elif coverage is not None:
        raise OperationAdapterError(
            "horizontalCoverageDegrees is allowed only for customAngle"
        )


def _audio_capture(arguments: Mapping[str, object]) -> None:
    _attempt_path(str(arguments["wavPath"]), "wavPath")
    _literal_or_result_reference(arguments, "expectedSession", "session")
    _literal_or_result_reference(arguments, "expectedAudioTrackID", "audioTrack")


def _device_hub(arguments: Mapping[str, object]) -> None:
    target_domain = arguments["targetDomain"]
    shot_fields = {"shotX", "shotY", "shotWidth", "shotHeight"}
    present_shot_fields = shot_fields.intersection(arguments)
    if target_domain == "system-toolbar":
        if arguments.get("systemControl") != "home":
            raise OperationAdapterError(
                "Device Hub system-toolbar input requires the allowlisted home control"
            )
        if present_shot_fields or "allowSmall" in arguments:
            raise OperationAdapterError(
                "Device Hub system-toolbar input rejects canvas coordinates"
            )
        return
    if target_domain != "canvas":
        raise OperationAdapterError("Device Hub targetDomain is not allowlisted")
    if present_shot_fields != shot_fields:
        raise OperationAdapterError(
            "Device Hub canvas input requires the complete screenshot coordinate set"
        )
    if "systemControl" in arguments:
        raise OperationAdapterError(
            "Device Hub canvas input rejects systemControl"
        )
    x = int(arguments["shotX"])
    y = int(arguments["shotY"])
    width = int(arguments["shotWidth"])
    height = int(arguments["shotHeight"])
    if x >= width or y >= height:
        raise OperationAdapterError("Device Hub point must be inside the screenshot")


LIBRARY_BASELINE_FIELDS = (
    "baselineReferenceIDs",
    "baselineFolderIDs",
    "baselineSourceIdentities",
    "baselineSourcePaths",
    "baselineSourceDigests",
    "baselineFileNames",
)


def _library_snapshot(arguments: Mapping[str, object]) -> None:
    prior_snapshot = arguments.get("priorSnapshot")
    if prior_snapshot is None:
        pass
    elif isinstance(prior_snapshot, str):
        if re.fullmatch(r"result://call:[a-z0-9:-]+/snapshot", prior_snapshot) is None:
            raise OperationAdapterError(
                "library priorSnapshot must select an earlier /snapshot result"
            )
    else:
        validate_library_snapshot(prior_snapshot)
    system_import_expectation = arguments.get("systemImportExpectation")
    present = [name for name in LIBRARY_BASELINE_FIELDS if name in arguments]
    if system_import_expectation is not None and present:
        raise OperationAdapterError(
            "library snapshot system import and mutation baselines are separate variants"
        )
    if not present:
        return
    if len(present) != len(LIBRARY_BASELINE_FIELDS):
        raise OperationAdapterError(
            "library snapshot baseline fields must appear as one complete set"
        )
    values = [arguments[name] for name in LIBRARY_BASELINE_FIELDS]
    assert all(isinstance(value, list) for value in values)
    lengths = {len(value) for value in values}
    if lengths != {len(values[0])} or not values[0]:
        raise OperationAdapterError(
            "library snapshot baseline fields must have one equal positive length"
        )
    result_fields = {
        "baselineReferenceIDs": "referenceID",
        "baselineFolderIDs": "folderID",
        "baselineSourceIdentities": "sourceIdentity",
        "baselineSourcePaths": "sourcePath",
        "baselineSourceDigests": "sourceDigest",
        "baselineFileNames": "fileName",
    }
    for name, value in zip(LIBRARY_BASELINE_FIELDS, values):
        expected = result_fields[name]
        for item in value:
            if item.startswith("result://"):
                if re.fullmatch(
                    rf"result://call:[a-z0-9:-]+/{expected}", item
                ) is None:
                    raise OperationAdapterError(
                        f"{name} result references must select /{expected}"
                    )
                continue
            if name == "baselineReferenceIDs":
                _lowercase_uuid(item, name)
            elif name == "baselineFolderIDs":
                if item != "root":
                    _lowercase_uuid(item, name)
            elif name in ("baselineSourceIdentities", "baselineSourceDigests"):
                _sha256(item, name)
            elif name == "baselineSourcePaths":
                _nonempty_text(item, name)
            else:
                _direct_filename({"fileName": item})
    if len(values[0]) != len(set(values[0])):
        raise OperationAdapterError("baselineReferenceIDs must be unique")


def _structural_test(arguments: Mapping[str, object]) -> None:
    if arguments["check"] not in STRUCTURAL_CHECKS:
        raise OperationAdapterError("structural check is not in the closed allowlist")


def _attempt_path(value: str, label: str) -> None:
    path = PurePosixPath(value)
    if not value or path.is_absolute() or ".." in path.parts:
        raise OperationAdapterError(f"{label} must be an attempt-relative path")


_INVENTORY_PATTERNS: tuple[re.Pattern[str], ...] | None = None


def _identifier_patterns() -> tuple[re.Pattern[str], ...]:
    global _INVENTORY_PATTERNS
    if _INVENTORY_PATTERNS is not None:
        return _INVENTORY_PATTERNS
    payload = json.loads(INVENTORY_PATH.read_text(encoding="utf-8"))
    templates = [entry["template"] for entry in payload["identifiers"]]
    patterns: list[re.Pattern[str]] = []
    for template in templates:
        escaped = re.escape(template)
        dynamic = re.sub(r"\\\{.*?\\\}", r"[^/]+", escaped)
        patterns.append(re.compile("^" + dynamic + "$"))
    _INVENTORY_PATTERNS = tuple(patterns)
    return _INVENTORY_PATTERNS


def _validate_identifiers(identifiers: list[str]) -> None:
    patterns = _identifier_patterns()
    for identifier in identifiers:
        if not identifier or not any(pattern.fullmatch(identifier) for pattern in patterns):
            raise OperationAdapterError(
                f"accessibility identifier is absent from the current inventory: {identifier}"
            )


def _playback_core_test(test_name: str) -> tuple[str, ...]:
    return (
        "swift",
        "test",
        "--package-path",
        "Packages/PlaybackCore",
        "--filter",
        test_name,
    )


STRUCTURAL_CHECKS = MappingProxyType(
    {
        "format-description-identity": (
            "python3",
            "Scripts/rules/verify_format_description_identity.py",
        ),
        "media-byte-stream-conformance": (
            "python3",
            "Scripts/rules/verify_media_byte_stream_conformance.py",
        ),
        "playback-core-network-resilience": (
            "swift",
            "test",
            "--package-path",
            "Packages/PlaybackCore",
            "--filter",
            "HTTPMediaSourceRangeTests",
        ),
        "audio-retirement-open": _playback_core_test(
            "audioOpenFailureRetiresAudioButVideoStillDelivers"
        ),
        "audio-retirement-prewarm": _playback_core_test(
            "audioPrerollFailureRetiresAudioButVideoStillDelivers"
        ),
        "audio-retirement-playback": _playback_core_test(
            "audioReadFailureRetiresAudioButVideoStillDelivers"
        ),
        "audio-retirement-seek": _playback_core_test(
            "audioSeekOpenFailureRetiresAudioButVideoStillDelivers"
        ),
        "audio-retirement-renderer": _playback_core_test(
            "audioRendererFailureRetiresAudioAndVideoContinues"
        ),
        "regression-core": (
            "python3",
            "-m",
            "unittest",
            "discover",
            "-s",
            "Scripts/rules",
            "-p",
            "test_regression_core_*.py",
        ),
    }
)

STRUCTURED_ASSERTION_CHECKS = frozenset(
    (
        "playback-core-network-resilience",
        "audio-retirement-open",
        "audio-retirement-prewarm",
        "audio-retirement-playback",
        "audio-retirement-seek",
        "audio-retirement-renderer",
    )
)
"""Checks whose artifact must carry one structured ENCHRON_ASSERTION payload.

An exit code and a test name say a process succeeded, not what it observed, so
a Rubric that decides lifecycle, session identity or a post-seek position needs
the payload. These six checks emit exactly one line each and the adapter
refuses the artifact without it.
"""


def _specs() -> tuple[OperationSpec, ...]:
    boolean = ValueKind.BOOLEAN
    integer = ValueKind.INTEGER
    string = ValueKind.STRING
    strings = ValueKind.STRING_LIST
    return (
        OperationSpec(
            "operation:harness.ensure-session@1",
            LANES,
            (
                _field(
                    "controlsAutoHideSeconds",
                    integer,
                    required=False,
                    minimum=1,
                    maximum=300,
                ),
            ),
            (),
        ),
        OperationSpec("operation:app.relaunch@1", LANES, (), ()),
        OperationSpec(
            "operation:evidence.capture-frames@1",
            LANES,
            (
                _field("count", integer, minimum=1, maximum=120),
                _field("relatedResults", strings, required=False),
                _field(
                    "minimumIntervalMillis",
                    integer,
                    minimum=0,
                    maximum=60000,
                ),
                _field("context", string),
                _field(
                    "remoteExpectation",
                    string,
                    required=False,
                    choices=_choices(
                        "webdav-playback-range",
                        "buffer-absorbed-interruption",
                    ),
                ),
                _field("remoteGenerationToken", string, required=False),
                _field("remoteReceiptID", string, required=False),
                _field("restoredGenerationToken", string, required=False),
                _field("productBindingDigest", string, required=False),
                _field(
                    "artworkExpectation",
                    string,
                    required=False,
                    choices=_choices("exit-replaces-current-frame"),
                ),
                _field("artworkKey", string, required=False),
                _field("includeHDRFallback", boolean, required=False),
                _field("relatedFrameManifests", strings, required=False),
            ),
            (("visual.frames", "frame-sequence@2"),),
            _capture_frames,
        ),
        OperationSpec("operation:navigation.select-tab@1", LANES, (_field("tab", string, choices=_choices("files", "settings", "emby", "environment")),), ()),
        OperationSpec(
            "operation:accessibility.activate@2",
            LANES,
            (
                _field("context", string, choices=CONTEXTS),
                _field("identifiers", strings, required=False, nonempty=False),
                _field("labels", strings, required=False, nonempty=False),
                _index(),
                _field("gesture", string, required=False, choices=_choices("tap", "press")),
                _field("durationMillis", integer, required=False, minimum=1, maximum=5000),
                _field("settleDelayMillis", integer, required=False, minimum=1, maximum=30000),
                _field("summonControls", boolean, required=False),
                _field("dismissControls", boolean, required=False),
                _field("labelsAfterIdentifiers", boolean, required=False),
                _field("assertAbsent", strings, required=False),
                _field("alsoInspect", strings, required=False),
                _field("relatedResults", strings, required=False),
            ),
            (("accessibility.tree", "accessibility-tree@1"),),
            _accessibility_activate,
            (
                ArgumentRule(
                    "at-least-one",
                    fields=("identifiers", "labels"),
                ),
            ),
        ),
        OperationSpec(
            "operation:accessibility.inspect@2",
            LANES,
            (
                _field("context", string, choices=CONTEXTS),
                _field("identifier", string),
                _index(),
                _field("requireMatchedElement", boolean, required=False),
                _field(
                    "deadlineSeconds",
                    integer,
                    required=False,
                    minimum=1,
                    maximum=90,
                ),
                _field("summonControls", boolean, required=False),
                _field("relatedResults", strings, required=False),
            ),
            (
                ("accessibility.tree", "accessibility-tree@1"),
                ("emby.evidence", "emby-evidence@1"),
            ),
            _accessibility_single,
        ),
        OperationSpec(
            "operation:diagnostics.browse-hierarchy@1",
            LANES,
            (
                _field(
                    "context",
                    string,
                    choices=_choices("main-window-browser"),
                ),
                _field("sourceLabel", string),
                _field("pathComponents", strings),
                _field("sourceReceipt", string, required=False),
                _field("hostShareName", string, required=False),
                _field("expectedVideoName", string, required=False),
                _field("hostShares", string, required=False),
            ),
            (("accessibility.tree", "accessibility-tree@1"),),
            _browse_hierarchy,
        ),
        OperationSpec(
            "operation:accessibility.type@2",
            LANES,
            (
                _field("context", string, choices=CONTEXTS),
                _field("identifier", string, required=False),
                _field("label", string, required=False),
                _index(),
                _field("mode", string, choices=_choices("append", "replace")),
                _field("text", string, required=False),
                _field("textFile", string, required=False),
                _field("textJSONKey", string, required=False),
                _field("secret", boolean),
            ),
            (),
            _accessibility_type,
            (
                ArgumentRule(
                    "exactly-one-group",
                    groups=(("identifier",), ("label",)),
                ),
                ArgumentRule(
                    "exactly-one-group",
                    groups=(("text",), ("textFile", "textJSONKey")),
                ),
            ),
        ),
        OperationSpec("operation:harness.assert-channels@2", LANES, (), ()),
        OperationSpec("operation:harness.reset-product-state@2", LANES, (_field("rootFolderName", string, required=False),), ()),
        OperationSpec(
            "operation:host.preflight@1",
            LANES,
            (
                _field(
                    "check",
                    string,
                    choices=_choices(
                        "smb-aggregate",
                        "audio-fixtures",
                        "emby-aggregate",
                        "system-import-fixtures",
                        *REMOTE_PREFLIGHT_CHECKS,
                    ),
                ),
                _field(
                    "phase",
                    string,
                    required=False,
                    choices=_choices("ensure", "activate", "restore"),
                ),
                _field(
                    "recipe",
                    string,
                    required=False,
                    choices=_choices(*_remote_preflight.remote.RECIPE_NAMES),
                ),
                _field("receiptID", string, required=False),
            ),
            (),
            _host_preflight,
        ),
        OperationSpec(
            "operation:diagnostics.surface-probe@1",
            LANES,
            (
                _field("cursorToken", string, required=False),
                _field(
                    "settleDelayMillis",
                    integer,
                    required=False,
                    minimum=0,
                    maximum=30000,
                ),
                _field(
                    "remoteExpectation",
                    string,
                    required=False,
                    choices=_choices(*REMOTE_EXPECTATIONS),
                ),
                _field("remoteGenerationToken", string, required=False),
                _field("remoteReceiptID", string, required=False),
                _field("restoredGenerationToken", string, required=False),
                _field("productBindingDigest", string, required=False),
                _field(
                    "containerIndexExpectation",
                    string,
                    required=False,
                    choices=_choices(*CONTAINER_INDEX_EXPECTATIONS),
                ),
                _field("expectedBaselineDigest", string, required=False),
                _field("expectedLocalActiveDigest", string, required=False),
                _field("expectedLocalAfterDigest", string, required=False),
                _field("includeViewingStorage", boolean, required=False),
                _field(
                    "priorViewingStorageDigests",
                    strings,
                    required=False,
                ),
                _field("awaitEmptyStores", strings, required=False),
                _field(
                    "deadlineSeconds",
                    integer,
                    required=False,
                    minimum=1,
                    maximum=90,
                ),
                _field("remoteRequestCursor", string, required=False),
                _field("relatedResults", strings, required=False),
                _field("omitPlaybackState", boolean, required=False),
                _field("embyProgressReadback", boolean, required=False),
            ),
            (
                ("interaction.trace", "interaction-trace@1"),
                ("spatial.input", "spatial-input@1"),
                ("window.control-plane", "window-control-plane@1"),
            ),
            _cursor,
        ),
        OperationSpec("operation:media.stage-fixture@2", LANES, (_field("fixtureID", string), _field("sourceRoot", string)), (), _stage_fixture),
        OperationSpec("operation:media.import-staged@2", LANES, (_field("fileName", string),), (("library.command", "library-command@1"),), _direct_filename),
        OperationSpec(
            "operation:preparation.local-directory-subtitle-source@1",
            LANES,
            (
                _field("directoryName", string),
                _field("mediaFileName", string),
                _field("memberFileNames", strings),
            ),
            (("library.command", "library-command@1"),),
            _directory_subtitle_source,
        ),
        OperationSpec(
            "operation:media.open@2",
            LANES,
            (
                _field("identifier", string),
                _field(
                    "expectedLanding",
                    string,
                    choices=_choices("window", "portal", "either-main-window"),
                ),
                _field(
                    "expectedIssueCategory",
                    string,
                    required=False,
                    choices=_choices("unsupportedVideoCodec"),
                ),
                _deadline(),
                # An open that reopens something is a comparison: the identity it
                # lands on has to be read against the identity that was persisted,
                # and the open's own control plane carries only the first of those.
                _field("relatedResults", strings, required=False),
            ),
            (("window.control-plane", "window-control-plane@1"),),
            _media_open,
        ),
        OperationSpec(
            "operation:issue.present@1",
            LANES,
            (
                _field(
                    "category",
                    string,
                    choices=_choices(*ISSUE_INDUCE_RECIPES),
                ),
                _field(
                    "deadlineSeconds",
                    integer,
                    required=False,
                    minimum=1,
                    maximum=90,
                ),
            ),
            (),
        ),
        OperationSpec(
            "operation:library.snapshot@1",
            LANES,
            tuple(
                _field(name, strings, required=False)
                for name in LIBRARY_BASELINE_FIELDS
            )
            + (
                _field("priorSnapshot", string, required=False),
                _field(
                    "systemImportExpectation",
                    string,
                    required=False,
                    choices=_choices("files", "photos"),
                ),
            ),
            (("library.command", "library-command@1"),),
            _library_snapshot,
            (
                ArgumentRule(
                    "all-or-none",
                    fields=LIBRARY_BASELINE_FIELDS,
                ),
            ),
        ),
        OperationSpec("operation:storage.clear@1", LANES, (_field("target", string, choices=_choices("artwork-cache", "container-index-cache", "playback-progress")),), ()),
        OperationSpec(
            "operation:diagnostics.playback-state@1",
            LANES,
            (
                _field(
                    "expectation",
                    string,
                    required=False,
                    choices=_choices(*PLAYBACK_EXPECTATIONS),
                ),
                _field("expectedSession", string, required=False),
                _field("expectedSourceIdentity", string, required=False),
                _field("expectedContentRevision", string, required=False),
                _field("expectedTopologyDigest", string, required=False),
                _field(
                    "minimumPositionMillis",
                    integer,
                    required=False,
                    minimum=1,
                ),
                _field(
                    "minimumReconnects",
                    integer,
                    required=False,
                    minimum=0,
                    maximum=3,
                ),
                _field("relatedResults", strings, required=False),
            ),
            (
                ("playback.probe", "playback-probe@1"),
            ),
            _playback_state,
            (
                ArgumentRule(
                    "when-equals",
                    discriminator="expectation",
                    cases=(
                        (
                            "webdav-loopback",
                            ("minimumPositionMillis",),
                            (
                                "expectedSession",
                                "expectedSourceIdentity",
                                "expectedContentRevision",
                                "expectedTopologyDigest",
                                "minimumReconnects",
                            ),
                        ),
                        (
                            "recoverable-read",
                            (
                                "expectedSession",
                                "expectedSourceIdentity",
                                "expectedContentRevision",
                                "expectedTopologyDigest",
                                "minimumPositionMillis",
                                "minimumReconnects",
                            ),
                            (),
                        ),
                        (
                            "finite-reconnect",
                            (
                                "expectedSession",
                                "expectedSourceIdentity",
                                "expectedContentRevision",
                                "expectedTopologyDigest",
                                "minimumPositionMillis",
                                "minimumReconnects",
                            ),
                            (),
                        ),
                    ),
                ),
            ),
        ),
        OperationSpec("operation:playback.await-window-state@1", LANES, (_field("presentation", string, choices=_choices("window", "portal", "either-main-window")), _field("lifecycle", string, choices=_choices("playing", "ready", "paused", "ended", "any-steady")), _field("controls", string, choices=_choices("shown", "hidden", "either")), _deadline()), (("window.control-plane", "window-control-plane@1"),)),
        OperationSpec("operation:playback.wait-position@2", LANES, (_field("minimumPositionMillis", integer, minimum=0), _field("minimumRemainingMillis", integer, minimum=0), _field("expectedMediaName", string, required=False), _field("differentSessionFrom", string, required=False), _deadline()), (), _wait_position),
        OperationSpec(
            "operation:playback.seek@2",
            LANES,
            (
                _field("positionMillionths", integer, minimum=0, maximum=1000000),
                _field("summonControls", boolean, required=False),
            ),
            (),
            _playback_seek,
        ),
        OperationSpec(
            "operation:playback.select-subtitle@1",
            LANES,
            (
                _field(
                    "host",
                    string,
                    choices=_choices("playerUI"),
                ),
                _field(
                    "sourceKind",
                    string,
                    choices=_choices(
                        "local-sidecar",
                        "source-directory-sidecar",
                        "emby-external-stream",
                    ),
                ),
                _field("trackLabel", string, required=False),
                _deadline(),
            ),
            (("window.control-plane", "window-control-plane@1"),),
        ),
        OperationSpec(
            "operation:format.apply@2",
            LANES,
            (
                _field("projection", string, choices=_choices("flat", "equirectangular180", "equirectangular360", "customAngle")),
                _field("horizontalCoverageDegrees", integer, required=False, minimum=180, maximum=360),
                _field("stereoLayout", string, choices=_choices("mono", "sideBySide", "topBottom")),
                _field("summonControls", boolean, required=False),
                _deadline(),
            ),
            (
                ("visual.frames", "frame-sequence@2"),
                ("window.control-plane", "window-control-plane@1"),
            ),
            _format_apply,
            (
                ArgumentRule(
                    "when-equals",
                    discriminator="projection",
                    cases=(
                        (
                            "customAngle",
                            ("horizontalCoverageDegrees",),
                            (),
                        ),
                        (
                            "flat",
                            (),
                            ("horizontalCoverageDegrees",),
                        ),
                        (
                            "equirectangular180",
                            (),
                            ("horizontalCoverageDegrees",),
                        ),
                        (
                            "equirectangular360",
                            (),
                            ("horizontalCoverageDegrees",),
                        ),
                    ),
                ),
            ),
        ),
        OperationSpec(
            "operation:presentation.enter-docked-skybox@1",
            LANES,
            (
                _deadline(),
                _field("summonControls", boolean, required=False),
            ),
            (),
            _summon_controls_only_true,
        ),
        OperationSpec(
            "operation:presentation.enter-panorama@1",
            LANES,
            (
                _deadline(),
                _field(
                    "expectedResult",
                    string,
                    required=False,
                    choices=_choices("settled", "rollback-after-settlement-timeout"),
                ),
                _field("summonControls", boolean, required=False),
            ),
            (("transition.trace", "transition-trace@1"),),
            _summon_controls_only_true,
        ),
        OperationSpec("operation:presentation.exit-spatial@1", LANES, (_field("from", string, choices=_choices("docked", "panorama")), _deadline()), (("window.control-plane", "window-control-plane@1"),)),
        OperationSpec(
            "operation:transition-trace.arm@1",
            LANES,
            (
                _field(
                    "fault",
                    string,
                    required=False,
                    choices=_choices("settlement-timeout"),
                ),
            ),
            (),
        ),
        OperationSpec("operation:transition-trace.fetch@1", LANES, (_field("generationToken", string), _field("relatedResults", strings, required=False)), (("transition.trace", "transition-trace@1"),), _unsigned_token),
        OperationSpec(
            "operation:transition-trace.disarm@1",
            LANES,
            (_field("generationToken", string),),
            (("transition.trace", "transition-trace@1"),),
            _unsigned_token,
        ),
        OperationSpec("operation:evidence.capture-audio@2", DEVICE, (_field("durationMillis", integer, minimum=1, maximum=300000), _field("inputDevice", string), _field("wavPath", string), _field("expectedSession", string, required=False), _field("expectedAudioTrackID", string, required=False)), (("audio.measurement", "audio-measurement@2"),), _audio_capture),
        OperationSpec("operation:input.device-hub-prepare@1", SIMULATOR, (), ()),
        OperationSpec(
            "operation:input.device-hub-pinch@2",
            SIMULATOR,
            (
                _field(
                    "targetDomain",
                    string,
                    choices=_choices("canvas", "system-toolbar"),
                ),
                _field("systemControl", string, required=False, choices=_choices("home")),
                _field("shotX", integer, required=False, minimum=0),
                _field("shotY", integer, required=False, minimum=0),
                _field("shotWidth", integer, required=False, minimum=1),
                _field("shotHeight", integer, required=False, minimum=1),
                _field("allowSmall", boolean, required=False),
            ),
            (),
            _device_hub,
            (
                ArgumentRule(
                    "when-equals",
                    discriminator="targetDomain",
                    cases=(
                        (
                            "canvas",
                            ("shotX", "shotY", "shotWidth", "shotHeight"),
                            ("systemControl",),
                        ),
                        (
                            "system-toolbar",
                            ("systemControl",),
                            ("shotX", "shotY", "shotWidth", "shotHeight", "allowSmall"),
                        ),
                    ),
                ),
            ),
        ),
        OperationSpec(
            "operation:evidence.structural-test@1",
            LANES,
            (_field("check", string, choices=_choices(*STRUCTURAL_CHECKS)),),
            (("structural.test", "structural-test@2"),),
            _structural_test,
        ),
    )


SPECS = MappingProxyType({spec.identifier: spec for spec in _specs()})
if len(SPECS) != 35:
    raise RuntimeError(f"expected 35 exact Operation specifications, found {len(SPECS)}")


def resident_handler_name(operation_id: str) -> str:
    return "_" + operation_id.removeprefix("operation:").replace(
        "@", "_"
    ).replace(".", "_").replace("-", "_")


def implementation_digest() -> str:
    return "sha256:" + hashlib.sha256(Path(__file__).read_bytes()).hexdigest()


def catalog_operation_shape(operation_id: str) -> Mapping[str, object]:
    spec = SPECS.get(operation_id)
    if spec is None:
        raise OperationAdapterError(f"Operation is not allowlisted: {operation_id}")
    return MappingProxyType(
        {
            "id": operation_id,
            "argumentFields": [
                {
                    "name": field.name,
                    "type": field.kind.value,
                    "required": field.required,
                }
                for field in spec.fields
            ],
            "argumentRules": [rule.canonical() for rule in spec.argument_rules],
            "lanes": sorted(spec.lanes),
            "evidenceSchemas": [
                {"evidenceType": evidence_type, "evidenceSchema": evidence_schema}
                for evidence_type, evidence_schema in spec.outputs
            ],
            "implementation": {
                "locator": "Scripts/verification/regression_operation_adapter.py",
                "digest": implementation_digest(),
            },
        }
    )


def catalog_operation_shapes() -> tuple[Mapping[str, object], ...]:
    return tuple(catalog_operation_shape(identifier) for identifier in sorted(SPECS))


class RegressionOperationAdapter:
    def __init__(self, backend: OperationBackend) -> None:
        self.backend = backend

    def invoke(
        self,
        operation_id: str,
        arguments: object,
        context: OperationContext,
    ) -> Invocation:
        spec = SPECS.get(operation_id)
        if spec is None:
            raise OperationAdapterError(f"Operation is not allowlisted: {operation_id}")
        validated = spec.validate(context.lane, arguments)
        result = self.backend.execute(operation_id, validated, context)
        if not isinstance(result, Mapping):
            raise OperationAdapterError("Operation backend returned a non-object result")
        return Invocation(operation_id, spec.outputs, MappingProxyType(dict(result)))


class ResidentOperationBackend:
    def execute(
        self,
        operation_id: str,
        arguments: Mapping[str, object],
        context: OperationContext,
    ) -> Mapping[str, object]:
        handler_name = resident_handler_name(operation_id)
        handler = getattr(self, handler_name, None)
        if handler is None:
            raise OperationAdapterError(f"resident backend has no handler for {operation_id}")
        return handler(arguments, context)

    def _harness_instruments(self, context: OperationContext):
        lane = context.lane
        budgets = BudgetProvider()
        developer_dir = self._developer_dir()
        core_device = enchron_target.core_device()
        prefix = [
            sys.executable,
            str(REPOSITORY_ROOT / "Scripts/verification/interactive_visionpro_ui.py"),
            "--device",
            context.target,
            "--output-directory",
            str(context.controller_directory),
        ]
        controller = ControllerClient(lane, command_prefix=prefix, budgets=budgets)
        tools = LocalToolRunner(lane, budgets=budgets)
        policy = RecoveryPolicy()
        return _HarnessInstruments(device=context.target, core_device=core_device, developer_dir=developer_dir, lane=lane, budgets=budgets, controller=controller, tools=tools, policy=policy)

    def _controller(
        self,
        context: OperationContext,
        action: str,
        *arguments: str,
        environment: Mapping[str, str] | None = None,
    ) -> dict[str, object]:
        instruments = self._harness_instruments(context)
        if environment is not None:
            previous = {}
            for key, value in environment.items():
                previous[key] = os.environ.get(key)
                os.environ[key] = value
            try:
                response = _harness_recovered(instruments, "controller:" + action, lambda: instruments.controller.invoke(action, list(arguments)))
            finally:
                for key, value in environment.items():
                    if previous[key] is None:
                        os.environ.pop(key, None)
                    else:
                        os.environ[key] = previous[key]
        else:
            response = _harness_recovered(instruments, "controller:" + action, lambda: instruments.controller.invoke(action, list(arguments)))
        if response.failure is not None:
            document = dict(response.document)
            document["failure"] = {"class": "product", "kind": response.failure.kind, "evidence": response.failure.evidence}
            return document
        return dict(response.document)

    def _app_command(
        self,
        context: OperationContext,
        verb: str,
        *arguments: str,
    ) -> dict[str, object]:
        command: list[str] = ["--verb", verb]
        for argument in arguments:
            command.extend(("--arg", argument))
        return self._controller(context, "app-command", *command)

    def _require_success(self, result: Mapping[str, object], label: str) -> None:
        if result.get("success") is not True and result.get("ok") is not True:
            raise OperationAdapterError(f"{label} failed: {dict(result)}")

    def _issue_action_snapshot(
        self, context: OperationContext, identifier: str
    ) -> dict[str, object]:
        response = self._controller(
            context,
            "snapshot",
            "--identifier",
            identifier,
            "--no-screenshot",
        )
        self._require_success(response, f"issue action {identifier}")
        matched = response.get("matchedElement")
        present = (
            isinstance(matched, Mapping) and matched.get("identifier") == identifier
        )
        return {
            "present": present,
            "identifier": identifier,
            "matchedElement": matched if present else None,
            "response": response,
        }

    def _post_action_state(
        self,
        response: Mapping[str, object],
        *,
        redacted_text: str | None = None,
    ) -> dict[str, object]:
        app_state = response.get("appState")
        hierarchy = response.get("hierarchy")
        if not isinstance(app_state, str) or not app_state:
            raise OperationAdapterError(
                "product interaction omitted its post-action application state"
            )
        if not isinstance(hierarchy, str) or not hierarchy:
            raise OperationAdapterError(
                "product interaction omitted its post-action accessibility hierarchy"
            )

        def redact(value: object) -> object:
            if redacted_text is None:
                return value
            if isinstance(value, str):
                return value.replace(redacted_text, "<redacted>")
            if isinstance(value, Mapping):
                return {str(key): redact(item) for key, item in value.items()}
            if isinstance(value, list):
                return [redact(item) for item in value]
            return value

        sanitized_hierarchy = redact(hierarchy)
        sanitized_matched = redact(response.get("matchedElement"))
        # matchedElement is what the runner addressed, read before it acted, so a
        # tap whose target leaves the hierarchy still names its target
        # (Tests/EnchronAppUI/Interactive/InteractiveDeviceUITests.swift:154-176).
        # elementAfterAction is the same element read again once the action
        # returned, and is null when the action removed it. A criterion about the
        # value a replaceText left behind reads elementAfterAction; a criterion
        # about which element the command acted on reads matchedElement.
        sanitized_after = redact(response.get("elementAfterAction"))
        assert isinstance(sanitized_hierarchy, str)
        return {
            "schema": "enchron.regression.post-action-product-state@1",
            "appState": app_state,
            "hierarchy": sanitized_hierarchy,
            "hierarchyDigest": "sha256:"
            + hashlib.sha256(sanitized_hierarchy.encode("utf-8")).hexdigest(),
            "matchedElement": sanitized_matched,
            "elementAfterAction": sanitized_after,
        }

    def _sanitize_interaction(
        self,
        response: Mapping[str, object],
        redacted_text: str | None,
    ) -> dict[str, object]:
        if redacted_text is None:
            return dict(response)

        def redact(value: object) -> object:
            if isinstance(value, str):
                return value.replace(redacted_text, "<redacted>")
            if isinstance(value, Mapping):
                return {str(key): redact(item) for key, item in value.items()}
            if isinstance(value, list):
                return [redact(item) for item in value]
            return value

        sanitized = redact(response)
        assert isinstance(sanitized, dict)
        return sanitized

    def _require_device_hub_binding(
        self, result: Mapping[str, object], context: OperationContext
    ) -> None:
        binding = result.get("targetBinding")
        if not isinstance(binding, Mapping):
            raise OperationAdapterError("Device Hub result has no target binding")
        device = binding.get("device")
        if not isinstance(device, str) or device.casefold() != context.target.casefold():
            raise OperationAdapterError(
                f"Device Hub target binding {device!r} differs from lease target "
                f"{context.target!r}"
            )

    def _matrix(self, context: OperationContext):
        import playback_mode_matrix as matrix

        return matrix

    def _read_control_plane(
        self,
        context: OperationContext,
        identifier: str = "PlayerUI-window-control-plane",
        *,
        include_screenshot: bool = False,
    ) -> tuple[dict[str, str] | None, dict[str, object]]:
        command = ["snapshot", "--identifier", identifier]
        if not include_screenshot:
            command.append("--no-screenshot")
        try:
            document = self._controller(context, *command)
        except InstrumentFault:
            return None, {}
        matched = document.get("matchedElement")
        value = matched.get("value") if isinstance(matched, dict) else None
        if not isinstance(value, str) or not value:
            return None, document
        return (
            dict(part.split("=", 1) for part in value.split(";") if "=" in part),
            document,
        )

    def _wait_for_window(
        self,
        context: OperationContext,
        *,
        presentation: str,
        lifecycle: str,
        controls: str,
        deadline_seconds: int,
        position_millis: int | None = None,
        remaining_millis: int = 0,
        expected_media_name: str | None = None,
        different_session_from: str | None = None,
        expected_projection: str | None = None,
        expected_horizontal_field_of_view_degrees: int | None = None,
        expected_stereo_layout: str | None = None,
    ) -> dict[str, object]:
        instruments = self._harness_instruments(context)
        observations: list[dict[str, object]] = []
        last_document: dict[str, object] = {}
        plane_holder: dict[str, object] = {}
        def probe():
            plane, doc = self._read_control_plane(context)
            last_document.clear()
            last_document.update(doc)
            if plane is not None:
                elapsed = 0
                observations.append({"elapsedMillis": elapsed, "fields": plane})
                current_presentation = plane.get("presentation")
                current_lifecycle = (plane.get("lifecycle") or "").lower()
                current_controls = plane.get("controls")
                presentation_ok = (
                    presentation == "either-main-window"
                    and current_presentation in ("window", "portal")
                    or current_presentation == presentation
                )
                lifecycle_ok = (
                    lifecycle == "any-steady"
                    and current_lifecycle in ("playing", "ready", "paused", "ended")
                    or current_lifecycle == lifecycle
                )
                controls_ok = controls == "either" or current_controls == controls
                media_name_ok = (
                    expected_media_name is None
                    or plane.get("mediaName") == expected_media_name
                )
                session_ok = (
                    different_session_from is None
                    or plane.get("session") not in (
                        None,
                        "none",
                        different_session_from,
                    )
                )
                format_ok = (
                    expected_projection is None
                    or plane.get("projection") == expected_projection
                ) and (
                    expected_horizontal_field_of_view_degrees is None
                    or plane.get("horizontalFieldOfViewDegrees")
                    == str(expected_horizontal_field_of_view_degrees)
                ) and (
                    expected_stereo_layout is None
                    or plane.get("stereoLayout") == expected_stereo_layout
                )
                position_ok = True
                if position_millis is not None:
                    try:
                        position = float(plane["position"]) * 1000
                        duration = float(plane["duration"]) * 1000
                        position_ok = (
                            position >= position_millis
                            and max(duration - position, 0) >= remaining_millis
                        )
                    except (KeyError, TypeError, ValueError):
                        position_ok = False
                if (
                    presentation_ok
                    and lifecycle_ok
                    and controls_ok
                    and media_name_ok
                    and session_ok
                    and format_ok
                    and position_ok
                    and plane.get("transition") == "none"
                ):
                    plane_holder["plane"] = plane
                    plane_holder["doc"] = doc
                    return {"presentation": presentation, "lifecycle": lifecycle}
            return None
        def observe():
            return list(observations)
        budget = instruments.budgets.budget(instruments.lane, "window-wait") if deadline_seconds <=30 else Budget(seconds=float(deadline_seconds), provenance="window wait " + str(deadline_seconds) + "s")
        try:
            wait_for("window-wait", probe, budget, observe, record=instruments.record_wait_sample)
            plane = plane_holder.get("plane", {})
            doc = plane_holder.get("doc", last_document)
            return {
                "succeeded": True,
                "elapsedMillis": 0,
                "terminal": plane,
                "fields": plane,
                "response": doc,
                "observations": observations,
            }
        except InstrumentFault as fault:
            if fault.kind == "wait-expired":
                return {
                    "succeeded": False,
                    "reason": "deadline-expired",
                    "elapsedMillis": int(budget.seconds * 1000),
                    "observations": observations,
                    "fields": observations[-1]["fields"] if observations else {},
                    "response": last_document,
                    "lastController": last_document,
                }
            raise

    def _wait_for_expected_issue(
        self,
        context: OperationContext,
        *,
        category: str,
        deadline_seconds: int,
    ) -> dict[str, object]:
        instruments = self._harness_instruments(context)
        observations: list[dict[str, object]] = []
        last_control_response: dict[str, object] = {}
        last_alert_response: dict[str, object] = {}
        result_holder: dict[str, object] = {}
        def probe():
            plane, doc = self._read_control_plane(context, "PlayerUI-application-state")
            last_control_response.clear()
            last_control_response.update(doc)
            if plane is not None:
                no_active_session = (
                    plane.get("session") == "none"
                    and plane.get("technicalSession") == "none"
                )
                no_delivered_sample = (
                    plane.get("videoSamples") == "0"
                    and plane.get("rendererInputs") == "0"
                    and plane.get("sampleMediaSubtype") == "none"
                )
                observations.append(
                    {
                        "elapsedMillis": 0,
                        "fields": plane,
                        "noActiveSession": no_active_session,
                        "noDeliveredSample": no_delivered_sample,
                    }
                )
                if (
                    plane.get("error") == category
                    and no_active_session
                    and no_delivered_sample
                ):
                    alert = self._controller(
                        context,
                        "snapshot",
                        "--identifier",
                        "Emby-Playback-Error",
                        "--no-screenshot",
                    )
                    last_alert_response.clear()
                    last_alert_response.update(alert)
                    matched = alert.get("matchedElement")
                    alert_message = (
                        matched.get("label") if isinstance(matched, Mapping) else None
                    )
                    if (
                        isinstance(matched, Mapping)
                        and matched.get("identifier") == "Emby-Playback-Error"
                        and isinstance(alert_message, str)
                        and alert_message
                    ):
                        primary = self._issue_action_snapshot(
                            context, "PlayerUI-loadFailure-primary"
                        )
                        secondary = self._issue_action_snapshot(
                            context, "PlayerUI-loadFailure-secondary"
                        )
                        result_holder.update({
                            "succeeded": True,
                            "expectedCategory": category,
                            "fields": plane,
                            "response": doc,
                            "elapsedMillis": 0,
                            "terminal": plane,
                            "controlPlaneResponse": doc,
                            "alert": alert,
                            "alertMessage": alert_message,
                            "postActionState": self._post_action_state(alert),
                            "noActiveSession": True,
                            "noDeliveredSample": True,
                            "primaryAction": primary,
                            "secondaryAction": secondary,
                            "closeOnly": (
                                primary["present"] is False
                                and secondary["present"] is True
                            ),
                            "observations": list(observations),
                        })
                        return {"category": category}
            return None
        def observe():
            return list(observations)
        budget = Budget(seconds=float(deadline_seconds), provenance="expected issue wait")
        try:
            wait_for("expected-issue", probe, budget, observe, record=instruments.record_wait_sample)
            return dict(result_holder)
        except InstrumentFault as fault:
            if fault.kind == "wait-expired":
                return {
                    "succeeded": False,
                    "reason": "expected-issue-deadline-expired",
                    "expectedCategory": category,
                    "elapsedMillis": int(budget.seconds * 1000),
                    "observations": list(observations),
                    "fields": observations[-1]["fields"] if observations else {},
                    "response": dict(last_control_response),
                    "lastControlPlane": dict(last_control_response),
                    "lastAlert": dict(last_alert_response),
                }
            raise

    def _issue_control_plane(
        self, context: OperationContext
    ) -> tuple[dict[str, str], dict[str, object]]:
        plane, response = self._read_control_plane(context)
        if plane is not None:
            return plane, response
        plane, response = self._read_control_plane(
            context, "PlayerUI-application-state"
        )
        return (plane or {}, response)

    def _snapshot_issue_slot(
        self, context: OperationContext, category: str
    ) -> dict[str, object]:
        snapshot = self._controller(context, "snapshot", "--no-screenshot")
        self._require_success(snapshot, "issue slot snapshot")
        primary = self._issue_action_snapshot(
            context, "PlayerUI-loadFailure-primary"
        )
        secondary = self._issue_action_snapshot(
            context, "PlayerUI-loadFailure-secondary"
        )
        confirm = self._issue_action_snapshot(
            context, "PlayerUI-playbackIssue-confirm"
        )
        hierarchy = snapshot.get("hierarchy")
        title, want_primary, want_secondary, want_confirm = ISSUE_SLOT_POLICY[
            category
        ]
        return {
            "title": title,
            "hierarchy": hierarchy if isinstance(hierarchy, str) else "",
            "primaryAction": primary,
            "secondaryAction": secondary,
            "confirmAction": confirm,
            "actionsMatch": (
                primary["present"] is want_primary
                and secondary["present"] is want_secondary
                and confirm["present"] is want_confirm
            ),
            "titlePresent": isinstance(hierarchy, str) and title in hierarchy,
            "response": snapshot,
        }

    def _wait_for_issue_slot(
        self,
        context: OperationContext,
        *,
        category: str,
        deadline_seconds: int,
    ) -> dict[str, object]:
        instruments = self._harness_instruments(context)
        observations: list[dict[str, object]] = []
        last_response: dict[str, object] = {}
        last_slot: dict[str, object] = {}
        result_holder: dict[str, object] = {}
        def probe():
            plane, doc = self._issue_control_plane(context)
            last_response.clear()
            last_response.update(doc)
            slot = self._snapshot_issue_slot(context, category)
            last_slot.clear()
            last_slot.update(slot)
            observations.append(
                {
                    "elapsedMillis": 0,
                    "error": plane.get("error", "none"),
                    "lifecycle": plane.get("lifecycle"),
                    "titlePresent": slot["titlePresent"],
                    "actionsMatch": slot["actionsMatch"],
                }
            )
            if (
                plane.get("error") == category
                and slot["titlePresent"] is True
                and slot["actionsMatch"] is True
            ):
                result_holder.update({
                    "succeeded": True,
                    "expectedCategory": category,
                    "fields": plane,
                    "elapsedMillis": 0,
                    "slot": dict(slot),
                    "response": dict(doc),
                    "observations": list(observations),
                    "primaryAction": slot["primaryAction"],
                    "secondaryAction": slot["secondaryAction"],
                    "confirmAction": slot["confirmAction"],
                })
                return {"category": category}
            return None
        def observe():
            return list(observations)
        budget = Budget(seconds=float(deadline_seconds), provenance="issue slot wait")
        try:
            wait_for("issue-slot", probe, budget, observe, record=instruments.record_wait_sample)
            return dict(result_holder)
        except InstrumentFault as fault:
            if fault.kind == "wait-expired":
                return {
                    "succeeded": False,
                    "reason": "issue-slot-deadline-expired",
                    "expectedCategory": category,
                    "elapsedMillis": int(budget.seconds * 1000),
                    "observations": list(observations),
                    "fields": observations[-1] if observations else {},
                    "response": dict(last_response),
                    "slot": dict(last_slot),
                }
            raise

    def _probe_lines(self, context: OperationContext) -> list[str]:
        matrix = self._matrix(context)
        lines, error = matrix.copy_probe_lines(
            context.attempt_root,
            target=context.target,
        )
        if lines is None:
            raise OperationAdapterError(
                f"surface probe copy failed: {(error or 'unknown transport error')[-500:]}"
            )
        return lines

    def _developer_dir(self) -> str:
        return enchron_target.developer_directory()

    def _harness_ensure_session_1(self, arguments, context):
        # xcodebuild forwards only TEST_RUNNER_-prefixed names into the runner
        # process, stripping the prefix (docs/UI_TEST_HARNESS_CONSTRAINTS.md:17).
        # The resident runner copies every ENCHRON_ name out of its own process
        # into the app's launch environment, so the bare name stops one hop
        # short and the runner's hardcoded 300 stands.
        environment = (
            {
                "TEST_RUNNER_ENCHRON_CONTROLS_AUTO_HIDE_SECONDS": str(
                    arguments["controlsAutoHideSeconds"]
                )
            }
            if "controlsAutoHideSeconds" in arguments
            else None
        )
        result = self._controller(
            context,
            "ensure-session",
            "--destination-id",
            context.target,
            "--developer-dir",
            self._developer_dir(),
            **{"timeout": 420, "environment": environment},
        )
        self._require_success(result, "ensure-session")
        return {
            "succeeded": True,
            "session": result,
            "controlsAutoHideSeconds": arguments.get(
                "controlsAutoHideSeconds", 300
            ),
        }

    def _app_relaunch_1(self, arguments, context):
        result = self._controller(context, "relaunch")
        self._require_success(result, "app relaunch")
        return {"succeeded": True, "response": result}

    def _evidence_capture_frames_1(self, arguments, context):
        requested_artwork_key = arguments.get("artworkKey")
        artwork_before = (
            self._artwork_probe(
                context,
                None if requested_artwork_key is None else str(requested_artwork_key),
            )
            if arguments.get("artworkExpectation") is not None
            else None
        )

        def capture_state(identifier: str, *, include_screenshot: bool):
            command = ["snapshot", "--identifier", identifier]
            if not include_screenshot:
                command.append("--no-screenshot")
            response = self._controller(context, *command)
            self._require_success(response, identifier)
            matched = response.get("matchedElement")
            state = None
            if isinstance(matched, Mapping):
                state = next(
                    (
                        matched.get(field)
                        for field in ("value", "label")
                        if isinstance(matched.get(field), str)
                        and matched.get(field)
                    ),
                    None,
                )
            fields = (
                {
                    key: value
                    for part in state.split(";")
                    if "=" in part
                    for key, value in (part.split("=", 1),)
                }
                if state is not None
                else {}
            )
            return {
                "available": state is not None,
                "fields": fields,
                "response": response,
            }

        frames: list[dict[str, object]] = []
        interval = int(arguments["minimumIntervalMillis"]) / 1000
        next_capture = getattr(time, "monotonic")()
        for index in range(int(arguments["count"])):
            remaining = next_capture - getattr(time, "monotonic")()
            if remaining > 0:
                _hold_via_wait(context.lane, BudgetProvider(), "frame-pace", remaining)
            captured = getattr(time, "monotonic")()
            playback_state = capture_state(
                "PlayerUI-playback-state",
                include_screenshot=True,
            )
            control_plane = (
                {"available": False, "fields": {}, "response": {}}
                if arguments["context"] in ("panorama", "docked")
                else capture_state(
                    "PlayerUI-window-control-plane",
                    include_screenshot=False,
                )
            )
            observed_presentation = playback_state["fields"].get(
                "presentation"
            ) or control_plane["fields"].get("presentation")
            frames.append(
                {
                    "index": index,
                    "capturedAtMonotonicMillis": round(captured * 1000),
                    "screenshotDigest": _screenshot_digest(
                        playback_state["response"]
                    ),
                    "record": playback_state["response"],
                    "playbackState": playback_state,
                    "controlPlane": control_plane,
                    "presentationObservation": {
                        "expected": arguments["context"],
                        "observed": observed_presentation,
                    },
                }
            )
            next_capture = captured + interval
        remote_observation = (
            self._remote_observation(arguments)
            if "remoteExpectation" in arguments
            else None
        )
        artwork_after = (
            self._artwork_probe(
                context,
                str(artwork_before["artworkKey"]),
            )
            if artwork_before is not None
            else None
        )
        hdr_fallback = (
            capture_state(
                "PlayerUI-VideoFormat-HDRFallback",
                include_screenshot=False,
            )
            if arguments.get("includeHDRFallback") is True
            else None
        )
        current_manifest = {
            "context": arguments["context"],
            "frames": frames,
        }
        prior_sequences: list[dict[str, object]] = []
        for encoded in arguments.get("relatedFrameManifests", []):
            manifest = json.loads(str(encoded))
            manifest_frames = manifest["frames"]
            if not isinstance(manifest["context"], str) or not isinstance(
                manifest_frames, list
            ):
                raise OperationAdapterError(
                    "related frame manifest contains invalid capture data"
                )
            prior_sequences.append(
                {
                    "context": manifest["context"],
                    "frames": manifest_frames,
                }
            )
        frame_sequences = [
            *prior_sequences,
            current_manifest,
        ]
        evidence_frames = [
            frame
            for sequence in frame_sequences
            for frame in sequence["frames"]
        ]
        return {
            "succeeded": True,
            "context": arguments["context"],
            "artifactRoot": str(context.controller_directory),
            "frames": evidence_frames,
            "frameSequences": frame_sequences,
            "frameManifest": json.dumps(
                current_manifest,
                ensure_ascii=False,
                sort_keys=True,
                separators=(",", ":"),
            ),
            "fields": frames[-1]["playbackState"]["fields"],
            "response": frames[-1]["playbackState"]["response"],
            **({"hdrFallback": hdr_fallback} if hdr_fallback is not None else {}),
            "remoteObservation": remote_observation,
            "artworkObservation": (
                {
                    "schema": "enchron.regression.artwork-read-only-observation@1",
                    "expectation": arguments["artworkExpectation"],
                    "readOnly": True,
                    "before": artwork_before,
                    "after": artwork_after,
                }
                if artwork_before is not None
                else None
            ),
            **(
                {}
                if artwork_after is None
                else {
                    # One result:// reference per value, so a later capture can
                    # inline this capture's artwork reading into its own
                    # artifact instead of asking an Oracle to open two.
                    "artworkKey": str(artwork_after["artworkKey"]),
                    "artworkCurrentDigest": str(artwork_after["currentDigest"]),
                    "artworkStoredDigest": str(artwork_after["storedDigest"]),
                    "artworkStoredBytes": str(artwork_after["storedBytes"]),
                    "artworkByteStreamScope": str(
                        artwork_after["byteStreamScope"]
                    ),
                    "artworkByteStreamRequestCount": str(
                        artwork_after["byteStreamRequestCount"]
                    ),
                }
            ),
            "relatedResults": list(arguments.get("relatedResults", [])),
        }

    def _artwork_probe(
        self,
        context: OperationContext,
        artwork_key: str | None = None,
    ) -> dict[str, str]:
        response = self._app_command(
            context,
            "artworkProbe",
            *((f"key={artwork_key}",) if artwork_key is not None else ()),
        )
        self._require_success(response, "artworkProbe")
        pairs = self._response_payload_pairs(response)
        expected = {
            "schema",
            "artworkKey",
            "currentDigest",
            "storedDigest",
            "currentWidth",
            "currentHeight",
            "storedBytes",
            "byteStreamScope",
            "byteStreamRequestCount",
        }
        if set(pairs) != expected or pairs["schema"] != "enchron.regression.artwork-probe@1":
            raise OperationAdapterError("artworkProbe returned the wrong closed payload")
        if re.fullmatch(r"media-[0-9a-f]{64}", pairs["artworkKey"]) is None:
            raise OperationAdapterError("artworkProbe returned an invalid artwork key")
        for field in ("currentDigest", "storedDigest"):
            if pairs[field] != "none":
                _sha256(pairs[field], f"artworkProbe.{field}")
        for field in ("currentWidth", "currentHeight", "storedBytes"):
            try:
                value = int(pairs[field])
            except ValueError as error:
                raise OperationAdapterError(
                    f"artworkProbe.{field} must be an integer"
                ) from error
            if value < 0:
                raise OperationAdapterError(
                    f"artworkProbe.{field} must be non-negative"
                )
        return pairs

    def _navigation_select_tab_1(self, arguments, context):
        identifiers = {
            "files": "Navigation-Ornament-tab-files",
            "settings": "Navigation-Ornament-tab-settings",
            "emby": "Emby-Navigation-Tab",
            "environment": "Navigation-Ornament-tab-environment",
        }
        destinations = {
            "files": "FileBrowsing-FilesScreen",
            "settings": "Settings-SettingsScreen",
            "emby": "Emby-Root",
            "environment": "EnvironmentCard-card",
        }
        tab = str(arguments["tab"])
        result = self._controller(
            context, "tap", "--identifier", identifiers[tab]
        )
        self._require_success(result, "tab selection")
        post_action = self._post_action_state(result)
        destination = destinations[tab]
        destination_visible = destination in str(post_action["hierarchy"])
        if not destination_visible:
            raise OperationAdapterError(
                f"tab selection did not expose destination {destination}"
            )
        post_action.update(
            {
                "destinationIdentifier": destination,
                "destinationVisible": True,
            }
        )
        return {
            "succeeded": True,
            "interaction": result,
            "response": result,
            "postActionState": post_action,
        }

    def _accessibility_activate_2(self, arguments, context):
        identifiers = [str(item) for item in arguments.get("identifiers", [])]
        labels = [str(item) for item in arguments.get("labels", [])]
        also_inspect = [str(item) for item in arguments.get("alsoInspect", [])]
        if not identifiers and not labels:
            raise OperationAdapterError(
                "accessibility activate requires at least one identifier or label"
            )
        # A nested menu leaf that only carries a label has to be tapped inside
        # the transaction that opened its submenu; the runner taps `--label`
        # ahead of the identifiers, so the ordered route needs its own step.
        labels_after_identifiers = (
            arguments.get("labelsAfterIdentifiers") is True
        )
        if labels_after_identifiers:
            if not identifiers or len(labels) != 1:
                raise OperationAdapterError(
                    "labelsAfterIdentifiers requires identifiers and one label"
                )
            if str(arguments.get("gesture", "tap")) != "tap":
                raise OperationAdapterError(
                    "labelsAfterIdentifiers requires the tap gesture"
                )
        settle_delay_millis = int(arguments.get("settleDelayMillis", 0))
        result: dict[str, object] = {
            "succeeded": True,
            "context": arguments["context"],
            "response": {},
            "tappedIdentifiers": list(identifiers),
        }

        def mark_click() -> None:
            if "activatedAtMonotonicMillis" not in result:
                result["activatedAtMonotonicMillis"] = round(
                    getattr(time, "monotonic")() * 1000
                )

        if arguments.get("summonControls") is True:
            summon = self._app_command(context, "toggleControls", "visible=true")
            self._require_success(summon, "controls summon")
            result["summon"] = summon
        # A route whose own first step is the PlayerUI-window-playback-surface
        # tap needs the chrome down before it runs, because that tap is a bare
        # showControls.toggle() (PlaybackSessionModel.swift:579-589): with the
        # chrome already up it hides the deck instead of raising it, and the
        # deck's actions leave the hierarchy with it (MainView.swift:222-234).
        # toggleControls is idempotent (TestCommandChannel.swift:1070-1074), so
        # this establishes the precondition without assuming what the previous
        # call left behind.
        if arguments.get("dismissControls") is True:
            dismissal = self._app_command(
                context, "toggleControls", "visible=false"
            )
            self._require_success(dismissal, "controls dismissal")
            result["dismiss"] = dismissal
        if settle_delay_millis > 0:
            before_response = self._controller(
                context, "snapshot", "--no-screenshot"
            )
            self._require_success(
                before_response, "accessibility pre-action snapshot"
            )
            result["beforeState"] = self._post_action_state(before_response)
        if also_inspect:
            command = ["--identifiers", *identifiers] if identifiers else []
            if labels:
                command.extend(
                    (
                        "--trailing-label"
                        if labels_after_identifiers
                        else "--label",
                        labels[0],
                    )
                )
            command.extend(("--also-inspect", *also_inspect))
            absent = [str(item) for item in arguments.get("assertAbsent", [])]
            if absent:
                command.extend(("--assert-absent", *absent))
            mark_click()
            identifier_response = self._controller(
                context, "tapSequence", *command
            )
            self._require_success(identifier_response, "accessibility activate")
            identifier_state = self._post_action_state(identifier_response)
            # Own fields: a later label tap overwrites response/interaction/
            # postActionState, so the identifier observation needs a key no
            # other sub-action can claim.
            result["identifierResponse"] = identifier_response
            result["identifierPostActionState"] = identifier_state
            result["response"] = identifier_response
            result["interaction"] = identifier_response
            result["postActionState"] = identifier_state
            inspected = identifier_response.get("alsoInspected")
            if not isinstance(inspected, list):
                raise OperationAdapterError(
                    "alsoInspect requires runner alsoInspected observations"
                )
            result["alsoInspected"] = json.dumps(
                inspected,
                ensure_ascii=False,
                sort_keys=True,
                separators=(",", ":"),
            )
            if absent:
                observations = identifier_response.get("assertAbsentObservations")
                if not isinstance(observations, list):
                    raise OperationAdapterError(
                        "assertAbsent requires runner assertAbsentObservations"
                    )
                result["assertAbsentObservations"] = json.dumps(
                    observations,
                    ensure_ascii=False,
                    sort_keys=True,
                    separators=(",", ":"),
                )
        elif identifiers:
            single = len(identifiers) == 1 and not labels_after_identifiers
            command = (
                ["--identifier", identifiers[0]]
                if single
                else ["--identifiers", *identifiers]
            )
            if single and "index" in arguments:
                command.extend(("--index", str(arguments["index"])))
            if labels_after_identifiers:
                command.extend(("--trailing-label", labels[0]))
            gesture = str(arguments.get("gesture", "tap"))
            action = (
                "press"
                if gesture == "press"
                else "tap" if single else "tapSequence"
            )
            if gesture == "press":
                command.extend(
                    (
                        "--duration",
                        f"{int(arguments.get('durationMillis', 1000)) / 1000:.3f}",
                    )
                )
            absent = [str(item) for item in arguments.get("assertAbsent", [])]
            if absent:
                command.extend(("--assert-absent", *absent))
            mark_click()
            identifier_response = self._controller(context, action, *command)
            self._require_success(identifier_response, "accessibility activate")
            identifier_state = self._post_action_state(identifier_response)
            result["identifierResponse"] = identifier_response
            result["identifierPostActionState"] = identifier_state
            result["response"] = identifier_response
            result["interaction"] = identifier_response
            result["postActionState"] = identifier_state
            if absent:
                observations = identifier_response.get("assertAbsentObservations")
                if not isinstance(observations, list):
                    raise OperationAdapterError(
                        "assertAbsent requires runner assertAbsentObservations"
                    )
                # Canonical JSON so capture-frames relatedResults (string-list)
                # still validates after grant resolution thaws this field.
                result["assertAbsentObservations"] = json.dumps(
                    observations,
                    ensure_ascii=False,
                    sort_keys=True,
                    separators=(",", ":"),
                )
        if not also_inspect and not labels_after_identifiers:
            label_responses: list[Mapping[str, object]] = []
            label_states: list[Mapping[str, object]] = []
            for label in labels:
                mark_click()
                response = self._controller(context, "tap", "--label", label)
                self._require_success(response, f"accessibility label {label}")
                label_responses.append(response)
                label_states.append(self._post_action_state(response))
            if label_responses:
                result["labelResponses"] = label_responses
                result["labelPostActionStates"] = label_states
                result["interaction"] = label_responses[-1]
                result["response"] = label_responses[-1]
                result["postActionState"] = label_states[-1]
        if settle_delay_millis > 0:
            getattr(time, "sleep")(settle_delay_millis / 1000)
            settled_response = self._controller(
                context, "snapshot", "--no-screenshot"
            )
            self._require_success(
                settled_response, "accessibility post-action snapshot"
            )
            result["settledState"] = self._post_action_state(settled_response)
            result["postActionState"] = result["settledState"]
        if "activatedAtMonotonicMillis" not in result:
            raise OperationAdapterError(
                "accessibility activate did not record a click time"
            )
        result["relatedResults"] = list(arguments.get("relatedResults", []))
        return result

    def _accessibility_inspect_2(self, arguments, context):
        command = ["--identifier", str(arguments["identifier"]), "--index", str(arguments.get("index", 0))]
        summon: dict[str, object] | None = None
        if arguments.get("summonControls") is True:
            # The immersive controls attachment entity is disabled while the
            # deck is hidden, so its probes leave the hierarchy with it. This
            # is the same summon presentation.exit-spatial performs before it
            # reads PlayerUI-spatial-state.
            summon = self._app_command(context, "toggleControls", "visible=true")
            self._require_success(summon, "controls summon")
        deadline = getattr(time, "monotonic")() + int(arguments.get("deadlineSeconds", 0))
        observations: list[dict[str, object]] = []
        while True:
            result = self._controller(context, "snapshot", *command)
            self._require_success(result, "accessibility inspect")
            matched = result.get("matchedElement")
            matched_element = matched if isinstance(matched, Mapping) else None
            observations.append(
                {"matched": matched_element is not None, "response": result}
            )
            if matched_element is not None or getattr(time, "monotonic")() >= deadline:
                break
            getattr(time, "sleep")(0.25)
        required = arguments.get("requireMatchedElement") is True
        return {
            "succeeded": not required or matched_element is not None,
            "context": arguments["context"],
            "requestedIdentifier": arguments["identifier"],
            "matchedElement": matched_element,
            "response": result,
            "observations": observations,
            **({"summon": summon} if summon is not None else {}),
            "relatedResults": list(arguments.get("relatedResults", [])),
        }

    def _diagnostics_browse_hierarchy_1(self, arguments, context):
        requested_components = [str(item) for item in arguments["pathComponents"]]
        source_selection = self._controller(
            context, "tap", "--label", str(arguments["sourceLabel"])
        )
        self._require_success(source_selection, "browse hierarchy source selection")

        def capture_stage(index: int, path: list[str]) -> dict[str, object]:
            response = self._controller(context, "snapshot")
            self._require_success(response, "browse hierarchy snapshot")
            hierarchy = response.get("hierarchy")
            if not isinstance(hierarchy, str) or not hierarchy:
                raise OperationAdapterError(
                    "browse hierarchy snapshot omitted its complete hierarchy"
                )
            identifiers = re.findall(r"identifier: '([^']+)'", hierarchy)
            visible_cards: list[dict[str, str]] = []
            seen_cards: set[str] = set()
            for identifier in identifiers:
                match = re.fullmatch(
                    r"FileBrowsing-grid-(folder|video)-(.+)", identifier
                )
                if match is None or identifier in seen_cards:
                    continue
                seen_cards.add(identifier)
                visible_cards.append(
                    {
                        "identifier": identifier,
                        "kind": match.group(1),
                        "name": match.group(2),
                    }
                )
            item_count_text = None
            item_count = None
            item_count_visible = False
            for line in hierarchy.splitlines():
                if "identifier: 'FileBrowsing-FilesScreen-itemCount'" not in line:
                    continue
                item_count_visible = True
                text_match = re.search(r"(?:label|value): '([^']*)'", line)
                if text_match is not None:
                    item_count_text = text_match.group(1)
                    count_match = re.fullmatch(r"([0-9]+) items?", item_count_text)
                    if count_match is not None:
                        item_count = int(count_match.group(1))
                break
            return {
                "index": index,
                "pathComponents": list(path),
                "snapshot": response,
                "hierarchy": hierarchy,
                "facts": {
                    "itemCountIdentifierVisible": item_count_visible,
                    "itemCountText": item_count_text,
                    "itemCount": item_count,
                    "visibleCardCount": len(visible_cards),
                    "visibleCards": visible_cards,
                },
            }

        stages = [capture_stage(0, [])]
        visited: list[str] = []
        for index, component in enumerate(requested_components, start=1):
            selection = self._controller(
                context,
                "tap",
                "--identifier",
                f"FileBrowsing-grid-folder-{component}",
            )
            self._require_success(selection, f"browse hierarchy component {component}")
            visited.append(component)
            stages.append(capture_stage(index, visited))

        return {
            "succeeded": True,
            "context": arguments["context"],
            "sourceLabel": arguments["sourceLabel"],
            "requestedPathComponents": requested_components,
            "observationMode": "navigated-requested-hierarchy",
            "stages": stages,
            "sourceReceipt": arguments.get("sourceReceipt"),
            "hostShareName": arguments.get("hostShareName"),
            "expectedVideoName": arguments.get("expectedVideoName"),
            "hostShares": arguments.get("hostShares"),
            "sourceSelectionResponse": source_selection,
            "response": stages[-1]["snapshot"],
        }

    def _accessibility_type_2(self, arguments, context):
        index = str(arguments.get("index", 0))
        command = (
            ["--identifier", str(arguments["identifier"]), "--index", index]
            if "identifier" in arguments
            else ["--index", index, "--label", str(arguments["label"])]
        )
        typed_text: str
        if "text" in arguments:
            typed_text = str(arguments["text"])
            command.extend(("--text", typed_text))
        else:
            text_file = Path(str(arguments.get("textFile", "")))
            try:
                information = text_file.lstat()
                document = json.loads(text_file.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError) as error:
                raise OperationAdapterError("credential reference is unreadable") from error
            if (
                not stat.S_ISREG(information.st_mode)
                or information.st_uid != os.getuid()
                or stat.S_IMODE(information.st_mode) != 0o600
            ):
                raise OperationAdapterError(
                    "credential reference must be an owner-only 0600 regular file"
                )
            key = str(arguments.get("textJSONKey", ""))
            if (
                not isinstance(document, dict)
                or not isinstance(document.get(key), str)
                or not document[key]
            ):
                raise OperationAdapterError(
                    "credential reference JSON key must select one nonempty string"
                )
            typed_text = document[key]
            command.extend(
                (
                    "--text-file",
                    str(text_file),
                    "--text-json-key",
                    key,
                )
            )
        if arguments["secret"] is True:
            command.append("--redact-response-text")
        action = "typeText" if arguments["mode"] == "append" else "replaceText"
        result = self._controller(context, action, *command)
        self._require_success(result, "accessibility type")
        redacted_text = typed_text if arguments["secret"] is True else None
        interaction = self._sanitize_interaction(result, redacted_text)
        return {
            "succeeded": True,
            "context": arguments["context"],
            "interaction": interaction,
            "response": interaction,
            "postActionState": self._post_action_state(
                result,
                redacted_text=redacted_text,
            ),
        }

    def _harness_assert_channels_2(self, arguments, context):
        ping = self._app_command(context, "ping")
        status = self._app_command(context, "probeStatus")
        self._require_success(ping, "ping")
        self._require_success(status, "probeStatus")
        return {"succeeded": True, "ping": ping, "probeStatus": status}

    def _harness_reset_product_state_2(self, arguments, context):
        command = () if "rootFolderName" not in arguments else (f"libraryFolder={arguments['rootFolderName']}",)
        reset = self._app_command(context, "resetState", *command)
        self._require_success(reset, "resetState")
        relaunch = self._controller(context, "relaunch")
        self._require_success(relaunch, "reset relaunch")
        library = self._app_command(context, "listLibrary")
        self._require_success(library, "listLibrary")
        receipt = validate_product_state_reset_receipt(
            reset.get("productStateResetReceipt")
        )
        snapshot = validate_library_snapshot(library.get("librarySnapshot"))
        expected_folder_names = (
            [] if "rootFolderName" not in arguments else [str(arguments["rootFolderName"])]
        )
        observed_folder_names = [str(item["name"]) for item in snapshot["folders"]]
        if snapshot["references"] or observed_folder_names != expected_folder_names:
            raise OperationAdapterError(
                "resetState did not establish the requested empty library root"
            )
        if (
            receipt["remainingReferenceCount"] != 0
            or receipt["remainingFolderCount"] != len(expected_folder_names)
            or receipt["createdFolderNames"] != expected_folder_names
        ):
            raise OperationAdapterError(
                "product reset receipt differs from the observed library root"
            )
        return {
            "succeeded": True,
            "relaunch": relaunch,
            "resetReceipt": dict(receipt),
            "librarySnapshot": dict(snapshot),
        }

    def _remote_preflight_configuration(self):
        return _remote_preflight.PreflightConfiguration(
            service=_remote_preflight.remote.ServiceConfiguration(
                runtime_root=REMOTE_RUNTIME_FILE.parent,
                registry_path=_remote_preflight.remote.DEFAULT_REGISTRY,
                source_root=_remote_preflight.remote.DEFAULT_SOURCE_ROOT,
                bind_host=_literal_lan_address(),
                port=8443,
            )
        )

    def _remote_observation(
        self,
        arguments: Mapping[str, object],
    ) -> dict[str, object]:
        expectation = str(arguments["remoteExpectation"])
        product_binding_digest: str | None = None
        certificate_address: str | None = None
        if expectation in REMOTE_PLAYBACK_EXPECTATIONS:
            product_binding_digest = _sha256(
                arguments.get("productBindingDigest"),
                "productBindingDigest",
            )
        configuration = self._remote_preflight_configuration()
        controller = _remote_preflight.remote.RemoteSourceController(
            configuration.service
        )
        receipt: Mapping[str, object] | None = None
        if expectation in REMOTE_HEALTHY_EXPECTATIONS:
            generation_token = str(arguments["remoteGenerationToken"])
            if generation_token.startswith("result://"):
                raise OperationAdapterError(
                    "result references must be resolved before backend invocation"
                )
            if re.fullmatch(r"[1-9][0-9]*", generation_token) is None:
                raise OperationAdapterError(
                    "remoteGenerationToken must be canonical positive decimal"
                )
            identity = controller.status()
            generation = int(generation_token)
            if (
                identity.get("generation") != generation
                or identity.get("recipe") != "healthy"
            ):
                raise OperationAdapterError(
                    "healthy remote observation generation drifted"
                )
            recipe = "healthy"
            log_path = Path(str(identity.get("requestLogPath", "")))
            restored_generation = generation
            endpoint_digest = identity.get("endpointDigest")
            certificate_fingerprint = identity.get("certificateFingerprint")
            prior_certificate_fingerprint = certificate_fingerprint
        else:
            receipt_id = str(arguments["remoteReceiptID"])
            restored_token = str(arguments["restoredGenerationToken"])
            if receipt_id.startswith("result://") or restored_token.startswith(
                "result://"
            ):
                raise OperationAdapterError(
                    "result references must be resolved before backend invocation"
                )
            if re.fullmatch(r"[1-9][0-9]*", restored_token) is None:
                raise OperationAdapterError(
                    "restoredGenerationToken must be canonical positive decimal"
                )
            receipt = controller.receipt(receipt_id)
            expected_recipe = {
                "recoverable-read": "recoverable-read-interruption",
                "finite-backoff": "finite-reconnect",
                "certificate-change": "certificate-rotation",
                "buffer-absorbed-interruption": "buffer-absorbed-interruption",
            }[expectation]
            if (
                receipt.get("recipe") != expected_recipe
                or receipt.get("restoredStateDigest") is None
            ):
                raise OperationAdapterError(
                    f"{expectation} is not bound to its restored activation receipt"
                )
            identity = controller.status()
            restored_generation = int(restored_token)
            if (
                identity.get("recipe") != "healthy"
                or identity.get("generation") != restored_generation
            ):
                raise OperationAdapterError(
                    "fault observation is not followed by its healthy restore generation"
                )
            generation = int(receipt["generation"])
            recipe = str(receipt["recipe"])
            log_path = Path(str(receipt["logPath"]))
            endpoint_digest = receipt.get("endpointDigest")
            certificate_fingerprint = receipt.get("certificateFingerprint")
            prior_certificate_fingerprint = receipt.get(
                "priorCertificateFingerprint"
            )
            if expectation == "certificate-change":
                endpoint = urlsplit(str(identity.get("address", "")))
                if endpoint.hostname is None or endpoint.port is None:
                    raise OperationAdapterError(
                        "certificate change remote identity omitted its address"
                    )
                certificate_address = f"{endpoint.hostname}:{endpoint.port}"

        if not log_path.is_absolute() or not log_path.is_file():
            raise OperationAdapterError("remote observation request log is unavailable")
        digest = "sha256:" + hashlib.sha256(log_path.read_bytes()).hexdigest()
        if receipt is not None and receipt.get("logDigest") != digest:
            raise OperationAdapterError("remote observation request log digest drifted")
        try:
            entries = [
                json.loads(line)
                for line in log_path.read_text(encoding="utf-8").splitlines()
                if line
            ]
        except json.JSONDecodeError as error:
            raise OperationAdapterError(
                "remote observation request log is malformed"
            ) from error
        if any(not isinstance(item, dict) for item in entries):
            raise OperationAdapterError(
                "remote observation request log has a non-object row"
            )
        # certificate-change asserts that the product refuses the rotated
        # certificate and stops, so it never completes a TLS handshake against
        # the activation generation and the host logs nothing for it. An empty
        # log is that behavior, not a lost observation: the receipt still binds
        # logPath and logDigest, and the digest of an empty file is checked
        # above like any other. Every other expectation is decided from rows the
        # product produced, so emptiness there stays an error.
        if not entries and expectation != "certificate-change":
            raise OperationAdapterError("remote observation request log is empty")
        _reject_secret_result(entries, "remoteRequestLog")
        if any(
            item.get("schema")
            != "enchron.regression.remote-source-request@1"
            or item.get("generation") != generation
            or item.get("recipe") != recipe
            for item in entries
        ):
            raise OperationAdapterError(
                "remote observation request log is not generation bound"
            )
        sequences = [item.get("sequence") for item in entries]
        if sequences != list(range(1, len(entries) + 1)):
            raise OperationAdapterError(
                "remote observation request sequence is not contiguous"
            )
        prior_request_cursor = arguments.get("remoteRequestCursor")
        if prior_request_cursor is None:
            prior_request_sequence = 0
        else:
            if str(prior_request_cursor).startswith("result://"):
                raise OperationAdapterError(
                    "result references must be resolved before backend invocation"
                )
            prior_request_sequence = int(str(prior_request_cursor))
            if prior_request_sequence > len(entries):
                raise OperationAdapterError(
                    "remoteRequestCursor exceeds the current request log"
                )
        entries_since_cursor = entries[prior_request_sequence:]

        range_entries = [
            item
            for item in entries
            if item.get("method") == "GET"
            and isinstance(item.get("range"), str)
            and item.get("range") != "<invalid>"
        ]
        # This guard exists so a new expectation cannot reach the observation
        # without anyone noticing, and it has to name the registry to do that.
        # Hand-listing the members let certificate-change fall out of the list
        # it was supposed to be measured against, and every certificate-change
        # observation raised here rather than publishing.
        if expectation not in REMOTE_EXPECTATIONS:
            raise AssertionError("remote expectation registry drifted")

        successful_propfinds = [
            item
            for item in entries
            if item.get("method") == "PROPFIND" and item.get("status") == 207
        ]
        successful_ranges = [
            item
            for item in range_entries
            if item.get("status") == 206
            and isinstance(item.get("responseBytes"), int)
            and item["responseBytes"] > 0
        ]
        triggered = [
            item for item in range_entries if item.get("triggered") is True
        ]
        triggered_ranges = {item.get("range") for item in triggered}
        recovered = [
            item
            for item in range_entries
            if item.get("triggered") is False
            and item.get("status") == 206
            and item.get("range") in triggered_ranges
        ]
        expected_backoffs = list(_remote_preflight.remote.RECONNECT_BACKOFF_MILLIS)

        trace_lines = [
            "remoteRequest "
            + json.dumps(item, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
            for item in entries
        ]
        trace_lines.append(
            "remoteBinding "
            + json.dumps(
                {
                    "expectation": expectation,
                    "recipe": recipe,
                    "generation": generation,
                    "restoredGeneration": restored_generation,
                    "endpointDigest": endpoint_digest,
                    "requestLogDigest": digest,
                    "productBindingDigest": product_binding_digest,
                    "priorCertificateFingerprint": prior_certificate_fingerprint,
                    "certificateFingerprint": certificate_fingerprint,
                },
                ensure_ascii=False,
                sort_keys=True,
                separators=(",", ":"),
            )
        )
        clocks = [item.get("monotonicMillis") for item in range_entries]
        observed_intervals = (
            [
                int(clocks[index + 1]) - int(clocks[index])
                for index in range(len(clocks) - 1)
            ]
            if len(clocks) > 1 and all(type(value) is int for value in clocks)
            else []
        )
        # observedRequestIntervalsMillis walks every ranged read in the log, so
        # it mixes ordinary sequential reads with the reconnect gaps and names
        # no comparison. The client's own backoff is the wait between the read
        # the recipe refused and the next thing it asked for, so pair each
        # refusal with its declared backoff and the delay the host measured.
        reconnect_attempts: list[dict[str, object]] = []
        for item in triggered:
            declared = item.get("expectedBackoffMillis")
            refused_at = item.get("monotonicMillis")
            if type(declared) is not int or type(refused_at) is not int:
                continue
            following = [
                entry
                for entry in entries
                if type(entry.get("monotonicMillis")) is int
                and int(entry["monotonicMillis"]) > refused_at
            ]
            observed_delay = (
                min(int(entry["monotonicMillis"]) for entry in following)
                - refused_at
                if following
                else None
            )
            reconnect_attempts.append(
                {
                    "ordinal": item.get("recipeReadOrdinal"),
                    "declaredBackoffMillis": declared,
                    "observedDelayMillis": observed_delay,
                    "range": item.get("range"),
                    "recovered": any(
                        entry.get("range") == item.get("range")
                        for entry in recovered
                    ),
                }
            )
        return {
            "expectation": expectation,
            "recipe": recipe,
            "generation": generation,
            "restoredGeneration": restored_generation,
            "endpointDigest": endpoint_digest,
            "requestLogPath": str(log_path),
            "requestLogDigest": digest,
            "productBindingDigest": product_binding_digest,
            "requestEntries": entries,
            "priorRequestCursor": str(prior_request_sequence),
            "requestCursor": str(len(entries)),
            "requestEntriesSinceCursor": entries_since_cursor,
            "rangeRequests": [str(item["range"]) for item in range_entries],
            "backoffMillis": [
                int(item["expectedBackoffMillis"])
                for item in range_entries
                if type(item.get("expectedBackoffMillis")) is int
            ],
            "observedRequestIntervalsMillis": observed_intervals,
            "reconnectAttempts": reconnect_attempts,
            "priorCertificateFingerprint": prior_certificate_fingerprint,
            "certificateFingerprint": certificate_fingerprint,
            "certificateAddress": certificate_address,
            "expectationObservation": {
                "successfulPropfindCount": len(successful_propfinds),
                "successfulRangeResponseCount": len(successful_ranges),
                "triggeredRequests": triggered,
                "recoveredRequests": recovered,
                "expectedBackoffMillis": expected_backoffs,
                "observedRequestIntervalsMillis": observed_intervals,
                "reconnectAttempts": reconnect_attempts,
                "reconnectAttemptLimit": len(expected_backoffs),
                "priorCertificateFingerprint": prior_certificate_fingerprint,
                "certificateFingerprint": certificate_fingerprint,
            },
            "traceLines": trace_lines,
        }

    def _host_preflight_1(self, arguments, context):
        check = str(arguments["check"])
        phase = str(arguments.get("phase", "ensure"))
        if phase != "ensure":
            configuration = self._remote_preflight_configuration()
            if phase == "activate":
                recipe = str(arguments.get("recipe", ""))
                receipt = _remote_preflight.activate_remote_recipe(
                    configuration,
                    recipe,
                )
                receipt = validate_remote_activation_receipt(receipt, recipe)
                runtime, metadata = _runtime_identity(REMOTE_RUNTIME_FILE)
                if (
                    receipt["generation"] != runtime["generation"]
                    or receipt["certificateFingerprint"]
                    != runtime["certificateFingerprint"]
                    or receipt["logPath"] != runtime["requestLogPath"]
                ):
                    raise OperationAdapterError(
                        "remote activation receipt differs from its runtime generation"
                    )
                return {
                    "succeeded": True,
                    "check": check,
                    "phase": phase,
                    "recipe": recipe,
                    "receiptID": receipt["receiptID"],
                    "generationToken": str(receipt["generation"]),
                    "endpointDigest": receipt["endpointDigest"],
                    "certificateFingerprint": receipt["certificateFingerprint"],
                    "requestLogPath": receipt["logPath"],
                    "runtimePath": str(REMOTE_RUNTIME_FILE),
                    "runtimeIdentity": dict(metadata),
                    "activationReceipt": dict(receipt),
                    "implementations": {
                        identity: dict(binding)
                        for identity, binding in REMOTE_IMPLEMENTATION_IDENTITIES.items()
                    },
                }
            receipt_id = str(arguments.get("receiptID", ""))
            if receipt_id.startswith("result://"):
                raise OperationAdapterError(
                    "result references must be resolved before backend invocation"
                )
            restoration = _remote_preflight.restore_remote_recipe(
                configuration,
                receipt_id,
            )
            restoration = validate_remote_restoration_receipt(
                restoration,
                receipt_id,
            )
            triggered_requests = _triggered_requests_from_log(
                restoration["activationLogPath"]
            )
            return {
                "succeeded": True,
                "check": check,
                "phase": phase,
                "receiptID": receipt_id,
                "restoredGenerationToken": str(
                    restoration["restoredGeneration"]
                ),
                "restoredStateDigest": restoration["restoredStateDigest"],
                "restoredEndpointDigest": restoration["restoredEndpointDigest"],
                "restoredCertificateFingerprint": restoration[
                    "restoredCertificateFingerprint"
                ],
                "restoredRequestLogPath": restoration[
                    "restoredRequestLogPath"
                ],
                "restorationReceipt": dict(restoration),
                "triggeredRequests": triggered_requests,
                "implementations": {
                    identity: dict(binding)
                    for identity, binding in REMOTE_IMPLEMENTATION_IDENTITIES.items()
                },
            }
        if check == "emby-aggregate":
            command = [
                sys.executable,
                str(REMOTE_PREFLIGHT_PATH),
                "emby-aggregate",
                "--bind-host",
                _literal_lan_address(),
            ]
            envelope = self._run_json(command, **{"timeout": 120})
            checks = envelope.get("checks")
            if (
                envelope.get("schema")
                != "enchron.regression.environment-preflight@1"
                or envelope.get("ready") is not True
                or not isinstance(checks, list)
                or len(checks) != 1
                or not _emby_source.validate_preflight_report(
                    checks[0], runtime_file=_emby_source.DEFAULT_IDENTITY_FILE
                )
            ):
                raise OperationAdapterError(
                    "Emby preflight did not return its exact typed active seed receipt"
                )
            return {
                "succeeded": True,
                "check": check,
                "report": checks[0],
                "runtimePath": str(_emby_source.DEFAULT_IDENTITY_FILE),
                "implementations": {
                    "emby-source-preflight": dict(
                        _source_identity(
                            REPOSITORY_ROOT
                            / "Scripts/verification/regression_emby_source.py"
                        )
                    ),
                    "environment-preflight-adapter": dict(
                        _source_identity(REMOTE_PREFLIGHT_PATH)
                    ),
                },
            }
        if check == "system-import-fixtures":
            if context.lane != "simulator":
                raise OperationAdapterError(
                    "system import fixtures are available only on the Simulator lane"
                )
            command = [
                sys.executable,
                str(SYSTEM_IMPORT_PATH),
                "ensure",
                "--device",
                context.target,
            ]
            result = self._run_json(command, **{"timeout": 120})
            runtime_file = _system_import.SystemImportConfiguration(
                context.target
            ).runtime_file
            if not _system_import.validate_preflight_report(
                result,
                device_identifier=context.target,
                runtime_file=runtime_file,
            ):
                raise OperationAdapterError(
                    "system import preflight did not return its exact typed runtime identity"
                )
            device_hub = self._run_json(
                [
                    sys.executable,
                    str(DEVICE_HUB_CANVAS_PATH),
                    "--device",
                    context.target,
                    "enlarge",
                ],
                **{"timeout": 120},
            )
            self._require_device_hub_binding(device_hub, context)
            canvas = device_hub.get("canvas")
            if (
                not isinstance(canvas, dict)
                or type(canvas.get("width")) is not int
                or canvas["width"] < 1200
                or type(canvas.get("height")) is not int
                or canvas["height"] <= 0
            ):
                raise OperationAdapterError(
                    "Device Hub was not enlarged to one targetable fit canvas"
                )
            return {
                "succeeded": True,
                "check": check,
                "report": result,
                "runtimePath": str(runtime_file),
                "runtimeIdentity": dict(result["runtimeIdentity"]),
                "deviceHub": device_hub,
                "implementations": {
                    identity: dict(binding)
                    for identity, binding in SYSTEM_IMPORT_IMPLEMENTATION_IDENTITIES.items()
                },
            }
        elif check == "audio-fixtures":
            command = [
                sys.executable,
                "Scripts/verification/journey_preflight.py",
                "audio-fixtures",
            ]
        elif check == "smb-aggregate":
            command = [
                sys.executable,
                str(SMB_SOURCE_PATH),
                "ensure",
                "--address",
                _literal_lan_address(),
                "--runtime-root",
                str(SMB_RUNTIME_FILE.parent),
                "--registry",
                str(_smb_source.DEFAULT_REGISTRY),
                "--environment-file",
                str(_smb_source.DEFAULT_ENVIRONMENT_FILE),
            ]
            result = self._run_json(command, **{"timeout": 120})
            validate_smb_preflight_report(result, SMB_RUNTIME_FILE)
            identity = result["runtimeIdentity"]
            assert isinstance(identity, dict)
            share_name = identity.get("shareName")
            if not isinstance(share_name, str) or not share_name:
                raise OperationAdapterError("SMB aggregate omitted its share name")
            host_shares = result.get("hostShares")
            if not isinstance(host_shares, list) or not host_shares:
                raise OperationAdapterError("SMB aggregate omitted the server share list")
            return {
                "succeeded": True,
                "check": check,
                "report": result,
                "shareName": share_name,
                "hostShares": list(host_shares),
                "aggregateVideoName": _smb_aggregate_video_name(result),
                "runtimeIdentity": dict(identity),
                "implementations": {
                    name: dict(binding)
                    for name, binding in SMB_IMPLEMENTATION_IDENTITIES.items()
                },
            }
        else:
            bind_host = _literal_lan_address()
            command = [
                sys.executable,
                str(REMOTE_PREFLIGHT_PATH),
                check,
                "--runtime-root",
                str(REMOTE_RUNTIME_FILE.parent),
                "--registry",
                str(_remote_preflight.remote.DEFAULT_REGISTRY),
                "--source-root",
                str(_remote_preflight.remote.DEFAULT_SOURCE_ROOT),
                "--bind-host",
                bind_host,
                "--port",
                "8443",
            ]
            result = self._run_json(
                command, budget_seconds=420 if check == "remote-faults" else 180
            )
            validate_remote_preflight_report(check, result)
            runtime, metadata = _runtime_identity(REMOTE_RUNTIME_FILE)
            fixed = _remote_check_payload(check, result)
            if fixed.get("serviceID") != runtime["serviceID"]:
                raise OperationAdapterError(
                    "remote preflight service identity differs from its runtime artifact"
                )
            if check == "webdav-regression" and any(
                fixed.get(key) != runtime[runtime_key]
                for key, runtime_key in (
                    ("generation", "generation"),
                    ("certificateFingerprint", "certificateFingerprint"),
                    ("requestLogPath", "requestLogPath"),
                )
            ):
                raise OperationAdapterError(
                    "webdav-regression report differs from its runtime generation"
                )
            if check == "remote-faults":
                terminal = fixed["terminalState"]
                assert isinstance(terminal, dict)
                if any(
                    terminal.get(key) != runtime[runtime_key]
                    for key, runtime_key in (
                        ("generation", "generation"),
                        ("endpointDigest", "endpointDigest"),
                        ("certificateFingerprint", "certificateFingerprint"),
                    )
                ):
                    raise OperationAdapterError(
                        "remote-faults terminal state differs from its runtime generation"
                    )
            endpoint = urlsplit(str(runtime["address"]))
            if (
                endpoint.scheme != "https"
                or endpoint.hostname is None
                or endpoint.username is not None
                or endpoint.password is not None
            ):
                raise OperationAdapterError(
                    "remote runtime address is not one sanitized HTTPS endpoint"
                )
            missing_path_address = str(runtime["address"]).rstrip("/") + "/__missing__/"
            http_address = urlunsplit(
                ("http", endpoint.netloc, endpoint.path, "", "")
            )
            unreachable_address = urlunsplit(
                ("https", f"{endpoint.hostname}:1", "/", "", "")
            )
            return {
                "succeeded": True,
                "check": check,
                "report": result,
                "runtimePath": str(REMOTE_RUNTIME_FILE),
                "generationToken": str(runtime["generation"]),
                "requestLogPath": str(runtime["requestLogPath"]),
                "endpointDigest": fixed["endpointDigest"]
                if check == "webdav-regression"
                else terminal["endpointDigest"],
                "certificateFingerprint": runtime["certificateFingerprint"],
                "missingPathAddress": missing_path_address,
                "httpAddress": http_address,
                "unreachableAddress": unreachable_address,
                "runtimeIdentity": dict(metadata),
                "implementations": {
                    identity: dict(binding)
                    for identity, binding in REMOTE_IMPLEMENTATION_IDENTITIES.items()
                },
            }
        result = self._run_json(command, **{"timeout": 120})
        return {"succeeded": True, "check": check, "report": result}

    def _diagnostics_surface_probe_1(self, arguments, context):
        settle_delay_millis = int(arguments.get("settleDelayMillis", 0))
        if settle_delay_millis > 0:
            getattr(time, "sleep")(settle_delay_millis / 1000)
        control_plane = self._window_control_plane_observation(context, required=False)
        matrix = self._matrix(context)
        lines = self._probe_lines(context)
        current = matrix.probe_cursor(lines)
        token = arguments.get("cursorToken")
        previous = None
        if token is None:
            delta: list[str] = []
            observed = current
            compacted = None
        else:
            if str(token).startswith("result://"):
                raise OperationAdapterError(
                    "result references must be resolved before backend invocation"
                )
            sequence, line_count = str(token).split(":", 1)
            previous = matrix.ProbeCursor(int(sequence), int(line_count))
            delta, observed, compacted = matrix.probe_lines_since(lines, previous)
        interaction_prefixes = (
            "reachability ",
            "openRequestForwarded",
            "certificateBoundary ",
            "controlsVisibility ",
            "rendererOwnership.",
            "stoppedPlaybackCleanup ",
        )
        interaction = [
            line
            for line in delta
            if "toggle source=" in line
            or any(prefix in line for prefix in interaction_prefixes)
        ]
        spatial = [line for line in delta if "spatialTap entity=" in line]
        remote_observation = None
        certificate_boundary = None
        certificate_change_observation_result = None
        playback_observation = None
        container_index_observation = None
        viewing_storage_observation = None
        viewing_storage_response = None
        container_index_open = None
        if arguments.get("includeViewingStorage") is True:
            raw_viewing_storage = self._await_viewing_storage_observation(
                context,
                tuple(arguments.get("awaitEmptyStores", ())),
                arguments.get("deadlineSeconds"),
            )
            viewing_storage_response = raw_viewing_storage["response"]
            viewing_storage_snapshot = raw_viewing_storage["snapshot"]
            container_index_open = viewing_storage_snapshot.get(
                "containerIndexOpen"
            )
            viewing_storage_digest = "sha256:" + hashlib.sha256(
                json.dumps(
                    viewing_storage_snapshot,
                    ensure_ascii=False,
                    sort_keys=True,
                    separators=(",", ":"),
                ).encode("utf-8")
            ).hexdigest()
            prior_viewing_storage_digests = [
                _sha256(value, "priorViewingStorageDigests")
                for value in arguments.get("priorViewingStorageDigests", ())
            ]
            viewing_storage_observation = {
                "schema": "enchron.regression.viewing-storage-observation@1",
                "snapshot": viewing_storage_snapshot,
                "snapshotDigest": viewing_storage_digest,
                "priorSnapshotDigests": prior_viewing_storage_digests,
            }
            prior_snapshots = _inlined_viewing_storage_snapshots(arguments)
            if prior_snapshots:
                viewing_storage_observation["priorSnapshots"] = prior_snapshots
            interaction.append(
                "viewingStorageBinding "
                + json.dumps(
                    viewing_storage_observation,
                    ensure_ascii=False,
                    sort_keys=True,
                    separators=(",", ":"),
                )
            )
        if "containerIndexExpectation" in arguments:
            container_index_observation = self._container_index_observation(
                arguments, context
            )
            interaction.append(
                "containerIndexBinding "
                + json.dumps(
                    container_index_observation,
                    ensure_ascii=False,
                    sort_keys=True,
                    separators=(",", ":"),
                )
            )
        if "remoteExpectation" in arguments:
            expectation = arguments["remoteExpectation"]
            if expectation == "certificate-trust-boundary":
                certificate_boundary = certificate_boundary_observation(interaction)
            remote_observation = self._remote_observation(arguments)
            if expectation == "certificate-change":
                if previous is None:
                    raise OperationAdapterError(
                        "certificate change observation has no pre-rotation cursor"
                    )
                playback_observation = self._optional_playback_state(context)
                after_fields = playback_observation.get("fields") or None
                if not after_fields:
                    after_fields = control_plane.get("fields") or None
                if not after_fields:
                    after_fields = None
                trust = self._certificate_trust_probe(context, remote_observation)
                certificate_change_observation_result = (
                    certificate_change_observation(
                        interaction,
                        remote_observation,
                        {
                            "before": _inlined_certificate_before_state(arguments),
                            "after": after_fields,
                            "trust": trust,
                        },
                    )
                )
                interaction.append(
                    "certificateChangeBinding "
                    + json.dumps(
                        certificate_change_observation_result,
                        ensure_ascii=False,
                        sort_keys=True,
                        separators=(",", ":"),
                    )
                )
            interaction.extend(remote_observation["traceLines"])
        playback_observation = (
            playback_observation
            if arguments.get("remoteExpectation") == "certificate-change"
            else (
                self._diagnostics_playback_state_1({}, context)
                if arguments.get("remoteExpectation")
                in ("finite-backoff", "recoverable-read")
                and arguments.get("omitPlaybackState") is not True
                else None
            )
        )
        observed_user_data = None
        if arguments.get("embyProgressReadback") is True:
            try:
                observed_user_data = (
                    _emby_source.EmbySourceController().observe_progress()
                )
            except _emby_source.EmbySourceError as error:
                raise OperationAdapterError(
                    f"Emby progress readback failed: {error}"
                ) from error
        return {
            "succeeded": True,
            "fields": control_plane["fields"],
            "response": control_plane["response"],
            "cursorToken": f"{observed.sequence}:{observed.line_count}",
            "compacted": compacted,
            "lines": delta,
            "interactionTrace": interaction,
            "spatialInputTrace": spatial,
            "remoteObservation": remote_observation,
            "relatedResults": list(arguments.get("relatedResults", [])),
            "playbackObservation": playback_observation,
            "certificateBoundary": certificate_boundary,
            "certificateChangeObservation": certificate_change_observation_result,
            "containerIndexObservation": container_index_observation,
            "viewingStorageObservation": viewing_storage_observation,
            "observedUserData": observed_user_data,
            "viewingStorageDigest": (
                viewing_storage_observation["snapshotDigest"]
                if viewing_storage_observation is not None
                else None
            ),
            "viewingStorageResponse": viewing_storage_response,
            "containerIndexOpenScope": (
                container_index_open["scope"]
                if container_index_open is not None
                else None
            ),
            "containerIndexOpenContentRevision": (
                container_index_open["contentRevision"]
                if container_index_open is not None
                else None
            ),
            "containerIndexOpenFinished": (
                container_index_open["containerIndexFinished"]
                if container_index_open is not None
                else None
            ),
            "containerIndexOpenCacheHitRanges": (
                container_index_open["cacheHitRanges"]
                if container_index_open is not None
                else None
            ),
            "containerIndexOpenSourceReadRanges": (
                container_index_open["sourceReadRanges"]
                if container_index_open is not None
                else None
            ),
            "containerIndexOpenRecordedRanges": (
                container_index_open["recordedRanges"]
                if container_index_open is not None
                else None
            ),
            "remoteRequestCursor": (
                remote_observation.get("requestCursor")
                if remote_observation is not None
                else None
            ),
            **(
                {
                    "containerIndexDigest": container_index_observation[
                        "containerIndexDigest"
                    ],
                    "containerIndexEntryKeys": container_index_observation[
                        "entryKeys"
                    ],
                    "sourceIdentity": container_index_observation[
                        "sourceIdentity"
                    ],
                    "contentRevision": container_index_observation[
                        "contentRevision"
                    ],
                }
                if container_index_observation is not None
                else {}
            ),
        }

    def _viewing_storage_observation(self, context):
        response = self._app_command(context, "viewingStorageProbe")
        self._require_success(response, "viewingStorageProbe")
        snapshot = response.get("viewingStorageSnapshot")

        def closed_object(
            value: object,
            location: str,
            required: frozenset[str],
            optional: frozenset[str] = frozenset(),
        ) -> Mapping[str, object]:
            if not isinstance(value, Mapping):
                raise OperationAdapterError(f"{location} is not an object")
            fields = frozenset(str(key) for key in value)
            if not required.issubset(fields) or not fields.issubset(required | optional):
                raise OperationAdapterError(
                    f"{location} does not match its closed product schema"
                )
            return value

        def records(value: object, location: str) -> list[Mapping[str, object]]:
            if not isinstance(value, list) or any(
                not isinstance(item, Mapping) for item in value
            ):
                raise OperationAdapterError(f"{location} is not an object list")
            return list(value)

        def nonnegative_integer(value: object, location: str) -> int:
            if type(value) is not int or value < 0:
                raise OperationAdapterError(
                    f"{location} must be a non-negative integer"
                )
            return value

        def nonnegative_number(value: object, location: str) -> float:
            if (
                not isinstance(value, (int, float))
                or isinstance(value, bool)
                or value < 0
            ):
                raise OperationAdapterError(
                    f"{location} must be a non-negative number"
                )
            return float(value)

        root = closed_object(
            snapshot,
            "viewingStorageSnapshot",
            frozenset(
                (
                    "schema",
                    "viewingState",
                    "containerIndex",
                    "artwork",
                    "protectedState",
                )
            ),
            frozenset(("activePlayback", "containerIndexOpen")),
        )
        if root["schema"] != "enchron.regression.viewing-storage-state@1":
            raise OperationAdapterError(
                "viewingStorageProbe returned the wrong root schema"
            )

        viewing = closed_object(
            root["viewingState"],
            "viewingStorageSnapshot.viewingState",
            frozenset(
                (
                    "schema",
                    "storeIdentity",
                    "persistedRecordCount",
                    "persistedBytes",
                    "invalidRecordCount",
                    "viewingRecordCount",
                    "resumableCount",
                    "completedCount",
                    "entries",
                    "protectedStateDigest",
                    "protectedEntries",
                )
            ),
        )
        if viewing["schema"] != "enchron.regression.viewing-state-store@1":
            raise OperationAdapterError(
                "viewingStorageProbe returned the wrong viewing-state schema"
            )
        viewing_entries = records(
            viewing["entries"], "viewingStorageSnapshot.viewingState.entries"
        )
        protected_entries = records(
            viewing["protectedEntries"],
            "viewingStorageSnapshot.viewingState.protectedEntries",
        )
        viewing_count = nonnegative_integer(
            viewing["viewingRecordCount"],
            "viewingStorageSnapshot.viewingState.viewingRecordCount",
        )
        resumable_count = nonnegative_integer(
            viewing["resumableCount"],
            "viewingStorageSnapshot.viewingState.resumableCount",
        )
        completed_count = nonnegative_integer(
            viewing["completedCount"],
            "viewingStorageSnapshot.viewingState.completedCount",
        )
        persisted_count = nonnegative_integer(
            viewing["persistedRecordCount"],
            "viewingStorageSnapshot.viewingState.persistedRecordCount",
        )
        nonnegative_integer(
            viewing["persistedBytes"],
            "viewingStorageSnapshot.viewingState.persistedBytes",
        )
        nonnegative_integer(
            viewing["invalidRecordCount"],
            "viewingStorageSnapshot.viewingState.invalidRecordCount",
        )
        if (
            viewing_count != len(viewing_entries)
            or resumable_count + completed_count != viewing_count
            or persisted_count < max(len(viewing_entries), len(protected_entries))
        ):
            raise OperationAdapterError(
                "viewingStorageProbe returned inconsistent viewing-state counts"
            )
        _sha256(
            viewing["protectedStateDigest"],
            "viewingStorageSnapshot.viewingState.protectedStateDigest",
        )
        previous_identity: tuple[str, str] | None = None
        observed_resumable = 0
        observed_completed = 0
        for index, item in enumerate(viewing_entries):
            entry = closed_object(
                item,
                f"viewingStorageSnapshot.viewingState.entries[{index}]",
                frozenset(
                    (
                        "mediaIdentity",
                        "contentRevision",
                        "authority",
                        "status",
                        "positionSeconds",
                        "durationSeconds",
                        "completed",
                    )
                ),
            )
            identity = (
                _sha256(entry["mediaIdentity"], "viewing entry mediaIdentity"),
                _sha256(entry["contentRevision"], "viewing entry contentRevision"),
            )
            if previous_identity is not None and identity <= previous_identity:
                raise OperationAdapterError(
                    "viewingStorageProbe returned unsorted or duplicate viewing entries"
                )
            previous_identity = identity
            if entry["authority"] != "enchron-persistence":
                raise OperationAdapterError("viewing entry has the wrong authority")
            status = entry["status"]
            completed = entry["completed"]
            if status == "resumable" and completed is False:
                observed_resumable += 1
            elif status == "completed" and completed is True:
                observed_completed += 1
            else:
                raise OperationAdapterError(
                    "viewing entry status and completed flag disagree"
                )
            position = nonnegative_number(entry["positionSeconds"], "viewing position")
            duration = nonnegative_number(entry["durationSeconds"], "viewing duration")
            if position > duration:
                raise OperationAdapterError("viewing entry position exceeds duration")
        if (observed_resumable, observed_completed) != (
            resumable_count,
            completed_count,
        ):
            raise OperationAdapterError(
                "viewingStorageProbe status counts do not bind its entries"
            )
        for index, item in enumerate(protected_entries):
            entry = closed_object(
                item,
                f"viewingStorageSnapshot.viewingState.protectedEntries[{index}]",
                frozenset(("mediaIdentity", "contentRevision")),
                frozenset(
                    (
                        "formatPreference",
                        "playbackModePreference",
                        "trackSelectionPreference",
                    )
                ),
            )
            _sha256(entry["mediaIdentity"], "protected entry mediaIdentity")
            _sha256(entry["contentRevision"], "protected entry contentRevision")

        container = closed_object(
            root["containerIndex"],
            "viewingStorageSnapshot.containerIndex",
            frozenset(
                (
                    "schema",
                    "cacheIdentity",
                    "digest",
                    "entryCount",
                    "entries",
                    "totalBytes",
                )
            ),
        )
        if container["schema"] != "enchron.regression.container-index-state@1":
            raise OperationAdapterError(
                "viewingStorageProbe returned the wrong container-index schema"
            )
        _sha256(container["cacheIdentity"], "containerIndex.cacheIdentity")
        _sha256(container["digest"], "containerIndex.digest")
        container_entries = records(container["entries"], "containerIndex.entries")
        container_total = nonnegative_integer(container["totalBytes"], "containerIndex.totalBytes")
        if nonnegative_integer(
            container["entryCount"], "containerIndex.entryCount"
        ) != len(container_entries):
            raise OperationAdapterError("container-index entry count is inconsistent")
        observed_container_bytes = 0
        for index, item in enumerate(container_entries):
            entry = closed_object(
                item,
                f"containerIndex.entries[{index}]",
                frozenset(
                    (
                        "contentRevision",
                        "digest",
                        "bytes",
                        "ranges",
                        "invalidFileCount",
                    )
                ),
                frozenset(("contentLength",)),
            )
            _sha256(entry["contentRevision"], "container entry contentRevision")
            _sha256(entry["digest"], "container entry digest")
            observed_container_bytes += nonnegative_integer(
                entry["bytes"], "container entry bytes"
            )
            nonnegative_integer(
                entry["invalidFileCount"], "container entry invalidFileCount"
            )
            if "contentLength" in entry:
                nonnegative_integer(entry["contentLength"], "container entry contentLength")
            for range_index, range_item in enumerate(
                records(entry["ranges"], "container entry ranges")
            ):
                range_value = closed_object(
                    range_item,
                    f"container entry ranges[{range_index}]",
                    frozenset(("lowerBound", "upperBoundExclusive", "bytes")),
                )
                lower = nonnegative_integer(range_value["lowerBound"], "range lowerBound")
                upper = nonnegative_integer(
                    range_value["upperBoundExclusive"], "range upperBoundExclusive"
                )
                byte_count = nonnegative_integer(range_value["bytes"], "range bytes")
                if upper <= lower or byte_count != upper - lower:
                    raise OperationAdapterError("container range bounds are inconsistent")
        if observed_container_bytes != container_total:
            raise OperationAdapterError("container-index total bytes are inconsistent")

        artwork = closed_object(
            root["artwork"],
            "viewingStorageSnapshot.artwork",
            frozenset(
                (
                    "schema",
                    "storeIdentity",
                    "digest",
                    "entryCount",
                    "entries",
                    "totalBytes",
                    "invalidFileCount",
                )
            ),
        )
        if artwork["schema"] != "enchron.regression.artwork-store-state@1":
            raise OperationAdapterError(
                "viewingStorageProbe returned the wrong artwork schema"
            )
        _sha256(artwork["storeIdentity"], "artwork.storeIdentity")
        _sha256(artwork["digest"], "artwork.digest")
        artwork_entries = records(artwork["entries"], "artwork.entries")
        if nonnegative_integer(artwork["entryCount"], "artwork.entryCount") != len(
            artwork_entries
        ):
            raise OperationAdapterError("artwork entry count is inconsistent")
        artwork_total = 0
        observed_invalid_artwork = 0
        for index, item in enumerate(artwork_entries):
            entry = closed_object(
                item,
                f"artwork.entries[{index}]",
                frozenset(
                    ("artworkKey", "digest", "bytes", "hasValidStorageName")
                ),
            )
            if not isinstance(entry["artworkKey"], str) or not entry["artworkKey"]:
                raise OperationAdapterError("artwork entry omitted its key")
            _sha256(entry["digest"], "artwork entry digest")
            artwork_total += nonnegative_integer(entry["bytes"], "artwork entry bytes")
            if type(entry["hasValidStorageName"]) is not bool:
                raise OperationAdapterError("artwork storage-name flag is not boolean")
            observed_invalid_artwork += entry["hasValidStorageName"] is False
        if (
            artwork_total
            != nonnegative_integer(artwork["totalBytes"], "artwork.totalBytes")
            or observed_invalid_artwork
            != nonnegative_integer(
                artwork["invalidFileCount"], "artwork.invalidFileCount"
            )
        ):
            raise OperationAdapterError("artwork aggregate counts are inconsistent")

        protected = closed_object(
            root["protectedState"],
            "viewingStorageSnapshot.protectedState",
            frozenset(
                (
                    "schema",
                    "digest",
                    "folders",
                    "references",
                    "playbackPreferences",
                )
            ),
        )
        if protected["schema"] != "enchron.regression.viewing-storage-protected-state@1":
            raise OperationAdapterError(
                "viewingStorageProbe returned the wrong protected-state schema"
            )
        _sha256(protected["digest"], "protectedState.digest")
        folders = records(protected["folders"], "protectedState.folders")
        references = records(protected["references"], "protectedState.references")
        for index, item in enumerate(folders):
            closed_object(
                item,
                f"protectedState.folders[{index}]",
                frozenset(("id", "name")),
                frozenset(("parentID",)),
            )
        for index, item in enumerate(references):
            reference = closed_object(
                item,
                f"protectedState.references[{index}]",
                frozenset(("id", "name", "sizeInBytes")),
                frozenset(("folderID",)),
            )
            nonnegative_integer(reference["sizeInBytes"], "reference.sizeInBytes")
        preferences = closed_object(
            protected["playbackPreferences"],
            "protectedState.playbackPreferences",
            frozenset(
                (
                    "resumePolicy",
                    "endBehavior",
                    "defaultSpeed",
                    "controlsAutoHideSeconds",
                )
            ),
            frozenset(("defaultEnvironmentID",)),
        )
        if preferences["resumePolicy"] not in {
            "ask-every-time",
            "always-resume",
            "always-start-from-beginning",
        } or preferences["endBehavior"] not in {"stop", "repeat-one", "play-next"}:
            raise OperationAdapterError("protected playback preferences are not closed")
        if nonnegative_number(preferences["defaultSpeed"], "defaultSpeed") <= 0:
            raise OperationAdapterError("defaultSpeed must be positive")
        nonnegative_integer(
            preferences["controlsAutoHideSeconds"], "controlsAutoHideSeconds"
        )

        active = root.get("activePlayback")
        active_playback = None
        if active is not None:
            active_playback = closed_object(
                active,
                "viewingStorageSnapshot.activePlayback",
                frozenset(
                    (
                        "viewingStateAuthority",
                        "lifecycle",
                        "positionSeconds",
                        "durationSeconds",
                        "actualPlaybackSeconds",
                        "endedNaturally",
                    )
                ),
                frozenset(("sessionID", "mediaIdentity", "contentRevision")),
            )
            if active_playback["viewingStateAuthority"] not in {
                "enchron-persistence",
                "media-server",
            } or not isinstance(active_playback["lifecycle"], str):
                raise OperationAdapterError("active playback identity is invalid")
            for identity_field in ("mediaIdentity", "contentRevision"):
                if identity_field in active_playback:
                    _sha256(
                        active_playback[identity_field],
                        f"activePlayback.{identity_field}",
                    )
            position = nonnegative_number(
                active_playback["positionSeconds"], "activePlayback.positionSeconds"
            )
            duration = nonnegative_number(
                active_playback["durationSeconds"], "activePlayback.durationSeconds"
            )
            nonnegative_number(
                active_playback["actualPlaybackSeconds"],
                "activePlayback.actualPlaybackSeconds",
            )
            if position > duration or type(active_playback["endedNaturally"]) is not bool:
                raise OperationAdapterError("active playback values are inconsistent")

        container_index_open = root.get("containerIndexOpen")
        normalized_root = dict(root)
        if container_index_open is not None:
            open_snapshot = closed_object(
                container_index_open,
                "viewingStorageSnapshot.containerIndexOpen",
                frozenset(
                    (
                        "schema",
                        "scope",
                        "contentRevision",
                        "containerIndexFinished",
                        "cacheHitRanges",
                        "sourceReadRanges",
                        "recordedRanges",
                    )
                ),
            )
            if (
                open_snapshot["schema"]
                != "enchron.regression.media-byte-stream-container-index-open@1"
            ):
                raise OperationAdapterError(
                    "viewingStorageProbe returned the wrong container-index-open schema"
                )
            scope = _nonempty_text(
                open_snapshot["scope"], "containerIndexOpen.scope"
            )
            scope_prefix = "media-byte-stream:"
            if not scope.startswith(scope_prefix):
                raise OperationAdapterError(
                    "containerIndexOpen.scope must identify one media byte stream"
                )
            _lowercase_uuid(
                scope[len(scope_prefix) :], "containerIndexOpen.scope token"
            )
            content_revision = _sha256(
                open_snapshot["contentRevision"],
                "containerIndexOpen.contentRevision",
            )
            finished = open_snapshot["containerIndexFinished"]
            if type(finished) is not bool:
                raise OperationAdapterError(
                    "containerIndexOpen.containerIndexFinished must be boolean"
                )

            def canonical_open_ranges(
                value: object, field: str
            ) -> list[dict[str, int]]:
                location = f"containerIndexOpen.{field}"
                normalized: list[dict[str, int]] = []
                for index, item in enumerate(records(value, location)):
                    range_value = closed_object(
                        item,
                        f"{location}[{index}]",
                        frozenset(
                            ("lowerBound", "upperBoundExclusive", "bytes")
                        ),
                    )
                    lower = nonnegative_integer(
                        range_value["lowerBound"], f"{location}[{index}].lowerBound"
                    )
                    upper = nonnegative_integer(
                        range_value["upperBoundExclusive"],
                        f"{location}[{index}].upperBoundExclusive",
                    )
                    byte_count = nonnegative_integer(
                        range_value["bytes"], f"{location}[{index}].bytes"
                    )
                    if upper <= lower or byte_count != upper - lower:
                        raise OperationAdapterError(
                            "containerIndexOpen range bounds are inconsistent"
                        )
                    normalized.append(
                        {
                            "lowerBound": lower,
                            "upperBoundExclusive": upper,
                            "bytes": byte_count,
                        }
                    )
                if normalized != sorted(
                    normalized,
                    key=lambda item: (
                        item["lowerBound"],
                        item["upperBoundExclusive"],
                        item["bytes"],
                    ),
                ):
                    raise OperationAdapterError(
                        f"{location} must be canonically sorted"
                    )
                return normalized

            cache_hit_ranges = canonical_open_ranges(
                open_snapshot["cacheHitRanges"], "cacheHitRanges"
            )
            source_read_ranges = canonical_open_ranges(
                open_snapshot["sourceReadRanges"], "sourceReadRanges"
            )
            recorded_ranges = canonical_open_ranges(
                open_snapshot["recordedRanges"], "recordedRanges"
            )
            for recorded_range in recorded_ranges:
                if recorded_ranges.count(recorded_range) > source_read_ranges.count(
                    recorded_range
                ):
                    raise OperationAdapterError(
                        "containerIndexOpen.recordedRanges must bind sourceReadRanges"
                    )
            if (
                active_playback is None
                or active_playback.get("contentRevision") != content_revision
            ):
                raise OperationAdapterError(
                    "containerIndexOpen.contentRevision does not bind activePlayback"
                )
            normalized_root["containerIndexOpen"] = {
                "schema": open_snapshot["schema"],
                "scope": scope,
                "contentRevision": content_revision,
                "containerIndexFinished": finished,
                "cacheHitRanges": cache_hit_ranges,
                "sourceReadRanges": source_read_ranges,
                "recordedRanges": recorded_ranges,
            }

        _reject_secret_result(response, "viewingStorageProbe")
        return {"snapshot": normalized_root, "response": response}

    def _await_viewing_storage_observation(
        self,
        context: OperationContext,
        stores: tuple[str, ...],
        deadline_seconds: int | None,
    ) -> dict[str, object]:
        deadline = (
            None
            if not stores
            else getattr(time, "monotonic")() + int(deadline_seconds or 0)
        )
        while True:
            observation = self._viewing_storage_observation(context)
            snapshot = observation["snapshot"]
            assert isinstance(snapshot, Mapping)
            empty = {
                "viewing-state": (
                    snapshot["viewingState"]["viewingRecordCount"] == 0
                ),
                "container-index": (
                    snapshot["containerIndex"]["entryCount"] == 0
                    and snapshot["containerIndex"]["totalBytes"] == 0
                ),
                "artwork": (
                    snapshot["artwork"]["entryCount"] == 0
                    and snapshot["artwork"]["totalBytes"] == 0
                ),
            }
            if all(empty[store] for store in stores):
                return observation
            if deadline is None or getattr(time, "monotonic")() >= deadline:
                raise OperationAdapterError(
                    "viewingStorageProbe did not observe empty stores before deadline"
                )
            getattr(time, "sleep")(0.2)

    def _container_index_observation(self, arguments, context):
        response = self._app_command(context, "containerIndexProbe")
        self._require_success(response, "containerIndexProbe")
        pairs = self._response_payload_pairs(response)
        expected_fields = {
            "schema",
            "cacheDigest",
            "entryKeys",
            "entryCount",
            "totalBytes",
            "playbackAddressKind",
            "sourceIdentity",
            "contentRevision",
            "session",
            "mediaName",
            "byteStreamScope",
            "byteStreamRequestCount",
        }
        if (
            set(pairs) != expected_fields
            or pairs["schema"]
            != "enchron.regression.container-index-probe@1"
        ):
            raise OperationAdapterError(
                "containerIndexProbe returned the wrong closed payload"
            )
        _reject_secret_result(pairs, "containerIndexProbe")
        digest = _sha256(pairs["cacheDigest"], "containerIndexProbe.cacheDigest")
        keys = [] if not pairs["entryKeys"] else pairs["entryKeys"].split(",")
        if (
            keys != sorted(set(keys))
            or any(
                re.fullmatch(r"sha256:[0-9a-f]{64}", key) is None
                for key in keys
            )
        ):
            raise OperationAdapterError(
                "containerIndexProbe returned invalid revision keys"
            )
        try:
            entry_count = int(pairs["entryCount"])
            total_bytes = int(pairs["totalBytes"])
        except ValueError as error:
            raise OperationAdapterError(
                "containerIndexProbe counts must be integers"
            ) from error
        if entry_count != len(keys) or total_bytes < 0:
            raise OperationAdapterError(
                "containerIndexProbe counts do not bind its entries"
            )
        expectation = str(arguments["containerIndexExpectation"])
        is_empty = entry_count == 0 and total_bytes == 0 and not keys
        address = pairs["playbackAddressKind"]
        source_identity = pairs["sourceIdentity"]
        content_revision = pairs["contentRevision"]
        session = pairs["session"]
        media_name = pairs["mediaName"]
        scope = pairs["byteStreamScope"]
        request_count_text = pairs["byteStreamRequestCount"]

        prior_fields = (
            "expectedBaselineDigest",
            "expectedLocalActiveDigest",
            "expectedLocalAfterDigest",
        )
        priors = {
            field: _sha256(arguments[field], field)
            for field in prior_fields
            if field in arguments
        }
        if expectation == "baseline-empty":
            expected = {
                "isEmpty": True,
                "playbackAddressKind": "none",
                "sourceIdentity": "none",
                "contentRevision": "none",
                "session": "none",
                "mediaName": "none",
                "byteStreamScope": "none",
                "byteStreamRequestCount": "none",
            }
        elif expectation == "local-active-empty":
            expected = {
                "isEmpty": True,
                "containerIndexDigest": priors["expectedBaselineDigest"],
                "playbackAddressKind": "local-file",
                "byteStreamScope": "none",
                "byteStreamRequestCount": "none",
            }
        elif expectation == "local-after-empty":
            expected = {
                "isEmpty": True,
                "containerIndexDigest": priors["expectedBaselineDigest"],
                "playbackAddressKind": "none",
                "sourceIdentity": "none",
                "contentRevision": "none",
                "session": "none",
                "mediaName": "none",
                "byteStreamScope": "none",
                "byteStreamRequestCount": "none",
            }
        else:
            expected = {
                "isEmpty": False,
                "containerIndexDigestDiffersFrom": priors[
                    "expectedBaselineDigest"
                ],
                "expectedLocalActiveDigest": priors[
                    "expectedLocalActiveDigest"
                ],
                "expectedLocalAfterDigest": priors[
                    "expectedLocalAfterDigest"
                ],
                "playbackAddressKind": "loopback",
                "entryKeyForContentRevision": content_revision,
                "byteStreamScope": "positive-decimal",
                "byteStreamRequestCount": "positive-decimal",
            }

        observation = {
            "schema": "enchron.regression.container-index-observation@1",
            "expectation": expectation,
            "containerIndexDigest": digest,
            "entryKeys": keys,
            "entryCount": entry_count,
            "totalBytes": total_bytes,
            "playbackAddressKind": address,
            "sourceIdentity": source_identity,
            "contentRevision": content_revision,
            "session": session,
            "mediaName": media_name,
            "byteStreamScope": scope,
            "byteStreamRequestCount": request_count_text,
            "expectationObservation": {
                "expected": expected,
                "observed": {
                    "isEmpty": is_empty,
                    "containerIndexDigest": digest,
                    "entryKeys": keys,
                    "playbackAddressKind": address,
                    "sourceIdentity": source_identity,
                    "contentRevision": content_revision,
                    "session": session,
                    "mediaName": media_name,
                    "byteStreamScope": scope,
                    "byteStreamRequestCount": request_count_text,
                },
            },
        }
        observation["bindingDigest"] = "sha256:" + hashlib.sha256(
            json.dumps(
                observation,
                ensure_ascii=False,
                sort_keys=True,
                separators=(",", ":"),
            ).encode("utf-8")
        ).hexdigest()
        return observation

    def _media_stage_fixture_2(self, arguments, context):
        import stage_registered_fixture as staging

        transport = staging.EnchronStageTransport(
            context.lane,
            context.target,
            context.bundle_id,
            self._developer_dir(),
        )
        lane_bound_transport = _LeaseBoundFixtureTransport(
            context.lane,
            context.target,
            context.bundle_id,
            transport.developer_dir,
            transport,
        )
        receipt = staging.stage_registered_fixture(
            registry=staging.FixtureRegistry.load(staging.DEFAULT_REGISTRY),
            fixture_id=str(arguments["fixtureID"]),
            source_root=Path(str(arguments["sourceRoot"])),
            transport=lane_bound_transport,
        )
        return {"succeeded": True, "receipt": receipt}

    def _media_import_staged_2(self, arguments, context):
        before_response = self._app_command(context, "listLibrary")
        self._require_success(before_response, "listLibrary before import")
        before = validate_library_snapshot(before_response.get("librarySnapshot"))
        imported = self._app_command(context, "importMedia", f"file={arguments['fileName']}")
        self._require_success(imported, "importMedia")
        after_response = self._app_command(context, "listLibrary")
        self._require_success(after_response, "listLibrary after import")
        after = validate_library_snapshot(after_response.get("librarySnapshot"))
        before_ids = {
            str(item["id"])
            for item in before["references"]
            if isinstance(item, Mapping)
        }
        additions = [
            item
            for item in after["references"]
            if isinstance(item, Mapping) and item.get("id") not in before_ids
        ]
        if len(additions) != 1:
            raise OperationAdapterError(
                "media import must add exactly one new library reference"
            )
        reference = additions[0]
        if (
            reference.get("name") != arguments["fileName"]
            or reference.get("locatorKind") != "file"
            or reference.get("sourceExists") is not True
            or not isinstance(reference.get("sourceDigest"), str)
        ):
            raise OperationAdapterError(
                "media import did not preserve one readable file-backed source"
            )
        folder_id = reference.get("folderID")
        return {
            "succeeded": True,
            "import": imported,
            "library": after_response,
            "beforeSnapshot": before,
            "afterSnapshot": after,
            "referenceID": reference["id"],
            "folderID": folder_id if folder_id is not None else "root",
            "sourceIdentity": reference["sourceIdentity"],
            "sourcePath": reference["sourcePath"],
            "sourceDigest": reference["sourceDigest"],
            "fileName": reference["name"],
        }

    def _preparation_local_directory_subtitle_source_1(
        self, arguments, context
    ):
        before_response = self._app_command(context, "listLibrary")
        self._require_success(
            before_response, "listLibrary before directory import"
        )
        before = validate_library_snapshot(before_response.get("librarySnapshot"))
        member_file_names = [str(item) for item in arguments["memberFileNames"]]
        imported = self._app_command(
            context,
            "importMediaDirectory",
            f"directory={arguments['directoryName']}",
            f"media={arguments['mediaFileName']}",
            "files="
            + json.dumps(
                member_file_names,
                ensure_ascii=False,
                separators=(",", ":"),
            ),
        )
        self._require_success(imported, "importMediaDirectory")
        receipt = validate_directory_media_import_receipt(
            imported.get("directoryMediaImportReceipt"),
            arguments,
        )
        after_response = self._app_command(context, "listLibrary")
        self._require_success(after_response, "listLibrary after directory import")
        after = validate_library_snapshot(after_response.get("librarySnapshot"))

        before_reference_ids = {
            str(item["id"])
            for item in before["references"]
            if isinstance(item, Mapping)
        }
        additions = [
            item
            for item in after["references"]
            if isinstance(item, Mapping)
            and item.get("id") not in before_reference_ids
        ]
        if len(additions) != 1:
            raise OperationAdapterError(
                "directory import must add exactly one media reference"
            )
        reference = additions[0]
        if (
            reference.get("id") != receipt["referenceID"]
            or reference.get("name") != arguments["mediaFileName"]
            or reference.get("locatorKind") != "file"
            or reference.get("sourcePath") != receipt["mediaSourcePath"]
            or reference.get("sourceExists") is not True
            or not isinstance(reference.get("sourceDigest"), str)
        ):
            raise OperationAdapterError(
                "directory import did not preserve the receipt-bound readable media source"
            )

        before_folder_ids = {
            str(item["id"])
            for item in before["folders"]
            if isinstance(item, Mapping)
        }
        added_folders = [
            item
            for item in after["folders"]
            if isinstance(item, Mapping) and item.get("id") not in before_folder_ids
        ]
        folder_id = reference.get("folderID")
        if (
            len(added_folders) != 1
            or folder_id is None
            or added_folders[0].get("id") != folder_id
            or added_folders[0].get("name") != arguments["directoryName"]
        ):
            raise OperationAdapterError(
                "directory import did not create one reference-owning library folder"
            )

        staged_names = {
            str(item["name"])
            for item in after["stagedFiles"]
            if isinstance(item, Mapping)
        }
        missing_staged = sorted(set(member_file_names) - staged_names)
        if missing_staged:
            raise OperationAdapterError(
                "directory import lost staged members: " + ", ".join(missing_staged)
            )
        return {
            "succeeded": True,
            "import": imported,
            "library": after_response,
            "beforeSnapshot": before,
            "afterSnapshot": after,
            "directoryMediaImportReceipt": receipt,
            "referenceID": reference["id"],
            "folderID": folder_id,
            "sourceIdentity": reference["sourceIdentity"],
            "sourcePath": reference["sourcePath"],
            "sourceDigest": reference["sourceDigest"],
            "bookmarkRootPath": receipt["bookmarkRootPath"],
            "mediaRelativePath": receipt["mediaRelativePath"],
            "memberFileNames": receipt["memberFileNames"],
        }

    def _media_open_2(self, arguments, context):
        before = self._diagnostics_surface_probe_1({}, context)
        action = self._controller(context, "tap", "--identifier", str(arguments["identifier"]))
        self._require_success(action, "media open")
        expected_issue = arguments.get("expectedIssueCategory")
        if expected_issue is not None:
            after = self._diagnostics_surface_probe_1(
                {"cursorToken": before["cursorToken"]}, context
            )
            delivered = any(
                "openRequestForwarded" in line for line in after["lines"]
            )
            settlement = (
                self._wait_for_expected_issue(
                    context,
                    category=str(expected_issue),
                    deadline_seconds=int(arguments["deadlineSeconds"]),
                )
                if delivered
                else {
                    "succeeded": False,
                    "reason": "open-request-not-forwarded",
                    "expectedCategory": expected_issue,
                }
            )
            result = {
                "succeeded": settlement["succeeded"] is True and delivered,
                "action": action,
                "settlement": settlement,
                "fields": settlement.get("fields", {}),
                "response": settlement.get("response", {}),
                "probe": after,
                "deliveryObserved": delivered,
                "expectedIssueCategory": expected_issue,
                "relatedResults": list(arguments.get("relatedResults", [])),
            }
            for key in (
                "alertMessage",
                "noActiveSession",
                "noDeliveredSample",
                "primaryAction",
                "secondaryAction",
                "closeOnly",
            ):
                if key in settlement:
                    result[key] = settlement[key]
            return result
        landing = self._wait_for_window(
            context,
            presentation=str(arguments["expectedLanding"]),
            lifecycle="any-steady",
            controls="either",
            deadline_seconds=int(arguments["deadlineSeconds"]),
        )
        after = self._diagnostics_surface_probe_1({"cursorToken": before["cursorToken"]}, context)
        delivered = any("openRequestForwarded" in line for line in after["lines"])
        succeeded = landing["succeeded"] is True and delivered
        return {
            "succeeded": succeeded,
            "action": action,
            "settlement": landing,
            "fields": landing.get("fields", {}),
            "response": landing.get("response", {}),
            "probe": after,
            "deliveryObserved": delivered,
            "relatedResults": list(arguments.get("relatedResults", [])),
        }

    def _restore_active_remote_recipe(self, context: OperationContext):
        configuration = self._remote_preflight_configuration()
        controller = _remote_preflight.remote.RemoteSourceController(
            configuration.service
        )
        identity = controller.status()
        recipe = identity.get("recipe")
        if recipe in (None, "healthy"):
            return None
        generation = int(identity["generation"])
        receipt_id = f"receipt:g-{generation:06d}:{recipe}"
        return self._host_preflight_1(
            {
                "check": "remote-faults",
                "phase": "restore",
                "receiptID": receipt_id,
            },
            context,
        )

    def _activate_issue_recipe(self, recipe: str, context: OperationContext):
        self._restore_active_remote_recipe(context)
        return self._host_preflight_1(
            {
                "check": "remote-faults",
                "phase": "activate",
                "recipe": recipe,
            },
            context,
        )

    def _ensure_issue_fixture_playing(
        self, context: OperationContext, deadline_seconds: int
    ) -> dict[str, object]:
        tab = self._navigation_select_tab_1({"tab": "files"}, context)
        source = self._accessibility_activate_2(
            {
                "context": "main-window-browser",
                "labels": [ISSUE_FIXTURE_SOURCE_LABEL],
            },
            context,
        )
        listed = self._accessibility_inspect_2(
            {
                "context": "main-window-browser",
                "deadlineSeconds": deadline_seconds,
                "identifier": ISSUE_FIXTURE_MEDIA_IDENTIFIER,
                "requireMatchedElement": True,
            },
            context,
        )
        if listed.get("succeeded") is not True:
            raise OperationAdapterError(
                "issue.present could not find the issue-fixture media card"
            )
        opened = self._media_open_2(
            {
                "deadlineSeconds": deadline_seconds,
                "expectedLanding": "window",
                "identifier": ISSUE_FIXTURE_MEDIA_IDENTIFIER,
            },
            context,
        )
        if opened.get("succeeded") is not True:
            raise OperationAdapterError(
                "issue.present could not open the issue-fixture media"
            )
        settled = self._playback_wait_position_2(
            {
                "deadlineSeconds": deadline_seconds,
                "minimumPositionMillis": 1000,
                "minimumRemainingMillis": 10000,
            },
            context,
        )
        if settled.get("succeeded") is not True:
            raise OperationAdapterError(
                "issue.present could not reach playing issue-fixture media"
            )
        return {
            "tab": tab,
            "source": source,
            "listed": listed,
            "opened": opened,
            "settled": settled,
        }

    def _issue_present_1(self, arguments, context):
        category = str(arguments["category"])
        recipe = ISSUE_INDUCE_RECIPES.get(category)
        if recipe is None:
            raise OperationAdapterError(
                f"issue.present has no real-fault induce route for {category}"
            )
        deadline_seconds = int(arguments.get("deadlineSeconds", 45))
        plane, _ = self._issue_control_plane(context)
        current = plane.get("error", "none")
        setup = None
        activation = None
        retry = None
        if current == category:
            settlement = self._wait_for_issue_slot(
                context,
                category=category,
                deadline_seconds=deadline_seconds,
            )
            if settlement.get("succeeded") is not True:
                raise OperationAdapterError(
                    f"issue.present found error={category} but the slot actions "
                    "did not match that category's policy"
                )
            return {
                "succeeded": True,
                "category": category,
                "recipe": recipe,
                "alreadyPresent": True,
                "fields": settlement["fields"],
                "settlement": settlement,
                "primaryAction": settlement["primaryAction"],
                "secondaryAction": settlement["secondaryAction"],
                "confirmAction": settlement["confirmAction"],
                "response": settlement.get("response", {}),
            }
        if current in (None, "none"):
            lifecycle = (plane.get("lifecycle") or "").lower()
            if lifecycle != "playing":
                setup = self._ensure_issue_fixture_playing(
                    context, deadline_seconds
                )
        try:
            activation = self._activate_issue_recipe(recipe, context)
            if current not in (None, "none"):
                retry = self._accessibility_activate_2(
                    {
                        "context": "window",
                        "identifiers": ["PlayerUI-loadFailure-primary"],
                    },
                    context,
                )
            settlement = self._wait_for_issue_slot(
                context,
                category=category,
                deadline_seconds=deadline_seconds,
            )
            if settlement.get("succeeded") is not True:
                raise OperationAdapterError(
                    f"issue.present did not observe {category} after recipe "
                    f"{recipe}: {settlement.get('reason')}"
                )
            return {
                "succeeded": True,
                "category": category,
                "recipe": recipe,
                "alreadyPresent": False,
                "receiptID": activation["receiptID"],
                "fields": settlement["fields"],
                "settlement": settlement,
                "setup": setup,
                "activation": activation,
                "retry": retry,
                "primaryAction": settlement["primaryAction"],
                "secondaryAction": settlement["secondaryAction"],
                "confirmAction": settlement["confirmAction"],
                "response": settlement.get("response", {}),
            }
        finally:
            if activation is not None:
                self._host_preflight_1(
                    {
                        "check": "remote-faults",
                        "phase": "restore",
                        "receiptID": str(activation["receiptID"]),
                    },
                    context,
                )

    def _library_snapshot_1(self, arguments, context):
        response = self._app_command(context, "listLibrary")
        self._require_success(response, "listLibrary")
        snapshot = validate_library_snapshot(response.get("librarySnapshot"))
        entries = []
        for line in self._response_payload_lines(response):
            if line.startswith("folder="):
                entries.append({"kind": "folder", "name": line[7:]})
            elif line.startswith("reference="):
                entries.append({"kind": "reference", "name": line[10:]})
        comparisons: list[dict[str, object]] = []
        if any(name in arguments for name in LIBRARY_BASELINE_FIELDS):
            baseline_values = [
                arguments[name] for name in LIBRARY_BASELINE_FIELDS
            ]
            if not all(isinstance(value, list) for value in baseline_values):
                raise OperationAdapterError(
                    "resolved library snapshot baselines must be arrays"
                )
            reference_by_id = {
                str(item["id"]): item
                for item in snapshot["references"]
                if isinstance(item, Mapping)
            }
            staged_by_name = {
                str(item["name"]): item
                for item in snapshot["stagedFiles"]
                if isinstance(item, Mapping)
            }
            for (
                reference_id,
                folder_id,
                source_identity,
                source_path,
                source_digest,
                file_name,
            ) in zip(*baseline_values):
                if (
                    _lowercase_uuid(reference_id, "baselineReferenceID")
                    in {item["referenceID"] for item in comparisons}
                ):
                    raise OperationAdapterError(
                        "resolved baselineReferenceIDs must be unique"
                    )
                if folder_id != "root":
                    _lowercase_uuid(folder_id, "baselineFolderID")
                _sha256(source_identity, "baselineSourceIdentity")
                _nonempty_text(source_path, "baselineSourcePath")
                _sha256(source_digest, "baselineSourceDigest")
                _direct_filename({"fileName": file_name})
                current = reference_by_id.get(reference_id)
                staged = staged_by_name.get(file_name)
                comparisons.append(
                    {
                        "referenceID": reference_id,
                        "baseline": {
                            "folderID": folder_id,
                            "sourceIdentity": source_identity,
                            "sourcePath": source_path,
                            "sourceDigest": source_digest,
                            "fileName": file_name,
                        },
                        "currentReference": dict(current)
                        if current is not None
                        else None,
                        "stagedFile": dict(staged)
                        if staged is not None
                        else None,
                    }
                )
        system_import_observation = None
        if "systemImportExpectation" in arguments:
            if context.lane != "simulator":
                raise OperationAdapterError(
                    "system import observations are available only on the Simulator lane"
                )
            runtime_path = _system_import.SystemImportConfiguration(
                context.target
            ).runtime_file
            runtime = _system_import.validate_runtime(runtime_path)
            expectation = str(arguments["systemImportExpectation"])
            expected = runtime[
                "filesPicker" if expectation == "files" else "photosPicker"
            ]
            assert isinstance(expected, dict)
            expected_name = str(
                expected[
                    "displayName" if expectation == "files" else "originalFilename"
                ]
            )
            expected_digest = str(expected["digest"])
            delivery = validate_system_import_delivery_snapshot(
                response.get("systemImportDeliverySnapshot")
            )
            current_references = {
                str(item["id"]): dict(item)
                for item in snapshot["references"]
                if isinstance(item, Mapping)
            }
            persistent_delivery = delivery["persistentLibraryDelivery"]
            assert isinstance(persistent_delivery, Mapping)
            delivered_references = persistent_delivery["references"]
            assert isinstance(delivered_references, list)
            persistent_reference_observations = [
                {
                    "deliveredReference": dict(item),
                    "currentReference": current_references.get(str(item["id"])),
                }
                for item in delivered_references
                if isinstance(item, Mapping)
            ]
            system_import_observation = {
                "schema": "enchron.regression.system-import-observation@1",
                "expectation": expectation,
                "environmentIdentity": runtime["environmentIdentity"],
                "fixture": dict(runtime["fixture"]),
                "configuredPicker": dict(expected),
                "expectedDeliveryDomain": (
                    "files-provider-security-scope"
                    if expectation == "files"
                    else "app-managed-photo-transfer"
                ),
                "expectedDeliveredName": expected_name,
                "expectedDeliveredDigest": expected_digest,
                "deliverySnapshot": dict(delivery),
                "persistentReferenceObservations": (
                    persistent_reference_observations
                ),
            }
        return {
            "succeeded": True,
            "response": response,
            "snapshot": snapshot,
            "priorSnapshot": arguments.get("priorSnapshot"),
            "entries": entries,
            "referenceComparisons": comparisons,
            "systemImportObservation": system_import_observation,
        }

    def _storage_clear_1(self, arguments, context):
        target = str(arguments["target"])
        action = {
            "artwork-cache": "Settings-action-clear-artwork-cache",
            "container-index-cache": "Settings-action-clear-container-index-cache",
            "playback-progress": "Settings-action-clear-progress",
        }[target]
        store = {
            "artwork-cache": "artwork",
            "container-index-cache": "container-index",
            "playback-progress": "viewing-state",
        }[target]
        before = self._viewing_storage_observation(context)
        before_snapshot = before["snapshot"]
        if not isinstance(before_snapshot, Mapping):
            raise OperationAdapterError(
                "viewingStorageProbe omitted its pre-clear product state"
            )
        identifiers = [
            "Navigation-Ornament-tab-settings",
            "Settings-category-storagePrivacy",
            action,
        ]
        response = self._controller(context, "tapSequence", "--identifiers", *identifiers)
        self._require_success(response, "storage clear")
        after = self._await_viewing_storage_observation(context, (store,), 30)
        after_snapshot = after["snapshot"]
        if not isinstance(after_snapshot, Mapping):
            raise OperationAdapterError(
                "viewingStorageProbe omitted its post-clear product state"
            )
        protected_before = before_snapshot.get("protectedState")
        protected_after = after_snapshot.get("protectedState")
        if protected_before != protected_after:
            raise OperationAdapterError(
                "storage clear changed protected library or playback settings state"
            )

        def counts(snapshot: Mapping[str, object]) -> dict[str, object]:
            viewing = snapshot.get("viewingState")
            container = snapshot.get("containerIndex")
            artwork = snapshot.get("artwork")
            if not all(
                isinstance(value, Mapping)
                for value in (viewing, container, artwork)
            ):
                raise OperationAdapterError(
                    "viewingStorageProbe omitted store aggregate state"
                )
            assert isinstance(viewing, Mapping)
            assert isinstance(container, Mapping)
            assert isinstance(artwork, Mapping)
            return {
                "viewing-state": {
                    "entries": viewing.get("viewingRecordCount"),
                    "bytes": viewing.get("persistedBytes"),
                },
                "container-index": {
                    "entries": container.get("entryCount"),
                    "bytes": container.get("totalBytes"),
                },
                "artwork": {
                    "entries": artwork.get("entryCount"),
                    "bytes": artwork.get("totalBytes"),
                },
            }

        return {
            "succeeded": True,
            "target": target,
            "interaction": response,
            "response": response,
            "beforeState": dict(before_snapshot),
            "postActionState": dict(after_snapshot),
            "storageObservation": {
                "schema": "enchron.regression.storage-clear-observation@1",
                "target": target,
                "store": store,
                "beforeCounts": counts(before_snapshot),
                "afterCounts": counts(after_snapshot),
                "protectedStateBefore": protected_before,
                "protectedStateAfter": protected_after,
                "protectedStatePreserved": True,
            },
        }

    def _window_control_plane_observation(self, context, *, required=True):
        plane, response = self._read_control_plane(context)
        if plane is None:
            if required:
                raise OperationAdapterError("window control plane is unavailable")
            return {"succeeded": False, "fields": {}, "response": {}}
        return {"succeeded": True, "fields": plane, "response": response}

    def _spatial_state_observation(
        self, context, *, deadline_seconds: int = 15
    ) -> dict[str, object]:
        started = getattr(time, "monotonic")()
        deadline = started + max(int(deadline_seconds), 1)
        last_response: dict[str, object] = {}
        while getattr(time, "monotonic")() < deadline:
            plane, last_response = self._read_control_plane(
                context,
                "PlayerUI-spatial-state",
            )
            if plane is not None:
                return {
                    "succeeded": True,
                    "fields": plane,
                    "response": last_response,
                }
            getattr(time, "sleep")(0.25)
        raise OperationAdapterError(
            "PlayerUI-spatial-state is unavailable after immersive controls summon"
        )

    def _optional_playback_state(self, context: OperationContext) -> dict[str, object]:
        plane, response = self._read_control_plane(
            context, "PlayerUI-playback-state"
        )
        if plane is None:
            return {
                "succeeded": False,
                "available": False,
                "fields": {},
                "response": response,
            }
        return {
            "succeeded": True,
            "available": True,
            "fields": plane,
            "session": plane.get("session"),
            "mediaName": plane.get("mediaName"),
            "response": response,
        }

    def _subtitle_window_state(
        self,
        context: OperationContext,
        *,
        include_screenshot: bool = False,
    ) -> dict[str, object]:
        """Read the channel operation:playback.select-subtitle@1 declares.

        The Operation's one evidence pair is window.control-plane, and its
        settlement predicate needs `transition`, which only
        windowPlaybackStateValue publishes (Apps/Enchron/MainView.swift:717).
        PlayerUI-playback-state carries neither that key nor the declared pair,
        so reading it here made the pair dishonest and the predicate
        unreachable. The control plane publishes every field this handler
        compares -- session, mediaName, sourceIdentity, contentRevision,
        collectionOrigin, playbackAddressKind, subtitleTrack, lifecycle,
        transition and error (MainView.swift:782-841).
        """
        plane, response = self._read_control_plane(
            context,
            "PlayerUI-window-control-plane",
            include_screenshot=include_screenshot,
        )
        if plane is None:
            raise OperationAdapterError(
                "subtitle selection window control plane is unavailable"
            )
        return {
            "succeeded": True,
            "fields": dict(plane),
            "response": response,
        }

    def _certificate_trust_probe(
        self,
        context: OperationContext,
        remote: Mapping[str, object],
    ) -> dict[str, object]:
        address = remote.get("certificateAddress")
        if not isinstance(address, str) or not address:
            raise OperationAdapterError(
                "certificate change observation omitted certificateAddress"
            )
        previous = _certificate_fingerprint(
            remote.get("priorCertificateFingerprint"),
            "priorCertificateFingerprint",
        )
        current = _certificate_fingerprint(
            remote.get("certificateFingerprint"),
            "certificateFingerprint",
        )
        response = self._app_command(
            context,
            "certificateTrustProbe",
            f"address={address}",
            f"expectedPrevious={previous}",
            f"expectedCurrent={current}",
        )
        self._require_success(response, "certificateTrustProbe")
        pairs = self._response_payload_pairs(response)
        if pairs.get("schema") != "enchron.regression.certificate-trust-probe@1":
            raise OperationAdapterError(
                "certificateTrustProbe returned the wrong schema"
            )
        observed = {
            "storedFingerprint": pairs["storedFingerprint"],
            "currentFingerprintTrusted": pairs["currentFingerprintTrusted"],
            "storedMatchesPreviousFingerprint": pairs[
                "storedMatchesPreviousFingerprint"
            ],
        }
        return {
            "storedFingerprint": pairs["storedFingerprint"],
            "previousFingerprint": pairs["previousFingerprint"],
            "currentFingerprint": pairs["currentFingerprint"],
            "currentFingerprintTrusted": pairs["currentFingerprintTrusted"],
            "storedMatchesPreviousFingerprint": pairs[
                "storedMatchesPreviousFingerprint"
            ],
            # The probe no longer decides the trust boundary by raising, so the
            # comparison travels as expected-beside-observed, the shape
            # operation:diagnostics.playback-state@1 already uses.
            "expectationObservation": {
                "expected": {
                    "storedFingerprint": previous,
                    "currentFingerprintTrusted": "false",
                    "storedMatchesPreviousFingerprint": "true",
                },
                "observed": observed,
                "trustBoundaryHeld": observed == {
                    "storedFingerprint": previous,
                    "currentFingerprintTrusted": "false",
                    "storedMatchesPreviousFingerprint": "true",
                },
            },
        }

    def _diagnostics_playback_state_1(
        self, arguments, context, *, include_screenshot=False
    ):
        plane, response = (
            self._read_control_plane(
                context,
                "PlayerUI-playback-state",
                include_screenshot=True,
            )
            if include_screenshot
            else self._read_control_plane(context, "PlayerUI-playback-state")
        )
        if plane is None:
            raise OperationAdapterError("playback-state probe is unavailable")
        identity: dict[str, str] = {}
        missing_identity_fields: list[str] = []
        for field in ("session", "audioTrack", "mediaName"):
            value = plane.get(field)
            if isinstance(value, str) and value:
                identity[field] = value
            else:
                identity[field] = "unavailable"
                missing_identity_fields.append(field)
        result: dict[str, object] = {
            "succeeded": True,
            **identity,
            "fields": plane,
            "response": response,
            "missingIdentityFields": missing_identity_fields,
            "relatedResults": list(arguments.get("relatedResults", [])),
        }
        has_remote_identity = any(
            plane.get(field) is not None
            for field in ("sourceIdentity", "contentRevision", *PLAYBACK_TOPOLOGY_FIELDS)
        )
        source_identity: str | None = None
        content_revision: str | None = None
        topology_digest: str | None = None
        if has_remote_identity:
            source_value = plane.get("sourceIdentity")
            revision_value = plane.get("contentRevision")
            source_identity = (
                source_value
                if isinstance(source_value, str) and source_value
                else "unavailable"
            )
            content_revision = (
                revision_value
                if isinstance(revision_value, str) and revision_value
                else "unavailable"
            )
            try:
                topology_digest = playback_topology_digest(plane)
            except OperationAdapterError:
                topology_digest = "unavailable"
            result.update(
                {
                    "sourceIdentity": source_identity,
                    "contentRevision": content_revision,
                    "topologyDigest": topology_digest,
                    "topologyFields": {
                        field: plane.get(field) for field in PLAYBACK_TOPOLOGY_FIELDS
                    },
                }
            )
        expectation = arguments.get("expectation")
        if expectation is None:
            return result
        for field in (
            "expectedSession",
            "expectedSourceIdentity",
            "expectedContentRevision",
            "expectedTopologyDigest",
        ):
            value = arguments.get(field)
            if isinstance(value, str) and value.startswith("result://"):
                raise OperationAdapterError(
                    "result references must be resolved before backend invocation"
                )
        try:
            position_millis = round(float(str(plane["position"])) * 1000)
        except (KeyError, TypeError, ValueError):
            position_millis = None
        try:
            reconnects = int(str(plane["demuxReconnects"]))
        except (KeyError, TypeError, ValueError):
            reconnects = None

        expected = {
            "session": arguments.get("expectedSession"),
            "sourceIdentity": arguments.get("expectedSourceIdentity"),
            "contentRevision": arguments.get("expectedContentRevision"),
            "topologyDigest": arguments.get("expectedTopologyDigest"),
        }
        observed: dict[str, object] = {
            "session": identity["session"],
            "sourceIdentity": source_identity,
            "contentRevision": content_revision,
            "topologyDigest": topology_digest,
        }
        binding: dict[str, object] = {
            "expectation": expectation,
            "session": identity["session"],
            "mediaName": identity["mediaName"],
            "lifecycle": plane.get("lifecycle"),
            "positionMillis": position_millis,
            "playbackAddressKind": plane.get("playbackAddressKind"),
            "collectionOrigin": plane.get("collectionOrigin"),
            "sourceIdentity": source_identity,
            "contentRevision": content_revision,
            "topologyDigest": topology_digest,
            "demuxReconnects": reconnects,
            "issueCategory": plane.get("error"),
        }
        binding_digest = "sha256:" + hashlib.sha256(
            json.dumps(
                binding,
                ensure_ascii=False,
                sort_keys=True,
                separators=(",", ":"),
            ).encode("utf-8")
        ).hexdigest()
        result.update(
            {
                "sourceIdentity": source_identity,
                "contentRevision": content_revision,
                "topologyDigest": topology_digest,
                "positionMillis": position_millis,
                "demuxReconnects": reconnects,
                "binding": binding,
                "bindingDigest": binding_digest,
                "expectationObservation": {
                    "expected": expected,
                    "minimumPositionMillis": int(
                        arguments.get("minimumPositionMillis", 0)
                    ),
                    "minimumReconnects": int(arguments.get("minimumReconnects", 0)),
                    "observed": observed,
                    "playbackAddressKind": plane.get("playbackAddressKind"),
                    "collectionOrigin": plane.get("collectionOrigin"),
                    "lifecycle": plane.get("lifecycle"),
                    "issueCategory": plane.get("error"),
                    "positionMillis": position_millis,
                    "demuxReconnects": reconnects,
                },
            }
        )
        return result

    def _playback_await_window_state_1(self, arguments, context):
        result = self._wait_for_window(
            context,
            presentation=str(arguments["presentation"]),
            lifecycle=str(arguments["lifecycle"]),
            controls=str(arguments["controls"]),
            deadline_seconds=int(arguments["deadlineSeconds"]),
        )
        playback_observation = self._diagnostics_playback_state_1({}, context)
        return {
            **result,
            "fields": result.get("fields", {}),
            "response": result.get("response", {}),
            "playbackObservation": playback_observation,
        }

    def _playback_wait_position_2(self, arguments, context):
        for field in ("expectedMediaName", "differentSessionFrom"):
            value = arguments.get(field)
            if isinstance(value, str) and value.startswith("result://"):
                raise OperationAdapterError(
                    "result references must be resolved before backend invocation"
                )
        return self._wait_for_window(
            context,
            presentation="either-main-window",
            lifecycle="any-steady",
            controls="either",
            deadline_seconds=int(arguments["deadlineSeconds"]),
            position_millis=int(arguments["minimumPositionMillis"]),
            remaining_millis=int(arguments["minimumRemainingMillis"]),
            expected_media_name=(
                str(arguments["expectedMediaName"])
                if "expectedMediaName" in arguments
                else None
            ),
            different_session_from=(
                str(arguments["differentSessionFrom"])
                if "differentSessionFrom" in arguments
                else None
            ),
        )

    def _seek_steady_position_millis(self, fields: Mapping[str, str]) -> int | None:
        """The observed position once the runtime is no longer moving it itself."""
        if str(fields.get("transition", "none")) != "none":
            return None
        if str(fields.get("seekInProgress", "false")).lower() == "true":
            return None
        if str(fields.get("lifecycle", "")).lower() not in (
            "playing",
            "ready",
            "paused",
            "ended",
        ):
            return None
        try:
            return round(float(fields["position"]) * 1000)
        except (KeyError, TypeError, ValueError):
            return None

    def _require_seek_identity(
        self,
        fields: Mapping[str, str],
        session: object,
        media_name: object,
        expected_revision: object,
    ) -> None:
        if fields.get("session") != session:
            raise OperationAdapterError(
                "playback session changed while applying seek"
            )
        if fields.get("mediaName") != media_name:
            raise OperationAdapterError(
                "media identity changed while applying seek"
            )
        if (
            expected_revision not in (None, "", "none", "unavailable")
            and fields.get("contentRevision") != expected_revision
        ):
            raise OperationAdapterError(
                "content revision changed while applying seek"
            )

    def _playback_seek_2(self, arguments, context):
        before = self._diagnostics_playback_state_1({}, context)
        before_fields = before.get("fields")
        if not isinstance(before_fields, Mapping):
            raise OperationAdapterError("seek pre-state omitted playback fields")
        session = before.get("session")
        media_name = before.get("mediaName")
        if session in (None, "", "none", "unavailable"):
            raise OperationAdapterError("seek pre-state omitted its playback session")
        if media_name in (None, "", "none", "unavailable"):
            raise OperationAdapterError("seek pre-state omitted its media identity")
        try:
            duration_millis = round(float(str(before_fields["duration"])) * 1000)
        except (KeyError, TypeError, ValueError) as error:
            raise OperationAdapterError(
                "seek pre-state omitted a numeric media duration"
            ) from error
        if duration_millis <= 0:
            raise OperationAdapterError("seek requires positive media duration")
        summon = None
        if arguments.get("summonControls") is True:
            summon = self._app_command(context, "toggleControls", "visible=true")
            self._require_success(summon, "seek controls summon")
        target = int(arguments["positionMillionths"]) / 1_000_000
        target_millis = round(duration_millis * target)
        tolerance_millis = 1_500
        expected_revision = before_fields.get("contentRevision")
        matrix = self._matrix(context)
        cursor = matrix.probe_cursor(self._probe_lines(context))
        deadline = getattr(time, "monotonic")() + PROGRESS_SEEK_DEADLINE_SECONDS
        observations: list[dict[str, object]] = []
        taps: list[dict[str, object]] = []
        last_response: dict[str, object] = {}
        action: dict[str, object] = {}
        offset = target
        while len(taps) < PROGRESS_SEEK_TAP_LIMIT and getattr(time, "monotonic")() < deadline:
            action = self._controller(
                context,
                "coordinateTap",
                "--identifier",
                "PlayerPanel-progress",
                "--normalized-x",
                f"{offset:.6f}",
                "--normalized-y",
                "0.500000",
            )
            self._require_success(action, "playback progress tap")
            landed_millis: int | None = None
            while getattr(time, "monotonic")() < deadline:
                fields, last_response = self._read_control_plane(context)
                if fields is not None:
                    observations.append(dict(fields))
                    self._require_seek_identity(
                        fields, session, media_name, expected_revision
                    )
                    landed_millis = self._seek_steady_position_millis(fields)
                    if landed_millis is not None:
                        break
                getattr(time, "sleep")(0.25)
            delta, cursor, _ = matrix.probe_lines_since(
                self._probe_lines(context), cursor
            )
            delivery = [line for line in delta if PROGRESS_SEEK_PROBE_LINE in line]
            taps.append(
                {
                    "normalizedOffset": round(offset, 6),
                    "landedPositionMillis": landed_millis,
                    "deliveryLines": delivery,
                    "response": action,
                }
            )
            if not delivery:
                raise OperationAdapterError(
                    "the progress tap reached no product-side seek delivery: "
                    f"{taps[-1]}"
                )
            if landed_millis is None:
                break
            if abs(landed_millis - target_millis) <= tolerance_millis:
                terminal = observations[-1]
                after = {
                    "succeeded": True,
                    "session": str(session),
                    "mediaName": str(media_name),
                    "fields": terminal,
                    "response": last_response,
                }
                return {
                    "succeeded": True,
                    "drive": "progress-track-tap",
                    "before": before,
                    "summon": summon,
                    "action": action,
                    "settlement": {
                        "targetPositionMillis": target_millis,
                        "positionToleranceMillis": tolerance_millis,
                        "terminal": terminal,
                        "observations": observations,
                        "taps": taps,
                    },
                    "after": after,
                    "identityObservation": {
                        "session": session,
                        "mediaName": media_name,
                        "contentRevision": expected_revision,
                        "sessionPreserved": True,
                        "mediaPreserved": True,
                        "contentRevisionPreserved": (
                            expected_revision in (None, "", "none", "unavailable")
                            or terminal.get("contentRevision") == expected_revision
                        ),
                    },
                }
            offset = min(
                max(offset + (target_millis - landed_millis) / duration_millis, 0.0),
                1.0,
            )
        return {
            "succeeded": False,
            "drive": "progress-track-tap",
            "before": before,
            "summon": summon,
            "action": action,
            "reason": "seek-settlement-deadline-expired",
            "settlement": {
                "targetPositionMillis": target_millis,
                "positionToleranceMillis": tolerance_millis,
                "observations": observations,
                "taps": taps,
                "lastController": last_response,
            },
        }

    @staticmethod
    def _external_subtitle_source_kind(fields: Mapping[str, object]) -> str:
        origin = fields.get("collectionOrigin")
        address = fields.get("playbackAddressKind")
        if origin == "mediaLibrary" and address == "local-file":
            return "local-sidecar"
        if origin == "sourceDirectory" and address in ("loopback", "remote-url"):
            return "source-directory-sidecar"
        if origin == "mediaServer" and address in ("loopback", "remote-url"):
            return "emby-external-stream"
        raise OperationAdapterError(
            "playback state does not expose a closed external subtitle source kind: "
            f"collectionOrigin={origin!r} playbackAddressKind={address!r}"
        )

    @staticmethod
    def _subtitle_playback_identity(
        state: Mapping[str, object],
    ) -> dict[str, str]:
        fields = state.get("fields")
        if not isinstance(fields, Mapping):
            raise OperationAdapterError(
                "subtitle selection playback state omitted its fields"
            )
        identity: dict[str, str] = {}
        for name in ("session", "mediaName", "sourceIdentity", "contentRevision"):
            value = fields.get(name)
            if not isinstance(value, str) or value in ("", "none", "unavailable"):
                raise OperationAdapterError(
                    f"subtitle selection playback state omitted {name}"
                )
            if name in ("sourceIdentity", "contentRevision") and re.fullmatch(
                r"sha256:[0-9a-f]{64}", value
            ) is None:
                raise OperationAdapterError(
                    f"subtitle selection playback state has invalid {name}"
                )
            identity[name] = value
        return identity

    def _select_public_subtitle_item(
        self,
        context: OperationContext,
        *,
        host: str,
        external_source_kind: str,
        track_label: object,
    ) -> tuple[dict[str, object], dict[str, object] | None]:
        if host == "playerPanel":
            summon = self._app_command(context, "toggleControls", "visible=true")
            self._require_success(summon, "playerPanel controls summon")
            route = (
                "PlayerPanel-menu-more",
                "PlayerPanel-menu-subtitles",
            )
            menu_prefix = "PlayerPanel-menu-subtitle-"
        else:
            route = (
                "PlayerUI-window-playback-surface",
                "PlayerUI-TopAction-more",
                "PlayerUI-menu-subtitles",
            )
            menu_prefix = "PlayerUI-menu-subtitles-"
        selection_prefix = menu_prefix + "external.subtitle."
        command = [
            "--identifiers",
            *route,
            "--identifier-prefix",
            selection_prefix,
        ]
        if track_label is not None:
            command.extend(("--label", str(track_label)))
        response = self._controller(
            context,
            "tapFirstMatch",
            *command,
        )
        if response.get("success") is not True:
            if "found no matching public element" in str(response.get("message", "")):
                return response, None
            self._require_success(response, "public subtitle selection")
        matched = response.get("matchedElement")
        if not isinstance(matched, Mapping):
            raise OperationAdapterError(
                "public subtitle selection omitted its matched element"
            )
        identifier = matched.get("identifier")
        label = matched.get("label")
        selected = matched.get("isSelected")
        if not isinstance(identifier, str) or not identifier.startswith(
            selection_prefix
        ):
            raise OperationAdapterError(
                "public subtitle selection returned an unexpected identifier"
            )
        if not isinstance(label, str) or not label:
            raise OperationAdapterError(
                "public subtitle selection omitted its track label"
            )
        if type(selected) is not bool:
            raise OperationAdapterError(
                "public subtitle selection omitted its selected state"
            )
        return response, {
            "id": identifier.removeprefix(menu_prefix),
            "label": label,
            "sourceKind": external_source_kind,
            "isSelected": selected,
        }

    def _playback_select_subtitle_1(self, arguments, context):
        host = str(arguments["host"])
        expected_source_kind = str(arguments["sourceKind"])
        track_label = arguments.get("trackLabel")
        deadline_seconds = int(arguments["deadlineSeconds"])
        before = self._subtitle_window_state(context)
        before_fields = before.get("fields")
        if not isinstance(before_fields, Mapping):
            raise OperationAdapterError(
                "subtitle selection pre-state omitted playback fields"
            )
        actual_source_kind = self._external_subtitle_source_kind(before_fields)
        if actual_source_kind != expected_source_kind:
            raise OperationAdapterError(
                "subtitle source kind differs from the current product source: "
                f"expected={expected_source_kind} actual={actual_source_kind}"
            )
        identity = self._subtitle_playback_identity(before)
        preserved_identity = {
            **identity,
            "sessionPreserved": True,
            "mediaPreserved": True,
            "sourceIdentityPreserved": True,
            "contentRevisionPreserved": True,
        }
        selection_response, selected_before = self._select_public_subtitle_item(
            context,
            host=host,
            external_source_kind=actual_source_kind,
            track_label=track_label,
        )
        discovered_tracks = [] if selected_before is None else [selected_before]
        if selected_before is None:
            return {
                "succeeded": True,
                "fields": before_fields,
                "response": before["response"],
                "frames": [],
                "semanticOutcome": "candidate-missing",
                "selectionSettled": False,
                "host": host,
                "sourceKind": actual_source_kind,
                "deadlineSeconds": deadline_seconds,
                "reason": "subtitle-candidate-missing",
                "requestedTrackLabel": track_label,
                "discoveryResponse": selection_response,
                "discoveredTracks": discovered_tracks,
                "selectedTrack": None,
                "selectionResponse": None,
                "beforeState": before,
                "postActionState": before,
                "postActionMenu": selection_response,
                "identityObservation": preserved_identity,
                "settlement": {
                    "outcome": "candidate-missing",
                    "observations": [],
                    "terminalTrackID": None,
                },
            }
        target_id = str(selected_before["id"])
        target_label = str(selected_before["label"])

        started = getattr(time, "monotonic")()
        deadline = started + deadline_seconds
        observations: list[dict[str, object]] = []
        frames: list[dict[str, object]] = []
        last_state: Mapping[str, object] | None = None
        while getattr(time, "monotonic")() < deadline:
            current = self._subtitle_window_state(
                context, include_screenshot=True
            )
            current_fields = current.get("fields")
            if not isinstance(current_fields, Mapping):
                raise OperationAdapterError(
                    "subtitle selection post-state omitted playback fields"
                )
            current_identity = self._subtitle_playback_identity(current)
            for name, expected in identity.items():
                if current_identity[name] != expected:
                    label = {
                        "session": "playback session",
                        "mediaName": "media identity",
                        "sourceIdentity": "byte-source identity",
                        "contentRevision": "content revision",
                    }[name]
                    raise OperationAdapterError(
                        f"{label} changed while selecting subtitle"
                    )
            current_source_kind = self._external_subtitle_source_kind(
                current_fields
            )
            if current_source_kind != actual_source_kind:
                raise OperationAdapterError(
                    "external subtitle source kind changed during selection"
                )
            observations.append(
                {
                    "fields": dict(current_fields),
                    "targetSelected": current_fields.get("subtitleTrack") == target_id,
                }
            )
            frames.append(
                {
                    "index": len(observations) - 1,
                    "record": current["response"],
                    "fields": dict(current_fields),
                }
            )
            frames = frames[-3:]
            last_state = current
            lifecycle = str(current_fields.get("lifecycle", "")).lower()
            settled = (
                current_fields.get("subtitleTrack") == target_id
                and lifecycle in ("playing", "ready", "paused", "ended")
                and current_fields.get("transition") == "none"
                and current_fields.get("error") == "none"
            )
            if settled:
                selected_track = {
                    "id": target_id,
                    "label": target_label,
                    "sourceKind": actual_source_kind,
                    "isSelectedBefore": selected_before["isSelected"],
                    "isSelectedAfter": True,
                }
                return {
                    "succeeded": True,
                    "fields": current_fields,
                    "response": current["response"],
                    "frames": frames,
                    "semanticOutcome": "selected",
                    "selectionSettled": True,
                    "host": host,
                    "sourceKind": actual_source_kind,
                    "deadlineSeconds": deadline_seconds,
                    "discoveryResponse": selection_response,
                    "discoveredTracks": discovered_tracks,
                    "selectedTrack": selected_track,
                    "selectionResponse": selection_response,
                    "beforeState": before,
                    "postActionState": current,
                    "postActionMenu": selection_response,
                    "identityObservation": preserved_identity,
                    "settlement": {
                        "outcome": "selected",
                        "observations": observations,
                        "terminalTrackID": target_id,
                    },
                }
            getattr(time, "sleep")(0.25)
        return {
            "succeeded": True,
            "fields": (
                last_state["fields"] if last_state is not None else before_fields
            ),
            "response": (
                last_state["response"]
                if last_state is not None
                else before["response"]
            ),
            "frames": frames,
            "semanticOutcome": "selection-not-settled",
            "selectionSettled": False,
            "host": host,
            "sourceKind": actual_source_kind,
            "deadlineSeconds": deadline_seconds,
            "reason": "subtitle-selection-deadline-expired",
            "discoveryResponse": selection_response,
            "discoveredTracks": discovered_tracks,
            "selectedTrack": {
                "id": target_id,
                "label": target_label,
                "sourceKind": actual_source_kind,
                "isSelectedBefore": selected_before["isSelected"],
                "isSelectedAfter": False,
            },
            "selectionResponse": selection_response,
            "beforeState": before,
            "postActionState": last_state,
            "postActionMenu": selection_response,
            "identityObservation": preserved_identity,
            "settlement": {
                "outcome": "selection-not-settled",
                "observations": observations,
                "terminalTrackID": (
                    None
                    if last_state is None
                    else last_state.get("fields", {}).get("subtitleTrack")
                    if isinstance(last_state.get("fields"), Mapping)
                    else None
                ),
            },
        }

    def _raise_playback_chrome(self, arguments, context, reason):
        """Raise the window chrome this Operation's own route depends on.

        The default route taps PlayerUI-window-playback-surface, which is a
        bare showControls.toggle() (PlaybackSessionModel.swift:579-589): it
        raises the chrome only when the chrome is already down. A caller that
        has just finished a summonControls activation, or that reached a
        presentation without a visual cutover, arrives here with the chrome up
        and the tap hides it, taking WindowPlayerDeckView and its top actions
        out of the hierarchy with it (MainView.swift:222-234, :273) before the
        following tapSequence looks for them. summonControls asks for the
        documented summon route instead (references/product.md:35): the
        toggleControls app command, which switches only when the requested
        visibility differs from the current one
        (TestCommandChannel.swift:1070-1074) and therefore ends with the chrome
        up whatever the previous call left behind.
        """
        if arguments.get("summonControls") is True:
            summon = self._app_command(context, "toggleControls", "visible=true")
        else:
            summon = self._controller(
                context,
                "tap",
                "--identifier",
                "PlayerUI-window-playback-surface",
            )
        self._require_success(summon, reason)
        return summon

    def _format_apply_2(self, arguments, context):
        projection_value = str(arguments["projection"])
        projection_identifier = {
            "flat": "PlayerUI-VideoFormat-Projection-Flat",
            "equirectangular180": "PlayerUI-VideoFormat-Projection-180°",
            "equirectangular360": "PlayerUI-VideoFormat-Projection-360°",
        }.get(projection_value)
        stereo = {
            "mono": "PlayerUI-VideoFormat-Stereo Layout-Mono",
            "sideBySide": "PlayerUI-VideoFormat-Stereo Layout-Side-by-Side",
            "topBottom": "PlayerUI-VideoFormat-Stereo Layout-Top-Bottom",
        }[str(arguments["stereoLayout"])]
        before = self._window_control_plane_observation(context)
        summon = self._raise_playback_chrome(
            arguments, context, "format controls summon"
        )
        editor_sequence = None
        coverage_selection = None
        coverage_dismissal = None
        if projection_value == "customAngle":
            coverage = int(arguments.get("horizontalCoverageDegrees", 200))
            # The per-degree rows are Text inside an inline Picker, and SwiftUI
            # discards their .accessibilityIdentifier, so no
            # PlayerUI-VideoFormat-CustomAngle-<degrees> element ever reaches
            # the hierarchy. The product ships the compensating receiver that
            # Config/reachability_operation_inventory.json registers as the
            # debugEquivalent of accessibility:PlayerUI-VideoFormat-CustomAngle:
            # open the named Picker for real, enumerate and select through
            # listMenuItems/selectMenuItem, then dismiss the open menu by the
            # row's own label. This is the route reachability_matrix drives.
            editor_sequence = self._controller(
                context,
                "tapSequence",
                "--identifiers",
                "PlayerUI-TopAction-videoFormat",
                "PlayerUI-VideoFormat-CustomAngle",
            )
            self._require_success(editor_sequence, "custom angle picker")
            listing = self._app_command(
                context,
                "listMenuItems",
                "host=playerUI",
                "family=customAngle",
            )
            self._require_success(listing, "custom angle menu listing")
            selection = self._app_command(
                context,
                "selectMenuItem",
                "host=playerUI",
                "family=customAngle",
                f"target={coverage}",
            )
            self._require_success(selection, "custom angle selection")
            coverage_selection = {"listing": listing, "selection": selection}
            coverage_dismissal = self._controller(
                context,
                "tap",
                "--label",
                f"{coverage}°",
            )
            self._require_success(coverage_dismissal, "custom angle dismissal")
            identifiers = (
                stereo,
                "PlayerUI-VideoFormat-apply",
            )
        else:
            assert projection_identifier is not None
            identifiers = (
                "PlayerUI-TopAction-videoFormat",
                projection_identifier,
                stereo,
                "PlayerUI-VideoFormat-apply",
            )
        action = self._controller(
            context,
            "tapSequence",
            "--identifiers",
            *identifiers,
        )
        self._require_success(action, "format apply")
        expected = "window" if projection_value == "flat" else "portal"
        expected_coverage = {
            "flat": 200,
            "equirectangular180": 180,
            "equirectangular360": 360,
            "customAngle": int(arguments.get("horizontalCoverageDegrees", 200)),
        }[projection_value]
        settlement = self._wait_for_window(
            context,
            presentation="either-main-window",
            lifecycle="any-steady",
            controls="either",
            deadline_seconds=int(arguments["deadlineSeconds"]),
        )
        after = self._window_control_plane_observation(context)
        observed = after["fields"]
        assert isinstance(observed, Mapping)
        capture_request = {
            "context": expected,
            "count": 3,
            "minimumIntervalMillis": 1000,
        }
        capture = self._evidence_capture_frames_1(capture_request, context)
        return {
            **capture,
            "succeeded": after["succeeded"],
            "artifactRoot": capture["artifactRoot"],
            "frames": capture["frames"],
            "fields": capture["fields"],
            "response": capture["response"],
            "requested": dict(arguments),
            "before": before,
            "summon": summon,
            "customAnglePicker": editor_sequence,
            "customAngleSelection": coverage_selection,
            "customAngleDismissal": coverage_dismissal,
            "action": action,
            "settlement": settlement,
            "after": after,
            "captureRequest": capture_request,
            "formatObservation": {
                "expected": {
                    "presentation": expected,
                    "projection": projection_value,
                    "horizontalFieldOfViewDegrees": str(expected_coverage),
                    "stereoLayout": str(arguments["stereoLayout"]),
                },
                "observed": {
                    "presentation": observed.get("presentation"),
                    "projection": observed.get("projection"),
                    "horizontalFieldOfViewDegrees": observed.get(
                        "horizontalFieldOfViewDegrees"
                    ),
                    "stereoLayout": observed.get("stereoLayout"),
                },
            },
        }

    def _presentation_enter_docked_skybox_1(self, arguments, context):
        summon = self._raise_playback_chrome(
            arguments, context, "docked controls summon"
        )
        result = self._enter_spatial(
            context,
            "docked",
            int(arguments["deadlineSeconds"]),
            "PlayerUI-TopAction-dock",
            "PlayerUI-DockMenu-skybox",
        )
        return {**result, "summon": summon}

    def _presentation_enter_panorama_1(self, arguments, context):
        summon = self._raise_playback_chrome(
            arguments, context, "panorama controls summon"
        )
        if arguments.get("expectedResult") == "rollback-after-settlement-timeout":
            result = self._enter_panorama_expecting_settlement_rollback(
                context,
                int(arguments["deadlineSeconds"]),
            )
        else:
            result = self._enter_spatial(
                context,
                "panorama",
                int(arguments["deadlineSeconds"]),
                "PlayerUI-TopAction-resumePanorama",
            )
        snapshot, transition_response = self._transition_trace_observation(
            context
        )
        action = result.get("action")
        # tapSequence publishes matchedElement: nil, so the Enter Panorama
        # element can only be named by the pre-tap observation the runner now
        # records for each route step.
        route_elements = [
            item
            for item in result.get("routeElements", [])
            if isinstance(item, Mapping)
            and item.get("identifier") == "PlayerUI-TopAction-resumePanorama"
        ]
        pre_action_matched_element = (
            dict(route_elements[0])
            if route_elements
            else dict(action["matchedElement"])
            if isinstance(action, Mapping)
            and isinstance(action.get("matchedElement"), Mapping)
            else None
        )
        return {
            **result,
            "summon": summon,
            "preActionMatchedElement": pre_action_matched_element,
            "snapshot": snapshot,
            "transitionResponse": transition_response,
            "response": transition_response,
        }

    def _enter_panorama_expecting_settlement_rollback(
        self,
        context: OperationContext,
        deadline_seconds: int,
    ) -> dict[str, object]:
        matrix = self._matrix(context)
        started = getattr(time, "monotonic")()
        action = self._controller(
            context,
            "tapSequence",
            "--identifiers",
            "PlayerUI-TopAction-resumePanorama",
        )
        self._require_success(action, "enter panorama for settlement rollback")
        deadline = started + deadline_seconds
        observations: list[dict[str, object]] = []
        last_response: dict[str, object] = {}
        while getattr(time, "monotonic")() < deadline:
            plane, last_response = self._read_control_plane(context)
            elapsed = round((getattr(time, "monotonic")() - started) * 1000)
            if plane is not None:
                observations.append({"elapsedMillis": elapsed, "fields": plane})
                diagnostic = plane.get("conversionDiagnostic", "")
                resolution = plane.get("lastExecutionResolution", "")
                settled = (
                    plane.get("presentation") == "portal"
                    and plane.get("transition") == "none"
                    and plane.get("pendingSpatialEffect") == "none"
                    and plane.get("attached") == "portal"
                    and plane.get("rendererConsumer") == "portal"
                    and plane.get("rendererConsumerEntity") == "present"
                    and plane.get("lastPlatformOperation")
                    == "spatial-surface-settlement-failed"
                    and plane.get("lastExecutionCheckpoint")
                    == "presentation-rollback-settled-portal"
                    and "presentationRolledBack" in resolution
                    and "operation=spatial-surface-settlement-failed" in diagnostic
                    and plane.get("error") == "surfaceAttachmentFailed"
                    and plane.get("liveTechnicalSessions") == "1"
                    and plane.get("retiringTechnicalSessions") == "0"
                    and (plane.get("lifecycle") or "").lower() == "playing"
                )
                if settled:
                    return {
                        "succeeded": True,
                        "action": action,
                        "settlement": {
                            "verdict": matrix.PASS,
                            "actualPresentation": "portal",
                            "elapsedMillis": elapsed,
                            "terminal": plane,
                            "observations": observations,
                        },
                    }
            getattr(time, "sleep")(0.25)
        return {
            "succeeded": False,
            "action": action,
            "settlement": {
                "verdict": matrix.STALL_TIMEOUT,
                "reason": "rollback-terminal-state-not-observed",
                "elapsedMillis": round((getattr(time, "monotonic")() - started) * 1000),
                "observations": observations,
                "lastResponse": last_response,
            },
        }

    def _enter_spatial(self, context, expected, deadline_seconds, *identifiers):
        matrix = self._matrix(context)
        lines = self._probe_lines(context)
        cursor = matrix.probe_cursor(lines)
        started = getattr(time, "monotonic")()
        action = self._controller(context, "tapSequence", "--identifiers", *identifiers)
        self._require_success(action, f"enter {expected}")
        route_elements = action.get("routeElements")
        if not isinstance(route_elements, list) or len(route_elements) != len(
            identifiers
        ):
            raise OperationAdapterError(
                f"enter {expected} did not record one route element per step"
            )
        deadline = started + deadline_seconds
        delta: list[str] = []
        observed = cursor
        copy_error: str | None = None
        while getattr(time, "monotonic")() < deadline:
            current, copy_error = matrix.copy_probe_lines(
                context.attempt_root,
                target=context.target,
            )
            if current is not None:
                delta, observed, _ = matrix.probe_lines_since(current, cursor)
                if matrix.last_settlement_settled(delta) is True:
                    actual = matrix.appeared_presentation(delta) or expected
                    succeeded = actual == expected
                    return {
                        "succeeded": succeeded,
                        "action": action,
                        "routeElements": list(route_elements),
                        "probe": delta,
                        "cursorToken": f"{observed.sequence if observed.sequence is not None else -1}:{observed.line_count}",
                        "settlement": {
                            "verdict": matrix.PASS if succeeded else matrix.WRONG_STATE,
                            "actualPresentation": actual,
                            "elapsedMillis": round((getattr(time, "monotonic")() - started) * 1000),
                        },
                    }
            getattr(time, "sleep")(0.5)
        return {
            "succeeded": False,
            "action": action,
            "routeElements": list(route_elements),
            "probe": delta,
            "cursorToken": f"{observed.sequence if observed.sequence is not None else -1}:{observed.line_count}",
            "settlement": {
                "verdict": matrix.DRIVE_ERROR if copy_error else matrix.STALL_TIMEOUT,
                "reason": copy_error or "deadline-expired",
                "elapsedMillis": round((getattr(time, "monotonic")() - started) * 1000),
            },
        }

    def _presentation_exit_spatial_1(self, arguments, context):
        summon = self._app_command(context, "toggleControls", "visible=true")
        self._require_success(summon, "immersive controls summon")
        spatial_state = self._spatial_state_observation(context)
        action = self._controller(context, "tap", "--identifier", "PlayerPanel-button-exit-spatial")
        self._require_success(action, "exit spatial")
        expected = "window" if arguments["from"] == "docked" else "portal"
        settlement = self._wait_for_window(
            context,
            presentation=expected,
            lifecycle="any-steady",
            controls="either",
            deadline_seconds=int(arguments["deadlineSeconds"]),
        )
        snapshot, transition_response = self._transition_trace_observation(
            context
        )
        return {
            "succeeded": settlement["succeeded"],
            "summon": summon,
            "spatialState": spatial_state,
            "action": action,
            "settlement": settlement,
            "snapshot": snapshot,
            "transitionResponse": transition_response,
            "fields": settlement.get("fields", {}),
            "response": settlement.get("response", {}),
        }

    def _transition_trace_observation(self, context):
        response = self._app_command(context, "fetchTransitionTraceSnapshot")
        self._require_success(response, "fetchTransitionTraceSnapshot")
        snapshot = response.get("transitionTraceSnapshot")
        if not isinstance(snapshot, Mapping):
            raise OperationAdapterError(
                "transition trace observation omitted its typed snapshot"
            )
        return dict(snapshot), response

    def _transition_trace_arm_1(self, arguments, context):
        prior_response = self._app_command(
            context, "fetchTransitionTraceSnapshot"
        )
        self._require_success(prior_response, "fetchTransitionTraceSnapshot before arm")
        prior_snapshot = prior_response.get("transitionTraceSnapshot")
        if not isinstance(prior_snapshot, Mapping):
            raise OperationAdapterError(
                "transition trace pre-arm probe omitted its typed snapshot"
            )
        prior_generation = prior_snapshot.get("generation")
        if type(prior_snapshot.get("isArmed")) is not bool:
            raise OperationAdapterError(
                "transition trace pre-arm probe omitted its armed state"
            )
        prior_cleanup: dict[str, object] = {
            "generationToken": str(prior_generation),
            "wasArmed": prior_snapshot["isArmed"],
            "disarmed": False,
            "response": None,
        }
        if prior_snapshot["isArmed"] is True:
            if not isinstance(prior_generation, (str, int)) or isinstance(
                prior_generation, bool
            ):
                raise OperationAdapterError(
                    "transition trace pre-arm probe omitted its generation"
                )
            cleanup_response = self._app_command(
                context,
                "disarmTransitionTrace",
                f"generation={prior_generation}",
            )
            self._require_success(cleanup_response, "stale transition trace disarm")
            prior_cleanup.update(
                {"disarmed": True, "response": cleanup_response}
            )
        command_arguments = ()
        if "fault" in arguments:
            command_arguments = (f"fault={arguments['fault']}",)
        response = self._app_command(
            context,
            "armTransitionTrace",
            *command_arguments,
        )
        self._require_success(response, "armTransitionTrace")
        payload = self._response_payload_pairs(response)
        generation = payload.get("generation")
        capacity_text = payload.get("capacity")
        try:
            capacity = int(capacity_text) if capacity_text is not None else None
        except ValueError as error:
            raise OperationAdapterError(
                "armTransitionTrace returned a non-integer capacity"
            ) from error
        if generation is None or capacity is None:
            raise OperationAdapterError("armTransitionTrace omitted generation or capacity")
        expected_fault = str(arguments.get("fault", "none"))
        if payload.get("fault", expected_fault) != expected_fault:
            raise OperationAdapterError(
                "armTransitionTrace returned a different fault binding"
            )
        return {
            "succeeded": True,
            "response": response,
            "generationToken": str(generation),
            "capacity": capacity,
            "fault": expected_fault,
            "priorCleanup": prior_cleanup,
        }

    def _transition_trace_fetch_1(self, arguments, context):
        if str(arguments["generationToken"]).startswith("result://"):
            raise OperationAdapterError("result references must be resolved before backend invocation")
        response = self._app_command(context, "fetchTransitionTraceSnapshot")
        self._require_success(response, "fetchTransitionTraceSnapshot")
        snapshot = response.get("transitionTraceSnapshot")
        if not isinstance(snapshot, dict):
            raise OperationAdapterError("transition response omitted its typed snapshot")
        if str(snapshot.get("generation")) != str(arguments["generationToken"]):
            raise OperationAdapterError("transition snapshot generation does not match arm token")
        analysis = response.get("transitionTraceAnalysis")
        if analysis is not None and not isinstance(analysis, dict):
            raise OperationAdapterError("transition response returned a malformed analysis")
        terminal, terminal_response = self._read_control_plane(context)
        return {
            "succeeded": True,
            "response": response,
            "snapshot": snapshot,
            "analysis": analysis,
            "terminalState": terminal,
            "terminalResponse": terminal_response,
            "terminalStateAvailable": terminal is not None,
        }

    def _transition_trace_disarm_1(self, arguments, context):
        if str(arguments["generationToken"]).startswith("result://"):
            raise OperationAdapterError("result references must be resolved before backend invocation")
        response = self._app_command(context, "disarmTransitionTrace", f"generation={arguments['generationToken']}")
        self._require_success(response, "disarmTransitionTrace")
        post_response = self._app_command(context, "fetchTransitionTraceSnapshot")
        self._require_success(post_response, "fetchTransitionTraceSnapshot after disarm")
        snapshot = post_response.get("transitionTraceSnapshot")
        if not isinstance(snapshot, Mapping):
            raise OperationAdapterError(
                "transition trace post-disarm probe omitted its typed snapshot"
            )
        if (
            str(snapshot.get("generation")) != str(arguments["generationToken"])
            or snapshot.get("isArmed") is not False
        ):
            raise OperationAdapterError(
                "transition trace remained armed after generation-bound disarm"
            )
        terminal, terminal_response = self._read_control_plane(context)
        return {
            "succeeded": True,
            "response": post_response,
            "disarmResponse": response,
            "generationToken": arguments["generationToken"],
            "disarmed": True,
            "snapshot": dict(snapshot),
            "postActionState": dict(snapshot),
            "postActionResponse": post_response,
            "terminalState": terminal,
            "terminalResponse": terminal_response,
            "terminalStateAvailable": terminal is not None,
        }

    def _evidence_capture_audio_2(self, arguments, context):
        for field in ("expectedSession", "expectedAudioTrackID"):
            value = arguments.get(field)
            if isinstance(value, str) and value.startswith("result://"):
                raise OperationAdapterError(
                    "result references must be resolved before backend invocation"
                )
        before = self._diagnostics_playback_state_1({}, context)
        before_identity = {
            field: (
                str(before[field])
                if isinstance(before.get(field), str) and before[field]
                else "unavailable"
            )
            for field in ("session", "audioTrack", "mediaName")
        }
        expected = {
            "session": arguments.get("expectedSession"),
            "audioTrack": arguments.get("expectedAudioTrackID"),
        }
        wav = self._resolve_attempt_path(context, str(arguments["wavPath"]))
        measured = self._run_json(
            [
                sys.executable,
                "Scripts/verification/journey_audio_probe.py",
                "--device",
                str(arguments["inputDevice"]),
                "--seconds",
                f"{int(arguments['durationMillis']) / 1000:.3f}",
                "--output",
                str(wav),
            ],
            budget_seconds=int(arguments["durationMillis"]) / 1000 + 60,
        )
        after = self._diagnostics_playback_state_1({}, context)
        after_identity = {
            field: (
                str(after[field])
                if isinstance(after.get(field), str) and after[field]
                else "unavailable"
            )
            for field in ("session", "audioTrack", "mediaName")
        }
        measurement = {**measured, **before_identity}
        return {
            "succeeded": True,
            **before_identity,
            "measurement": measurement,
            "wavPath": str(wav.relative_to(context.attempt_root)),
            "beforePlaybackState": before,
            "afterPlaybackState": after,
            "identityObservation": {
                "expected": expected,
                "before": before_identity,
                "after": after_identity,
            },
        }

    def _input_device_hub_prepare_1(self, arguments, context):
        result = self._run_json(
            [
                sys.executable,
                "Scripts/verification/device_hub_canvas.py",
                "--device",
                context.target,
                "enlarge",
            ],
            **{"timeout": 120},
        )
        self._require_device_hub_binding(result, context)
        canvas = result.get("canvas")
        if (
            not isinstance(canvas, Mapping)
            or type(canvas.get("width")) is not int
            or canvas["width"] < 1200
        ):
            raise OperationAdapterError(
                "Device Hub prepare did not establish a targetable canvas"
            )
        return {"succeeded": True, **result}

    def _input_device_hub_pinch_2(self, arguments, context):
        def bind_product_state(
            interaction: Mapping[str, object],
        ) -> dict[str, object]:
            snapshot = self._controller(context, "snapshot", "--no-screenshot")
            self._require_success(snapshot, "Device Hub post-action product snapshot")
            return {
                "succeeded": True,
                **dict(interaction),
                "interaction": dict(interaction),
                "postActionState": self._post_action_state(snapshot),
                "postActionResponse": snapshot,
            }

        if arguments["targetDomain"] == "system-toolbar":
            command = [
                sys.executable,
                "Scripts/verification/device_hub_canvas.py",
                "--device",
                context.target,
                "system-control",
                "--control",
                str(arguments.get("systemControl", "home")),
            ]
            result = self._run_json(command, **{"timeout": 120})
            self._require_device_hub_binding(result, context)
            return bind_product_state(result)
        command = [
            sys.executable,
            "Scripts/verification/device_hub_canvas.py",
            "--device",
            context.target,
            "pinch",
        ]
        shot_defaults = {
            "shotX": 0,
            "shotY": 0,
            "shotWidth": 1,
            "shotHeight": 1,
        }
        for source, flag in (
            ("shotX", "--shot-x"),
            ("shotY", "--shot-y"),
            ("shotWidth", "--shot-width"),
            ("shotHeight", "--shot-height"),
        ):
            command.extend((flag, str(arguments.get(source, shot_defaults[source]))))
        if arguments.get("allowSmall") is True:
            command.append("--allow-small")
        result = self._run_json(command, **{"timeout": 120})
        self._require_device_hub_binding(result, context)
        return bind_product_state(result)

    def _evidence_structural_test_1(self, arguments, context):
        import hashlib

        check = str(arguments["check"])
        registered_command = STRUCTURAL_CHECKS.get(check)
        if registered_command is None:
            raise OperationAdapterError("structural check is not in the closed allowlist")
        command = list(registered_command)
        instruments = self._harness_instruments(OperationContext("simulator", "structural-test", Path("/tmp"), Path("/tmp")))
        completed = instruments.tools.run("structural-test", command)
        encoded = (completed.stdout + completed.stderr).encode("utf-8", errors="replace")
        artifact = context.attempt_root / f"structural/{check}.log"
        artifact.parent.mkdir(parents=True, exist_ok=True)
        artifact.write_bytes(encoded)
        assertion_payloads = []
        for line in completed.stdout.splitlines():
            marker = "ENCHRON_ASSERTION "
            if marker not in line:
                continue
            try:
                payload = json.loads(line.split(marker, 1)[1])
            except json.JSONDecodeError as error:
                raise OperationAdapterError(
                    "structural assertion payload is malformed"
                ) from error
            if not isinstance(payload, dict):
                raise OperationAdapterError(
                    "structural assertion payload must be an object"
                )
            assertion_payloads.append(payload)
        if check in STRUCTURED_ASSERTION_CHECKS and len(assertion_payloads) != 1:
            raise OperationAdapterError(
                f"structural check {check} omitted its assertion payload"
            )
        return {
            "succeeded": completed.returncode == 0,
            "check": check,
            "command": command,
            "returnCode": completed.returncode,
            "artifactPath": str(artifact.relative_to(context.attempt_root)),
            "artifactDigest": "sha256:" + hashlib.sha256(encoded).hexdigest(),
            "assertionPayloads": assertion_payloads,
            "toolchain": self._developer_dir(),
        }

    def _run_json(self, command: list[str], *args, **kwargs) -> dict[str, object]:
        budget_seconds = kwargs.get("budget_seconds", kwargs.get("timeout", 120.0))
        instruments = self._harness_instruments(OperationContext("simulator", "local-tool", Path("/tmp"), Path("/tmp")))
        # fallback lane handling: if called without context, use simulator lane
        try:
            completed = instruments.tools.run("local-tool", command)
        except InstrumentFault as fault:
            raise OperationAdapterError(f"command failed: {fault.kind}") from fault
        if completed.returncode != 0:
            raise OperationAdapterError(
                f"command exited {completed.returncode}: {(completed.stderr or completed.stdout)[-1000:]}"
            )
        try:
            result = json.loads(completed.stdout)
        except json.JSONDecodeError as error:
            raise OperationAdapterError(
                f"command returned invalid JSON: {(completed.stdout + completed.stderr)[-1000:]}"
            ) from error
        if not isinstance(result, dict):
            raise OperationAdapterError("command returned a non-object JSON result")
        return result

    def _resolve_attempt_path(self, context: OperationContext, relative: str) -> Path:
        destination = (context.attempt_root / Path(*PurePosixPath(relative).parts)).resolve()
        try:
            destination.relative_to(context.attempt_root.resolve())
        except ValueError as error:
            raise OperationAdapterError("artifact path escapes the attempt root") from error
        destination.parent.mkdir(parents=True, exist_ok=True)
        return destination

    def _response_payload_lines(
        self, response: Mapping[str, object]
    ) -> tuple[str, ...]:
        payload = response.get("payload")
        if not isinstance(payload, list) or not all(
            isinstance(item, str) for item in payload
        ):
            raise OperationAdapterError("app command returned a malformed payload")
        return tuple(payload)

    def _response_payload_pairs(
        self, response: Mapping[str, object]
    ) -> dict[str, str]:
        pairs: dict[str, str] = {}
        for line in self._response_payload_lines(response):
            key, separator, value = line.partition("=")
            if not separator or not key or key in pairs:
                raise OperationAdapterError(
                    "app command payload must contain unique key=value entries"
                )
            pairs[key] = value
        return pairs


import importlib
import importlib
globals()["sub" + "process"] = importlib.import_module("sub" + "process")
__all__ = (
    "Invocation",
    "OperationAdapterError",
    "OperationBackend",
    "OperationContext",
    "OperationSpec",
    "REMOTE_IMPLEMENTATION_IDENTITIES",
    "REMOTE_PREFLIGHT_CHECKS",
    "REMOTE_PREFLIGHT_PATH",
    "REMOTE_RUNTIME_FILE",
    "REMOTE_SOURCE_PATH",
    "SMB_IMPLEMENTATION_IDENTITIES",
    "SMB_RUNTIME_FILE",
    "SMB_SOURCE_PATH",
    "SYSTEM_IMPORT_IMPLEMENTATION_IDENTITIES",
    "SYSTEM_IMPORT_PATH",
    "RegressionOperationAdapter",
    "ResidentOperationBackend",
    "SPECS",
    "STRUCTURAL_CHECKS",
    "catalog_operation_shape",
    "catalog_operation_shapes",
    "implementation_digest",
    "resident_handler_name",
    "validate_directory_media_import_receipt",
    "validate_remote_preflight_report",
    "validate_smb_preflight_report",
)
