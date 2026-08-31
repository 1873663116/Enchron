#!/usr/bin/env python3

from __future__ import annotations

import argparse
from dataclasses import dataclass
import os
from pathlib import Path
import re
import sys
import tempfile
from typing import BinaryIO, Mapping, Sequence


if __package__ in (None, ""):
    scripts_root = Path(__file__).resolve().parents[1]
    if str(scripts_root) not in sys.path:
        sys.path.insert(0, str(scripts_root))
    from regression.completion import (
        AUDIT_EVIDENCE_NAMES,
        CompletionError,
        artifact_record,
        validate_audit_manifest,
        validate_configuration_receipt,
        verification_log_records,
    )
    from regression.core.digest import canonical_bytes, digest_bytes
else:
    from .completion import (
        AUDIT_EVIDENCE_NAMES,
        CompletionError,
        artifact_record,
        validate_audit_manifest,
        validate_configuration_receipt,
        verification_log_records,
    )
    from .core.digest import canonical_bytes, digest_bytes


AUDIT_MANIFEST_NAME = "audit-manifest.json"
CONFIGURATION_RECEIPT_NAME = "configuration-receipt.json"
SHA256 = re.compile(r"^sha256:[0-9a-f]{64}$")


class FinalArtifactError(ValueError):
    pass


@dataclass(frozen=True)
class FinalArtifactInputs:
    final_root: Path
    source_digest: str
    verification_summary: Path
    no_comments_evidence: Path
    interrogate_evidence: Path
    blast_radius_evidence: Path
    vp_e2e_evidence: Path
    write_set_receipt: Path
    product_swift_coverage: Path
    blueprint_digest: str
    catalog_digest: str
    review_completion_digest: str
    semantic_authority_digest: str
    merge_run_receipt: Path
    simulator_build_result: Path
    device_build_result: Path

    @property
    def evidence(self) -> Mapping[str, Path]:
        return {
            "no-comments": self.no_comments_evidence,
            "interrogate": self.interrogate_evidence,
            "blast-radius": self.blast_radius_evidence,
            "vp-e2e": self.vp_e2e_evidence,
        }


@dataclass(frozen=True)
class FinalArtifactResult:
    audit_manifest: Path
    audit_manifest_digest: str
    configuration_receipt: Path
    configuration_receipt_digest: str

    def payload(self) -> dict[str, object]:
        return {
            "auditManifest": {
                "path": str(self.audit_manifest),
                "sha256": self.audit_manifest_digest,
            },
            "configurationReceipt": {
                "path": str(self.configuration_receipt),
                "sha256": self.configuration_receipt_digest,
            },
        }


@dataclass(frozen=True)
class _BoundArtifact:
    label: str
    path: Path
    record: dict[str, str]


def _final_root(path: Path) -> Path:
    lexical = Path(path)
    if lexical.is_symlink() or not lexical.is_dir():
        raise FinalArtifactError(f"final root must be a current real directory: {lexical}")
    return lexical.resolve()


def _input_path(final_root: Path, path: Path) -> Path:
    candidate = Path(path)
    return candidate if candidate.is_absolute() else final_root / candidate


def _require_digest(value: str, label: str) -> str:
    if not isinstance(value, str) or SHA256.fullmatch(value) is None:
        raise FinalArtifactError(f"{label} must be a SHA-256 identity")
    return value


def _bind_artifact(
    final_root: Path,
    path: Path,
    label: str,
) -> _BoundArtifact:
    candidate = _input_path(final_root, path)
    record = artifact_record(candidate, final_root)
    source = candidate.read_bytes()
    if not source:
        raise FinalArtifactError(f"{label} must not be empty")
    if str(digest_bytes(source)) != record["sha256"]:
        raise FinalArtifactError(f"{label} changed while its digest was recorded")
    return _BoundArtifact(label, candidate.resolve(), record)


