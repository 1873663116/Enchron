#!/usr/bin/env python3

from __future__ import annotations

from dataclasses import dataclass, field
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess
import sys
import tempfile
from types import MappingProxyType
from typing import Mapping, Protocol

import regression_operation_adapter as operations
import regression_remote_source as remote
import regression_smb_source as smb
import regression_emby_source as emby
import regression_system_import as system_import


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
FIXTURE_REGISTRY_PATH = REPOSITORY_ROOT / "Tests/Fixtures/fixture-registry.json"
SEMANTIC_AUTHORITY_SOURCE_PATH = (
    REPOSITORY_ROOT / "Config/regression/catalog-root/semantic-authority.json"
)
SEMANTIC_AUTHORITY_PATH = REPOSITORY_ROOT / "Regression/semantic-authority.json"
OPERATION_ADAPTER_PATH = REPOSITORY_ROOT / "Scripts/verification/regression_operation_adapter.py"
REMOTE_RUNTIME_FILE = operations.REMOTE_RUNTIME_FILE
REMOTE_IMPLEMENTATION_IDENTITIES = operations.REMOTE_IMPLEMENTATION_IDENTITIES
SMB_RUNTIME_FILE = operations.SMB_RUNTIME_FILE
SMB_IMPLEMENTATION_IDENTITIES = operations.SMB_IMPLEMENTATION_IDENTITIES
EMBY_RUNTIME_FILE = emby.DEFAULT_IDENTITY_FILE
EMBY_CONTAINER_IDENTITY_PATH = "Documents/Regression/emby-runtime-identity.json"
EMBY_ACCOUNT_PREPARATION_VERB = "prepareEmbyAccount"
EMBY_ACCOUNT_PREPARATION_SCHEMA = "enchron.regression.emby-account-preparation@1"
SYSTEM_IMPORT_IMPLEMENTATION_IDENTITIES = (
    operations.SYSTEM_IMPORT_IMPLEMENTATION_IDENTITIES
)
SYSTEM_IMPORT_RUNTIME_ROOT = system_import.DEFAULT_RUNTIME_ROOT
SHA256 = "sha256:"


class PreparationAdapterError(ValueError):
    pass


class PreparationImplementationBlocked(PreparationAdapterError):
    def __init__(self, preparation_id: str, missing_capabilities: tuple[str, ...]):
        self.preparation_id = preparation_id
        self.missing_capabilities = missing_capabilities
        super().__init__(
            f"{preparation_id} has an implementation blocker: "
            + "; ".join(missing_capabilities)
        )


class PreparationExecutionError(PreparationAdapterError):
    pass


@dataclass(frozen=True)
class EmbyAccountPreparationRequest:
    identity_digest: str
    item_id: str
    media_source_id: str
    external_subtitle_stream_index: int

    def arguments(self) -> dict[str, str]:
        return {
            "identityDigest": self.identity_digest,
            "itemID": self.item_id,
            "mediaSourceID": self.media_source_id,
            "externalSubtitleStreamIndex": str(
                self.external_subtitle_stream_index
            ),
        }


@dataclass(frozen=True)
class EmbyAccountPreparationReceipt:
    schema: str
    identity_digest: str
    server_id: str
    user_id: str
    item_id: str
    media_source_id: str
    external_subtitle_stream_index: int
    external_subtitle_source_id: str
    persisted: bool

    def canonical(self) -> dict[str, object]:
        return {
            "schema": self.schema,
            "identityDigest": self.identity_digest,
            "serverID": self.server_id,
            "userID": self.user_id,
            "itemID": self.item_id,
            "mediaSourceID": self.media_source_id,
            "externalSubtitleStreamIndex": self.external_subtitle_stream_index,
            "externalSubtitleSourceID": self.external_subtitle_source_id,
            "persisted": self.persisted,
        }


@dataclass(frozen=True)
class _EmbyRuntimeIdentity:
    encoded: bytes = field(repr=False)
    digest: str
    server_id: str
    user_id: str
    secret_values: tuple[str, ...] = field(repr=False)


@dataclass(frozen=True)
class _EmbySeedBinding:
    server_id: str
    user_id: str
    item_id: str
    media_source_id: str
    external_subtitle_stream_index: int


class EmbyAccountPreparationRoute(Protocol):
    def prepare(
        self,
        request: EmbyAccountPreparationRequest,
        identity_file: Path,
        secret_values: tuple[str, ...],
        context: object,
    ) -> object: ...


@dataclass(frozen=True)
class FixtureBinding:
    identifier: str
    device_import_path: str
    digest: str

    @property
    def file_name(self) -> str:
        return PurePosixPath(self.device_import_path).name

    def canonical(self) -> dict[str, str]:
        return {
            "registryID": self.identifier,
            "deviceImportPath": self.device_import_path,
            "digest": self.digest,
        }


@dataclass(frozen=True)
class Prerequisite:
    kind: str
    identity: str
    digest: str | None = None

    def canonical(self) -> dict[str, str]:
        document = {"kind": self.kind, "identity": self.identity}
        if self.digest is not None:
            document["digest"] = self.digest
        return document


@dataclass(frozen=True)
class PreparationCall:
    call_id: str
    operation_id: str
    arguments: Mapping[str, object]

    def canonical(self) -> dict[str, object]:
        return {
            "callId": self.call_id,
            "operation": self.operation_id,
            "arguments": _plain(self.arguments),
        }


@dataclass(frozen=True)
class StateContract:
    key: str
    schema: str
    tags: tuple[str, ...]
    produced_by_call: str | None

    def canonical(self) -> dict[str, object]:
        document: dict[str, object] = {
            "key": self.key,
            "schema": self.schema,
            "tags": list(self.tags),
        }
        if self.produced_by_call is not None:
            document["producedByCall"] = self.produced_by_call
        return document


@dataclass(frozen=True)
class ImplementationBlocker:
    kind: str
    missing_capabilities: tuple[str, ...]

    def canonical(self) -> dict[str, object]:
        return {
            "kind": self.kind,
            "missingCapabilities": list(self.missing_capabilities),
        }


@dataclass(frozen=True)
class PreparationPlan:
    preparation_id: str
    lane: str
    target: str
    prerequisites: tuple[Prerequisite, ...]
    calls: tuple[PreparationCall, ...]
    state: StateContract
    blocker: ImplementationBlocker | None
    implementation_digest: str
    plan_digest: str

    @property
    def readiness(self) -> str:
        return "implementation-blocked" if self.blocker is not None else "ready"

    def canonical(self, *, include_plan_digest: bool = True) -> dict[str, object]:
        document: dict[str, object] = {
            "schema": "enchron.regression.preparation-plan",
            "schemaVersion": 2,
            "id": self.preparation_id,
            "lane": self.lane,
            "target": self.target,
            "readiness": self.readiness,
            "prerequisites": [item.canonical() for item in self.prerequisites],
            "calls": [call.canonical() for call in self.calls],
            "stateContract": self.state.canonical(),
            "implementationDigest": self.implementation_digest,
        }
        if self.blocker is not None:
            document["blocker"] = self.blocker.canonical()
        if include_plan_digest:
            document["planDigest"] = self.plan_digest
        return document


@dataclass(frozen=True)
class DirectorySourceBinding:
    directory_name: str
    media_fixture_id: str
    member_fixture_ids: tuple[str, ...]

    def canonical(self) -> dict[str, object]:
        return {
            "directoryName": self.directory_name,
            "mediaFixtureID": self.media_fixture_id,
            "memberFixtureIDs": list(self.member_fixture_ids),
        }


@dataclass(frozen=True)
class PreparationSpec:
    identifier: str
    lane: str
    state_key: str
    state_schema: str
    tags: tuple[str, ...]
    fixture_ids: tuple[str, ...] = ()
    preflight: str | None = None
    import_staged: bool = False
    connect_webdav: bool = False
    connect_smb: bool = False
    controls_auto_hide_seconds: int | None = None
    prepare_device_hub: bool = False
    clear_storage_targets: tuple[str, ...] = ()
    blocker_capabilities: tuple[str, ...] = ()
    directory_source: DirectorySourceBinding | None = None

    def canonical(self) -> dict[str, object]:
        document: dict[str, object] = {
            "id": self.identifier,
            "lane": self.lane,
            "stateKey": self.state_key,
            "stateSchema": self.state_schema,
            "tags": list(self.tags),
            "fixtureIDs": list(self.fixture_ids),
            "importStaged": self.import_staged,
            "connectWebDAV": self.connect_webdav,
            "connectSMB": self.connect_smb,
            "controlsAutoHideSeconds": self.controls_auto_hide_seconds,
            "prepareDeviceHub": self.prepare_device_hub,
            "clearStorageTargets": list(self.clear_storage_targets),
        }
        if self.preflight is not None:
            document["preflight"] = self.preflight
        if self.blocker_capabilities:
            document["blocker"] = {
                "kind": "implementation-blocker",
                "missingCapabilities": list(self.blocker_capabilities),
            }
        if self.directory_source is not None:
            document["directorySource"] = self.directory_source.canonical()
        return document


