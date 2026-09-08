from __future__ import annotations

import csv
from collections.abc import Mapping as MappingABC
from dataclasses import dataclass
from datetime import datetime
import io
import json
import os
from pathlib import Path
import re
from types import MappingProxyType
import sys
import tempfile
from typing import Any, Dict, Iterable, List, Mapping, Sequence, Tuple

from .core.applicability import ReviewedFact
from .core.catalog import load_catalog
from .core.compiler import analyze_catalog
from .core.contracts import (
    BoundLane,
    DraftCatalog,
    FactDeclaration,
    JourneyContract,
    OperationContract,
    OracleContract,
    PreparationContract,
    PromiseContract,
    RubricContract,
    ScenarioContract,
)
from .core.digest import (
    canonical_bytes,
    canonical_digest,
    digest_bytes,
    digest_text_file,
)
from .core.errors import RegressionError
from .core.frontmatter import parse_frontmatter
from .core.ids import Digest, FactID, parse_identifier
from .core.plan import (
    AgentEnvironment,
    BuildIdentity,
    CompileRequest,
    EvidenceEnvironmentIdentity,
    FullSelector,
    LaneBuildArtifact,
    ToolchainIdentity,
)
from .core.review import (
    BudgetAmount,
    BudgetApprovedReview,
    BudgetUnit,
    PlannedReview,
    ReviewActorIdentity,
    ReviewClass,
    ReviewPacket,
    ReviewPolicy,
    ReviewReceipt,
    ReviewUnitKind,
    ReviewUsage,
    approve_review_budgets,
)
from .core.review_catalog import plan_catalog_reviews
from .review_io import (
    load_review_assessment,
    load_review_policy,
    load_review_receipts,
    load_review_report,
    report_bytes,
    write_review_assessment,
    write_review_receipt,
    write_review_report,
)


PACKET_MANIFEST_SCHEMA = "enchron.regression.review-packet-manifest"
AGENT_ASSESSMENT_SCHEMA = "enchron.regression.agent-operability-assessment"
REVIEW_REPORT_SCHEMA = "enchron.regression.review-report"
SCHEMA_VERSION = 1

DETERMINISTIC_ACTOR_ID = "checker:regression-review-stage"
AGENT_REVIEW_RUNTIME = "codex-agent-operability-v1"
AGENT_REVIEW_PROTOCOL_PATH = Path(
    "Regression/agent-operability-review-protocol.md"
)
SEMANTIC_AUTHORITY_PATH = Path("Regression/semantic-authority.json")
DERIVED_HUMAN_ACTOR_ID = "authority:approved-composite-design"
DERIVED_HUMAN_RUNTIME = "semantic-authority-derivation-v1"
_CATALOG_SCOPE_FACT = FactID("fact:runtime.catalog-scope-included")
_EXPECTED_PROMISES = 65
_EXPECTED_SCENARIOS = 70

_CONTRACT_KIND = (
    (PromiseContract, ReviewUnitKind.PROMISE),
    (FactDeclaration, ReviewUnitKind.FACT),
    (PreparationContract, ReviewUnitKind.PREPARATION),
    (OperationContract, ReviewUnitKind.OPERATION),
    (OracleContract, ReviewUnitKind.ORACLE),
    (RubricContract, ReviewUnitKind.RUBRIC),
    (JourneyContract, ReviewUnitKind.JOURNEY),
    (ScenarioContract, ReviewUnitKind.SCENARIO),
)

_CHECKER_SOURCE_PATHS = (
    "Scripts/regression/review_stage.py",
    "Scripts/regression/review_io.py",
    "Scripts/regression/core/applicability.py",
    "Scripts/regression/core/catalog.py",
    "Scripts/regression/core/compiler.py",
    "Scripts/regression/core/contracts.py",
    "Scripts/regression/core/digest.py",
    "Scripts/regression/core/frontmatter.py",
    "Scripts/regression/core/plan.py",
    "Scripts/regression/core/review.py",
    "Scripts/regression/core/review_catalog.py",
)


class _DuplicateKeyError(ValueError):
    pass


class _InvalidConstantError(ValueError):
    pass


@dataclass(frozen=True)
class PreparedReview:
    catalog_digest: Digest
    plan_digest: Digest
    policy_digest: Digest
    approval_digest: Digest
    manifest_paths: Tuple[Path, ...]


@dataclass(frozen=True)
class IssuedReview:
    receipt: ReviewReceipt
    report_path: Path
    receipt_path: Path


@dataclass(frozen=True)
class DeterministicReviewResult:
    catalog_digest: Digest
    plan_digest: Digest
    environment_digest: Digest
    issued: Tuple[IssuedReview, ...]


@dataclass(frozen=True)
class DerivedHumanCoverageResult:
    catalog_digest: Digest
    plan_digest: Digest
    authority_digest: Digest
    issued: Tuple[IssuedReview, ...]


@dataclass(frozen=True)
class ReviewStatus:
    catalog_digest: Digest
    plan_digest: Digest
    policy_digest: Digest
    approval_digest: Digest
    total: Mapping[ReviewClass, int]
    completed: Mapping[ReviewClass, int]
    pending: Mapping[ReviewClass, int]

    def as_payload(self) -> Mapping[str, Any]:
        return {
            "catalogDigest": str(self.catalog_digest),
            "planDigest": str(self.plan_digest),
            "policyDigest": str(self.policy_digest),
            "approvalDigest": str(self.approval_digest),
            "total": {
                reviewer.value: self.total[reviewer]
                for reviewer in ReviewClass
            },
            "completed": {
                reviewer.value: self.completed[reviewer]
                for reviewer in ReviewClass
            },
            "pending": {
                reviewer.value: self.pending[reviewer]
                for reviewer in ReviewClass
            },
        }


@dataclass(frozen=True)
class _ReviewContext:
    repository_root: Path
    catalog_root: Path
    catalog: DraftCatalog
    policy: ReviewPolicy
    planned: PlannedReview
    approved: BudgetApprovedReview
    source_paths: Mapping[Tuple[str, str], str]


@dataclass(frozen=True)
class _AgentAssessment:
    source: Mapping[str, Any]
    actor: ReviewActorIdentity
    usage: ReviewUsage
    issued_at: str


@dataclass(frozen=True)
class _SemanticAuthority:
    digest: Digest
    kind: str
    decision_ids: Tuple[str, ...]
    decision_log_path: str
    decision_log_digest: Digest


def _error(code: str, location: str, detail: str) -> RegressionError:
    return RegressionError(code, location, detail)


def _object_without_duplicates(pairs: List[Tuple[str, Any]]) -> Dict[str, Any]:
    result: Dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise _DuplicateKeyError(key)
        result[key] = value
    return result


def _reject_constant(value: str) -> Any:
    raise _InvalidConstantError(value)


def _keys(
    value: object, required: Iterable[str], location: str
) -> Mapping[str, Any]:
    if not isinstance(value, MappingABC):
        raise _error("review.stage.not_object", location, "expected a JSON object")
    expected = frozenset(required)
    unknown = sorted(set(value) - expected)
    missing = sorted(expected - set(value))
    if unknown:
        raise _error(
            "review.stage.unknown_field",
            location,
            "unknown field(s): " + ", ".join(unknown),
        )
    if missing:
        raise _error(
            "review.stage.missing_field",
            location,
            "missing field(s): " + ", ".join(missing),
        )
    return value