def _assert_current(final_root: Path, artifact: _BoundArtifact) -> None:
    current = _bind_artifact(
        final_root,
        artifact.path,
        artifact.label,
    )
    if current.record != artifact.record:
        raise FinalArtifactError(
            f"{artifact.label} changed while final artifacts were generated"
        )


def audit_manifest_payload(
    source_digest: str,
    verification_record: Mapping[str, str],
    verification_log_records: Sequence[Mapping[str, str]],
    evidence_records: Mapping[str, Mapping[str, str]],
    write_set_receipt: Mapping[str, str],
    product_swift_coverage: Mapping[str, str],
) -> dict[str, object]:
    return {
        "schema": "enchron.regression.final-audit-manifest",
        "schemaVersion": 2,
        "sourceDigest": source_digest,
        "preFreezeVerification": dict(verification_record),
        "verificationLogs": [dict(record) for record in verification_log_records],
        "evidence": {
            name: dict(evidence_records[name]) for name in AUDIT_EVIDENCE_NAMES
        },
        "writeSetReceipt": dict(write_set_receipt),
        "productSwiftCoverage": dict(product_swift_coverage),
    }


def configuration_receipt_payload(
    *,
    source_digest: str,
    blueprint_digest: str,
    catalog_digest: str,
    review_completion_digest: str,
    semantic_authority_digest: str,
    verification_record: Mapping[str, str],
    merge_run_receipt: Mapping[str, str],
    simulator_build_result: Mapping[str, str],
    device_build_result: Mapping[str, str],
) -> dict[str, object]:
    return {
        "schema": "enchron.regression.configuration-receipt",
        "schemaVersion": 1,
        "sourceDigest": source_digest,
        "blueprintDigest": blueprint_digest,
        "catalogDigest": catalog_digest,
        "reviewCompletionDigest": review_completion_digest,
        "semanticAuthorityDigest": semantic_authority_digest,
        "preFreezeVerification": dict(verification_record),
        "mergeRunReceipt": dict(merge_run_receipt),
        "buildLogs": {
            "simulator": dict(simulator_build_result),
            "device": dict(device_build_result),
        },
    }


def _stage(parent: Path, name: str, source: bytes) -> Path:
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{name}.", suffix=".tmp", dir=str(parent)
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as output:
            output.write(source)
            output.flush()
            os.fsync(output.fileno())
    except BaseException:
        temporary.unlink(missing_ok=True)
        raise
    return temporary


def _check_destination(destination: Path, source: bytes) -> None:
    if destination.is_symlink():
        raise FinalArtifactError(f"output may not be a symbolic link: {destination}")
    if not destination.exists():
        return
    if not destination.is_file():
        raise FinalArtifactError(f"output is not a regular file: {destination}")
    if destination.read_bytes() != source:
        raise FinalArtifactError(
            f"output already contains different bytes: {destination}"
        )


def _publish(staged: Path, destination: Path, source: bytes) -> None:
    _check_destination(destination, source)
    if destination.exists():
        return
    try:
        os.link(staged, destination)
    except FileExistsError:
        _check_destination(destination, source)


