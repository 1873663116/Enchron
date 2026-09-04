#!/usr/bin/env python3

"""Render the Regression Catalog v2 blueprint into an isolated staging root."""

from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path
import re
import sys
from typing import Any, Iterable, Mapping, Sequence

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
if str(REPOSITORY_ROOT) not in sys.path:
    sys.path.insert(0, str(REPOSITORY_ROOT))

from Scripts.regression.core import transition_trace

from Scripts.verification import regression_operation_adapter as operation_adapter
sys.modules["regression_operation_adapter"] = operation_adapter
from Scripts.verification import regression_oracle_adapter as oracle_adapter
from Scripts.verification import regression_preparation_adapter as preparation_adapter
from Scripts.regression.core.errors import RegressionError
from Scripts.regression.core.frontmatter import load_frontmatter


LIVE_CATALOG_ROOT = (REPOSITORY_ROOT / "Regression").resolve()
CATALOG_SOURCE_ROOT = (
    REPOSITORY_ROOT / "Config/regression/catalog-root"
).resolve()
SEMANTIC_AUTHORITY_DECISIONS_LOCATOR = (
    "Config/regression/semantic-authority-decisions.tsv"
)
SEMANTIC_AUTHORITY_DECISIONS_PATH = (
    REPOSITORY_ROOT / SEMANTIC_AUTHORITY_DECISIONS_LOCATOR
)
SCHEMA_VERSION = 2
PERSISTENT_ROOT_DOCUMENTS = frozenset(
    {
        "README.md",
        "agent-operability-review-protocol.md",
        "execution-protocol.md",
        "oracle-protocol.md",
        "review-policy.md",
        "semantic-authority.json",
    }
)
PERSISTENT_SOURCE_DIRECTORIES = frozenset({"facts", "promises"})
EXACT_JOURNEY_EDGES: frozenset[tuple[str, str]] = frozenset(
    {
        (
            "scenario:local-media-lifecycle:injected-import-rejoins-ingest",
            "scenario:local-media-lifecycle:artwork-captured-on-exit",
        ),
        (
            "scenario:local-media-lifecycle:injected-import-rejoins-ingest",
            "scenario:local-media-lifecycle:audio-track-switch-same-session",
        ),
        (
            "scenario:local-media-lifecycle:injected-import-rejoins-ingest",
            "scenario:local-media-lifecycle:external-subtitle-source-matrix",
        ),
        (
            "scenario:local-media-lifecycle:injected-import-rejoins-ingest",
            "scenario:local-media-lifecycle:subtitle-switch-and-off",
        ),

    }
)
MEDIA_CARD_PREFIXES = (
    "MediaLibrary-grid-video-",
    "FileBrowsing-grid-video-",
)
RETIRED_OPERATION_IDS = frozenset(
    {
        "operation:accessibility.activate@1",
        "operation:accessibility.inspect@1",
        "operation:accessibility.swipe@1",
        "operation:accessibility.type@1",
        "operation:cache.manage@1",
        "operation:diagnostics.snapshot@1",
        "operation:evidence.archive@1",
        "operation:evidence.capture-audio@1",
        "operation:evidence.capture-transition@1",
        "operation:evidence.record-observation@1",
        "operation:format.apply@1",
        "operation:harness.assert-channels@1",
        "operation:harness.reset-product-state@1",
        "operation:host.configure-fault@1",
        "operation:host.query@1",
        "operation:host.restore@1",
        "operation:input.device-hub-pinch@1",
        "operation:issue.act@1",
        "operation:library.mutate@1",
        "operation:library.search@1",
        "operation:media.import-staged@1",
        "operation:media.open@1",
        "operation:media.stage-fixture@1",
        "operation:menu.select@1",
        "operation:playback.await-state@1",
        "operation:playback.seek@1",
        "operation:playback.wait-position@1",
        "operation:presentation.transition@1",
        "operation:settings.set@1",
        "operation:source.browse@1",
        "operation:source.connect@1",
        "operation:tracks.select-sequence@1",
    }
)
RETIRED_ORACLE_IDS = frozenset(
    {
        "oracle:agent-audio@1",
        "oracle:agent-multimodal@1",
        "oracle:agent-visual@1",
        "oracle:deterministic-accessibility@1",
        "oracle:deterministic-event-sequence@1",
        "oracle:deterministic-state@1",
        "oracle:deterministic-structure@1",
    }
)
FORBIDDEN_ARGUMENT_KEYS = frozenset(
    {"query", "fields", "system", "mediaAlias", "semanticAlias", "fixtureSet"}
)
FORBIDDEN_RUNTIME_VALUES = frozenset(
    {"human", "wearer", "skipped", "voided", "notapplicable"}
)
RESULT_REFERENCE = re.compile(r"^result://(call:[a-z0-9:-]+)/([A-Za-z][A-Za-z0-9]*)$")
SHA256 = re.compile(r"^sha256:[0-9a-f]{64}$")
OPERATION_BLUEPRINT_KEYS = frozenset(
    {"contract", "filename", "id", "invalidatesTags", "role", "title"}
)
ORACLE_BLUEPRINT_KEYS = frozenset({"contract", "filename", "id", "title"})
PREPARATION_BLUEPRINT_KEYS = frozenset(
    {"contract", "estimatedCostMillis", "filename", "id", "title"}
)
EXTERNAL_SUBTITLE_SCENARIO_ID = (
    "scenario:local-media-lifecycle:external-subtitle-source-matrix"
)
EXTERNAL_SUBTITLE_TRACK_LABELS = {
    "local-sidecar": "sdr-bframe-aggregate-30s.zh-CN.srt",
    "webdav-sidecar": "sdr-bframe-aggregate-30s.zh-CN.srt",
}
"""generated-sdr-avc-bframe-aggregate-30s-v1 registers two sidecars beside the
same .mkv, and both reach the menu, so the two file-backed attempts have to name
the one their rubric reviews. The Emby attempt has no entry because its seeder
registers a single external file and a label there could only miss it."""

EXTERNAL_SUBTITLE_RELATED_RESULT_FIELDS = (
    "host",
    "sourceKind",
    "deadlineSeconds",
    "discoveredTracks",
    "selectedTrack",
    "settlement",
    "identityObservation",
)
"""An Oracle reads its producer's observation and content-bound attachments, so
the selection each obligation adjudicates has to travel with the frames."""

EXTERNAL_SUBTITLE_ATTEMPTS = (
    (
        "local-sidecar",
        "local-sidecar",
        (
            "operation:app.relaunch@1",
            "operation:navigation.select-tab@1",
            "operation:accessibility.activate@2",
            "operation:media.open@2",
            "operation:playback.await-window-state@1",
            "operation:playback.select-subtitle@1",
            "operation:evidence.capture-frames@1",
        ),
    ),
    (
        "webdav-sidecar",
        "source-directory-sidecar",
        (
            "operation:app.relaunch@1",
            "operation:navigation.select-tab@1",
            "operation:accessibility.activate@2",
            "operation:accessibility.inspect@2",
            "operation:media.open@2",
            "operation:playback.await-window-state@1",
            "operation:playback.select-subtitle@1",
            "operation:evidence.capture-frames@1",
        ),
    ),
    (
        "emby-external-stream",
        "emby-external-stream",
        (
            "operation:app.relaunch@1",
            "operation:navigation.select-tab@1",
            "operation:accessibility.activate@2",
            "operation:playback.await-window-state@1",
            "operation:playback.select-subtitle@1",
            "operation:evidence.capture-frames@1",
        ),
    ),
)


class MaterializationError(ValueError):
    pass


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise MaterializationError(message)