def _canonical_json(path: Path) -> Mapping[str, Any]:
    path = Path(path)
    source = path.read_bytes()
    if not source.endswith(b"\n"):
        raise _error(
            "review.stage.noncanonical_json",
            str(path),
            "assessment JSON must end with one newline",
        )
    try:
        value = json.loads(
            source.decode("utf-8"),
            object_pairs_hook=_object_without_duplicates,
            parse_constant=_reject_constant,
        )
    except UnicodeDecodeError as error:
        raise _error(
            "review.stage.invalid_utf8", str(path), "assessment must be UTF-8"
        ) from error
    except _DuplicateKeyError as error:
        raise _error(
            "review.stage.duplicate_field",
            str(path),
            f"JSON field {error.args[0]!r} appears more than once",
        ) from error
    except (_InvalidConstantError, json.JSONDecodeError) as error:
        raise _error(
            "review.stage.invalid_json", str(path), f"invalid JSON: {error}"
        ) from error
    try:
        canonical_source = canonical_bytes(value) + b"\n"
    except (TypeError, UnicodeEncodeError, ValueError) as error:
        raise _error(
            "review.stage.invalid_json", str(path), "assessment is not canonical JSON"
        ) from error
    if canonical_source != source:
        raise _error(
            "review.stage.noncanonical_json",
            str(path),
            "assessment JSON must use canonical encoding",
        )
    if not isinstance(value, MappingABC):
        raise _error("review.stage.not_object", str(path), "expected a JSON object")
    return value


def _repository_path(repository_root: Path, value: Path, location: str) -> Path:
    candidate = Path(value)
    if not candidate.is_absolute():
        candidate = repository_root / candidate
    try:
        resolved = candidate.resolve(strict=True)
    except FileNotFoundError as error:
        raise _error("review.stage.missing_path", str(candidate), location) from error
    try:
        resolved.relative_to(repository_root)
    except ValueError as error:
        raise _error(
            "review.stage.path.outside_repository",
            str(candidate),
            f"{location} must stay inside the repository",
        ) from error
    return resolved


_MARKDOWN_HEADING = re.compile(
    r"^ {0,3}#{1,6}[ \t]+(?P<heading>.*?)(?:[ \t]+#+[ \t]*)?$"
)
_SOURCE_IDENTIFIER = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")


def _evidence_anchor_error(path: Path, location: str, detail: str) -> RegressionError:
    return _error(
        "review.stage.semantic_authority.evidence.anchor",
        f"{location} ({path})",
        detail,
    )


def _text_evidence(path: Path, location: str) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except UnicodeDecodeError as error:
        raise _evidence_anchor_error(
            path,
            location,
            "an anchored evidence file must be UTF-8",
        ) from error


def _json_has_key(value: object, anchor: str) -> bool:
    if isinstance(value, MappingABC):
        return anchor in value or any(
            _json_has_key(item, anchor) for item in value.values()
        )
    if isinstance(value, list):
        return any(_json_has_key(item, anchor) for item in value)
    return False


def _semantic_authority_evidence_anchor(
    path: Path,
    anchor: str,
    location: str,
) -> None:
    source = _text_evidence(path, location)
    suffix = path.suffix.lower()
    if suffix == ".md":
        headings = tuple(
            match.group("heading").strip()
            for line in source.splitlines()
            if (match := _MARKDOWN_HEADING.fullmatch(line)) is not None
        )
        if anchor not in headings:
            raise _evidence_anchor_error(
                path,
                location,
                f"Markdown heading {anchor!r} does not exist",
            )
        return
    if suffix in {".swift", ".py"}:
        if _SOURCE_IDENTIFIER.fullmatch(anchor) is None:
            raise _evidence_anchor_error(
                path,
                location,
                "source anchors must be identifiers",
            )
        token = re.compile(
            rf"(?<![A-Za-z0-9_]){re.escape(anchor)}(?![A-Za-z0-9_])"
        )
        if token.search(source) is None:
            raise _evidence_anchor_error(
                path,
                location,
                f"source identifier {anchor!r} does not exist",
            )
        return
    if suffix == ".json":
        try:
            document = json.loads(
                source,
                object_pairs_hook=_object_without_duplicates,
                parse_constant=_reject_constant,
            )
        except (_DuplicateKeyError, _InvalidConstantError, json.JSONDecodeError) as error:
            raise _evidence_anchor_error(
                path,
                location,
                f"anchored JSON is invalid: {error}",
            ) from error
        if not _json_has_key(document, anchor):
            raise _evidence_anchor_error(
                path,
                location,
                f"JSON key {anchor!r} does not exist",
            )
        return
    if suffix == ".tsv":
        try:
            rows = tuple(csv.reader(io.StringIO(source), delimiter="\t", strict=True))
        except csv.Error as error:
            raise _evidence_anchor_error(
                path,
                location,
                f"anchored TSV is invalid: {error}",
            ) from error
        if not rows or not rows[0] or not any(
            row and row[0] == anchor for row in rows[1:]
        ):
            raise _evidence_anchor_error(
                path,
                location,
                f"TSV first-column record {anchor!r} does not exist",
            )
        return
    raise _evidence_anchor_error(
        path,
        location,
        "anchors are supported only for Markdown headings, source identifiers, "
        "JSON keys, and TSV first-column records",
    )


def _semantic_authority_evidence_locator(
    repository_root: Path,
    locator: object,
    location: str,
) -> Path:
    if (
        not isinstance(locator, str)
        or not locator
        or locator != locator.strip()
        or locator.count("#") > 1
    ):
        raise _error(
            "review.stage.semantic_authority.evidence.locator",
            location,
            "evidence locators must use repository/path.ext or "
            "repository/path.ext#anchor",
        )
    path_text, separator, anchor = locator.partition("#")
    if (
        not path_text
        or any(character.isspace() for character in path_text)
        or "\\" in path_text
        or (separator and (not anchor or anchor != anchor.strip()))
    ):
        raise _error(
            "review.stage.semantic_authority.evidence.locator",
            location,
            "evidence locators must use repository/path.ext or "
            "repository/path.ext#anchor",
        )
    relative = Path(path_text)
    if relative.is_absolute() or ".." in relative.parts:
        raise _error(
            "review.stage.semantic_authority.evidence.outside_repository",
            location,
            "evidence paths must stay inside the repository",
        )
    if relative.as_posix() != path_text or "." in relative.parts:
        raise _error(
            "review.stage.semantic_authority.evidence.locator",
            location,
            "evidence paths must use canonical repository-relative POSIX syntax",
        )
    candidate = repository_root / relative
    try:
        resolved = candidate.resolve(strict=True)
    except FileNotFoundError as error:
        raise _error(
            "review.stage.semantic_authority.evidence.missing_path",
            location,
            f"evidence path {path_text!r} does not exist",
        ) from error
    try:
        resolved.relative_to(repository_root)
    except ValueError as error:
        raise _error(
            "review.stage.semantic_authority.evidence.outside_repository",
            location,
            f"evidence path {path_text!r} escapes the repository",
        ) from error
    if not resolved.is_file():
        raise _error(
            "review.stage.semantic_authority.evidence.missing_path",
            location,
            f"evidence path {path_text!r} must resolve to a file",
        )
    if separator:
        _semantic_authority_evidence_anchor(resolved, anchor, location)
    return resolved