def _fsync_directory(path: Path) -> None:
    descriptor = os.open(path, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def write_final_artifacts(inputs: FinalArtifactInputs) -> FinalArtifactResult:
    root = _final_root(inputs.final_root)
    digests = {
        "source digest": _require_digest(inputs.source_digest, "source digest"),
        "blueprint digest": _require_digest(
            inputs.blueprint_digest, "blueprint digest"
        ),
        "catalog digest": _require_digest(inputs.catalog_digest, "catalog digest"),
        "review completion digest": _require_digest(
            inputs.review_completion_digest, "review completion digest"
        ),
        "semantic authority digest": _require_digest(
            inputs.semantic_authority_digest, "semantic authority digest"
        ),
    }

    verification = _bind_artifact(
        root, inputs.verification_summary, "full verification summary"
    )
    verification_logs = tuple(
        _bind_artifact(
            root,
            root / record["path"],
            f"verification log {record['path']}",
        )
        for record in verification_log_records(verification.path, root)
    )
    evidence = {
        name: _bind_artifact(root, path, f"{name} audit evidence")
        for name, path in inputs.evidence.items()
    }
    if set(evidence) != set(AUDIT_EVIDENCE_NAMES):
        raise FinalArtifactError("audit evidence must cover the four required classes")
    if len({item.record["path"] for item in evidence.values()}) != len(
        AUDIT_EVIDENCE_NAMES
    ):
        raise FinalArtifactError("the four audit evidence files must be distinct")
    if verification.record["path"] in {
        item.record["path"] for item in evidence.values()
    }:
        raise FinalArtifactError(
            "full verification summary must be distinct from audit evidence"
        )

    write_set_receipt = _bind_artifact(
        root,
        inputs.write_set_receipt,
        "actual write-set receipt",
    )
    product_swift_coverage = _bind_artifact(
        root,
        inputs.product_swift_coverage,
        "product Swift coverage receipt",
    )

    merge_receipt = _bind_artifact(
        root, inputs.merge_run_receipt, "merge RunReceipt"
    )
    simulator_result = _bind_artifact(
        root,
        inputs.simulator_build_result,
        "simulator build result",
    )
    device_result = _bind_artifact(
        root,
        inputs.device_build_result,
        "device build result",
    )
    if simulator_result.record["path"] == device_result.record["path"]:
        raise FinalArtifactError("simulator and device build results must be distinct")
    if merge_receipt.record["path"] in {
        simulator_result.record["path"],
        device_result.record["path"],
    }:
        raise FinalArtifactError("merge RunReceipt must be distinct from build results")

    audit_payload = audit_manifest_payload(
        digests["source digest"],
        verification.record,
        tuple(item.record for item in verification_logs),
        {name: item.record for name, item in evidence.items()},
        write_set_receipt.record,
        product_swift_coverage.record,
    )
    configuration_payload = configuration_receipt_payload(
        source_digest=digests["source digest"],
        blueprint_digest=digests["blueprint digest"],
        catalog_digest=digests["catalog digest"],
        review_completion_digest=digests["review completion digest"],
        semantic_authority_digest=digests["semantic authority digest"],
        verification_record=verification.record,
        merge_run_receipt=merge_receipt.record,
        simulator_build_result=simulator_result.record,
        device_build_result=device_result.record,
    )
    audit_source = canonical_bytes(audit_payload) + b"\n"
    configuration_source = canonical_bytes(configuration_payload) + b"\n"
    audit_destination = root / AUDIT_MANIFEST_NAME
    configuration_destination = root / CONFIGURATION_RECEIPT_NAME

    staged: list[Path] = []
    try:
        staged_audit = _stage(root, AUDIT_MANIFEST_NAME, audit_source)
        staged.append(staged_audit)
        staged_configuration = _stage(
            root, CONFIGURATION_RECEIPT_NAME, configuration_source
        )
        staged.append(staged_configuration)

        audit_proof = validate_audit_manifest(
            staged_audit, root, digests["source digest"]
        )
        validate_configuration_receipt(
            staged_configuration,
            root,
            expected_source_digest=digests["source digest"],
            expected_blueprint_digest=digests["blueprint digest"],
            expected_catalog_digest=digests["catalog digest"],
            expected_review_digest=digests["review completion digest"],
            expected_semantic_authority_digest=digests[
                "semantic authority digest"
            ],
            expected_verification_record=audit_proof.verification_record,
            expected_developer_directory=str(
                audit_proof.verification_summary["developerDirectory"]
            ),
        )

        bound_inputs = (
            verification,
            *verification_logs,
            *evidence.values(),
            write_set_receipt,
            product_swift_coverage,
            merge_receipt,
            simulator_result,
            device_result,
        )
        for artifact in bound_inputs:
            _assert_current(root, artifact)

        _check_destination(audit_destination, audit_source)
        _check_destination(configuration_destination, configuration_source)
        _publish(staged_audit, audit_destination, audit_source)
        _publish(
            staged_configuration,
            configuration_destination,
            configuration_source,
        )
        _fsync_directory(root)
    finally:
        for path in staged:
            path.unlink(missing_ok=True)

    audit_proof = validate_audit_manifest(
        audit_destination, root, digests["source digest"]
    )
    validate_configuration_receipt(
        configuration_destination,
        root,
        expected_source_digest=digests["source digest"],
        expected_blueprint_digest=digests["blueprint digest"],
        expected_catalog_digest=digests["catalog digest"],
        expected_review_digest=digests["review completion digest"],
        expected_semantic_authority_digest=digests["semantic authority digest"],
        expected_verification_record=audit_proof.verification_record,
        expected_developer_directory=str(
            audit_proof.verification_summary["developerDirectory"]
        ),
    )
    return FinalArtifactResult(
        audit_destination,
        str(digest_bytes(audit_destination.read_bytes())),
        configuration_destination,
        str(digest_bytes(configuration_destination.read_bytes())),
    )


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Validate final Regression evidence and atomically write the canonical "
            "audit manifest and configuration receipt. Relative input paths are "
            "resolved inside --final-root."
        )
    )
    parser.add_argument("--final-root", type=Path, required=True)
    parser.add_argument("--source-digest", required=True)
    parser.add_argument("--verification-summary", type=Path, required=True)
    parser.add_argument("--no-comments-evidence", type=Path, required=True)
    parser.add_argument("--interrogate-evidence", type=Path, required=True)
    parser.add_argument("--blast-radius-evidence", type=Path, required=True)
    parser.add_argument("--vp-e2e-evidence", type=Path, required=True)
    parser.add_argument("--write-set-receipt", type=Path, required=True)
    parser.add_argument("--product-swift-coverage", type=Path, required=True)
    parser.add_argument("--blueprint-digest", required=True)
    parser.add_argument("--catalog-digest", required=True)
    parser.add_argument("--review-completion-digest", required=True)
    parser.add_argument("--semantic-authority-digest", required=True)
    parser.add_argument("--merge-run-receipt", type=Path, required=True)
    parser.add_argument("--simulator-build-result", type=Path, required=True)
    parser.add_argument("--device-build-result", type=Path, required=True)
    return parser