def _canonical_json_bytes(value: object) -> bytes:
    return json.dumps(
        value, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")


def _sha256(data: bytes) -> str:
    return "sha256:" + hashlib.sha256(data).hexdigest()


def _operation_runtime_shapes() -> dict[str, Mapping[str, Any]]:
    shapes = tuple(operation_adapter.catalog_operation_shapes())
    identifiers = [item.get("id") for item in shapes]
    _require(
        len(identifiers) == len(set(identifiers)),
        "Operation runtime registry repeats an ID",
    )
    _require(
        set(identifiers) == set(operation_adapter.SPECS),
        "Operation runtime shapes and SPECS drifted",
    )
    result: dict[str, Mapping[str, Any]] = {}
    for index, item in enumerate(shapes):
        _require(
            set(item)
            == {"id", "argumentFields", "argumentRules", "lanes", "evidenceSchemas", "implementation"},
            f"Operation runtime shape {index} has invalid keys",
        )
        identifier = item["id"]
        _require(isinstance(identifier, str), f"Operation runtime shape {index} has no ID")
        spec = operation_adapter.SPECS[identifier]
        expected_fields = [
            {
                "name": field.name,
                "type": field.kind.value,
                "required": field.required,
            }
            for field in spec.fields
        ]
        expected_evidence = [
            {"evidenceType": evidence_type, "evidenceSchema": evidence_schema}
            for evidence_type, evidence_schema in spec.outputs
        ]
        _require(item["argumentFields"] == expected_fields, f"{identifier} argument schema drifted from SPECS")
        _require(
            item["argumentRules"] == [rule.canonical() for rule in spec.argument_rules],
            f"{identifier} argument rules drifted from SPECS",
        )
        _require(item["lanes"] == sorted(spec.lanes), f"{identifier} lane support drifted from SPECS")
        _require(item["evidenceSchemas"] == expected_evidence, f"{identifier} evidence pairs drifted from SPECS")
        implementation = item["implementation"]
        _require(
            isinstance(implementation, Mapping)
            and set(implementation) == {"locator", "digest"}
            and isinstance(implementation["locator"], str)
            and implementation["locator"]
            and isinstance(implementation["digest"], str)
            and SHA256.fullmatch(implementation["digest"]),
            f"{identifier} has an invalid implementation identity",
        )
        result[identifier] = item
    return result


def _oracle_runtime_shapes() -> dict[str, Mapping[str, Any]]:
    result: dict[str, Mapping[str, Any]] = {}
    for identifier, spec in oracle_adapter.SPECS.items():
        identity = oracle_adapter.implementation_identity(identifier)
        _require(
            isinstance(identity.locator, str)
            and identity.locator
            and isinstance(identity.digest, str)
            and SHA256.fullmatch(identity.digest),
            f"{identifier} has an invalid implementation identity",
        )
        result[identifier] = {
            "id": identifier,
            "kind": spec.kind.value,
            "evidenceSchemas": [
                {
                    "evidenceType": spec.evidence_type,
                    "evidenceSchema": spec.evidence_schema,
                }
            ],
            "implementation": {
                "locator": identity.locator,
                "digest": identity.digest,
            },
        }
    return result


def _preparation_runtime_shapes() -> dict[str, Mapping[str, Any]]:
    result: dict[str, Mapping[str, Any]] = {}
    for identifier, spec in preparation_adapter.PREPARATION_REGISTRY.items():
        target = f"catalog-v2-{spec.lane}"
        plan = preparation_adapter.build_plan(identifier, spec.lane, target)
        preparation_adapter.validate_plan(plan)
        ready = plan.blocker is None
        blockers = (
            []
            if ready
            else [
                {
                    "kind": "implementation-gap",
                    "capability": capability,
                    "detail": f"{identifier} requires this runtime capability: {capability}",
                }
                for capability in plan.blocker.missing_capabilities
            ]
        )
        operations = [
            {**call.canonical(), "maxInvocations": 1}
            for call in plan.calls
        ]
        produces = [
            {
                "key": plan.state.key,
                "schema": plan.state.schema,
                "producedByCall": plan.state.produced_by_call,
                "dependsOnTags": list(plan.state.tags),
            }
        ]
        plan_projection = plan.canonical()
        del plan_projection["target"]
        del plan_projection["planDigest"]
        result[identifier] = {
            "id": identifier,
            "lane": plan.lane,
            "readiness": "ready" if ready else "implementation-gap",
            "blockers": blockers,
            "prerequisites": [],
            "operations": operations,
            "produces": produces,
            "implementation": {
                "locator": (
                    "python://Scripts/verification/regression_preparation_adapter.py"
                    f"#build_plan({identifier})"
                ),
                "digest": plan.implementation_digest,
            },
            "planProjection": plan_projection,
        }
    _require(
        len(result) == 18
        and set(result) == set(preparation_adapter.PREPARATION_REGISTRY),
        "Preparation runtime registry must contain exactly its 18 registered IDs",
    )
    return result


def _load_blueprint(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise MaterializationError(f"cannot load blueprint {path}: {error}") from error
    _require(isinstance(value, dict), "blueprint must be a JSON object")
    _require(value.get("schemaVersion") == SCHEMA_VERSION, "schemaVersion must be 2")
    recorded = value.get("contentDigest")
    _require(isinstance(recorded, str) and SHA256.fullmatch(recorded), "invalid contentDigest")
    unsigned = dict(value)
    del unsigned["contentDigest"]
    actual = _sha256(_canonical_json_bytes(unsigned))
    _require(recorded == actual, f"blueprint digest mismatch: expected {recorded}, found {actual}")
    return value


def _prepare_output_root(path: Path) -> Path:
    resolved = path.resolve()
    _require(resolved != LIVE_CATALOG_ROOT, "refusing to render into live Regression")
    _require(
        LIVE_CATALOG_ROOT not in resolved.parents,
        "refusing to render below live Regression",
    )
    if resolved.exists():
        _require(resolved.is_dir(), "output root exists and is not a directory")
        _require(not any(resolved.iterdir()), "output root must be empty")
    else:
        resolved.mkdir(parents=True)
    return resolved


def _document_bytes(metadata: Mapping[str, Any], body: str) -> bytes:
    _require(isinstance(body, str) and body.strip(), "contract body must not be empty")
    text = "---\n" + json.dumps(metadata, ensure_ascii=False, indent=2)
    text += "\n---\n" + body.rstrip() + "\n"
    return text.encode("utf-8")


def _write(root: Path, relative: str, payload: bytes, written: set[str]) -> None:
    _require(relative not in written, f"duplicate output path {relative}")
    relative_path = Path(relative)
    _require(not relative_path.is_absolute() and ".." not in relative_path.parts, f"unsafe output path {relative}")
    destination = root / relative_path
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(payload)
    written.add(relative_path.as_posix())


def _copy_documents(
    blueprint: Mapping[str, Any], root: Path, written: set[str]
) -> None:
    declared = {item["path"] for item in blueprint["copyDocuments"]}
    available = {
        source.relative_to(CATALOG_SOURCE_ROOT).as_posix()
        for source in CATALOG_SOURCE_ROOT.rglob("*")
        if source.is_file()
    }
    _require(
        available == declared,
        "persistent Catalog source mismatch: "
        f"missing={sorted(declared - available)}, extra={sorted(available - declared)}",
    )
    for index, item in enumerate(blueprint["copyDocuments"]):
        _require(isinstance(item, dict), f"copyDocuments[{index}] must be an object")
        _require(set(item) == {"path", "digest"}, f"copyDocuments[{index}] keys are invalid")
        relative = item["path"]
        _require(isinstance(relative, str), f"copyDocuments[{index}].path must be text")
        relative_path = Path(relative)
        _require(
            not relative_path.is_absolute() and ".." not in relative_path.parts,
            f"copyDocuments[{index}].path is unsafe",
        )
        source = CATALOG_SOURCE_ROOT / relative_path
        _require(source.is_file(), f"copy source does not exist: {relative}")
        payload = source.read_bytes()
        _require(_sha256(payload) == item["digest"], f"copy source digest changed: {relative}")
        _write(root, relative, payload, written)


def _semantic_authority_source_identity() -> Mapping[str, str]:
    authority_path = CATALOG_SOURCE_ROOT / "semantic-authority.json"
    try:
        document = json.loads(authority_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise MaterializationError(
            f"cannot load semantic authority source {authority_path}: {error}"
        ) from error
    _require(isinstance(document, Mapping), "semantic authority must be an object")
    authority = document.get("authority")
    _require(isinstance(authority, Mapping), "semantic authority.authority must be an object")
    _require(
        authority.get("source") == SEMANTIC_AUTHORITY_DECISIONS_LOCATOR,
        "semantic authority must use the persistent Config decision source",
    )
    source_digest = authority.get("sourceDigest")
    _require(
        isinstance(source_digest, str) and SHA256.fullmatch(source_digest),
        "semantic authority sourceDigest is invalid",
    )
    _require(
        SEMANTIC_AUTHORITY_DECISIONS_PATH.is_file()
        and not SEMANTIC_AUTHORITY_DECISIONS_PATH.is_symlink(),
        "semantic authority decision source must be a regular file",
    )
    actual_digest = _sha256(SEMANTIC_AUTHORITY_DECISIONS_PATH.read_bytes())
    _require(
        actual_digest == source_digest,
        "semantic authority decision source digest changed",
    )
    return {
        "locator": SEMANTIC_AUTHORITY_DECISIONS_LOCATOR,
        "digest": actual_digest,
    }


def _persistent_promise_count() -> int:
    promises_root = CATALOG_SOURCE_ROOT / "promises"
    try:
        sources = tuple(sorted(promises_root.glob("*.md")))
    except OSError as error:
        raise MaterializationError(
            f"cannot enumerate persistent Promise sources {promises_root}: {error}"
        ) from error

    total = 0
    for source in sources:
        try:
            document = load_frontmatter(source)
        except (OSError, RegressionError) as error:
            raise MaterializationError(
                f"cannot load persistent Promise source {source}: {error}"
            ) from error
        promises = document.metadata.get("promises")
        _require(
            isinstance(promises, tuple),
            f"persistent Promise source has no promises array: {source}",
        )
        total += len(promises)
    return total


def _render_promises(blueprint: Mapping[str, Any], root: Path, written: set[str]) -> None:
    grouped: dict[str, list[Mapping[str, Any]]] = defaultdict(list)
    for promise in blueprint["promises"]:
        grouped[promise["feature"]].append(promise)
    for feature, promises in sorted(grouped.items()):
        metadata = {
            "schema": "enchron.regression.promises",
            "schemaVersion": 1,
            "feature": feature,
            "title": promises[0]["featureTitle"],
            "promises": [
                {
                    "id": item["id"],
                    "title": item["title"],
                    "statement": item["statement"],
                    "automation": {"scope": "included"},
                }
                for item in promises
            ],
        }
        body = "# " + promises[0]["featureTitle"] + "\n\n"
        body += "These commitments are included in unattended Regression Catalog v2 coverage."
        _write(root, f"promises/{feature}.md", _document_bytes(metadata, body), written)


def _render_operations(
    blueprint: Mapping[str, Any],
    runtime_shapes: Mapping[str, Mapping[str, Any]],
    root: Path,
    written: set[str],
) -> None:
    for item in blueprint["operations"]:
        runtime = runtime_shapes[item["id"]]
        metadata = {
            "schema": "enchron.regression.operation",
            "schemaVersion": 1,
            "id": item["id"],
            "title": item["title"],
            "role": item["role"],
            "lanes": runtime["lanes"],
            "argumentSchema": {
                "fields": runtime["argumentFields"],
                "rules": runtime["argumentRules"],
                "additionalProperties": False,
            },
            "invalidatesTags": item["invalidatesTags"],
            "evidenceSchemas": runtime["evidenceSchemas"],
            "implementation": runtime["implementation"],
        }
        body = f"# {item['title']}\n\n{item['contract']}"
        _write(root, f"operations/{item['filename']}", _document_bytes(metadata, body), written)


def _render_oracles(
    blueprint: Mapping[str, Any],
    runtime_shapes: Mapping[str, Mapping[str, Any]],
    root: Path,
    written: set[str],
) -> None:
    for item in blueprint["oracles"]:
        runtime = runtime_shapes[item["id"]]
        metadata = {
            "schema": "enchron.regression.oracle",
            "schemaVersion": 1,
            "id": item["id"],
            "title": item["title"],
            "kind": runtime["kind"],
            "evidenceSchemas": runtime["evidenceSchemas"],
            "implementation": runtime["implementation"],
        }
        body = f"# {item['title']}\n\n{item['contract']}"
        _write(root, f"oracles/{item['filename']}", _document_bytes(metadata, body), written)


def _render_rubrics(blueprint: Mapping[str, Any], root: Path, written: set[str]) -> None:
    for item in blueprint["rubrics"]:
        metadata = {
            "schema": "enchron.regression.rubric",
            "schemaVersion": 1,
            "id": item["id"],
            "title": item["title"],
            "criteria": item["criteria"],
            "negativeControls": item["negativeControls"],
        }
        body = f"# {item['title']}\n\nThe Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control."
        _write(root, f"rubrics/{item['filename']}", _document_bytes(metadata, body), written)


def _render_preparations(
    blueprint: Mapping[str, Any],
    runtime_shapes: Mapping[str, Mapping[str, Any]],
    root: Path,
    written: set[str],
) -> None:
    for item in blueprint["preparations"]:
        runtime = runtime_shapes[item["id"]]
        metadata = {
            "schema": "enchron.regression.preparation",
            "schemaVersion": 1,
            "id": item["id"],
            "title": item["title"],
            "lane": runtime["lane"],
            "estimatedCostMillis": item["estimatedCostMillis"],
            "readiness": runtime["readiness"],
            "blockers": runtime["blockers"],
            "prerequisites": runtime["prerequisites"],
            "operations": runtime["operations"],
            "produces": runtime["produces"],
        }
        body = f"# {item['title']}\n\n{item['contract']}"
        _write(root, f"preparations/{item['filename']}", _document_bytes(metadata, body), written)


def _render_journeys(blueprint: Mapping[str, Any], root: Path, written: set[str]) -> None:
    for item in blueprint["journeys"]:
        metadata = {
            "schema": "enchron.regression.journey",
            "schemaVersion": 1,
            "id": item["id"],
            "title": item["title"],
            "scenarioRefs": item["scenarioRefs"],
            "ordering": item["ordering"],
            "sharedState": item["sharedState"],
        }
        body = f"# {item['title']}\n\nThe Journey groups scenarios and declares only the reviewed state-handoff edges."
        slug = item["id"].removeprefix("journey:")
        _write(root, f"journeys/{slug}/journey.md", _document_bytes(metadata, body), written)


def _render_scenarios(blueprint: Mapping[str, Any], root: Path, written: set[str]) -> None:
    for item in blueprint["scenarios"]:
        metadata = {
            "schema": "enchron.regression.scenario",
            "schemaVersion": 1,
            "id": item["id"],
            "title": item["title"],
            "journey": item["journey"],
            "promiseRefs": item["promiseRefs"],
            "applicability": item["applicability"],
            "lane": item["lane"],
            "estimatedCostMillis": item["estimatedCostMillis"],
            "staticCases": item["staticCases"],
            "readiness": item["readiness"],
            "blockers": item["blockers"],
            "prerequisites": item["prerequisites"],
            "operations": item["operations"],
            "obligations": item["obligations"],
            "success": item["success"],
        }
        if item["mainGateFor"]:
            metadata["mainGateFor"] = item["mainGateFor"]
        body = f"# {item['title']}\n\n{item['contract']}"
        journey = item["journey"].removeprefix("journey:")
        scenario = item["id"].rsplit(":", 1)[-1]
        _write(root, f"journeys/{journey}/scenarios/{scenario}.md", _document_bytes(metadata, body), written)


def _walk_strings(value: object) -> Iterable[str]:
    if isinstance(value, str):
        yield value
    elif isinstance(value, list):
        for item in value:
            yield from _walk_strings(item)
    elif isinstance(value, dict):
        for item in value.values():
            yield from _walk_strings(item)


def _success_refs(value: object) -> list[str]:
    _require(isinstance(value, dict) and len(value) == 1, "SuccessExpression must have one operator")
    operator, operand = next(iter(value.items()))
    if operator == "observation":
        _require(isinstance(operand, str), "SuccessExpression observation must be text")
        return [operand]
    if operator == "not":
        return _success_refs(operand)
    if operator in {"all", "any"}:
        _require(isinstance(operand, list) and operand, f"SuccessExpression {operator} must be non-empty")
        return [reference for term in operand for reference in _success_refs(term)]
    if operator == "atLeast":
        _require(isinstance(operand, dict) and set(operand) == {"count", "of"}, "invalid atLeast")
        return [reference for term in operand["of"] for reference in _success_refs(term)]
    raise MaterializationError(f"unknown SuccessExpression operator {operator!r}")


def _validate_node_calls(
    owner: str,
    calls: Sequence[Mapping[str, Any]],
    global_calls: set[str],
    lane: str | None = None,
) -> None:
    seen: list[str] = []
    owner_prefix = (
        f"call:{owner}:"
        if owner.startswith("preparation:")
        else "call:" + owner.removeprefix("scenario:") + ":"
    )
    for call in calls:
        _require(set(call) == {"callId", "operation", "arguments", "maxInvocations"}, f"{owner} call keys are invalid")
        call_id = call["callId"]
        _require(isinstance(call_id, str) and call_id.startswith(owner_prefix), f"{owner} has cross-node call {call_id}")
        _require(
            call_id == f"{owner_prefix}{len(seen) + 1:02d}",
            f"{owner} call sequence is not contiguous at {call_id}",
        )
        _require(call_id not in global_calls, f"duplicate callId {call_id}")
        _require(call["maxInvocations"] == 1, f"{call_id} must have maxInvocations=1")
        _require(call["operation"] not in RETIRED_OPERATION_IDS, f"retired v1 Operation {call['operation']}")
        spec = operation_adapter.SPECS.get(call["operation"])
        _require(spec is not None, f"{call_id} names unknown runtime Operation {call['operation']}")
        arguments = call["arguments"]
        _require(isinstance(arguments, dict), f"{call_id} arguments must be an object")
        forbidden = sorted(set(arguments) & FORBIDDEN_ARGUMENT_KEYS)
        _require(not forbidden, f"{call_id} contains arbitrary argument(s): {', '.join(forbidden)}")
        for value in _walk_strings(arguments):
            match = RESULT_REFERENCE.fullmatch(value)
            if value.startswith("result://"):
                _require(match is not None, f"{call_id} has malformed result reference: {value}")
            if match is not None:
                target = match.group(1)
                _require(target in seen, f"{call_id} result reference is not earlier in the same node: {target}")
            _require(not value.startswith("fixture:"), f"{call_id} uses semantic fixture alias {value}")
        lanes = {
            "simulator": ("simulator",),
            "device": ("device",),
            "either": ("simulator", "device"),
            "both": ("simulator", "device"),
        }.get(lane, ())
        for concrete_lane in lanes:
            try:
                spec.validate(concrete_lane, arguments)
            except operation_adapter.OperationAdapterError as error:
                raise MaterializationError(f"{call_id} violates runtime Operation schema: {error}") from error
        global_calls.add(call_id)
        seen.append(call_id)


def _validate_transition_trace_sequences(
    scenarios: Sequence[Mapping[str, Any]],
) -> None:
    transition_scenarios = {
        scenario["id"]
        for scenario in scenarios
        for call in scenario["operations"]
        if call["operation"] == transition_trace.ARM
    }
    transition_count = transition_trace.count(scenarios)
    for scenario in scenarios:
        for failure in transition_trace.failures(scenario):
            _require(False, failure)

    _require(
        transition_count > 0,
        "active Catalog contains no transition capture sequence",
    )
    _require(
        transition_count == 7
        and len(transition_scenarios) == 6
        and all(
            scenario_id.startswith("scenario:presentation-tour:")
            for scenario_id in transition_scenarios
        ),
        "Catalog must contain exactly seven transition captures across six "
        "presentation-tour Scenarios",
    )


def _concrete_lanes(lane: str) -> tuple[str, ...]:
    return {
        "simulator": ("simulator",),
        "device": ("device",),
        "either": ("simulator", "device"),
        "both": ("simulator", "device"),
    }.get(lane, ())


def _validate_scenario_media_bindings(
    scenarios: Sequence[Mapping[str, Any]],
    preparations: Mapping[str, Mapping[str, Any]],
) -> None:
    staged_by_state: dict[tuple[str, str, str], frozenset[str]] = {}
    imported_by_state: dict[tuple[str, str, str], frozenset[str]] = {}
    for preparation in preparations.values():
        staged_files: set[str] = set()
        imported_files: set[str] = set()
        for call in preparation["operations"]:
            if call["operation"] == "operation:media.stage-fixture@2":
                fixture_id = call["arguments"]["fixtureID"]
                fixture = preparation_adapter.STAGEABLE_FIXTURES.get(fixture_id)
                _require(
                    fixture is not None,
                    f"{call['callId']} stages an unregistered fixture {fixture_id}",
                )
                staged_files.add(fixture.file_name)
            elif call["operation"] == "operation:media.import-staged@2":
                file_name = call["arguments"]["fileName"]
                _require(
                    file_name in staged_files,
                    f"{call['callId']} imports {file_name} before its Preparation stages it",
                )
                _require(
                    file_name not in imported_files,
                    f"{call['callId']} repeats Preparation import {file_name}",
                )
                imported_files.add(file_name)
            elif call["operation"] == (
                "operation:preparation.local-directory-subtitle-source@1"
            ):
                file_name = call["arguments"]["mediaFileName"]
                member_files = set(call["arguments"]["memberFileNames"])
                _require(
                    file_name in staged_files and member_files <= staged_files,
                    f"{call['callId']} imports a directory before its Preparation "
                    "stages every member",
                )
                _require(
                    file_name not in imported_files,
                    f"{call['callId']} repeats Preparation import {file_name}",
                )
                imported_files.add(file_name)
        for state in preparation["produces"]:
            for lane in _concrete_lanes(preparation["lane"]):
                identity = (lane, state["key"], state["schema"])
                _require(
                    identity not in staged_by_state,
                    "multiple Preparations produce "
                    f"{state['key']} ({state['schema']}) on {lane}",
                )
                staged_by_state[identity] = frozenset(staged_files)
                imported_by_state[identity] = frozenset(imported_files)

    for scenario in scenarios:
        for lane in _concrete_lanes(scenario["lane"]):
            available: set[str] = set()
            imported: set[str] = set()
            for prerequisite in scenario["prerequisites"]:
                identity = (lane, prerequisite["key"], prerequisite["schema"])
                available.update(staged_by_state.get(identity, ()))
                imported.update(imported_by_state.get(identity, ()))
            for call in scenario["operations"]:
                if call["operation"] == "operation:harness.reset-product-state@2":
                    imported.clear()
                    continue
                if call["operation"] == "operation:media.import-staged@2":
                    file_name = call["arguments"]["fileName"]
                    _require(
                        file_name in available,
                        f"{call['callId']} local media {file_name} is not staged by "
                        f"its prerequisite Preparations on {lane}",
                    )
                    _require(
                        file_name not in imported,
                        f"{call['callId']} repeats import of {file_name} already supplied "
                        f"by its prerequisite Preparation on {lane}",
                    )
                    imported.add(file_name)
                    continue
                local_names = {
                    value.removeprefix(MEDIA_CARD_PREFIXES[0])
                    for value in _walk_strings(call["arguments"])
                    if value.startswith(MEDIA_CARD_PREFIXES[0])
                }
                for file_name in local_names:
                    _require(
                        file_name in available,
                        f"{call['callId']} local media {file_name} is not staged by "
                        f"its prerequisite Preparations on {lane}",
                    )
                    _require(
                        file_name in imported,
                        f"{call['callId']} local media {file_name} was not imported "
                        "by a prerequisite Preparation or earlier Scenario call",
                    )


def _validate_registered_media_basenames(
    scenarios: Sequence[Mapping[str, Any]],
) -> None:
    registered = {
        fixture.file_name
        for fixture in preparation_adapter.STAGEABLE_FIXTURES.values()
    }
    for scenario in scenarios:
        for call in scenario["operations"]:
            candidates: set[str] = set()
            if call["operation"] == "operation:media.import-staged@2":
                candidates.add(call["arguments"]["fileName"])
            for value in _walk_strings(call["arguments"]):
                for prefix in MEDIA_CARD_PREFIXES:
                    if value.startswith(prefix):
                        candidates.add(value.removeprefix(prefix))
            for basename in sorted(candidates):
                _require(
                    basename in registered,
                    f"{call['callId']} names unregistered media basename {basename}",
                )


def _validate_scenario_time_bounds(
    scenarios: Sequence[Mapping[str, Any]],
) -> None:
    for scenario in scenarios:
        declared_wait_millis = 0
        for call in scenario["operations"]:
            arguments = call["arguments"]
            declared_wait_millis += int(arguments.get("deadlineSeconds", 0)) * 1000
            if call["operation"] == "operation:evidence.capture-frames@1":
                declared_wait_millis += (
                    int(arguments["count"]) - 1
                ) * int(arguments["minimumIntervalMillis"])
            declared_wait_millis += int(arguments.get("settleDelayMillis", 0))
        _require(
            scenario["estimatedCostMillis"] >= declared_wait_millis,
            f"{scenario['id']} estimatedCostMillis is below its declared sequential waits "
            f"({scenario['estimatedCostMillis']} < {declared_wait_millis})",
        )


def _validate_external_subtitle_matrix(
    scenarios: Sequence[Mapping[str, Any]],
    preparations: Mapping[str, Mapping[str, Any]],
) -> None:
    scenario = next(
        (item for item in scenarios if item["id"] == EXTERNAL_SUBTITLE_SCENARIO_ID),
        None,
    )
    _require(scenario is not None, "external subtitle source matrix is missing")
    _require(
        scenario["readiness"] == "ready" and not scenario["blockers"],
        "external subtitle source matrix must have a complete Operation graph",
    )
    expected_prerequisites = {
        ("local-aggregate-staged", "fixture-set.local-aggregate-staged@2"),
        (
            "local-directory-subtitle-source-ready",
            "media-source.local-directory-sidecars@1",
        ),
    }
    actual_prerequisites = {
        (item["key"], item["schema"]) for item in scenario["prerequisites"]
    }
    _require(
        actual_prerequisites == expected_prerequisites,
        "external subtitle source matrix lacks its exact Preparation identities",
    )
    declared_states = {
        (state["key"], state["schema"])
        for preparation in preparations.values()
        for state in preparation["produces"]
    }
    _require(
        expected_prerequisites <= declared_states,
        "external subtitle source matrix depends on an undeclared Preparation identity",
    )

    calls = scenario["operations"]
    cursor = 0
    obligations = {item["caseKey"]: item for item in scenario["obligations"]}
    _require(
        tuple(scenario["staticCases"])
        == tuple(item[0] for item in EXTERNAL_SUBTITLE_ATTEMPTS),
        "external subtitle source matrix case order changed",
    )
    for case_key, source_kind, operation_ids in EXTERNAL_SUBTITLE_ATTEMPTS:
        attempt = calls[cursor : cursor + len(operation_ids)]
        cursor += len(operation_ids)
        _require(
            tuple(item["operation"] for item in attempt) == operation_ids,
            f"external subtitle {case_key} attempt call order changed",
        )
        _require(
            attempt[0]["operation"] == "operation:app.relaunch@1",
            f"external subtitle {case_key} attempt is not isolated by relaunch",
        )
        if case_key == "local-sidecar":
            folder = attempt[2]
            _require(
                folder["arguments"]
                == {
                    "context": "main-window-browser",
                    "identifiers": [
                        "MediaLibrary-grid-folder-sdr-bframe-aggregate-30s-sidecars"
                    ],
                },
                "external subtitle local-sidecar must open the imported directory folder",
            )
        selection = attempt[-2]
        capture = attempt[-1]
        expected_selection = {
            "host": "playerUI",
            "sourceKind": source_kind,
            "deadlineSeconds": 30,
        }
        registered_label = EXTERNAL_SUBTITLE_TRACK_LABELS.get(case_key)
        if registered_label is not None:
            expected_selection["trackLabel"] = registered_label
        _require(
            selection["arguments"] == expected_selection,
            f"external subtitle {case_key} must discover and select one dynamic track "
            "behind its registered sidecar label",
        )
        _require(
            capture["arguments"]
            == {
                "context": "window",
                "count": 3,
                "minimumIntervalMillis": 1000,
                "relatedResults": [
                    f"result://{selection['callId']}/{field}"
                    for field in EXTERNAL_SUBTITLE_RELATED_RESULT_FIELDS
                ],
            },
            f"external subtitle {case_key} lacks its immediate post-action capture "
            "bound to its own selection observation",
        )
        obligation = obligations.get(case_key)
        _require(
            obligation is not None
            and obligation["producedByCall"] == capture["callId"]
            and obligation["evidenceType"] == "visual.frames"
            and obligation["evidenceSchema"] == "frame-sequence@2"
            and obligation["oracle"] == "oracle:agent-visual@2",
            f"external subtitle {case_key} lacks mandatory Oracle adjudication",
        )
    _require(
        cursor == len(calls),
        "external subtitle source matrix contains calls outside its isolated attempts",
    )


def _validate_high_risk_playback_semantics(
    scenarios: Sequence[Mapping[str, Any]],
    rubrics: Sequence[Mapping[str, Any]],
) -> None:
    by_id = {item["id"]: item for item in scenarios}

    codec = by_id["scenario:format-coverage:audio-delivery-codec-matrix"]
    codec_calls = codec["operations"]
    producer_indexes = {
        obligation["caseKey"]: next(
            index
            for index, call in enumerate(codec_calls)
            if call["callId"] == obligation["producedByCall"]
        )
        for obligation in codec["obligations"]
    }
    for case_key, track_id in {
        "ac3": "2",
        "eac3-joc": "3",
        "aac": "1",
        "flac": "8",
    }.items():
        selected = [
            identifier
            for call in codec_calls[: producer_indexes[case_key]]
            if call["operation"] == "operation:accessibility.activate@2"
            for identifier in call["arguments"]["identifiers"]
            if identifier.startswith("PlayerUI-menu-audio-")
        ]
        _require(
            selected and selected[-1] == f"PlayerUI-menu-audio-{track_id}",
            f"audio codec case {case_key} does not select stream {track_id}",
        )

    audio = by_id[
        "scenario:local-media-lifecycle:audio-track-switch-same-session"
    ]
    audio_opens = [
        call["arguments"]["identifier"]
        for call in audio["operations"]
        if call["operation"] == "operation:media.open@2"
    ]
    _require(
        audio_opens
        == ["MediaLibrary-grid-video-sdr-bframe-duplicate-label-audio-30s.mkv"]
        and sum(
            call["operation"] == "operation:app.relaunch@1"
            for call in audio["operations"]
        )
        == 1,
        "audio track selection must use the duplicate-label fixture in one session",
    )
    baseline = next(
        call
        for call in audio["operations"]
        if call["operation"] == "operation:diagnostics.playback-state@1"
    )
    captures = [
        call
        for call in audio["operations"]
        if call["operation"] == "operation:evidence.capture-audio@2"
    ]
    _require(
        [call["arguments"].get("expectedAudioTrackID") for call in captures]
        == ["1", "2", "3"]
        and {
            call["arguments"].get("expectedSession") for call in captures
        }
        == {f"result://{baseline['callId']}/session"},
        "audio capture does not bind all three tracks to one session",
    )

    subtitles = by_id["scenario:local-media-lifecycle:subtitle-switch-and-off"]
    _require(
        sum(
            call["operation"] == "operation:app.relaunch@1"
            for call in subtitles["operations"]
        )
        == 1
        and sum(
            call["operation"] == "operation:media.open@2"
            for call in subtitles["operations"]
        )
        == 1,
        "subtitle sequence must remain in one playback session",
    )
    subtitle_items = [
        identifier
        for call in subtitles["operations"]
        if call["operation"] == "operation:accessibility.activate@2"
        for identifier in call["arguments"]["identifiers"]
        if identifier.startswith("PlayerUI-menu-subtitles-")
    ]
    _require(
        subtitle_items
        == [
            "PlayerUI-menu-subtitles-ffmpeg.subtitle.3",
            "PlayerUI-menu-subtitles-ffmpeg.subtitle.5",
            "PlayerUI-menu-subtitles-off",
            "PlayerUI-menu-subtitles-ffmpeg.subtitle.3",
        ],
        "subtitle sequence must select text, bitmap, off, then restore text",
    )

    panorama = by_id["scenario:projection-and-stereo:panorama-coverage-angle"]
    _require(
        [
            call["arguments"].get("horizontalCoverageDegrees")
            for call in panorama["operations"]
            if call["operation"] == "operation:format.apply@2"
            and call["arguments"].get("projection") == "customAngle"
        ]
        == [200, 240],
        "panorama custom-angle cases do not apply 200 and 240 degrees",
    )

    play_next = by_id[
        "scenario:local-media-lifecycle:automatic-play-next-resume-policy"
    ]
    _require(
        [
            call["arguments"]["fileName"]
            for call in play_next["operations"]
            if call["operation"] == "operation:media.import-staged@2"
        ]
        == [
            "sdr-bframe-multiaudio-avsync-30s.mp4",
            "viewing-storage-16m01s.mp4",
        ],
        "Play Next needs one naturally ordered two-item queue whose second item "
        "outlasts ViewingStatePolicy.minimumContentDurationSeconds (15 * 60 s), "
        "so its exit leaves a resumable state to advance into",
    )
    baseline = next(
        call
        for call in play_next["operations"]
        if call["operation"] == "operation:diagnostics.playback-state@1"
    )
    terminal_wait = next(
        (
            call
            for call in play_next["operations"]
            if call["operation"] == "operation:playback.wait-position@2"
            and "differentSessionFrom" in call["arguments"]
        ),
        None,
    )
    _require(
        terminal_wait is not None
        and terminal_wait["arguments"].get("expectedMediaName")
        == "viewing-storage-16m01s.mp4"
        and terminal_wait["arguments"].get("differentSessionFrom")
        == f"result://{baseline['callId']}/session",
        "Play Next does not wait for the exact next media and a new session",
    )
    rubric = next(
        item
        for item in rubrics
        if item["id"]
        == "rubric:local-media-lifecycle.automatic-play-next-resume-policy.o01@1"
    )
    rubric_text = "\n".join(rubric["criteria"] + rubric["negativeControls"])
    _require(
        all(
            token in rubric_text
            for token in (
                "resumePromptPresentations=1",
                "automaticResumeBypasses=1",
                "pendingResumePrompt=false",
            )
        ),
        "Play Next Rubric omits its direct-versus-automatic prompt counters",
    )


def _validate_blueprint(
    blueprint: Mapping[str, Any],
    operation_runtime: Mapping[str, Mapping[str, Any]] | None = None,
    oracle_runtime: Mapping[str, Mapping[str, Any]] | None = None,
    preparation_runtime: Mapping[str, Mapping[str, Any]] | None = None,
) -> None:
    required = {
        "schemaVersion",
        "contentDigest",
        "expectedCounts",
        "objective",
        "copyDocuments",
        "analysisFactValues",
        "promises",
        "operations",
        "oracles",
        "rubrics",
        "preparations",
        "journeys",
        "scenarios",
    }
    _require(set(blueprint) == required, "blueprint top-level keys are invalid")
    if operation_runtime is None:
        operation_runtime = _operation_runtime_shapes()
    if oracle_runtime is None:
        oracle_runtime = _oracle_runtime_shapes()
    if preparation_runtime is None:
        preparation_runtime = _preparation_runtime_shapes()
    copy_paths: list[str] = []
    for index, item in enumerate(blueprint["copyDocuments"]):
        _require(
            isinstance(item, Mapping) and set(item) == {"path", "digest"},
            f"copyDocuments[{index}] is invalid",
        )
        relative = item["path"]
        _require(
            isinstance(relative, str)
            and relative
            and not Path(relative).is_absolute()
            and ".." not in Path(relative).parts,
            f"copyDocuments[{index}].path is unsafe",
        )
        _require(
            isinstance(item["digest"], str) and SHA256.fullmatch(item["digest"]),
            f"copyDocuments[{index}].digest is invalid",
        )
        copy_paths.append(relative)
    _require(
        len(copy_paths) == len(set(copy_paths)),
        "copyDocuments repeats an output path",
    )
    _require(
        {relative for relative in copy_paths if "/" not in relative}
        == PERSISTENT_ROOT_DOCUMENTS,
        "copyDocuments must contain the exact persistent root documents",
    )
    _require(
        "human-coverage-questions.md" not in copy_paths
        and not any(
            relative == "reviews" or relative.startswith("reviews/")
            for relative in copy_paths
        ),
        "copyDocuments must exclude retired questions and review history",
    )
    _require(
        all(
            len(Path(relative).parts) == 2
            and Path(relative).parts[0] in PERSISTENT_SOURCE_DIRECTORIES
            and Path(relative).suffix == ".md"
            for relative in copy_paths
            if "/" in relative
        ),
        "copyDocuments contains an unsupported persistent source path",
    )
    semantic_authority = next(
        item for item in blueprint["copyDocuments"]
        if item["path"] == "semantic-authority.json"
    )
    _require(
        semantic_authority["digest"]
        == preparation_adapter.SEMANTIC_AUTHORITY_DIGEST,
        "semantic authority source drifted from the Preparation registry",
    )
    for index, item in enumerate(blueprint["operations"]):
        _require(
            isinstance(item, Mapping) and set(item) == OPERATION_BLUEPRINT_KEYS,
            f"Operation runtime shape is forbidden in blueprint operations[{index}]",
        )
    for index, item in enumerate(blueprint["oracles"]):
        _require(
            isinstance(item, Mapping) and set(item) == ORACLE_BLUEPRINT_KEYS,
            f"Oracle runtime shape is forbidden in blueprint oracles[{index}]",
        )
    for index, item in enumerate(blueprint["preparations"]):
        _require(
            isinstance(item, Mapping) and set(item) == PREPARATION_BLUEPRINT_KEYS,
            f"Preparation runtime shape is forbidden in blueprint preparations[{index}]",
        )
    _require(
        blueprint["objective"]
        == {
            "preparationReadiness": "declared",
            "scenarioReadiness": "declared",
        },
        "the v2 objective must require declared Preparation and Scenario gaps",
    )
    expected = blueprint["expectedCounts"]
    actual = {
        "promises": len(blueprint["promises"]) + _persistent_promise_count(),
        "operations": len(blueprint["operations"]),
        "oracles": len(blueprint["oracles"]),
        "rubrics": len(blueprint["rubrics"]),
        "preparations": len(blueprint["preparations"]),
        "journeys": len(blueprint["journeys"]),
        "scenarios": len(blueprint["scenarios"]),
        "staticCases": sum(len(item["staticCases"]) for item in blueprint["scenarios"]),
    }
    _require(actual == expected, f"blueprint count mismatch: expected {expected}, found {actual}")
    _require(actual["promises"] == 65 and actual["scenarios"] == 65, "Catalog must contain 65 Promises and 65 Scenarios")
    _require(actual["operations"] == 35, "Catalog must contain 35 Operations")
    _require(actual["oracles"] == 11, "Catalog must contain 11 Oracles")
    _require(actual["journeys"] == 14, "Catalog must contain 14 Journeys")

    all_strings = tuple(_walk_strings(blueprint))
    _require("evidence-bundle" not in all_strings, "evidence-bundle is forbidden")
    _require(not (set(all_strings) & RETIRED_OPERATION_IDS), "blueprint references retired v1 Operation")
    _require(not (set(all_strings) & RETIRED_ORACLE_IDS), "blueprint references retired v1 Oracle")
    runtime_values = {value.lower() for value in all_strings}
    forbidden_runtime = sorted(runtime_values & FORBIDDEN_RUNTIME_VALUES)
    _require(not forbidden_runtime, f"forbidden runtime outcome/actor: {', '.join(forbidden_runtime)}")

    operation_metadata = {item["id"]: item for item in blueprint["operations"]}
    oracle_metadata = {item["id"]: item for item in blueprint["oracles"]}
    preparation_metadata = {item["id"]: item for item in blueprint["preparations"]}
    operations = {
        identifier: {**operation_metadata[identifier], **runtime}
        for identifier, runtime in operation_runtime.items()
        if identifier in operation_metadata
    }
    oracles = {
        identifier: {**oracle_metadata[identifier], **runtime}
        for identifier, runtime in oracle_runtime.items()
        if identifier in oracle_metadata
    }
    preparations = {
        identifier: {**preparation_metadata[identifier], **runtime}
        for identifier, runtime in preparation_runtime.items()
        if identifier in preparation_metadata
    }
    _require(
        set(operation_metadata) == set(operation_runtime),
        "blueprint Operation IDs do not exactly match the runtime registry",
    )
    _require(
        set(oracle_metadata) == set(oracle_runtime),
        "blueprint Oracle IDs do not exactly match the runtime registry",
    )
    _require(
        set(preparation_metadata) == set(preparation_runtime),
        "blueprint Preparation IDs do not exactly match the runtime registry",
    )
    rubrics = {item["id"] for item in blueprint["rubrics"]}
    _require(len(operations) == 35, "Operation IDs must be unique")
    _require(len(oracles) == 11, "Oracle IDs must be unique")
    global_calls: set[str] = set()
    for preparation in preparations.values():
        _validate_node_calls(
            preparation["id"], preparation["operations"], global_calls, preparation["lane"]
        )
        if preparation["readiness"] == "ready":
            _require(preparation["operations"] and preparation["produces"], f"{preparation['id']} is ready without producers")
        else:
            _require(
                len(preparation["produces"]) == 1
                and preparation["produces"][0]["producedByCall"] is None,
                f"{preparation['id']} lacks its non-ready semantic state declaration",
            )
            _require(preparation["blockers"], f"{preparation['id']} needs typed blockers")

    _validate_registered_media_basenames(blueprint["scenarios"])
    _validate_scenario_media_bindings(blueprint["scenarios"], preparations)
    _validate_scenario_time_bounds(blueprint["scenarios"])
    _validate_external_subtitle_matrix(blueprint["scenarios"], preparations)
    _validate_high_risk_playback_semantics(
        blueprint["scenarios"], blueprint["rubrics"]
    )

    scenario_ids = {item["id"] for item in blueprint["scenarios"]}
    _require(len(scenario_ids) == 65, "Scenario IDs must be unique")
    obligation_ids: set[str] = set()
    for scenario in blueprint["scenarios"]:
        _require(
            scenario["readiness"] in {"ready", "implementation-gap"},
            f"{scenario['id']} has invalid readiness",
        )
        _require(
            isinstance(scenario["blockers"], list),
            f"{scenario['id']} blockers must be an array",
        )
        blocker_capabilities: set[str] = set()
        for blocker in scenario["blockers"]:
            _require(
                isinstance(blocker, Mapping)
                and set(blocker) == {"kind", "capability", "detail"},
                f"{scenario['id']} has an invalid blocker",
            )
            _require(
                blocker["kind"] == "implementation-gap",
                f"{scenario['id']} blocker kind must be implementation-gap",
            )
            capability = blocker["capability"]
            _require(
                isinstance(capability, str)
                and capability
                and not capability.startswith("producer:"),
                f"{scenario['id']} has a generic producer blocker",
            )
            _require(
                capability.startswith(("operation:", "evidence:")),
                f"{scenario['id']} blocker does not name a typed missing capability",
            )
            _require(
                capability not in blocker_capabilities,
                f"{scenario['id']} repeats a missing capability",
            )
            blocker_capabilities.add(capability)
            _require(
                isinstance(blocker["detail"], str) and blocker["detail"].strip(),
                f"{scenario['id']} blocker needs a precise detail",
            )
        _require(scenario["staticCases"] and len(scenario["staticCases"]) == len(set(scenario["staticCases"])), f"{scenario['id']} staticCases are not explicit and unique")
        _validate_node_calls(
            scenario["id"], scenario["operations"], global_calls, scenario["lane"]
        )
        calls = {call["callId"]: call for call in scenario["operations"]}
        obligations = scenario["obligations"]
        _require(obligations, f"{scenario['id']} has no obligation")
        local_ids = {item["id"] for item in obligations}
        _require(len(local_ids) == len(obligations), f"{scenario['id']} repeats an obligation")
        _require(not (local_ids & obligation_ids), f"{scenario['id']} repeats a global obligation")
        obligation_ids.update(local_ids)
        refs = _success_refs(scenario["success"])
        _require(len(refs) == len(set(refs)) and set(refs) == local_ids, f"{scenario['id']} SuccessExpression does not compose every obligation exactly once")
        for obligation in obligations:
            _require(obligation["caseKey"] in scenario["staticCases"], f"{obligation['id']} binds an undeclared case")
            pair = {"evidenceType": obligation["evidenceType"], "evidenceSchema": obligation["evidenceSchema"]}
            oracle = oracles.get(obligation["oracle"])
            _require(oracle is not None and pair in oracle["evidenceSchemas"], f"{obligation['id']} Oracle evidence pair mismatch")
            _require(obligation["rubric"] in rubrics, f"{obligation['id']} names unknown Rubric")
            producer_id = obligation["producedByCall"]
            if scenario["readiness"] == "ready":
                _require(not scenario["blockers"], f"{scenario['id']} is ready with blockers")
                _require(producer_id in calls, f"{obligation['id']} lacks an exact producer")
                producer = operations[calls[producer_id]["operation"]]
                _require(pair in producer["evidenceSchemas"], f"{obligation['id']} producer evidence pair mismatch")
            else:
                _require(not scenario["operations"] and producer_id is None, f"{scenario['id']} fabricates calls while non-ready")
                _require(scenario["blockers"], f"{scenario['id']} needs typed blockers")

    _require(
        len(obligation_ids) == 149,
        "Catalog must contain exactly 149 globally unique obligations",
    )

    _validate_transition_trace_sequences(blueprint["scenarios"])

    edge_sequence: list[tuple[str, str]] = []
    for journey in blueprint["journeys"]:
        members = set(journey["scenarioRefs"])
        for edge in journey["ordering"]:
            pair = (edge["before"], edge["after"])
            _require(
                pair[0] in members and pair[1] in members,
                f"{journey['id']} ordering edges must stay within its Journey",
            )
            edge_sequence.append(pair)
    edges = set(edge_sequence)
    _require(
        len(edge_sequence) == len(edges) == len(EXACT_JOURNEY_EDGES),
        "Journey graph contains ordering without a declared shared-state handoff",
    )
    _require(
        edges == EXACT_JOURNEY_EDGES,
        "Journey graph contains ordering without a declared shared-state handoff",
    )
    _require(all(before in scenario_ids and after in scenario_ids for before, after in edges), "Journey edge references unknown Scenario")


def _expected_paths(blueprint: Mapping[str, Any]) -> set[str]:
    paths = {
        item["path"]
        for item in blueprint["copyDocuments"]
    }
    paths.update(f"promises/{feature}.md" for feature in {item["feature"] for item in blueprint["promises"]})
    paths.update(f"operations/{item['filename']}" for item in blueprint["operations"])
    paths.update(f"oracles/{item['filename']}" for item in blueprint["oracles"])
    paths.update(f"rubrics/{item['filename']}" for item in blueprint["rubrics"])
    paths.update(f"preparations/{item['filename']}" for item in blueprint["preparations"])
    for journey in blueprint["journeys"]:
        paths.add(f"journeys/{journey['id'].removeprefix('journey:')}/journey.md")
    for scenario in blueprint["scenarios"]:
        journey = scenario["journey"].removeprefix("journey:")
        paths.add(f"journeys/{journey}/scenarios/{scenario['id'].rsplit(':', 1)[-1]}.md")
    return paths


def _catalog_digest(root: Path, paths: Iterable[str]) -> str:
    digest = hashlib.sha256()
    for relative in sorted(paths):
        digest.update(relative.encode("utf-8"))
        digest.update(b"\0")
        digest.update((root / relative).read_bytes())
        digest.update(b"\0")
    return "sha256:" + digest.hexdigest()


def _load_and_analyze(root: Path, blueprint: Mapping[str, Any]) -> Mapping[str, Any]:
    repository_text = str(REPOSITORY_ROOT)
    if repository_text not in sys.path:
        sys.path.insert(0, repository_text)
    try:
        from Scripts.regression.core.applicability import ReviewedFact
        from Scripts.regression.core.catalog import load_catalog
        from Scripts.regression.core.compiler import analyze_catalog
        from Scripts.regression.core.contracts import BoundLane
        from Scripts.regression.core.ids import Digest
        from Scripts.regression.core.plan import (
            AgentEnvironment,
            BuildIdentity,
            CompileRequest,
            EvidenceEnvironmentIdentity,
            FullSelector,
            LaneBuildArtifact,
            ToolchainIdentity,
        )
    except (ImportError, AttributeError) as error:
        return {"status": "unavailable", "reason": str(error)}

    catalog = load_catalog(root)
    fact_values = blueprint["analysisFactValues"]
    zero = Digest("sha256:" + "0" * 64)
    one = Digest("sha256:" + "1" * 64)
    two = Digest("sha256:" + "2" * 64)
    three = Digest("sha256:" + "3" * 64)
    four = Digest("sha256:" + "4" * 64)
    five = Digest("sha256:" + "5" * 64)
    six = Digest("sha256:" + "6" * 64)
    seven = Digest("sha256:" + "7" * 64)
    reviewed_facts = tuple(
        ReviewedFact(fact.id, fact_values[str(fact.id)], fact.source_digest, zero)
        for fact in catalog.facts
    )
    request = CompileRequest(
        FullSelector(),
        reviewed_facts,
        (BoundLane.SIMULATOR, BoundLane.DEVICE),
        BuildIdentity(
            "dev.rench.Enchron",
            "catalog-v2-analysis",
            zero,
            one,
            ToolchainIdentity(
                "catalog-v2",
                "catalog-v2",
                "visionOS",
                "catalog-v2",
                "visionOS Simulator",
                "catalog-v2",
            ),
            (
                LaneBuildArtifact(BoundLane.SIMULATOR, two, three, four),
                LaneBuildArtifact(BoundLane.DEVICE, five, six, seven),
            ),
        ),
        EvidenceEnvironmentIdentity(
            {operation.id: zero for operation in catalog.operations},
            AgentEnvironment("catalog-v2-analysis", zero, one),
        ),
    )
    analysis = analyze_catalog(catalog, request)
    return {
        "status": "loaded-and-analyzed",
        "coreCatalogDigest": str(catalog.digest),
        "selectedScenarios": len(analysis.selected_scenarios),
        "journeyDependencies": [
            {
                "before": str(item.predecessor),
                "after": str(item.successor),
            }
            for item in analysis.journey_dependencies
        ],
        "scenarioReadiness": dict(
            sorted(Counter(item.readiness.value for item in analysis.scenario_readiness).items())
        ),
        "preparationReadiness": dict(
            sorted(Counter(item.readiness.value for item in analysis.preparation_readiness).items())
        ),
    }


def _compare_live(generated: Path, live: Path, expected: set[str]) -> None:
    live = live.resolve()
    _require(live.is_dir(), f"check root is not a directory: {live}")
    actual: set[str] = set()
    actual_directories: set[str] = set()
    for candidate in live.rglob("*"):
        relative_path = candidate.relative_to(live)
        if relative_path.parts[0] == "reviews":
            continue
        relative = relative_path.as_posix()
        if candidate.is_file():
            actual.add(relative)
        elif candidate.is_dir():
            actual_directories.add(relative)
    expected_directories = {
        parent.as_posix()
        for relative in expected
        for parent in Path(relative).parents
        if parent != Path(".")
    }
    missing = sorted(expected - actual)
    extra = sorted(actual - expected)
    extra_directories = sorted(actual_directories - expected_directories)
    changed = sorted(
        relative
        for relative in expected & actual
        if (generated / relative).read_bytes() != (live / relative).read_bytes()
    )
    if missing or extra or extra_directories or changed:
        details = []
        if missing:
            details.append("missing=" + ",".join(missing))
        if extra:
            details.append("extra=" + ",".join(extra))
        if extra_directories:
            details.append(
                "extraDirectories=" + ",".join(extra_directories)
            )
        if changed:
            details.append("changed=" + ",".join(changed))
        raise MaterializationError("live Catalog differs: " + "; ".join(details))


def materialize(blueprint_path: Path, output_root: Path, report_path: Path, check_root: Path | None) -> Mapping[str, Any]:
    blueprint = _load_blueprint(blueprint_path)
    semantic_authority_source = _semantic_authority_source_identity()
    operation_runtime = _operation_runtime_shapes()
    oracle_runtime = _oracle_runtime_shapes()
    preparation_runtime = _preparation_runtime_shapes()
    _validate_blueprint(
        blueprint, operation_runtime, oracle_runtime, preparation_runtime
    )
    root = _prepare_output_root(output_root)
    resolved_report = report_path.resolve()
    _require(
        resolved_report != root and root not in resolved_report.parents,
        "report must be outside the staged Catalog root",
    )
    written: set[str] = set()
    _copy_documents(blueprint, root, written)
    _render_promises(blueprint, root, written)
    _render_operations(blueprint, operation_runtime, root, written)
    _render_oracles(blueprint, oracle_runtime, root, written)
    _render_rubrics(blueprint, root, written)
    _render_preparations(blueprint, preparation_runtime, root, written)
    _render_journeys(blueprint, root, written)
    _render_scenarios(blueprint, root, written)
    expected = _expected_paths(blueprint)
    _require(written == expected, f"rendered manifest mismatch: missing={sorted(expected-written)}, extra={sorted(written-expected)}")
    disk_paths = {path.relative_to(root).as_posix() for path in root.rglob("*") if path.is_file()}
    _require(disk_paths == expected, f"stale output files: {sorted(disk_paths-expected)}")
    analysis = _load_and_analyze(root, blueprint)
    readiness = Counter(item["readiness"] for item in blueprint["scenarios"])
    preparation_readiness = Counter(
        item["readiness"] for item in preparation_runtime.values()
    )
    declared_scenario_readiness = dict(sorted(readiness.items()))
    declared_preparation_readiness = dict(sorted(preparation_readiness.items()))
    _require(
        analysis.get("status") == "loaded-and-analyzed",
        "compiler analysis is unavailable: "
        + str(analysis.get("reason", analysis.get("status", "unknown failure"))),
    )
    _require(
        analysis.get("selectedScenarios") == len(blueprint["scenarios"]),
        "compiler analysis did not select every Catalog v2 Scenario",
    )
    _require(
        {
            (item["before"], item["after"])
            for item in analysis.get("journeyDependencies", ())
        }
        == EXACT_JOURNEY_EDGES,
        "compiler analysis Journey dependencies differ from the reviewed state handoffs",
    )
    _require(
        analysis.get("scenarioReadiness") == declared_scenario_readiness,
        "compiler analysis Scenario readiness differs from the staged declarations",
    )
    _require(
        analysis.get("preparationReadiness") == declared_preparation_readiness,
        "compiler analysis Preparation readiness differs from the runtime registry",
    )
    obligation_pairs = Counter(
        f"{item['evidenceType']}|{item['evidenceSchema']}"
        for scenario in blueprint["scenarios"]
        for item in scenario["obligations"]
    )
    report = {
        "schemaVersion": 2,
        "blueprintDigest": blueprint["contentDigest"],
        "catalogDigest": _catalog_digest(root, expected),
        "counts": blueprint["expectedCounts"],
        "objective": blueprint["objective"],
        "callCount": (
            sum(len(item["operations"]) for item in preparation_runtime.values())
            + sum(len(item["operations"]) for item in blueprint["scenarios"])
        ),
        "obligationCount": sum(len(item["obligations"]) for item in blueprint["scenarios"]),
        "obligationsByEvidenceSchema": dict(sorted(obligation_pairs.items())),
        "scenarioReadiness": declared_scenario_readiness,
        "scenarioReadinessGaps": [
            {"id": item["id"], "blockers": item["blockers"]}
            for item in blueprint["scenarios"]
            if item["readiness"] != "ready"
        ],
        "preparationReadiness": declared_preparation_readiness,
        "preparationReadinessGaps": [
            {"id": identifier, "blockers": runtime["blockers"]}
            for identifier, runtime in sorted(preparation_runtime.items())
            if runtime["readiness"] != "ready"
        ],
        "runtimeAuthorities": {
            "semanticAuthorityDecisionSource": semantic_authority_source,
            "operationImplementations": {
                identifier: runtime["implementation"]
                for identifier, runtime in sorted(operation_runtime.items())
            },
            "oracleImplementations": {
                identifier: runtime["implementation"]
                for identifier, runtime in sorted(oracle_runtime.items())
            },
            "preparationRegistryDigest": preparation_adapter.REGISTRY_DIGEST,
            "preparationImplementations": {
                identifier: runtime["implementation"]
                for identifier, runtime in sorted(preparation_runtime.items())
            },
            "preparationPlanProjections": {
                identifier: runtime["planProjection"]
                for identifier, runtime in sorted(preparation_runtime.items())
            },
        },
        "journeyEdges": [list(edge) for edge in sorted(EXACT_JOURNEY_EDGES)],
        "coreAnalysis": analysis,
        "expectedPaths": sorted(expected),
    }
    if check_root is not None:
        _compare_live(root, check_root, expected)
        report["check"] = "matched"
    resolved_report.parent.mkdir(parents=True, exist_ok=True)
    resolved_report.write_bytes(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True).encode("utf-8") + b"\n")
    return report


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--blueprint", required=True, type=Path)
    parser.add_argument("--output-root", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--check", nargs="?", const=LIVE_CATALOG_ROOT, type=Path)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        report = materialize(args.blueprint, args.output_root, args.report, args.check)
    except MaterializationError as error:
        print(f"catalog-v2 materialization failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps({"catalogDigest": report["catalogDigest"], "counts": report["counts"]}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