def _semantic_authority(repository_root: Path) -> _SemanticAuthority:
    path = _repository_path(
        repository_root,
        SEMANTIC_AUTHORITY_PATH,
        "approved semantic authority",
    )
    if not path.is_file() or path.is_symlink():
        raise _error(
            "review.stage.semantic_authority.invalid",
            str(path),
            "semantic authority must be a regular file",
        )
    source = path.read_bytes()
    try:
        value = json.loads(
            source.decode("utf-8"),
            object_pairs_hook=_object_without_duplicates,
            parse_constant=_reject_constant,
        )
    except UnicodeDecodeError as error:
        raise _error(
            "review.stage.semantic_authority.invalid_utf8",
            str(path),
            "semantic authority must be UTF-8",
        ) from error
    except _DuplicateKeyError as error:
        raise _error(
            "review.stage.semantic_authority.duplicate_field",
            str(path),
            f"JSON field {error.args[0]!r} appears more than once",
        ) from error
    except (_InvalidConstantError, json.JSONDecodeError) as error:
        raise _error(
            "review.stage.semantic_authority.invalid_json",
            str(path),
            f"invalid JSON: {error}",
        ) from error

    root = _keys(value, ("version", "authority", "decisions"), str(path))
    if type(root["version"]) is not int or root["version"] != 1:
        raise _error(
            "review.stage.semantic_authority.version",
            f"{path}.version",
            "semantic authority version must be integer 1",
        )
    authority = _keys(
        root["authority"],
        (
            "kind",
            "equivalentDerivedHumanCoverageAuthorized",
            "runtimeHumanActorAllowed",
            "source",
            "sourceDigest",
        ),
        f"{path}.authority",
    )
    expected_kind = "approved-composite-design-with-autonomous-evidence-resolution"
    if authority["kind"] != expected_kind:
        raise _error(
            "review.stage.semantic_authority.kind",
            f"{path}.authority.kind",
            f"authority kind must be {expected_kind!r}",
        )
    if authority["equivalentDerivedHumanCoverageAuthorized"] is not True:
        raise _error(
            "review.stage.semantic_authority.derivation_not_authorized",
            f"{path}.authority.equivalentDerivedHumanCoverageAuthorized",
            "derived HumanCoverage must be explicitly authorized",
        )
    if authority["runtimeHumanActorAllowed"] is not False:
        raise _error(
            "review.stage.semantic_authority.runtime_human_forbidden",
            f"{path}.authority.runtimeHumanActorAllowed",
            "runtime human actors must remain forbidden",
        )
    source_locator = authority["source"]
    if not isinstance(source_locator, str) or not source_locator.strip():
        raise _error(
            "review.stage.semantic_authority.source",
            f"{path}.authority.source",
            "authority source must be a non-empty repository-relative path",
        )
    relative_source = Path(source_locator)
    if relative_source.is_absolute() or ".." in relative_source.parts:
        raise _error(
            "review.stage.semantic_authority.source",
            f"{path}.authority.source",
            "authority source must be a safe repository-relative path",
        )
    source_candidate = repository_root
    for part in relative_source.parts:
        source_candidate /= part
        if source_candidate.is_symlink():
            raise _error(
                "review.stage.semantic_authority.source",
                str(source_candidate),
                "authority source must not traverse a symbolic link",
            )
    decision_log = _repository_path(
        repository_root,
        relative_source,
        "semantic authority decision log",
    )
    if not decision_log.is_file() or decision_log.is_symlink():
        raise _error(
            "review.stage.semantic_authority.source",
            str(decision_log),
            "authority source must be a regular file",
        )
    expected_source_digest = _digest(
        authority["sourceDigest"], f"{path}.authority.sourceDigest"
    )
    actual_source_digest = digest_bytes(decision_log.read_bytes())
    if actual_source_digest != expected_source_digest:
        raise _error(
            "review.stage.semantic_authority.source_digest",
            str(decision_log),
            "authority source digest does not match authority.sourceDigest",
        )

    decisions = root["decisions"]
    if not isinstance(decisions, list):
        raise _error(
            "review.stage.semantic_authority.decisions",
            f"{path}.decisions",
            "decisions must be a JSON array",
        )
    expected_ids = tuple(f"HC-{index:03d}" for index in range(24))
    actual_ids = []
    for index, item in enumerate(decisions):
        location = f"{path}.decisions[{index}]"
        decision = _keys(
            item,
            (
                "id",
                "status",
                "policy",
                "applicability",
                "evidence",
                "requiredWork",
            ),
            location,
        )
        actual_ids.append(decision["id"])
        if decision["status"] != "decided":
            raise _error(
                "review.stage.semantic_authority.undecided",
                f"{location}.status",
                "every HumanCoverage decision must be decided",
            )
        for field in ("policy", "applicability"):
            if not isinstance(decision[field], str) or not decision[field].strip():
                raise _error(
                    "review.stage.semantic_authority.empty_text",
                    f"{location}.{field}",
                    f"{field} must be non-empty text",
                )
        evidence = decision["evidence"]
        if (
            not isinstance(evidence, list)
            or not evidence
            or any(not isinstance(value, str) or not value.strip() for value in evidence)
        ):
            raise _error(
                "review.stage.semantic_authority.evidence",
                f"{location}.evidence",
                "evidence must contain at least one non-empty locator",
            )
        for evidence_index, locator in enumerate(evidence):
            _semantic_authority_evidence_locator(
                repository_root,
                locator,
                f"{location}.evidence[{evidence_index}]",
            )
        required_work = decision["requiredWork"]
        if not isinstance(required_work, list) or any(
            not isinstance(value, str) or not value.strip()
            for value in required_work
        ):
            raise _error(
                "review.stage.semantic_authority.required_work",
                f"{location}.requiredWork",
                "requiredWork must be an array of non-empty identifiers",
            )
    if tuple(actual_ids) != expected_ids:
        raise _error(
            "review.stage.semantic_authority.population",
            f"{path}.decisions",
            "decisions must contain HC-000 through HC-023 exactly once and in order",
        )
    return _SemanticAuthority(
        digest_bytes(source),
        expected_kind,
        expected_ids,
        source_locator,
        actual_source_digest,
    )


def _derived_human_environment_digest(
    context: _ReviewContext,
    packet: ReviewPacket,
    authority: _SemanticAuthority,
) -> Digest:
    return canonical_digest(
        {
            "actorId": DERIVED_HUMAN_ACTOR_ID,
            "runtime": DERIVED_HUMAN_RUNTIME,
            "catalogDigest": str(context.catalog.catalog_digest),
            "planDigest": str(context.planned.plan_digest),
            "packetDigest": str(packet.packet_digest),
            "authorityDigest": str(authority.digest),
            "decisionLog": {
                "path": authority.decision_log_path,
                "digest": str(authority.decision_log_digest),
            },
            "decisionIds": list(authority.decision_ids),
            "runtimeHumanActorAllowed": False,
        }
    )


def agent_review_environment_digest(
    repository_root: Path, packet_digest: Digest
) -> Digest:
    repository = Path(repository_root).resolve(strict=True)
    current_packet_digest = Digest(
        parse_identifier(
            "digest", packet_digest, "agentReviewEnvironment.packetDigest"
        )
    )
    protocol = _repository_path(
        repository,
        AGENT_REVIEW_PROTOCOL_PATH,
        "AgentOperability review protocol",
    )
    if not protocol.is_file():
        raise _error(
            "review.stage.agent_protocol.invalid",
            str(protocol),
            "AgentOperability review protocol must be a file",
        )
    return canonical_digest(
        {
            "packetDigest": str(current_packet_digest),
            "protocolDigest": str(digest_bytes(protocol.read_bytes())),
            "reviewRuntime": AGENT_REVIEW_RUNTIME,
        }
    )


def _relative_source_path(repository_root: Path, path: Path) -> str:
    resolved = path.resolve(strict=True)
    try:
        return resolved.relative_to(repository_root).as_posix()
    except ValueError as error:
        raise _error(
            "review.stage.source.outside_repository",
            str(path),
            "Catalog source must stay inside the repository",
        ) from error