def _inputs(arguments: argparse.Namespace) -> FinalArtifactInputs:
    return FinalArtifactInputs(
        final_root=arguments.final_root,
        source_digest=arguments.source_digest,
        verification_summary=arguments.verification_summary,
        no_comments_evidence=arguments.no_comments_evidence,
        interrogate_evidence=arguments.interrogate_evidence,
        blast_radius_evidence=arguments.blast_radius_evidence,
        vp_e2e_evidence=arguments.vp_e2e_evidence,
        write_set_receipt=arguments.write_set_receipt,
        product_swift_coverage=arguments.product_swift_coverage,
        blueprint_digest=arguments.blueprint_digest,
        catalog_digest=arguments.catalog_digest,
        review_completion_digest=arguments.review_completion_digest,
        semantic_authority_digest=arguments.semantic_authority_digest,
        merge_run_receipt=arguments.merge_run_receipt,
        simulator_build_result=arguments.simulator_build_result,
        device_build_result=arguments.device_build_result,
    )


def main(
    argv: Sequence[str] | None = None, *, stdout: BinaryIO | None = None
) -> int:
    parser = _parser()
    arguments = parser.parse_args(argv)
    try:
        result = write_final_artifacts(_inputs(arguments))
    except (CompletionError, FinalArtifactError, OSError) as error:
        parser.exit(2, f"final_artifacts: {error}\n")
    output = sys.stdout.buffer if stdout is None else stdout
    output.write(canonical_bytes(result.payload()) + b"\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())


__all__ = (
    "FinalArtifactError",
    "FinalArtifactInputs",
    "FinalArtifactResult",
    "audit_manifest_payload",
    "configuration_receipt_payload",
    "write_final_artifacts",
)