class OperationInvoker(Protocol):
    def invoke(self, operation_id: str, arguments: object, context: object) -> object: ...


@dataclass(frozen=True)
class PreparationExecution:
    plan_digest: str
    state: StateContract
    invocations: tuple[object, ...]
    emby_account_preparation_receipt: EmbyAccountPreparationReceipt | None = None


def _read_json(path: Path) -> tuple[dict[str, object], str]:
    encoded = path.read_bytes()
    payload = json.loads(encoded)
    if not isinstance(payload, dict):
        raise RuntimeError(f"{path} must contain one JSON object")
    return payload, SHA256 + hashlib.sha256(encoded).hexdigest()


def _plain(value: object) -> object:
    if isinstance(value, Mapping):
        return {str(key): _plain(item) for key, item in value.items()}
    if isinstance(value, tuple):
        return [_plain(item) for item in value]
    if isinstance(value, list):
        return [_plain(item) for item in value]
    return value


def _digest(value: object) -> str:
    encoded = json.dumps(
        _plain(value), ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")
    return SHA256 + hashlib.sha256(encoded).hexdigest()


_fixture_registry, FIXTURE_REGISTRY_DIGEST = _read_json(FIXTURE_REGISTRY_PATH)
_semantic_authority, SEMANTIC_AUTHORITY_DIGEST = _read_json(
    SEMANTIC_AUTHORITY_SOURCE_PATH
)
if _semantic_authority.get("authority", {}).get("runtimeHumanActorAllowed") is not False:
    raise RuntimeError("semantic authority must forbid a runtime Human actor")

OPERATION_ALLOWLIST = frozenset(operations.SPECS)
if len(OPERATION_ALLOWLIST) != 35:
    raise RuntimeError(
        f"Operation adapter must expose 35 exact Operations, found {len(OPERATION_ALLOWLIST)}"
    )
OPERATION_IMPLEMENTATION_DIGEST = operations.implementation_digest()


def _implementation_binding(path: Path) -> dict[str, str]:
    return {
        "path": path.relative_to(REPOSITORY_ROOT).as_posix(),
        "digest": SHA256 + hashlib.sha256(path.read_bytes()).hexdigest(),
    }


EMBY_IMPLEMENTATION_IDENTITIES = MappingProxyType(
    {
        "preparation-adapter": MappingProxyType(
            _implementation_binding(Path(__file__).resolve())
        ),
        "emby-source-adapter": MappingProxyType(
            _implementation_binding(REPOSITORY_ROOT / "Scripts/verification/regression_emby_source.py")
        ),
        "environment-preflight-adapter": MappingProxyType(
            _implementation_binding(
                REPOSITORY_ROOT / "Scripts/verification/regression_environment_preflight.py"
            )
        ),
        "emby-command-channel": MappingProxyType(
            _implementation_binding(REPOSITORY_ROOT / "Apps/Enchron/TestCommandChannel.swift")
        ),
        "emby-account-session": MappingProxyType(
            _implementation_binding(REPOSITORY_ROOT / "Modules/Emby/EmbySessionViewModel.swift")
        ),
        "interactive-command-controller": MappingProxyType(
            _implementation_binding(
                REPOSITORY_ROOT / "Scripts/verification/interactive_visionpro_ui.py"
            )
        ),
    }
)


def _load_fixtures() -> tuple[Mapping[str, FixtureBinding], str]:
    if _fixture_registry.get("schemaVersion") != 2:
        raise RuntimeError("fixture registry must use schemaVersion 2")
    root = _fixture_registry.get("deviceMediaRoot")
    if not isinstance(root, str) or root != "$WORKSPACE/TestMedia":
        raise RuntimeError("fixture registry deviceMediaRoot changed from its reviewed value")
    entries = _fixture_registry.get("fixtures")
    if not isinstance(entries, list):
        raise RuntimeError("fixture registry fixtures must be a list")
    bindings: dict[str, FixtureBinding] = {}
    for entry in entries:
        if not isinstance(entry, dict) or "deviceImportPath" not in entry:
            continue
        identifier = entry.get("id")
        path = entry.get("deviceImportPath")
        digest = entry.get("sha256")
        if not isinstance(identifier, str) or not identifier:
            raise RuntimeError("stageable fixture has no exact ID")
        if not isinstance(path, str) or not path or path.startswith("/") or ".." in PurePosixPath(path).parts:
            raise RuntimeError(f"stageable fixture has unsafe deviceImportPath: {identifier}")
        if not isinstance(digest, str) or re.fullmatch(r"[0-9a-f]{64}", digest) is None:
            raise RuntimeError(f"stageable fixture has no exact SHA-256: {identifier}")
        if identifier in bindings:
            raise RuntimeError(f"duplicate stageable fixture ID: {identifier}")
        bindings[identifier] = FixtureBinding(identifier, path, SHA256 + digest)
    if not bindings:
        raise RuntimeError("fixture registry has no stageable fixtures")
    return MappingProxyType(bindings), str((REPOSITORY_ROOT.parent / "TestMedia").resolve())


STAGEABLE_FIXTURES, FIXTURE_SOURCE_ROOT = _load_fixtures()


def _load_regression_fixture_sets() -> Mapping[str, tuple[str, ...]]:
    expected = {
        "audio-only",
        "dynamic-range",
        "format-corpus",
        "presentation-tour",
        "projection-stereo",
        "remote-aggregate",
        "system-import",
        "viewing-storage",
    }
    fixture_sets: dict[str, list[str]] = {name: [] for name in expected}
    entries = _fixture_registry.get("fixtures")
    assert isinstance(entries, list)
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        identifier = entry.get("id")
        set_names = entry.get("regressionSets", [])
        if not isinstance(set_names, list) or any(
            not isinstance(name, str) for name in set_names
        ):
            raise RuntimeError(f"fixture {identifier} has invalid regressionSets")
        for name in set_names:
            if name not in expected:
                raise RuntimeError(f"fixture {identifier} names unknown regression set {name}")
            if not isinstance(identifier, str) or identifier not in STAGEABLE_FIXTURES:
                raise RuntimeError(
                    f"regression fixture {identifier} has no stageable byte binding"
                )
            fixture_sets[name].append(identifier)
    missing = sorted(name for name, identifiers in fixture_sets.items() if not identifiers)
    if missing:
        raise RuntimeError("empty regression fixture sets: " + ", ".join(missing))
    return MappingProxyType(
        {name: tuple(identifiers) for name, identifiers in sorted(fixture_sets.items())}
    )


REGRESSION_FIXTURE_SETS = _load_regression_fixture_sets()
if REGRESSION_FIXTURE_SETS["remote-aggregate"] != remote.AGGREGATE_FIXTURE_IDS:
    raise RuntimeError(
        "remote source aggregate fixtures drifted from the registered regression set"
    )

FORMAT_CORPUS_REQUIRED_FIXTURES = frozenset(
    (
        "generated-sdr-avc-bframe-audio-codec-matrix-15s-v1",
        "internal-fate-dts-es-v1",
        "internal-fate-truehd-atmos-v1",
        "internal-fate-vorbis-v1",
        "internal-apple-apmp-180-v1",
        "internal-apple-mvhevc-short-v1",
        "internal-fate-mpeg4-part2-packed-bframes-v1",
    )
)
if not FORMAT_CORPUS_REQUIRED_FIXTURES.issubset(
    REGRESSION_FIXTURE_SETS["format-corpus"]
):
    missing = sorted(
        FORMAT_CORPUS_REQUIRED_FIXTURES
        - set(REGRESSION_FIXTURE_SETS["format-corpus"])
    )
    raise RuntimeError("format corpus omitted required fixtures: " + ", ".join(missing))
REMOTE_PRIMARY_FILE_NAME = STAGEABLE_FIXTURES[
    remote.AGGREGATE_FIXTURE_IDS[0]
].file_name


LOCAL_AGGREGATE_FIXTURES = (
    "generated-sdr-avc-bframe-multiaudio-avsync-30s-v1",
    "generated-sdr-avc-bframe-aggregate-30s-v1",
    "generated-sdr-avc-bframe-aggregate-external-subrip-zh-cn-v1",
    "generated-sdr-avc-bframe-aggregate-external-ass-styled-v1",
    "generated-sdr-avc-bframe-multiaudio-subtitles-30s-v3",
    "generated-sdr-avc-bframe-multiaudio-avsync-120s-v1",
    "generated-sdr-avc-bframe-duplicate-label-audio-30s-v1",
)

LOCAL_DIRECTORY_SUBTITLE_FIXTURES = (
    "generated-sdr-avc-bframe-aggregate-30s-v1",
    "generated-sdr-avc-bframe-aggregate-external-subrip-zh-cn-v1",
    "generated-sdr-avc-bframe-aggregate-external-ass-styled-v1",
)
LOCAL_DIRECTORY_SUBTITLE_SOURCE = DirectorySourceBinding(
    directory_name="sdr-bframe-aggregate-30s-sidecars",
    media_fixture_id=LOCAL_DIRECTORY_SUBTITLE_FIXTURES[0],
    member_fixture_ids=LOCAL_DIRECTORY_SUBTITLE_FIXTURES,
)
if (
    LOCAL_DIRECTORY_SUBTITLE_SOURCE.media_fixture_id
    not in LOCAL_DIRECTORY_SUBTITLE_SOURCE.member_fixture_ids
    or not set(LOCAL_DIRECTORY_SUBTITLE_SOURCE.member_fixture_ids).issubset(
        STAGEABLE_FIXTURES
    )
):
    raise RuntimeError("local directory subtitle source has invalid fixture bindings")


def _specs() -> tuple[PreparationSpec, ...]:
    return (
        PreparationSpec(
            "preparation:audio-only-fixtures", "device", "audio-only-fixtures-ready",
            "fixture-set.audio-only@2", ("app.session", "fixture.corpus", "lane.instance", "library.contents"),
            fixture_ids=REGRESSION_FIXTURE_SETS["audio-only"],
            preflight="audio-fixtures",
            import_staged=True,
        ),
        PreparationSpec(
            "preparation:local-aggregate-device", "device", "local-aggregate-staged",
            "fixture-set.local-aggregate-staged@2", ("app.session", "fixture.corpus", "lane.instance"),
            fixture_ids=LOCAL_AGGREGATE_FIXTURES,
        ),
        PreparationSpec(
            "preparation:local-directory-subtitle-source",
            "device",
            "local-directory-subtitle-source-ready",
            "media-source.local-directory-sidecars@1",
            ("app.session", "fixture.corpus", "lane.instance", "library.contents"),
            fixture_ids=LOCAL_DIRECTORY_SUBTITLE_FIXTURES,
            directory_source=LOCAL_DIRECTORY_SUBTITLE_SOURCE,
        ),
        PreparationSpec(
            "preparation:local-aggregate-simulator", "simulator", "local-aggregate-staged",
            "fixture-set.local-aggregate-staged@2", ("app.session", "fixture.corpus", "lane.instance"),
            fixture_ids=LOCAL_AGGREGATE_FIXTURES,
        ),
        PreparationSpec(
            "preparation:smb-test-source", "device", "smb-test-source-ready",
            "remote-source.smb-fixture@2", ("app.session", "fixture.corpus", "lane.instance", "source.smb"),
            preflight="smb-aggregate",
            connect_smb=True,
        ),
        PreparationSpec(
            "preparation:window-input-fixture", "simulator", "window-input-fixture-ready",
            "fixture-set.window-input@2", ("app.session", "fixture.corpus", "input.device-hub", "lane.instance", "library.contents", "settings.state"),
            fixture_ids=("generated-sdr-avc-bframe-multiaudio-avsync-120s-v1",), import_staged=True,
            controls_auto_hide_seconds=8,
            prepare_device_hub=True,
        ),
        PreparationSpec(
            "preparation:system-import-fixtures", "simulator", "system-import-fixtures-ready",
            "fixture-set.system-import@2", ("fixture.corpus", "input.device-hub", "lane.instance", "system.permission"),
            preflight="system-import-fixtures",
        ),
        PreparationSpec(
            "preparation:dynamic-range-corpus", "device", "dynamic-range-corpus-ready",
            "fixture-set.dynamic-range@2", ("app.session", "display.capture", "fixture.corpus", "lane.instance", "library.contents"),
            fixture_ids=REGRESSION_FIXTURE_SETS["dynamic-range"], import_staged=True,
        ),
        PreparationSpec(
            "preparation:emby-test-library", "device", "emby-test-library-ready",
            "remote-source.emby-library@2", ("app.session", "emby.account", "lane.instance", "source.emby", "source.emby.fixture-revision"),
            preflight="emby-aggregate",
        ),
        PreparationSpec(
            "preparation:faultable-remote-source", "device", "faultable-remote-source-ready",
            "remote-source.faultable@2", ("app.session", "certificate.trust", "fixture.corpus", "lane.instance", "network.fault", "source.webdav"),
            preflight="remote-faults",
            connect_webdav=True,
        ),
        PreparationSpec(
            "preparation:format-corpus", "device", "format-corpus-ready",
            "fixture-set.format-corpus@2", ("app.session", "audio.capture", "fixture.corpus", "lane.instance", "library.contents"),
            fixture_ids=REGRESSION_FIXTURE_SETS["format-corpus"], import_staged=True,
        ),
        PreparationSpec(
            "preparation:issue-fixtures", "device", "issue-fixtures-ready",
            "fixture-set.issue-surfaces@2", ("app.session", "certificate.trust", "issue.surface", "lane.instance", "source.webdav"),
            preflight="remote-faults",
            connect_webdav=True,
        ),
        PreparationSpec(
            "preparation:presentation-fixtures-device", "device", "presentation-fixtures-ready",
            "fixture-set.presentation-tour@2", ("app.session", "fixture.corpus", "lane.instance", "library.contents", "presentation.state", "source.webdav"),
            fixture_ids=REGRESSION_FIXTURE_SETS["presentation-tour"], import_staged=True,
            preflight="webdav-regression",
            connect_webdav=True,
        ),
        PreparationSpec(
            "preparation:presentation-fixtures-simulator", "simulator", "presentation-fixtures-ready",
            "fixture-set.presentation-tour@2", ("app.session", "fixture.corpus", "lane.instance", "library.contents", "presentation.state", "source.webdav"),
            fixture_ids=REGRESSION_FIXTURE_SETS["presentation-tour"], import_staged=True,
            preflight="webdav-regression",
            connect_webdav=True,
        ),
        PreparationSpec(
            "preparation:projection-corpus", "device", "projection-corpus-ready",
            "fixture-set.projection-stereo@2", ("app.session", "display.capture", "fixture.corpus", "lane.instance", "library.contents"),
            fixture_ids=REGRESSION_FIXTURE_SETS["projection-stereo"], import_staged=True,
        ),
        PreparationSpec(
            "preparation:viewing-storage-fixtures-device", "device", "viewing-storage-fixtures-ready",
            "fixture-set.viewing-storage@2", ("app.session", "cache.state", "fixture.corpus", "lane.instance", "library.contents", "settings.state", "source.webdav", "viewing.state"),
            fixture_ids=REGRESSION_FIXTURE_SETS["viewing-storage"], import_staged=False,
            preflight="webdav-regression",
            connect_webdav=True,
            clear_storage_targets=("container-index-cache", "playback-progress"),
        ),
        PreparationSpec(
            "preparation:viewing-storage-fixtures-simulator", "simulator", "viewing-storage-fixtures-ready",
            "fixture-set.viewing-storage@2", ("app.session", "cache.state", "fixture.corpus", "lane.instance", "library.contents", "settings.state", "source.webdav", "viewing.state"),
            fixture_ids=REGRESSION_FIXTURE_SETS["viewing-storage"], import_staged=False,
            preflight="webdav-regression",
            connect_webdav=True,
            clear_storage_targets=("container-index-cache", "playback-progress"),
        ),
        PreparationSpec(
            "preparation:webdav-test-source", "device", "webdav-test-source-ready",
            "remote-source.webdav-fixture@2", ("app.session", "certificate.trust", "fixture.corpus", "lane.instance", "source.webdav", "system.permission"),
            preflight="webdav-regression",
            connect_webdav=True,
        ),
    )


_spec_sequence = _specs()
PREPARATION_REGISTRY = MappingProxyType({spec.identifier: spec for spec in _spec_sequence})
if len(PREPARATION_REGISTRY) != 18:
    raise RuntimeError(f"expected 18 exact Preparation specifications, found {len(PREPARATION_REGISTRY)}")


def _uses_remote_service(spec: PreparationSpec) -> bool:
    return (
        spec.preflight in operations.REMOTE_PREFLIGHT_CHECKS
        and spec.preflight != "emby-aggregate"
    ) or spec.connect_webdav


def _uses_smb_source(spec: PreparationSpec) -> bool:
    return spec.preflight == "smb-aggregate" or spec.connect_smb


def _uses_emby_source(spec: PreparationSpec) -> bool:
    return spec.preflight == "emby-aggregate"


def _uses_system_import(spec: PreparationSpec) -> bool:
    return spec.preflight == "system-import-fixtures"


def _implementation_document(spec: PreparationSpec) -> dict[str, object]:
    document: dict[str, object] = {
        "schema": "enchron.regression.preparation-implementation",
        "schemaVersion": 2,
        "spec": spec.canonical(),
        "operationAllowlist": sorted(OPERATION_ALLOWLIST),
        "operationImplementationDigest": OPERATION_IMPLEMENTATION_DIGEST,
        "fixtureRegistryDigest": FIXTURE_REGISTRY_DIGEST,
        "semanticAuthorityDigest": SEMANTIC_AUTHORITY_DIGEST,
        "fixtures": [STAGEABLE_FIXTURES[item].canonical() for item in spec.fixture_ids],
    }
    if _uses_remote_service(spec):
        document["remoteImplementations"] = {
            identity: dict(binding)
            for identity, binding in REMOTE_IMPLEMENTATION_IDENTITIES.items()
        }
        document["runtimeIdentityPath"] = str(REMOTE_RUNTIME_FILE)
    if _uses_smb_source(spec):
        document["smbImplementations"] = {
            identity: dict(binding)
            for identity, binding in SMB_IMPLEMENTATION_IDENTITIES.items()
        }
        document["smbRuntimeIdentityPath"] = str(SMB_RUNTIME_FILE)
    if _uses_emby_source(spec):
        document["embyImplementations"] = {
            identity: dict(binding)
            for identity, binding in EMBY_IMPLEMENTATION_IDENTITIES.items()
        }
        document["embyRuntimeIdentityPath"] = str(EMBY_RUNTIME_FILE)
    if _uses_system_import(spec):
        document["systemImportImplementations"] = {
            identity: dict(binding)
            for identity, binding in SYSTEM_IMPORT_IMPLEMENTATION_IDENTITIES.items()
        }
        document["systemImportRuntimeRoot"] = str(SYSTEM_IMPORT_RUNTIME_ROOT)
    return document


IMPLEMENTATION_DIGESTS = MappingProxyType(
    {
        spec.identifier: _digest(_implementation_document(spec))
        for spec in _spec_sequence
    }
)

CANONICAL_REGISTRY = MappingProxyType(
    {
        spec.identifier: MappingProxyType(
            {
                **spec.canonical(),
                "implementationDigest": IMPLEMENTATION_DIGESTS[spec.identifier],
            }
        )
        for spec in _spec_sequence
    }
)

REGISTRY_DIGEST = _digest(
    {
        "schema": "enchron.regression.preparation-registry",
        "schemaVersion": 2,
        "operationImplementationDigest": OPERATION_IMPLEMENTATION_DIGEST,
        "fixtureRegistryDigest": FIXTURE_REGISTRY_DIGEST,
        "semanticAuthorityDigest": SEMANTIC_AUTHORITY_DIGEST,
        "operationAllowlist": sorted(OPERATION_ALLOWLIST),
        "remoteImplementations": {
            identity: dict(binding)
            for identity, binding in REMOTE_IMPLEMENTATION_IDENTITIES.items()
        },
        "smbImplementations": {
            identity: dict(binding)
            for identity, binding in SMB_IMPLEMENTATION_IDENTITIES.items()
        },
        "embyImplementations": {
            identity: dict(binding)
            for identity, binding in EMBY_IMPLEMENTATION_IDENTITIES.items()
        },
        "systemImportImplementations": {
            identity: dict(binding)
            for identity, binding in SYSTEM_IMPORT_IMPLEMENTATION_IDENTITIES.items()
        },
        "preparations": [_plain(CANONICAL_REGISTRY[item]) for item in sorted(CANONICAL_REGISTRY)],
    }
)


def _call(preparation_id: str, sequence: int, operation_id: str, arguments: Mapping[str, object]) -> PreparationCall:
    return PreparationCall(
        f"call:{preparation_id}:{sequence:02d}",
        operation_id,
        MappingProxyType(dict(arguments)),
    )


def _materialize_calls(spec: PreparationSpec) -> tuple[PreparationCall, ...]:
    calls: list[PreparationCall] = []
    if spec.preflight is not None:
        calls.append(_call(spec.identifier, len(calls) + 1, "operation:host.preflight@1", {"check": spec.preflight}))
    if spec.fixture_ids or spec.connect_webdav or spec.connect_smb:
        session_arguments = (
            {"controlsAutoHideSeconds": spec.controls_auto_hide_seconds}
            if spec.controls_auto_hide_seconds is not None
            else {}
        )
        calls.extend(
            (
                _call(
                    spec.identifier,
                    len(calls) + 1,
                    "operation:harness.ensure-session@1",
                    session_arguments,
                ),
                _call(spec.identifier, len(calls) + 2, "operation:app.relaunch@1", {}),
                _call(spec.identifier, len(calls) + 3, "operation:harness.reset-product-state@2", {"rootFolderName": "Journey Fixture"}),
                _call(spec.identifier, len(calls) + 4, "operation:harness.assert-channels@2", {}),
            )
        )
        if spec.prepare_device_hub:
            calls.append(
                _call(
                    spec.identifier,
                    len(calls) + 1,
                    "operation:input.device-hub-prepare@1",
                    {},
                )
            )
        for fixture_id in spec.fixture_ids:
            fixture = STAGEABLE_FIXTURES[fixture_id]
            calls.append(
                _call(
                    spec.identifier,
                    len(calls) + 1,
                    "operation:media.stage-fixture@2",
                    {"fixtureID": fixture.identifier, "sourceRoot": FIXTURE_SOURCE_ROOT},
                )
            )
            if spec.import_staged:
                calls.append(
                    _call(
                        spec.identifier,
                        len(calls) + 1,
                        "operation:media.import-staged@2",
                        {"fileName": fixture.file_name},
                    )
                )
        if spec.directory_source is not None:
            source = spec.directory_source
            media_file = STAGEABLE_FIXTURES[source.media_fixture_id].file_name
            member_files = [
                STAGEABLE_FIXTURES[fixture_id].file_name
                for fixture_id in source.member_fixture_ids
            ]
            calls.append(
                _call(
                    spec.identifier,
                    len(calls) + 1,
                    "operation:preparation.local-directory-subtitle-source@1",
                    {
                        "directoryName": source.directory_name,
                        "mediaFileName": media_file,
                        "memberFileNames": member_files,
                    },
                )
            )
        if spec.import_staged:
            calls.append(_call(spec.identifier, len(calls) + 1, "operation:library.snapshot@1", {}))
            calls.append(
                _call(
                    spec.identifier,
                    len(calls) + 1,
                    "operation:harness.assert-channels@2",
                    {},
                )
            )
        for target in spec.clear_storage_targets:
            calls.append(
                _call(
                    spec.identifier,
                    len(calls) + 1,
                    "operation:storage.clear@1",
                    {"target": target},
                )
            )
    if spec.connect_webdav:
        runtime_file = str(REMOTE_RUNTIME_FILE)
        calls.extend(
            (
                _call(
                    spec.identifier,
                    len(calls) + 1,
                    "operation:navigation.select-tab@1",
                    {"tab": "files"},
                ),
                _call(
                    spec.identifier,
                    len(calls) + 2,
                    "operation:accessibility.activate@2",
                    {
                        "context": "main-window-browser",
                        "identifiers": [
                            "FileBrowsing-SourcesSidebar-sourceMore",
                            "FileBrowsing-SourcesSidebar-add",
                            "FileBrowsing-SourcesSidebar-addWebDAV",
                        ],
                    },
                ),
                _call(
                    spec.identifier,
                    len(calls) + 3,
                    "operation:accessibility.type@2",
                    {
                        "context": "main-window-browser",
                        "identifier": "FileBrowsing-SourceConnection-webDAV-name",
                        "mode": "replace",
                        "text": "Enchron Regression WebDAV",
                        "secret": False,
                    },
                ),
                _call(
                    spec.identifier,
                    len(calls) + 4,
                    "operation:accessibility.type@2",
                    {
                        "context": "main-window-browser",
                        "identifier": "FileBrowsing-SourceConnection-webDAV-address",
                        "mode": "replace",
                        "textFile": runtime_file,
                        "textJSONKey": "address",
                        "secret": False,
                    },
                ),
                _call(
                    spec.identifier,
                    len(calls) + 5,
                    "operation:accessibility.type@2",
                    {
                        "context": "main-window-browser",
                        "identifier": "FileBrowsing-SourceConnection-webDAV-username",
                        "mode": "replace",
                        "textFile": runtime_file,
                        "textJSONKey": "user",
                        "secret": False,
                    },
                ),
                _call(
                    spec.identifier,
                    len(calls) + 6,
                    "operation:accessibility.type@2",
                    {
                        "context": "main-window-browser",
                        "identifier": "FileBrowsing-SourceConnection-webDAV-password",
                        "mode": "replace",
                        "textFile": runtime_file,
                        "textJSONKey": "password",
                        "secret": True,
                    },
                ),
                _call(
                    spec.identifier,
                    len(calls) + 7,
                    "operation:accessibility.activate@2",
                    {
                        "context": "main-window-browser",
                        "identifiers": ["FileBrowsing-SourceConnection-webDAV-connect"],
                    },
                ),
                _call(
                    spec.identifier,
                    len(calls) + 8,
                    "operation:accessibility.activate@2",
                    {
                        "context": "main-window-browser",
                        "identifiers": ["FileBrowsing-CertificateTrust-trust"],
                    },
                ),
                _call(
                    spec.identifier,
                    len(calls) + 9,
                    "operation:accessibility.activate@2",
                    {
                        "context": "main-window-browser",
                        "labels": ["以后"],
                    },
                ),
                _call(
                    spec.identifier,
                    len(calls) + 10,
                    "operation:accessibility.inspect@2",
                    {
                        "context": "main-window-browser",
                        "identifier": f"FileBrowsing-grid-video-{REMOTE_PRIMARY_FILE_NAME}",
                        "requireMatchedElement": True,
                    },
                ),
                _call(
                    spec.identifier,
                    len(calls) + 11,
                    "operation:host.preflight@1",
                    {"check": "webdav-regression"},
                ),
            )
        )
    if spec.connect_smb:
        runtime_file = str(SMB_RUNTIME_FILE)
        calls.extend(
            (
                _call(
                    spec.identifier,
                    len(calls) + 1,
                    "operation:navigation.select-tab@1",
                    {"tab": "files"},
                ),
                _call(
                    spec.identifier,
                    len(calls) + 2,
                    "operation:accessibility.activate@2",
                    {
                        "context": "main-window-browser",
                        "identifiers": [
                            "FileBrowsing-SourcesSidebar-sourceMore",
                            "FileBrowsing-SourcesSidebar-add",
                            "FileBrowsing-SourcesSidebar-addSMB",
                        ],
                    },
                ),
                _call(
                    spec.identifier,
                    len(calls) + 3,
                    "operation:accessibility.type@2",
                    {
                        "context": "main-window-browser",
                        "identifier": "FileBrowsing-SourceConnection-smb-name",
                        "mode": "replace",
                        "text": "Enchron Regression SMB",
                        "secret": False,
                    },
                ),
                _call(
                    spec.identifier,
                    len(calls) + 4,
                    "operation:accessibility.type@2",
                    {
                        "context": "main-window-browser",
                        "identifier": "FileBrowsing-SourceConnection-smb-address",
                        "mode": "replace",
                        "textFile": runtime_file,
                        "textJSONKey": "address",
                        "secret": False,
                    },
                ),
                _call(
                    spec.identifier,
                    len(calls) + 5,
                    "operation:accessibility.type@2",
                    {
                        "context": "main-window-browser",
                        "identifier": "FileBrowsing-SourceConnection-smb-username",
                        "mode": "replace",
                        "textFile": runtime_file,
                        "textJSONKey": "user",
                        "secret": False,
                    },
                ),
                _call(
                    spec.identifier,
                    len(calls) + 6,
                    "operation:accessibility.type@2",
                    {
                        "context": "main-window-browser",
                        "identifier": "FileBrowsing-SourceConnection-smb-password",
                        "mode": "replace",
                        "textFile": runtime_file,
                        "textJSONKey": "password",
                        "secret": True,
                    },
                ),
                _call(
                    spec.identifier,
                    len(calls) + 7,
                    "operation:accessibility.activate@2",
                    {
                        "context": "main-window-browser",
                        "identifiers": ["FileBrowsing-SourceConnection-smb-connect"],
                    },
                ),
                _call(
                    spec.identifier,
                    len(calls) + 8,
                    "operation:accessibility.activate@2",
                    {
                        "context": "main-window-browser",
                        "labels": ["以后"],
                    },
                ),
                _call(
                    spec.identifier,
                    len(calls) + 9,
                    "operation:accessibility.activate@2",
                    {
                        "context": "main-window-browser",
                        "identifiers": [f"FileBrowsing-grid-folder-{smb.SHARE_NAME}"],
                    },
                ),
                _call(
                    spec.identifier,
                    len(calls) + 10,
                    "operation:accessibility.activate@2",
                    {
                        "context": "main-window-browser",
                        "identifiers": ["FileBrowsing-grid-folder-TestVectors"],
                    },
                ),
                _call(
                    spec.identifier,
                    len(calls) + 11,
                    "operation:accessibility.activate@2",
                    {
                        "context": "main-window-browser",
                        "identifiers": ["FileBrowsing-grid-folder-Enchron"],
                    },
                ),
                _call(
                    spec.identifier,
                    len(calls) + 12,
                    "operation:accessibility.activate@2",
                    {
                        "context": "main-window-browser",
                        "identifiers": ["FileBrowsing-grid-folder-PlaybackBehavior"],
                    },
                ),
                _call(
                    spec.identifier,
                    len(calls) + 13,
                    "operation:accessibility.inspect@2",
                    {
                        "context": "main-window-browser",
                        "identifier": f"FileBrowsing-grid-video-{REMOTE_PRIMARY_FILE_NAME}",
                        "requireMatchedElement": True,
                    },
                ),
                _call(
                    spec.identifier,
                    len(calls) + 14,
                    "operation:host.preflight@1",
                    {"check": "smb-aggregate"},
                ),
            )
        )
    return tuple(calls)


def _prerequisites(
    spec: PreparationSpec, target: str
) -> tuple[Prerequisite, ...]:
    prerequisites = [
        Prerequisite(
            "operation-adapter",
            OPERATION_ADAPTER_PATH.relative_to(REPOSITORY_ROOT).as_posix(),
            OPERATION_IMPLEMENTATION_DIGEST,
        ),
        Prerequisite("fixture-registry", FIXTURE_REGISTRY_PATH.relative_to(REPOSITORY_ROOT).as_posix(), FIXTURE_REGISTRY_DIGEST),
        Prerequisite("semantic-authority", SEMANTIC_AUTHORITY_PATH.relative_to(REPOSITORY_ROOT).as_posix(), SEMANTIC_AUTHORITY_DIGEST),
    ]
    for fixture_id in spec.fixture_ids:
        fixture = STAGEABLE_FIXTURES[fixture_id]
        prerequisites.append(Prerequisite("registered-fixture", fixture.identifier, fixture.digest))
    if spec.preflight is not None:
        prerequisites.append(Prerequisite("fixed-preflight", spec.preflight))
    if spec.connect_webdav and spec.preflight != "webdav-regression":
        prerequisites.append(Prerequisite("fixed-preflight", "webdav-regression"))
    if spec.connect_smb and spec.preflight != "smb-aggregate":
        prerequisites.append(Prerequisite("fixed-preflight", "smb-aggregate"))
    if _uses_remote_service(spec):
        for identity, binding in REMOTE_IMPLEMENTATION_IDENTITIES.items():
            prerequisites.append(
                Prerequisite(identity, binding["path"], binding["digest"])
            )
        prerequisites.append(
            Prerequisite("runtime-identity", str(REMOTE_RUNTIME_FILE))
        )
    if _uses_smb_source(spec):
        for identity, binding in SMB_IMPLEMENTATION_IDENTITIES.items():
            prerequisites.append(
                Prerequisite(identity, binding["path"], binding["digest"])
            )
        prerequisites.append(Prerequisite("runtime-identity", str(SMB_RUNTIME_FILE)))
    if _uses_emby_source(spec):
        for identity, binding in EMBY_IMPLEMENTATION_IDENTITIES.items():
            prerequisites.append(
                Prerequisite(identity, binding["path"], binding["digest"])
            )
        prerequisites.append(Prerequisite("runtime-identity", str(EMBY_RUNTIME_FILE)))
    if _uses_system_import(spec):
        for identity, binding in SYSTEM_IMPORT_IMPLEMENTATION_IDENTITIES.items():
            prerequisites.append(
                Prerequisite(identity, binding["path"], binding["digest"])
            )
        prerequisites.append(
            Prerequisite(
                "runtime-identity",
                str((SYSTEM_IMPORT_RUNTIME_ROOT / target / "runtime.json").resolve()),
            )
        )
    return tuple(prerequisites)


def build_plan(preparation_id: str, lane: str, target: str) -> PreparationPlan:
    spec = PREPARATION_REGISTRY.get(preparation_id)
    if spec is None:
        raise PreparationAdapterError(f"unknown Preparation ID: {preparation_id}")
    if lane != spec.lane:
        raise PreparationAdapterError(
            f"{preparation_id} requires lane {spec.lane}, not {lane}"
        )
    if not isinstance(target, str) or not target or target.strip() != target:
        raise PreparationAdapterError("target must be one exact nonempty lane target")
    if any(marker in target for marker in ("<", ">", "${", "lease://", "target://")):
        raise PreparationAdapterError("target must be literal, not symbolic")
    calls = _materialize_calls(spec)
    blocker = (
        ImplementationBlocker("implementation-blocker", spec.blocker_capabilities)
        if spec.blocker_capabilities
        else None
    )
    producer = calls[-1].call_id if blocker is None and calls else None
    state = StateContract(spec.state_key, spec.state_schema, spec.tags, producer)
    without_digest = PreparationPlan(
        preparation_id,
        lane,
        target,
        _prerequisites(spec, target),
        calls,
        state,
        blocker,
        IMPLEMENTATION_DIGESTS[preparation_id],
        "",
    )
    plan = PreparationPlan(
        preparation_id,
        lane,
        target,
        without_digest.prerequisites,
        calls,
        state,
        blocker,
        without_digest.implementation_digest,
        _digest(without_digest.canonical(include_plan_digest=False)),
    )
    validate_plan(plan)
    return plan


def validate_plan(plan: PreparationPlan) -> None:
    spec = PREPARATION_REGISTRY.get(plan.preparation_id)
    if spec is None:
        raise PreparationAdapterError(f"unknown Preparation ID: {plan.preparation_id}")
    if plan.lane != spec.lane:
        raise PreparationAdapterError(f"wrong lane for {plan.preparation_id}")
    expected_prefix = f"call:{plan.preparation_id}:"
    seen: set[str] = set()
    for index, call in enumerate(plan.calls, start=1):
        if call.call_id != f"{expected_prefix}{index:02d}" or call.call_id in seen:
            raise PreparationAdapterError("Preparation call IDs must be unique and ordered")
        seen.add(call.call_id)
        if call.operation_id not in OPERATION_ALLOWLIST:
            raise PreparationAdapterError(f"undeclared Operation ID: {call.operation_id}")
        _reject_unsafe_arguments(call.operation_id, call.arguments)
        try:
            operations.SPECS[call.operation_id].validate(plan.lane, dict(call.arguments))
        except operations.OperationAdapterError as error:
            raise PreparationAdapterError(
                f"invalid {call.operation_id} call arguments: {error}"
            ) from error
        fixture_id = call.arguments.get("fixtureID")
        if fixture_id is not None:
            if not isinstance(fixture_id, str) or fixture_id not in STAGEABLE_FIXTURES:
                raise PreparationAdapterError(f"unregistered fixture ID: {fixture_id}")
            fixture = STAGEABLE_FIXTURES[fixture_id]
            prerequisite = next(
                (item for item in plan.prerequisites if item.kind == "registered-fixture" and item.identity == fixture_id),
                None,
            )
            if prerequisite is None or prerequisite.digest != fixture.digest:
                raise PreparationAdapterError(f"fixture digest prerequisite is missing for {fixture_id}")
        text_file = call.arguments.get("textFile")
        if text_file is not None and not any(
            item.kind == "runtime-identity" and item.identity == text_file
            for item in plan.prerequisites
        ):
            raise PreparationAdapterError(
                f"runtime identity prerequisite is missing for {text_file}"
            )
    expected_preflights = [spec.preflight] if spec.preflight is not None else []
    if spec.connect_webdav:
        expected_preflights.append("webdav-regression")
    if spec.connect_smb:
        expected_preflights.append("smb-aggregate")
    observed_preflights = [
        call.arguments.get("check")
        for call in plan.calls
        if call.operation_id == "operation:host.preflight@1"
    ]
    if observed_preflights != expected_preflights:
        raise PreparationAdapterError("Preparation fixed preflight calls drifted")
    if _uses_remote_service(spec):
        for identity, binding in REMOTE_IMPLEMENTATION_IDENTITIES.items():
            if not any(
                item.kind == identity
                and item.identity == binding["path"]
                and item.digest == binding["digest"]
                for item in plan.prerequisites
            ):
                raise PreparationAdapterError(
                    f"remote implementation prerequisite is missing: {identity}"
                )
        if not any(
            item.kind == "runtime-identity"
            and item.identity == str(REMOTE_RUNTIME_FILE)
            and item.digest is None
            for item in plan.prerequisites
        ):
            raise PreparationAdapterError("remote runtime identity prerequisite is missing")
    if _uses_smb_source(spec):
        for identity, binding in SMB_IMPLEMENTATION_IDENTITIES.items():
            if not any(
                item.kind == identity
                and item.identity == binding["path"]
                and item.digest == binding["digest"]
                for item in plan.prerequisites
            ):
                raise PreparationAdapterError(
                    f"SMB implementation prerequisite is missing: {identity}"
                )
        if not any(
            item.kind == "runtime-identity"
            and item.identity == str(SMB_RUNTIME_FILE)
            and item.digest is None
            for item in plan.prerequisites
        ):
            raise PreparationAdapterError("SMB runtime identity prerequisite is missing")
    if _uses_emby_source(spec):
        for identity, binding in EMBY_IMPLEMENTATION_IDENTITIES.items():
            if not any(
                item.kind == identity
                and item.identity == binding["path"]
                and item.digest == binding["digest"]
                for item in plan.prerequisites
            ):
                raise PreparationAdapterError(
                    f"Emby implementation prerequisite is missing: {identity}"
                )
        if not any(
            item.kind == "runtime-identity"
            and item.identity == str(EMBY_RUNTIME_FILE)
            and item.digest is None
            for item in plan.prerequisites
        ):
            raise PreparationAdapterError("Emby runtime identity prerequisite is missing")
    if _uses_system_import(spec):
        for identity, binding in SYSTEM_IMPORT_IMPLEMENTATION_IDENTITIES.items():
            if not any(
                item.kind == identity
                and item.identity == binding["path"]
                and item.digest == binding["digest"]
                for item in plan.prerequisites
            ):
                raise PreparationAdapterError(
                    f"system import implementation prerequisite is missing: {identity}"
                )
        expected_runtime = str(
            (SYSTEM_IMPORT_RUNTIME_ROOT / plan.target / "runtime.json").resolve()
        )
        if not any(
            item.kind == "runtime-identity"
            and item.identity == expected_runtime
            and item.digest is None
            for item in plan.prerequisites
        ):
            raise PreparationAdapterError(
                "system import runtime identity prerequisite is missing"
            )
    expected_calls = [call.canonical() for call in _materialize_calls(spec)]
    if [call.canonical() for call in plan.calls] != expected_calls:
        raise PreparationAdapterError("Preparation concrete call graph drifted")
    if plan.blocker is None:
        if not plan.calls or plan.state.produced_by_call != plan.calls[-1].call_id:
            raise PreparationAdapterError("ready Preparation state must be produced by its final call")
    elif plan.state.produced_by_call is not None:
        raise PreparationAdapterError("blocked Preparation cannot claim a producer call")
    expected = _digest(plan.canonical(include_plan_digest=False))
    if plan.plan_digest != expected:
        raise PreparationAdapterError("Preparation plan digest does not match canonical content")


def _reject_unsafe_arguments(operation_id: str, arguments: Mapping[str, object]) -> None:
    for key, value in arguments.items():
        folded = key.casefold().replace("_", "").replace("-", "")
        if folded in {"password", "authorization", "accesstoken", "secretbytes"}:
            raise PreparationAdapterError(f"raw secret argument is forbidden: {key}")
        for string in _strings(value):
            if string.startswith("fixture-set:"):
                raise PreparationAdapterError("symbolic fixture sets are forbidden")
            if re.match(r"(?i)^(?:basic|bearer)\s+\S", string):
                raise PreparationAdapterError("raw authorization bytes are forbidden")
            if re.match(r"^[a-z][a-z0-9+.-]*://[^/@:]+:[^/@]+@", string, re.IGNORECASE):
                raise PreparationAdapterError("URL userinfo is forbidden")
    if operation_id == "operation:accessibility.type@2" and arguments.get("secret") is True:
        if "text" in arguments or not {"textFile", "textJSONKey"}.issubset(arguments):
            raise PreparationAdapterError("secret input must use a credential file and JSON key")


def _strings(value: object) -> tuple[str, ...]:
    if isinstance(value, str):
        return (value,)
    if isinstance(value, Mapping):
        return tuple(item for nested in value.values() for item in _strings(nested))
    if isinstance(value, (tuple, list)):
        return tuple(item for nested in value for item in _strings(nested))
    return ()


def _read_emby_runtime_identity(path: Path) -> _EmbyRuntimeIdentity:
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        raise PreparationExecutionError(
            "Emby runtime identity is unavailable"
        ) from error
    try:
        information = os.fstat(descriptor)
        if (
            not stat.S_ISREG(information.st_mode)
            or information.st_uid != os.getuid()
            or stat.S_IMODE(information.st_mode) != 0o600
        ):
            raise PreparationExecutionError(
                "Emby runtime identity must be an owner-only 0600 regular file"
            )
        with os.fdopen(descriptor, "rb", closefd=False) as stream:
            encoded = stream.read()
    finally:
        os.close(descriptor)
    try:
        document = json.loads(encoded)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise PreparationExecutionError(
            "Emby runtime identity is not valid JSON"
        ) from error
    required = {
        "schema",
        "address",
        "username",
        "password",
        "serverID",
        "userID",
    }
    if (
        not isinstance(document, dict)
        or set(document) != required
        or document.get("schema") != emby.RUNTIME_IDENTITY_SCHEMA
        or any(
            not isinstance(document.get(key), str) or not document[key]
            for key in required - {"schema"}
        )
    ):
        raise PreparationExecutionError(
            "Emby runtime identity has an unexpected schema"
        )
    return _EmbyRuntimeIdentity(
        encoded=encoded,
        digest=SHA256 + hashlib.sha256(encoded).hexdigest(),
        server_id=document["serverID"],
        user_id=document["userID"],
        secret_values=(document["username"], document["password"]),
    )


def _emby_seed_binding(
    report: object, runtime_identity: _EmbyRuntimeIdentity
) -> _EmbySeedBinding:
    if not emby.validate_preflight_report(report, runtime_file=EMBY_RUNTIME_FILE):
        raise PreparationExecutionError(
            "Emby Preparation requires the exact typed Emby seed receipt"
        )
    if _contains_secret(
        report, runtime_identity.secret_values
    ) or _contains_credential_field(report):
        raise PreparationExecutionError(
            "Emby seed receipt contains forbidden credential material"
        )
    assert isinstance(report, Mapping)
    receipt = report["receipt"]
    assert isinstance(receipt, Mapping)
    catalog = receipt["catalog"]
    external_subtitle = receipt["externalSubtitle"]
    assert isinstance(catalog, Mapping)
    assert isinstance(external_subtitle, Mapping)
    if (
        receipt["serverID"] != runtime_identity.server_id
        or receipt["userID"] != runtime_identity.user_id
    ):
        raise PreparationExecutionError(
            "Emby seed receipt identity differs from the runtime identity"
        )
    return _EmbySeedBinding(
        server_id=receipt["serverID"],
        user_id=receipt["userID"],
        item_id=catalog["episodeID"],
        media_source_id=catalog["mediaSourceID"],
        external_subtitle_stream_index=external_subtitle["streamIndex"],
    )


def _emby_account_receipt(
    response: object,
    request: EmbyAccountPreparationRequest,
    seed: _EmbySeedBinding,
) -> EmbyAccountPreparationReceipt:
    if (
        not isinstance(response, Mapping)
        or response.get("success") is not True
        or response.get("ok") is not True
    ):
        raise PreparationExecutionError(
            "prepareEmbyAccount did not return a successful typed response"
        )
    document = response.get("embyAccountPreparationReceipt")
    required = {
        "schema",
        "identityDigest",
        "serverID",
        "userID",
        "itemID",
        "mediaSourceID",
        "externalSubtitleStreamIndex",
        "externalSubtitleSourceID",
        "persisted",
    }
    if not isinstance(document, Mapping) or set(document) != required:
        raise PreparationExecutionError(
            "prepareEmbyAccount omitted its exact typed receipt"
        )
    string_fields = required - {"externalSubtitleStreamIndex", "persisted"}
    if (
        any(
            not isinstance(document.get(key), str) or not document[key]
            for key in string_fields
        )
        or document.get("schema") != EMBY_ACCOUNT_PREPARATION_SCHEMA
        or type(document.get("externalSubtitleStreamIndex")) is not int
        or document["externalSubtitleStreamIndex"] < 0
        or document.get("persisted") is not True
    ):
        raise PreparationExecutionError(
            "prepareEmbyAccount returned an invalid typed receipt"
        )
    expected = {
        "identityDigest": request.identity_digest,
        "serverID": seed.server_id,
        "userID": seed.user_id,
        "itemID": request.item_id,
        "mediaSourceID": request.media_source_id,
        "externalSubtitleStreamIndex": request.external_subtitle_stream_index,
        "externalSubtitleSourceID": (
            f"emby.subtitle.{request.external_subtitle_stream_index}"
        ),
    }
    if any(document.get(key) != value for key, value in expected.items()):
        raise PreparationExecutionError(
            "prepareEmbyAccount receipt identity differs from the seed binding"
        )
    return EmbyAccountPreparationReceipt(
        schema=document["schema"],
        identity_digest=document["identityDigest"],
        server_id=document["serverID"],
        user_id=document["userID"],
        item_id=document["itemID"],
        media_source_id=document["mediaSourceID"],
        external_subtitle_stream_index=document[
            "externalSubtitleStreamIndex"
        ],
        external_subtitle_source_id=document["externalSubtitleSourceID"],
        persisted=True,
    )


def _contains_secret(value: object, secret_values: tuple[str, ...]) -> bool:
    return any(
        secret in text
        for text in _strings(value)
        for secret in secret_values
        if secret
    )


def _contains_credential_field(value: object) -> bool:
    if isinstance(value, Mapping):
        for key, nested in value.items():
            folded = str(key).casefold().replace("_", "").replace("-", "")
            if any(
                marker in folded
                for marker in (
                    "password",
                    "token",
                    "secret",
                    "authorization",
                    "credential",
                    "apikey",
                )
            ):
                return True
            if _contains_credential_field(nested):
                return True
        return False
    if isinstance(value, (tuple, list)):
        return any(_contains_credential_field(item) for item in value)
    return False


class ResidentEmbyAccountPreparationRoute:
    def __init__(self, runner: object | None = None) -> None:
        self._runner = subprocess.run if runner is None else runner

    def prepare(
        self,
        request: EmbyAccountPreparationRequest,
        identity_file: Path,
        secret_values: tuple[str, ...],
        context: object,
    ) -> object:
        if getattr(context, "lane", None) != "device":
            raise PreparationExecutionError(
                "prepareEmbyAccount is available only on the device lane"
            )
        arguments = request.arguments()
        if set(arguments) != {
            "identityDigest",
            "itemID",
            "mediaSourceID",
            "externalSubtitleStreamIndex",
        } or _contains_secret(arguments, secret_values):
            raise PreparationExecutionError(
                "prepareEmbyAccount arguments crossed the credential boundary"
            )
        session = self._controller(
            context,
            "ensure-session",
            timeout=600,
            secret_values=secret_values,
        )
        if session.get("success") is not True:
            raise PreparationExecutionError(
                "prepareEmbyAccount could not obtain an interactive product session"
            )
        self._stage_identity(identity_file, secret_values, context)
        command_arguments: list[str] = [
            "--verb",
            EMBY_ACCOUNT_PREPARATION_VERB,
        ]
        for key in (
            "identityDigest",
            "itemID",
            "mediaSourceID",
            "externalSubtitleStreamIndex",
        ):
            command_arguments.extend(("--arg", f"{key}={arguments[key]}"))
        command_arguments.extend(
            ("--timeout-seconds", str(emby.PRODUCT_DEADLINE_SECONDS))
        )
        response = self._controller(
            context,
            "app-command",
            *command_arguments,
            timeout=emby.PRODUCT_DEADLINE_SECONDS + 30,
            secret_values=secret_values,
        )
        if _contains_secret(response, secret_values):
            raise PreparationExecutionError(
                "prepareEmbyAccount exposed credential bytes in its response"
            )
        return response

    def _stage_identity(
        self,
        identity_file: Path,
        secret_values: tuple[str, ...],
        context: object,
    ) -> None:
        try:
            information = identity_file.stat()
        except OSError as error:
            raise PreparationExecutionError(
                "private Emby identity snapshot is unavailable"
            ) from error
        if (
            not stat.S_ISREG(information.st_mode)
            or information.st_uid != os.getuid()
            or stat.S_IMODE(information.st_mode) != 0o600
        ):
            raise PreparationExecutionError(
                "private Emby identity snapshot must use mode 0600"
            )
        selected = self._runner(
            ["xcode-select", "-p"],
            capture_output=True,
            text=True,
            timeout=30,
        )
        developer_dir = (
            selected.stdout.strip()
            if selected.returncode == 0 and isinstance(selected.stdout, str)
            else ""
        )
        if not developer_dir:
            raise PreparationExecutionError(
                "the active Xcode developer directory is unavailable"
            )
        target = getattr(context, "target", None)
        bundle_id = getattr(context, "bundle_id", None)
        if not isinstance(target, str) or not target or not isinstance(
            bundle_id, str
        ) or not bundle_id:
            raise PreparationExecutionError(
                "prepareEmbyAccount execution context is incomplete"
            )
        command = [
            "xcrun",
            "devicectl",
            "device",
            "copy",
            "to",
            "--device",
            target,
            "--domain-type",
            "appDataContainer",
            "--domain-identifier",
            bundle_id,
            "--source",
            str(identity_file),
            "--destination",
            EMBY_CONTAINER_IDENTITY_PATH,
        ]
        if _contains_secret(command, secret_values):
            raise PreparationExecutionError(
                "Emby credential bytes entered the staging command"
            )
        completed = self._runner(
            command,
            capture_output=True,
            text=True,
            timeout=600,
            env={"DEVELOPER_DIR": developer_dir, "PATH": "/usr/bin:/bin"},
        )
        output = (completed.stdout or "") + (completed.stderr or "")
        if any(secret in output for secret in secret_values if secret):
            raise PreparationExecutionError(
                "Emby credential bytes entered staging output"
            )
        if completed.returncode != 0:
            raise PreparationExecutionError(
                "the private Emby identity snapshot could not be staged"
            )

    def _controller(
        self,
        context: object,
        action: str,
        *arguments: str,
        timeout: float,
        secret_values: tuple[str, ...] = (),
    ) -> dict[str, object]:
        target = getattr(context, "target", None)
        controller_directory = getattr(context, "controller_directory", None)
        if (
            not isinstance(target, str)
            or not target
            or not isinstance(controller_directory, Path)
            or not controller_directory.is_absolute()
        ):
            raise PreparationExecutionError(
                "prepareEmbyAccount controller context is incomplete"
            )
        command = [
            sys.executable,
            str(
                REPOSITORY_ROOT
                / "Scripts/verification/interactive_visionpro_ui.py"
            ),
            "--device",
            target,
            "--output-directory",
            str(controller_directory),
            action,
            *arguments,
        ]
        if _contains_secret(command, secret_values):
            raise PreparationExecutionError(
                "Emby credential bytes entered the product command"
            )
        try:
            completed = self._runner(
                command,
                cwd=REPOSITORY_ROOT,
                capture_output=True,
                text=True,
                timeout=timeout,
            )
        except (OSError, subprocess.TimeoutExpired) as error:
            raise PreparationExecutionError(
                f"{action} did not complete"
            ) from error
        output = (completed.stdout or "") + (completed.stderr or "")
        if any(secret in output for secret in secret_values if secret):
            raise PreparationExecutionError(
                "Emby credential bytes entered controller output"
            )
        try:
            result = json.loads(completed.stdout)
        except (TypeError, json.JSONDecodeError) as error:
            raise PreparationExecutionError(
                f"{action} returned invalid controller JSON"
            ) from error
        if not isinstance(result, dict):
            raise PreparationExecutionError(
                f"{action} returned a non-object controller result"
            )
        if completed.returncode != 0 and result.get("success") is True:
            raise PreparationExecutionError(
                f"{action} returned inconsistent controller status"
            )
        return result


def execute_plan(
    plan: PreparationPlan,
    invoker: OperationInvoker,
    context: object,
    *,
    emby_account_route: EmbyAccountPreparationRoute | None = None,
) -> PreparationExecution:
    validate_plan(plan)
    if plan.blocker is not None:
        raise PreparationImplementationBlocked(
            plan.preparation_id, plan.blocker.missing_capabilities
        )
    if getattr(context, "lane", None) != plan.lane:
        raise PreparationExecutionError("execution context lane differs from the plan")
    if getattr(context, "target", None) != plan.target:
        raise PreparationExecutionError("execution context target differs from the plan")
    invocations: list[object] = []
    emby_runtime_identity: _EmbyRuntimeIdentity | None = None
    emby_seed: _EmbySeedBinding | None = None
    for call in plan.calls:
        invocation = invoker.invoke(call.operation_id, dict(call.arguments), context)
        result = getattr(invocation, "result", None)
        if isinstance(result, Mapping) and result.get("succeeded") is False:
            raise PreparationExecutionError(f"{call.call_id} failed at runtime")
        if call.operation_id == (
            "operation:preparation.local-directory-subtitle-source@1"
        ):
            receipt = (
                result.get("directoryMediaImportReceipt")
                if isinstance(result, Mapping)
                else None
            )
            try:
                operations.validate_directory_media_import_receipt(
                    receipt,
                    call.arguments,
                )
            except operations.OperationAdapterError as error:
                raise PreparationExecutionError(
                    "local directory subtitle Preparation requires its typed import receipt"
                ) from error
        if plan.preparation_id == "preparation:emby-test-library":
            report = result.get("report") if isinstance(result, Mapping) else None
            emby_runtime_identity = _read_emby_runtime_identity(
                EMBY_RUNTIME_FILE
            )
            emby_seed = _emby_seed_binding(report, emby_runtime_identity)
        if plan.preparation_id == "preparation:system-import-fixtures":
            report = result.get("report") if isinstance(result, Mapping) else None
            runtime_file = (
                SYSTEM_IMPORT_RUNTIME_ROOT / plan.target / "runtime.json"
            ).resolve()
            device_hub = (
                result.get("deviceHub") if isinstance(result, Mapping) else None
            )
            canvas = (
                device_hub.get("canvas")
                if isinstance(device_hub, Mapping)
                else None
            )
            if (
                not system_import.validate_preflight_report(
                    report,
                    device_identifier=plan.target,
                    runtime_file=runtime_file,
                )
                or not isinstance(canvas, Mapping)
                or type(canvas.get("width")) is not int
                or canvas["width"] < 1200
            ):
                raise PreparationExecutionError(
                    "system import Preparation requires typed assets and an enlarged Device Hub canvas"
                )
        invocations.append(invocation)
    emby_account_receipt = None
    if plan.preparation_id == "preparation:emby-test-library":
        if emby_runtime_identity is None or emby_seed is None:
            raise PreparationExecutionError(
                "Emby Preparation did not obtain its seed binding"
            )
        request = EmbyAccountPreparationRequest(
            identity_digest=emby_runtime_identity.digest,
            item_id=emby_seed.item_id,
            media_source_id=emby_seed.media_source_id,
            external_subtitle_stream_index=(
                emby_seed.external_subtitle_stream_index
            ),
        )
        route = (
            ResidentEmbyAccountPreparationRoute()
            if emby_account_route is None
            else emby_account_route
        )
        with tempfile.TemporaryDirectory(
            prefix="enchron-emby-identity-"
        ) as directory:
            private_identity = Path(directory) / "emby-runtime-identity.json"
            descriptor = os.open(
                private_identity,
                os.O_WRONLY | os.O_CREAT | os.O_EXCL,
                0o600,
            )
            try:
                os.fchmod(descriptor, 0o600)
                with os.fdopen(descriptor, "wb", closefd=False) as stream:
                    stream.write(emby_runtime_identity.encoded)
                    stream.flush()
                    os.fsync(stream.fileno())
            finally:
                os.close(descriptor)
            try:
                response = route.prepare(
                    request,
                    private_identity,
                    emby_runtime_identity.secret_values,
                    context,
                )
            except PreparationExecutionError:
                raise
            except Exception:
                raise PreparationExecutionError(
                    "prepareEmbyAccount failed before producing its typed receipt"
                ) from None
        if _contains_secret(
            response, emby_runtime_identity.secret_values
        ):
            raise PreparationExecutionError(
                "prepareEmbyAccount exposed credential bytes in its result"
            )
        emby_account_receipt = _emby_account_receipt(
            response,
            request,
            emby_seed,
        )
    return PreparationExecution(
        plan.plan_digest,
        plan.state,
        tuple(invocations),
        emby_account_receipt,
    )


__all__ = (
    "CANONICAL_REGISTRY",
    "EMBY_ACCOUNT_PREPARATION_SCHEMA",
    "EMBY_ACCOUNT_PREPARATION_VERB",
    "EMBY_CONTAINER_IDENTITY_PATH",
    "EMBY_IMPLEMENTATION_IDENTITIES",
    "EMBY_RUNTIME_FILE",
    "FIXTURE_REGISTRY_DIGEST",
    "FIXTURE_SOURCE_ROOT",
    "IMPLEMENTATION_DIGESTS",
    "LOCAL_AGGREGATE_FIXTURES",
    "LOCAL_DIRECTORY_SUBTITLE_FIXTURES",
    "LOCAL_DIRECTORY_SUBTITLE_SOURCE",
    "OPERATION_ALLOWLIST",
    "OPERATION_IMPLEMENTATION_DIGEST",
    "PREPARATION_REGISTRY",
    "REGISTRY_DIGEST",
    "REGRESSION_FIXTURE_SETS",
    "REMOTE_IMPLEMENTATION_IDENTITIES",
    "REMOTE_PRIMARY_FILE_NAME",
    "REMOTE_RUNTIME_FILE",
    "SMB_IMPLEMENTATION_IDENTITIES",
    "SMB_RUNTIME_FILE",
    "SEMANTIC_AUTHORITY_DIGEST",
    "SEMANTIC_AUTHORITY_SOURCE_PATH",
    "STAGEABLE_FIXTURES",
    "SYSTEM_IMPORT_IMPLEMENTATION_IDENTITIES",
    "SYSTEM_IMPORT_RUNTIME_ROOT",
    "FixtureBinding",
    "DirectorySourceBinding",
    "EmbyAccountPreparationReceipt",
    "EmbyAccountPreparationRequest",
    "EmbyAccountPreparationRoute",
    "ImplementationBlocker",
    "PreparationAdapterError",
    "PreparationCall",
    "PreparationExecution",
    "PreparationExecutionError",
    "PreparationImplementationBlocked",
    "PreparationPlan",
    "PreparationSpec",
    "Prerequisite",
    "ResidentEmbyAccountPreparationRoute",
    "StateContract",
    "build_plan",
    "execute_plan",
    "validate_plan",
)