def _source_kind(catalog_root: Path, path: Path) -> str:
    parts = path.relative_to(catalog_root).parts
    if len(parts) == 2 and parts[0] in {
        "promises",
        "facts",
        "operations",
        "oracles",
        "rubrics",
        "preparations",
    }:
        return parts[0]
    if len(parts) == 3 and parts[0] == "journeys" and parts[2] == "journey.md":
        return "journeys"
    if len(parts) == 4 and parts[0] == "journeys" and parts[2] == "scenarios":
        return "scenarios"
    return ""


def _contract_kind(contract: object) -> ReviewUnitKind:
    for contract_type, kind in _CONTRACT_KIND:
        if isinstance(contract, contract_type):
            return kind
    raise _error(
        "review.stage.source.unsupported_contract",
        type(contract).__name__,
        "Catalog contains an unsupported contract type",
    )


def _resolve_source_paths(
    repository_root: Path, catalog_root: Path, catalog: DraftCatalog
) -> Mapping[Tuple[str, str], str]:
    by_digest: Dict[Digest, List[Path]] = {}
    for path in sorted(
        catalog_root.rglob("*.md"),
        key=lambda item: item.relative_to(catalog_root).as_posix(),
    ):
        if not _source_kind(catalog_root, path):
            continue
        if path.is_symlink() or not path.is_file():
            raise _error(
                "review.stage.source.invalid",
                str(path),
                "Catalog source must be a regular Markdown file",
            )
        _relative_source_path(repository_root, path)
        by_digest.setdefault(digest_text_file(path), []).append(path)

    resolved: Dict[Tuple[str, str], str] = {}
    for contract in catalog.contracts:
        kind = _contract_kind(contract)
        identity = (kind.value, str(contract.id))
        candidates = by_digest.get(contract.source_digest, [])
        if not candidates:
            raise _error(
                "review.stage.source.missing",
                f"{kind.value}:{contract.id}",
                "no authoritative Markdown source matches the Catalog leaf",
            )
        if len(candidates) != 1:
            raise _error(
                "review.stage.source.ambiguous",
                f"{kind.value}:{contract.id}",
                "multiple Markdown sources match the Catalog leaf: "
                + ", ".join(str(item) for item in candidates),
            )
        resolved[identity] = _relative_source_path(
            repository_root, candidates[0]
        )
    return MappingProxyType(resolved)


def _load_context(
    repository_root: Path, catalog_root: Path, policy_path: Path
) -> _ReviewContext:
    try:
        repository = Path(repository_root).resolve(strict=True)
    except FileNotFoundError as error:
        raise _error(
            "review.stage.repository.missing",
            str(repository_root),
            "repository root does not exist",
        ) from error
    if not repository.is_dir():
        raise _error(
            "review.stage.repository.invalid",
            str(repository),
            "repository root must be a directory",
        )
    catalog_path = _repository_path(
        repository, Path(catalog_root), "Catalog root"
    )
    if not catalog_path.is_dir():
        raise _error(
            "review.stage.catalog.invalid",
            str(catalog_path),
            "Catalog root must be a directory",
        )
    policy = _repository_path(repository, Path(policy_path), "Review policy")
    if not policy.is_file():
        raise _error(
            "review.stage.policy.invalid",
            str(policy),
            "Review policy must be a file",
        )

    catalog = load_catalog(catalog_path)
    review_policy = load_review_policy(policy)
    planned = plan_catalog_reviews(catalog, review_policy)
    approved = approve_review_budgets(planned)
    sources = _resolve_source_paths(repository, catalog_path, catalog)
    return _ReviewContext(
        repository,
        catalog_path,
        catalog,
        review_policy,
        planned,
        approved,
        sources,
    )


def _write_once(path: Path, source: bytes) -> Path:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_symlink() or path.parent.is_symlink():
        raise _error(
            "review.stage.invalid_path", str(path), "review files cannot use symlinks"
        )
    if path.exists():
        if not path.is_file() or path.read_bytes() != source:
            raise _error(
                "review.stage.write_conflict",
                str(path),
                "existing packet manifest has different content",
            )
        return path
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=".review-stage-", dir=str(path.parent)
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as output:
            output.write(source)
            output.flush()
            os.fsync(output.fileno())
        try:
            os.link(str(temporary), str(path))
        except FileExistsError:
            if (
                path.is_symlink()
                or not path.is_file()
                or path.read_bytes() != source
            ):
                raise _error(
                    "review.stage.write_conflict",
                    str(path),
                    "concurrent packet manifest has different content",
                )
    finally:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass
    return path


def _packet_manifest(
    context: _ReviewContext, packet: ReviewPacket
) -> Mapping[str, Any]:
    return {
        "schema": PACKET_MANIFEST_SCHEMA,
        "schemaVersion": SCHEMA_VERSION,
        "catalogDigest": str(context.catalog.catalog_digest),
        "planDigest": str(context.planned.plan_digest),
        "policyDigest": str(context.policy.policy_digest),
        "approvalDigest": str(context.approved.approval_digest),
        "packetId": str(packet.packet_id),
        "packetDigest": str(packet.packet_digest),
        "reviewer": packet.reviewer.value,
        "scope": packet.scope,
        "approvedBudget": packet.approved_budget.as_dict(),
        "units": [
            {
                "kind": unit.kind.value,
                "ref": unit.ref,
                "contentDigest": str(unit.content_digest),
                "sourcePath": context.source_paths[unit.identity],
            }
            for unit in packet.units
        ],
    }


def _manifest_path(root: Path, context: _ReviewContext, packet: ReviewPacket) -> Path:
    return (
        Path(root)
        / "plans"
        / str(context.planned.plan_digest).removeprefix("sha256:")
        / packet.reviewer.value
        / (str(packet.packet_digest).removeprefix("sha256:") + ".json")
    )


def prepare_review_packets(
    repository_root: Path,
    catalog_root: Path,
    policy_path: Path,
    staging_root: Path,
) -> PreparedReview:
    context = _load_context(repository_root, catalog_root, policy_path)
    paths = []
    for packet in context.approved.packets:
        source = canonical_bytes(_packet_manifest(context, packet)) + b"\n"
        paths.append(
            _write_once(_manifest_path(staging_root, context, packet), source)
        )
    return PreparedReview(
        context.catalog.catalog_digest,
        context.planned.plan_digest,
        context.policy.policy_digest,
        context.approved.approval_digest,
        tuple(paths),
    )


def _issued_at(value: object, location: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise _error(
            "review.stage.invalid_issued_at",
            location,
            "issuedAt must be a non-empty RFC 3339 timestamp",
        )
    candidate = value[:-1] + "+00:00" if value.endswith("Z") else value
    try:
        parsed = datetime.fromisoformat(candidate)
    except ValueError as error:
        raise _error(
            "review.stage.invalid_issued_at",
            location,
            "issuedAt must be an RFC 3339 timestamp",
        ) from error
    if "T" not in value or parsed.tzinfo is None:
        raise _error(
            "review.stage.invalid_issued_at",
            location,
            "issuedAt must include a date, time, and UTC offset",
        )
    return value


def _analysis_request(catalog: DraftCatalog, fact: FactDeclaration) -> CompileRequest:
    fact_receipt = canonical_digest(
        {
            "checker": DETERMINISTIC_ACTOR_ID,
            "fact": str(fact.id),
            "sourceDigest": str(fact.source_digest),
            "value": True,
        }
    )
    reviewed_fact = ReviewedFact(
        fact.id, True, fact.source_digest, fact_receipt
    )
    lanes = (BoundLane.SIMULATOR, BoundLane.DEVICE)
    artifacts = tuple(
        LaneBuildArtifact(
            lane,
            canonical_digest(
                {
                    "analysisArtifact": "xctestrun",
                    "analysisLane": lane.value,
                    "catalogDigest": str(catalog.catalog_digest),
                }
            ),
            canonical_digest(
                {
                    "analysisArtifact": "test-products",
                    "analysisLane": lane.value,
                    "catalogDigest": str(catalog.catalog_digest),
                }
            ),
            canonical_digest(
                {
                    "analysisArtifact": "application-code",
                    "analysisLane": lane.value,
                    "catalogDigest": str(catalog.catalog_digest),
                }
            ),
        )
        for lane in lanes
    )
    build = BuildIdentity(
        "com.chenzhong.Enchron",
        "catalog-review",
        catalog.catalog_digest,
        canonical_digest({"reviewStage": 1, "selector": "full"}),
        ToolchainIdentity(
            "catalog-analysis-only",
            "catalog-analysis-only",
            "catalog-analysis-only",
            "catalog-analysis-only",
            "catalog-analysis-only",
            "catalog-analysis-only",
        ),
        artifacts,
    )
    agent = AgentEnvironment(
        "catalog-analysis-placeholder",
        canonical_digest({"prompt": "catalog-analysis", "version": 1}),
        canonical_digest({"configuration": "no-agent-execution"}),
    )
    environment = EvidenceEnvironmentIdentity(
        {
            operation.id: canonical_digest(
                {"runtime": "review-stage", "operation": str(operation.id)}
            )
            for operation in catalog.operations
        },
        agent,
    )
    return CompileRequest(
        FullSelector(), (reviewed_fact,), lanes, build, environment
    )


def _implementation_locators(
    context: _ReviewContext,
) -> Tuple[Tuple[str, str, Digest], ...]:
    results = []
    for contract in context.catalog.operations + context.catalog.oracles:
        locator = Path(contract.implementation_locator)
        if locator.is_absolute():
            raise _error(
                "review.stage.implementation.outside_repository",
                str(contract.id),
                "implementation locator must be repository-relative",
            )
        candidate = context.repository_root / locator
        try:
            resolved = candidate.resolve(strict=True)
        except FileNotFoundError as error:
            raise _error(
                "review.stage.implementation.missing",
                str(contract.id),
                f"implementation locator {contract.implementation_locator!r} is absent",
            ) from error
        try:
            resolved.relative_to(context.repository_root)
        except ValueError as error:
            raise _error(
                "review.stage.implementation.outside_repository",
                str(contract.id),
                "implementation locator "
                f"{contract.implementation_locator!r} escapes the repository",
            ) from error
        if not resolved.is_file():
            raise _error(
                "review.stage.implementation.invalid",
                str(contract.id),
                "implementation locator must resolve to a file",
            )
        actual = digest_text_file(resolved)
        if actual != contract.implementation_digest:
            raise _error(
                "review.stage.implementation.digest_mismatch",
                str(contract.id),
                f"declared {contract.implementation_digest}, found {actual}",
            )
        results.append(
            (str(contract.id), contract.implementation_locator, actual)
        )
    return tuple(sorted(results, key=lambda item: item[0]))


def _checker_environment_digest(
    context: _ReviewContext,
    locators: Sequence[Tuple[str, str, Digest]],
) -> Digest:
    sources = []
    for relative in _CHECKER_SOURCE_PATHS:
        path = _repository_path(
            context.repository_root, Path(relative), "Checker source"
        )
        if not path.is_file():
            raise _error(
                "review.stage.checker_source.invalid",
                str(path),
                "checker source must be a file",
            )
        sources.append(
            {"path": relative, "digest": str(digest_text_file(path))}
        )
    return canonical_digest(
        {
            "checker": {
                "actorId": DETERMINISTIC_ACTOR_ID,
                "protocolVersion": 1,
                "sources": sources,
            },
            "python": {
                "implementation": sys.implementation.name,
                "cacheTag": sys.implementation.cache_tag,
                "version": list(sys.version_info[:3]),
            },
            "inputs": {
                "catalogDigest": str(context.catalog.catalog_digest),
                "policyDigest": str(context.policy.policy_digest),
                "implementationLocators": [
                    {
                        "contract": contract,
                        "locator": locator,
                        "digest": str(digest),
                    }
                    for contract, locator, digest in locators
                ],
            },
            "assertions": {
                "targetPromises": _EXPECTED_PROMISES,
                "selectedScenarios": _EXPECTED_SCENARIOS,
                "requestedLanes": ["simulator", "device"],
                "mainGateJourneyEdges": 0,
            },
        }
    )


def _run_deterministic_checks(
    context: _ReviewContext,
) -> Tuple[Any, Tuple[Tuple[str, str, Digest], ...], Digest]:
    matching_facts = tuple(
        fact for fact in context.catalog.facts if fact.id == _CATALOG_SCOPE_FACT
    )
    if len(matching_facts) != 1:
        raise _error(
            "review.stage.catalog_scope_fact.invalid",
            str(_CATALOG_SCOPE_FACT),
            "Catalog must declare the reviewed scope fact exactly once",
        )
    analysis = analyze_catalog(
        context.catalog, _analysis_request(context.catalog, matching_facts[0])
    )
    if len(analysis.target_promises) != _EXPECTED_PROMISES:
        raise _error(
            "review.stage.target_promise_count",
            "catalogAnalysis.targetPromises",
            f"expected {_EXPECTED_PROMISES}, found {len(analysis.target_promises)}",
        )
    if len(analysis.selected_scenarios) != _EXPECTED_SCENARIOS:
        raise _error(
            "review.stage.selected_scenario_count",
            "catalogAnalysis.selectedScenarios",
            f"expected {_EXPECTED_SCENARIOS}, found {len(analysis.selected_scenarios)}",
        )
    expected_lanes = (BoundLane.SIMULATOR, BoundLane.DEVICE)
    actual_lanes = tuple(item.lane for item in analysis.main_gates)
    if actual_lanes != expected_lanes:
        raise _error(
            "review.stage.main_gate_coverage",
            "catalogAnalysis.mainGates",
            "analysis must contain exactly one MainGate attempt per lane",
        )
    gate_scenarios = frozenset(item.scenario_id for item in analysis.main_gates)
    for journey in context.catalog.journeys:
        for before, after in journey.ordering:
            if before in gate_scenarios or after in gate_scenarios:
                raise _error(
                    "review.stage.main_gate_journey_edge",
                    str(journey.id),
                    f"Journey ordering edge {before} -> {after} involves a MainGate",
                )
    locators = _implementation_locators(context)
    environment_digest = _checker_environment_digest(context, locators)
    return analysis, locators, environment_digest


def _report_metadata(
    packet: ReviewPacket,
    actor: ReviewActorIdentity,
    usage: ReviewUsage,
    issued_at: str,
) -> Mapping[str, Any]:
    return {
        "schema": REVIEW_REPORT_SCHEMA,
        "schemaVersion": SCHEMA_VERSION,
        "packetId": str(packet.packet_id),
        "packetDigest": str(packet.packet_digest),
        "reviewer": packet.reviewer.value,
        "actor": {
            "actorId": actor.actor_id,
            "environmentDigest": str(actor.environment_digest),
        },
        "usage": usage.as_dict(),
        "issuedAt": issued_at,
    }


def _report(
    metadata: Mapping[str, Any], heading: str, body: Sequence[str]
) -> str:
    return "\n".join(
        (
            "---",
            canonical_bytes(metadata).decode("utf-8"),
            "---",
            "",
            f"# {heading}",
            "",
        )
        + tuple(body)
    )


def _deterministic_report(
    context: _ReviewContext,
    packet: ReviewPacket,
    actor: ReviewActorIdentity,
    usage: ReviewUsage,
    issued_at: str,
    analysis: Any,
    locators: Sequence[Tuple[str, str, Digest]],
) -> str:
    gates = ", ".join(
        f"{item.lane.value}={item.scenario_id}" for item in analysis.main_gates
    )
    lines = [
        f"This report accepts `{packet.packet_id}` (`{packet.packet_digest}`).",
        "",
        "## Catalog-wide checks",
        "",
        f"- Catalog digest: `{context.catalog.catalog_digest}`",
        f"- Review plan digest: `{context.planned.plan_digest}`",
        f"- Target Promises: `{len(analysis.target_promises)}`",
        f"- Selected Scenarios: `{len(analysis.selected_scenarios)}`",
        f"- MainGate attempts: `{gates}`",
        "- Journey ordering edges involving a MainGate: `0`",
        f"- Verified Operation and Oracle locators: `{len(locators)}`",
        "",
        "## Implementation locators",
        "",
    ]
    lines.extend(
        f"- `{contract}` uses `{locator}` at `{digest}`"
        for contract, locator, digest in locators
    )
    lines.extend(
        (
            "",
            "## Packet units",
            "",
        )
    )
    lines.extend(
        f"- `{unit.kind.value}:{unit.ref}` `{unit.content_digest}` "
        f"from `{context.source_paths[unit.identity]}`"
        for unit in packet.units
    )
    return _report(
        _report_metadata(packet, actor, usage, issued_at),
        "Deterministic Catalog review",
        lines,
    )


def run_deterministic_reviews(
    repository_root: Path,
    catalog_root: Path,
    policy_path: Path,
    reviews_root: Path,
    issued_at: str,
) -> DeterministicReviewResult:
    context = _load_context(repository_root, catalog_root, policy_path)
    issued = _issued_at(issued_at, "issuedAt")
    analysis, locators, environment_digest = _run_deterministic_checks(context)
    actor = ReviewActorIdentity(DETERMINISTIC_ACTOR_ID, environment_digest)
    packets = tuple(
        packet
        for packet in context.approved.packets
        if packet.reviewer is ReviewClass.DETERMINISTIC
    )
    if not packets:
        raise _error(
            "review.stage.deterministic_packets.missing",
            "approvedReview.packets",
            "current partition has no deterministic packets",
        )

    results = []
    for packet in packets:
        if packet.reviewer is ReviewClass.HUMAN_COVERAGE:
            raise _error(
                "review.stage.human_receipt.forbidden",
                str(packet.packet_id),
                "this API cannot issue HumanCoverage receipts",
            )
        usage = ReviewUsage(tuple(packet.approved_budget.amounts))
        report_digest, report_path = write_review_report(
            reviews_root,
            _deterministic_report(
                context,
                packet,
                actor,
                usage,
                issued,
                analysis,
                locators,
            ),
        )
        receipt = ReviewReceipt(
            packet.packet_digest,
            ReviewClass.DETERMINISTIC,
            actor,
            report_digest,
            True,
            usage,
            issued,
        )
        persisted_receipt = write_review_receipt(reviews_root, receipt)
        results.append(IssuedReview(receipt, report_path, persisted_receipt))
    return DeterministicReviewResult(
        context.catalog.catalog_digest,
        context.planned.plan_digest,
        environment_digest,
        tuple(results),
    )


def _digest(value: object, location: str) -> Digest:
    return Digest(parse_identifier("digest", value, location))


def _review_usage(value: object, location: str) -> ReviewUsage:
    if not isinstance(value, MappingABC) or not value:
        raise _error(
            "review.stage.usage.empty",
            location,
            "usage must contain at least one typed budget unit",
        )
    known = {unit.value: unit for unit in BudgetUnit}
    unknown = sorted(set(value) - set(known))
    if unknown:
        raise _error(
            "review.stage.usage.unknown_unit",
            location,
            "unknown budget unit(s): " + ", ".join(unknown),
        )
    return ReviewUsage(
        tuple(BudgetAmount(known[name], value[name]) for name in sorted(value))
    )


def _require_usage_within(
    usage: ReviewUsage, packet: ReviewPacket, location: str
) -> None:
    for amount in usage.amounts:
        maximum = packet.approved_budget.amount_for(amount.unit)
        if maximum is None or amount.amount > maximum:
            raise _error(
                "review.stage.usage.exceeds_budget",
                location,
                f"{amount.unit.value} usage {amount.amount} exceeds approved budget {maximum}",
            )


def _agent_assessment(
    path: Path,
    packet: ReviewPacket,
    expected_environment_digest: Digest,
) -> _AgentAssessment:
    return _validated_agent_assessment(
        _canonical_json(path), str(path), packet, expected_environment_digest
    )


def _validated_agent_assessment(
    document: Mapping[str, Any],
    path: str,
    packet: ReviewPacket,
    expected_environment_digest: Digest,
) -> _AgentAssessment:
    source = _keys(
        document,
        (
            "schema",
            "schemaVersion",
            "packetDigest",
            "reviewer",
            "actor",
            "usage",
            "issuedAt",
            "units",
        ),
        str(path),
    )
    if source["schema"] != AGENT_ASSESSMENT_SCHEMA:
        raise _error(
            "review.stage.assessment.schema",
            f"{path}.schema",
            f"expected {AGENT_ASSESSMENT_SCHEMA!r}",
        )
    if type(source["schemaVersion"]) is not int or source["schemaVersion"] != 1:
        raise _error(
            "review.stage.assessment.schema_version",
            f"{path}.schemaVersion",
            "schemaVersion must be integer 1",
        )
    if source["reviewer"] == ReviewClass.HUMAN_COVERAGE.value:
        raise _error(
            "review.stage.human_receipt.forbidden",
            f"{path}.reviewer",
            "this API cannot issue HumanCoverage receipts",
        )
    if source["reviewer"] != ReviewClass.AGENT_OPERABILITY.value:
        raise _error(
            "review.stage.assessment.reviewer",
            f"{path}.reviewer",
            "assessment reviewer must be agent-operability",
        )
    declared_packet = _digest(source["packetDigest"], f"{path}.packetDigest")
    if declared_packet != packet.packet_digest:
        raise _error(
            "review.stage.assessment.packet_mismatch",
            f"{path}.packetDigest",
            f"expected {packet.packet_digest}, found {declared_packet}",
        )

    actor_value = _keys(
        source["actor"],
        ("actorId", "environmentDigest"),
        f"{path}.actor",
    )
    actor = ReviewActorIdentity(
        actor_value["actorId"],
        _digest(
            actor_value["environmentDigest"],
            f"{path}.actor.environmentDigest",
        ),
    )
    if actor.environment_digest != expected_environment_digest:
        raise _error(
            "review.stage.assessment.environment_mismatch",
            f"{path}.actor.environmentDigest",
            "assessment does not bind the current packet and "
            "AgentOperability review protocol",
        )
    usage = _review_usage(source["usage"], f"{path}.usage")
    _require_usage_within(usage, packet, f"{path}.usage")
    issued = _issued_at(source["issuedAt"], f"{path}.issuedAt")

    values = source["units"]
    if not isinstance(values, list):
        raise _error(
            "review.stage.assessment.units.invalid",
            f"{path}.units",
            "units must be a JSON array",
        )
    expected = {unit.identity: unit for unit in packet.units}
    found: Dict[Tuple[str, str], Mapping[str, Any]] = {}
    rejected = []
    for index, item in enumerate(values):
        location = f"{path}.units[{index}]"
        unit_value = _keys(
            item,
            ("kind", "ref", "contentDigest", "decision", "rationale"),
            location,
        )
        try:
            kind = ReviewUnitKind(unit_value["kind"])
        except (TypeError, ValueError) as error:
            raise _error(
                "review.stage.assessment.unit_kind",
                f"{location}.kind",
                f"unknown review unit kind {unit_value['kind']!r}",
            ) from error
        ref = unit_value["ref"]
        if not isinstance(ref, str) or not ref.strip():
            raise _error(
                "review.stage.assessment.unit_ref",
                f"{location}.ref",
                "unit ref must be non-empty text",
            )
        identity = (kind.value, ref)
        if identity in found:
            raise _error(
                "review.stage.assessment.unit_duplicate",
                location,
                f"unit {kind.value}:{ref} appears more than once",
            )
        found[identity] = unit_value
        expected_unit = expected.get(identity)
        if expected_unit is None:
            raise _error(
                "review.stage.assessment.unit_extra",
                location,
                f"unit {kind.value}:{ref} is not in packet {packet.packet_id}",
            )
        content_digest = _digest(
            unit_value["contentDigest"], f"{location}.contentDigest"
        )
        if content_digest != expected_unit.content_digest:
            raise _error(
                "review.stage.assessment.unit_digest_mismatch",
                f"{location}.contentDigest",
                f"expected {expected_unit.content_digest}, found {content_digest}",
            )
        if unit_value["decision"] not in ("accepted", "rejected"):
            raise _error(
                "review.stage.assessment.decision",
                f"{location}.decision",
                "decision must be accepted or rejected",
            )
        rationale = unit_value["rationale"]
        if not isinstance(rationale, str) or not rationale.strip():
            raise _error(
                "review.stage.assessment.rationale",
                f"{location}.rationale",
                "each unit needs a non-empty rationale",
            )
        if unit_value["decision"] == "rejected":
            rejected.append(identity)

    missing = set(expected) - set(found)
    if missing:
        kind, ref = sorted(missing)[0]
        raise _error(
            "review.stage.assessment.unit_missing",
            f"{path}.units",
            f"packet unit {kind}:{ref} is absent",
        )
    if len(found) != len(expected):
        raise _error(
            "review.stage.assessment.unit_coverage",
            f"{path}.units",
            "assessment units do not match the packet one-to-one",
        )
    if rejected:
        kind, ref = sorted(rejected)[0]
        raise _error(
            "review.stage.assessment.rejected",
            f"{path}.units",
            f"unit {kind}:{ref} was rejected",
        )
    return _AgentAssessment(source, actor, usage, issued)


def _agent_report(
    packet: ReviewPacket, assessment: _AgentAssessment
) -> str:
    source = canonical_bytes(assessment.source).decode("utf-8")
    body = (
        f"This report accepts `{packet.packet_id}` (`{packet.packet_digest}`).",
        "",
        "Every packet unit has an accepted decision and a non-empty rationale.",
        "",
        "## Canonical assessment",
        "",
        "    " + source,
    )
    return _report(
        _report_metadata(
            packet, assessment.actor, assessment.usage, assessment.issued_at
        ),
        "Agent operability review",
        body,
    )


def accept_agent_assessment(
    repository_root: Path,
    catalog_root: Path,
    policy_path: Path,
    reviews_root: Path,
    assessment_path: Path,
) -> IssuedReview:
    context = _load_context(repository_root, catalog_root, policy_path)
    preview = _canonical_json(assessment_path)
    reviewer = preview.get("reviewer")
    if reviewer == ReviewClass.HUMAN_COVERAGE.value:
        raise _error(
            "review.stage.human_receipt.forbidden",
            f"{assessment_path}.reviewer",
            "this API cannot issue HumanCoverage receipts",
        )
    if reviewer != ReviewClass.AGENT_OPERABILITY.value:
        raise _error(
            "review.stage.assessment.reviewer",
            f"{assessment_path}.reviewer",
            "assessment reviewer must be agent-operability",
        )
    declared_digest = _digest(
        preview.get("packetDigest"), f"{assessment_path}.packetDigest"
    )
    packet = next(
        (
            item
            for item in context.approved.packets
            if item.packet_digest == declared_digest
        ),
        None,
    )
    if packet is None:
        raise _error(
            "review.stage.assessment.stale_packet",
            f"{assessment_path}.packetDigest",
            "assessment does not name a packet in the current partition",
        )
    if packet.reviewer is ReviewClass.HUMAN_COVERAGE:
        raise _error(
            "review.stage.human_receipt.forbidden",
            str(packet.packet_id),
            "this API cannot issue HumanCoverage receipts",
        )
    if packet.reviewer is not ReviewClass.AGENT_OPERABILITY:
        raise _error(
            "review.stage.assessment.packet_reviewer",
            str(packet.packet_id),
            "assessment packet is not assigned to agent-operability",
        )
    assessment = _agent_assessment(
        assessment_path,
        packet,
        agent_review_environment_digest(
            context.repository_root, packet.packet_digest
        ),
    )
    assessment_digest, _ = write_review_assessment(
        reviews_root, assessment.source
    )
    report_digest, report_path = write_review_report(
        reviews_root, _agent_report(packet, assessment)
    )
    receipt = ReviewReceipt(
        packet.packet_digest,
        ReviewClass.AGENT_OPERABILITY,
        assessment.actor,
        report_digest,
        True,
        assessment.usage,
        assessment.issued_at,
        assessment_digest,
    )
    persisted_receipt = write_review_receipt(reviews_root, receipt)
    return IssuedReview(receipt, report_path, persisted_receipt)


def _derived_human_report(
    context: _ReviewContext,
    packet: ReviewPacket,
    actor: ReviewActorIdentity,
    usage: ReviewUsage,
    issued_at: str,
    authority: _SemanticAuthority,
) -> str:
    body = [
        f"This report accepts `{packet.packet_id}` (`{packet.packet_digest}`).",
        "",
        "The receipt is mechanically derived from the approved composite design. "
        "It records no new subjective judgment and introduces no runtime human step.",
        "",
        "## Approved semantic authority",
        "",
        f"- Authority kind: `{authority.kind}`",
        f"- Authority digest: `{authority.digest}`",
        f"- Decision log: `{authority.decision_log_path}` "
        f"(`{authority.decision_log_digest}`)",
        f"- Decisions: `{', '.join(authority.decision_ids)}`",
        "- Runtime human actor allowed: `false`",
        f"- Catalog digest: `{context.catalog.catalog_digest}`",
        f"- Review plan digest: `{context.planned.plan_digest}`",
        "",
        "## Packet units",
        "",
    ]
    body.extend(
        f"- `{unit.kind.value}:{unit.ref}` `{unit.content_digest}` "
        f"from `{context.source_paths[unit.identity]}`"
        for unit in packet.units
    )
    return _report(
        _report_metadata(packet, actor, usage, issued_at),
        "Derived HumanCoverage review",
        body,
    )


def derive_human_coverage_reviews(
    repository_root: Path,
    catalog_root: Path,
    policy_path: Path,
    reviews_root: Path,
    issued_at: str,
) -> DerivedHumanCoverageResult:
    context = _load_context(repository_root, catalog_root, policy_path)
    issued = _issued_at(issued_at, "issuedAt")
    current = review_status(
        repository_root, catalog_root, policy_path, reviews_root
    )
    pending_non_human = {
        reviewer.value: current.pending[reviewer]
        for reviewer in (
            ReviewClass.DETERMINISTIC,
            ReviewClass.AGENT_OPERABILITY,
        )
        if current.pending[reviewer]
    }
    if pending_non_human:
        detail = ", ".join(
            f"{reviewer}={count}"
            for reviewer, count in sorted(pending_non_human.items())
        )
        raise _error(
            "review.stage.derived_human.non_human_incomplete",
            str(reviews_root),
            "derived HumanCoverage requires complete non-human reviews; " + detail,
        )

    authority = _semantic_authority(context.repository_root)
    packets = tuple(
        packet
        for packet in context.approved.packets
        if packet.reviewer is ReviewClass.HUMAN_COVERAGE
    )
    if not packets:
        raise _error(
            "review.stage.derived_human.packets_missing",
            "approvedReview.packets",
            "current partition has no HumanCoverage packets",
        )

    results = []
    for packet in packets:
        usage = ReviewUsage(tuple(packet.approved_budget.amounts))
        actor = ReviewActorIdentity(
            DERIVED_HUMAN_ACTOR_ID,
            _derived_human_environment_digest(context, packet, authority),
        )
        report_digest, report_path = write_review_report(
            reviews_root,
            _derived_human_report(
                context,
                packet,
                actor,
                usage,
                issued,
                authority,
            ),
        )
        receipt = ReviewReceipt(
            packet.packet_digest,
            ReviewClass.HUMAN_COVERAGE,
            actor,
            report_digest,
            True,
            usage,
            issued,
        )
        persisted_receipt = write_review_receipt(reviews_root, receipt)
        results.append(IssuedReview(receipt, report_path, persisted_receipt))
    return DerivedHumanCoverageResult(
        context.catalog.catalog_digest,
        context.planned.plan_digest,
        authority.digest,
        tuple(results),
    )


def _verify_report_binding(
    source: str, packet: ReviewPacket, receipt: ReviewReceipt
) -> None:
    document = parse_frontmatter(source, f"report:{receipt.report_digest}")
    expected = _report_metadata(
        packet, receipt.actor, receipt.usage, receipt.issued_at
    )
    if dict(document.metadata) != expected:
        raise _error(
            "review.stage.report.binding_mismatch",
            f"report:{receipt.report_digest}",
            f"report metadata does not bind packet {packet.packet_id} and its receipt",
        )


def _verify_agent_assessment_binding(
    reviews_root: Path,
    packet: ReviewPacket,
    receipt: ReviewReceipt,
    expected_environment_digest: Digest,
) -> None:
    """Re-derive the receipt's verdict from the assessment bytes it names.

    The receipt asserts that every packet unit was accepted. Nothing else in the
    status path recomputes that, so the assessment is validated again against
    the current packet and the report is rebuilt from it; a report that no
    longer follows from its assessment fails here.
    """
    document = load_review_assessment(reviews_root, receipt.assessment_digest)
    assessment = _validated_agent_assessment(
        document,
        f"assessment:{receipt.assessment_digest}",
        packet,
        expected_environment_digest,
    )
    if (
        assessment.actor != receipt.actor
        or assessment.usage != receipt.usage
        or assessment.issued_at != receipt.issued_at
    ):
        raise _error(
            "review.stage.status.assessment_mismatch",
            str(receipt.packet_digest),
            "AgentOperability receipt does not match the assessment it names",
        )
    if digest_bytes(report_bytes(_agent_report(packet, assessment))) != (
        receipt.report_digest
    ):
        raise _error(
            "review.stage.status.report_not_derived",
            f"report:{receipt.report_digest}",
            "AgentOperability report does not follow from its assessment",
        )


def review_status(
    repository_root: Path,
    catalog_root: Path,
    policy_path: Path,
    reviews_root: Path,
) -> ReviewStatus:
    context = _load_context(repository_root, catalog_root, policy_path)
    packets_by_digest = {
        packet.packet_digest: packet for packet in context.approved.packets
    }
    receipts = load_review_receipts(reviews_root)
    completed = {reviewer: 0 for reviewer in ReviewClass}
    deterministic_environment = None
    semantic_authority = None
    for receipt in receipts:
        packet = packets_by_digest.get(receipt.packet_digest)
        if packet is None:
            raise _error(
                "review.stage.status.stale_receipt",
                str(receipt.packet_digest),
                "receipt is not part of the current packet partition",
            )
        if receipt.reviewer is not packet.reviewer:
            raise _error(
                "review.stage.status.reviewer_mismatch",
                str(receipt.packet_digest),
                "receipt reviewer does not match the planned packet",
            )
        if not receipt.accepted:
            raise _error(
                "review.stage.status.rejected_receipt",
                str(receipt.packet_digest),
                "current packet receipt is not accepted",
            )
        _require_usage_within(
            receipt.usage, packet, f"receipt:{receipt.receipt_digest}.usage"
        )
        report = load_review_report(reviews_root, receipt.report_digest)
        _verify_report_binding(report, packet, receipt)
        if receipt.reviewer is ReviewClass.DETERMINISTIC:
            if deterministic_environment is None:
                _, _, deterministic_environment = _run_deterministic_checks(
                    context
                )
            if (
                receipt.actor.actor_id != DETERMINISTIC_ACTOR_ID
                or receipt.actor.environment_digest
                != deterministic_environment
            ):
                raise _error(
                    "review.stage.status.environment_mismatch",
                    str(receipt.packet_digest),
                    "deterministic receipt does not bind the current "
                    "checker environment",
                )
        elif receipt.reviewer is ReviewClass.AGENT_OPERABILITY:
            expected_environment = agent_review_environment_digest(
                context.repository_root, packet.packet_digest
            )
            if receipt.actor.environment_digest != expected_environment:
                raise _error(
                    "review.stage.status.environment_mismatch",
                    str(receipt.packet_digest),
                    "AgentOperability receipt does not bind the current "
                    "packet and review protocol",
                )
            _verify_agent_assessment_binding(
                reviews_root, packet, receipt, expected_environment
            )
        elif receipt.reviewer is ReviewClass.HUMAN_COVERAGE:
            if semantic_authority is None:
                semantic_authority = _semantic_authority(
                    context.repository_root
                )
            expected_environment = _derived_human_environment_digest(
                context, packet, semantic_authority
            )
            if (
                receipt.actor.actor_id != DERIVED_HUMAN_ACTOR_ID
                or receipt.actor.environment_digest != expected_environment
            ):
                raise _error(
                    "review.stage.status.environment_mismatch",
                    str(receipt.packet_digest),
                    "HumanCoverage receipt does not bind the approved "
                    "semantic authority and current packet",
                )
        completed[packet.reviewer] += 1

    total = {
        reviewer: sum(
            1
            for packet in context.approved.packets
            if packet.reviewer is reviewer
        )
        for reviewer in ReviewClass
    }
    pending = {
        reviewer: total[reviewer] - completed[reviewer]
        for reviewer in ReviewClass
    }
    return ReviewStatus(
        context.catalog.catalog_digest,
        context.planned.plan_digest,
        context.policy.policy_digest,
        context.approved.approval_digest,
        MappingProxyType(total),
        MappingProxyType(completed),
        MappingProxyType(pending),
    )


__all__ = (
    "AGENT_REVIEW_PROTOCOL_PATH",
    "AGENT_REVIEW_RUNTIME",
    "AGENT_ASSESSMENT_SCHEMA",
    "DETERMINISTIC_ACTOR_ID",
    "DERIVED_HUMAN_ACTOR_ID",
    "DeterministicReviewResult",
    "DerivedHumanCoverageResult",
    "IssuedReview",
    "PACKET_MANIFEST_SCHEMA",
    "PreparedReview",
    "REVIEW_REPORT_SCHEMA",
    "ReviewStatus",
    "accept_agent_assessment",
    "agent_review_environment_digest",
    "derive_human_coverage_reviews",
    "prepare_review_packets",
    "review_status",
    "run_deterministic_reviews",
)
