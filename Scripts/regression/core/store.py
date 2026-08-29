from __future__ import annotations

from dataclasses import dataclass
import errno
import hashlib
import os
from pathlib import Path, PurePosixPath
import stat
import tempfile
from typing import Any, List, Sequence, Tuple, Union

from .digest import canonical_bytes, canonical_digest
from .errors import RegressionError
from .ids import EvidenceSchema, Digest, LeaseID, parse_evidence_schema, parse_identifier


@dataclass(frozen=True)
class ArtifactReceipt:
    lease_id: LeaseID
    evidence_schema: EvidenceSchema
    relative_path: str
    byte_length: int
    digest: Digest
    object_path: Path
    receipt_digest: Digest
    receipt_path: Path


@dataclass(frozen=True)
class ArtifactInput:
    evidence_schema: EvidenceSchema
    relative_path: Union[str, Path]
    byte_length: int
    digest: Digest


class ArtifactStore:
    def __init__(self, run_directory: Path) -> None:
        self.run_directory = Path(run_directory)

    def ingest(
        self,
        lease_id: LeaseID,
        evidence_schema: EvidenceSchema,
        relative_path: Union[str, Path],
        byte_length: int,
        digest: Digest,
    ) -> ArtifactReceipt:
        return self.ingest_many(
            lease_id,
            (ArtifactInput(evidence_schema, relative_path, byte_length, digest),),
        )[0]

    def ingest_many(
        self,
        lease_id: LeaseID,
        artifacts: Sequence[ArtifactInput],
    ) -> Tuple[ArtifactReceipt, ...]:
        parsed_lease = parse_identifier("lease", lease_id, "leaseId")
        inputs = tuple(artifacts)
        if not inputs or any(not isinstance(item, ArtifactInput) for item in inputs):
            raise RegressionError(
                "artifact.invalid_batch",
                str(parsed_lease),
                "artifact batch must contain ArtifactInput values",
            )
        verified = []
        seen_paths = set()
        for item in inputs:
            parsed_schema = parse_evidence_schema(
                item.evidence_schema, "evidenceSchema"
            )
            parsed_digest = parse_identifier("digest", item.digest, "digest")
            if type(item.byte_length) is not int or item.byte_length <= 0:
                raise RegressionError(
                    "artifact.invalid_byte_length",
                    "byteLength",
                    "byteLength must be a positive integer",
                )
            parts = _safe_relative_parts(item.relative_path)
            relative_text = "/".join(parts)
            if relative_text in seen_paths:
                raise RegressionError(
                    "artifact.duplicate_path",
                    relative_text,
                    "an artifact batch cannot repeat a staging path",
                )
            seen_paths.add(relative_text)
            data = self._read_staging_file(parsed_lease, parts)
            if len(data) != item.byte_length:
                raise RegressionError(
                    "artifact.byte_length_mismatch",
                    relative_text,
                    f"expected {item.byte_length} bytes, found {len(data)}",
                )
            actual = Digest("sha256:" + hashlib.sha256(data).hexdigest())
            if actual != parsed_digest:
                raise RegressionError(
                    "artifact.sha256_mismatch",
                    relative_text,
                    f"expected {parsed_digest}, found {actual}",
                )
            verified.append(
                (
                    EvidenceSchema(parsed_schema),
                    relative_text,
                    item.byte_length,
                    Digest(parsed_digest),
                    data,
                )
            )

        return tuple(
            self._commit(
                parsed_lease,
                evidence_schema,
                relative_path,
                byte_length,
                digest,
                data,
            )
            for evidence_schema, relative_path, byte_length, digest, data in verified
        )

    def _commit(
        self,
        lease_id: LeaseID,
        evidence_schema: EvidenceSchema,
        relative_path: str,
        byte_length: int,
        digest: Digest,
        data: bytes,
    ) -> ArtifactReceipt:
        object_path = self._store_object(digest, data)
        receipt_value = {
            "leaseId": str(lease_id),
            "evidenceSchema": str(evidence_schema),
            "relativePath": relative_path,
            "byteLength": byte_length,
            "digest": str(digest),
            "objectPath": f"objects/sha256/{str(digest)[7:]}",
        }
        receipt_digest = canonical_digest(receipt_value)
        receipt_path = self._store_receipt(receipt_digest, receipt_value)
        return ArtifactReceipt(
            lease_id,
            evidence_schema,
            relative_path,
            byte_length,
            digest,
            object_path,
            receipt_digest,
            receipt_path,
        )

    def _read_staging_file(
        self, lease_id: LeaseID, parts: Tuple[str, ...]
    ) -> bytes:
        assignments = self.run_directory / "assignments"
        opened: List[int] = []
        directory_flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
        no_follow = getattr(os, "O_NOFOLLOW", 0)
        try:
            assignments_fd = os.open(str(assignments), directory_flags | no_follow)
            opened.append(assignments_fd)
            lease_fd = os.open(
                str(lease_id), directory_flags | no_follow, dir_fd=assignments_fd
            )
            opened.append(lease_fd)
            current_fd = lease_fd
            for component in parts[:-1]:
                current_fd = os.open(
                    component, directory_flags | no_follow, dir_fd=current_fd
                )
                opened.append(current_fd)
            file_fd = os.open(
                parts[-1], os.O_RDONLY | no_follow, dir_fd=current_fd
            )
            opened.append(file_fd)
            metadata = os.fstat(file_fd)
            if not stat.S_ISREG(metadata.st_mode):
                raise RegressionError(
                    "artifact.path.not_file",
                    "/".join(parts),
                    "staged artifact must be a regular file",
                )
            chunks = []
            while True:
                chunk = os.read(file_fd, 1024 * 1024)
                if not chunk:
                    break
                chunks.append(chunk)
            return b"".join(chunks)
        except RegressionError:
            raise
        except OSError as error:
            code = (
                "artifact.path.symlink"
                if error.errno == errno.ELOOP
                else "artifact.source.missing"
                if error.errno in (errno.ENOENT, errno.ENOTDIR)
                else "artifact.source.unreadable"
            )
            raise RegressionError(
                code,
                str(assignments / str(lease_id) / Path(*parts)),
                f"cannot read staged artifact: {error.strerror}",
            ) from error
        finally:
            for descriptor in reversed(opened):
                os.close(descriptor)

    def _store_object(self, digest: Digest, data: bytes) -> Path:
        object_directory = _secure_child_directory(
            self.run_directory, ("objects", "sha256"), "artifact.cas.invalid_directory"
        )
        destination = object_directory / str(digest)[7:]
        if destination.is_symlink():
            raise RegressionError(
                "artifact.cas.invalid_existing",
                str(destination),
                "existing CAS entry cannot be a symlink",
            )
        if destination.exists():
            if not destination.is_file():
                raise RegressionError(
                    "artifact.cas.invalid_existing",
                    str(destination),
                    "existing CAS entry must be a regular file",
                )
            existing = destination.read_bytes()
            if hashlib.sha256(existing).digest() != hashlib.sha256(data).digest():
                raise RegressionError(
                    "artifact.cas.collision",
                    str(destination),
                    "existing CAS bytes do not match their digest path",
                )
            return destination

        descriptor, temporary_name = tempfile.mkstemp(
            prefix=".artifact-", dir=str(object_directory)
        )
        temporary = Path(temporary_name)
        try:
            with os.fdopen(descriptor, "wb") as output:
                output.write(data)
                output.flush()
                os.fsync(output.fileno())
            try:
                os.link(str(temporary), str(destination))
            except FileExistsError:
                existing = destination.read_bytes()
                if hashlib.sha256(existing).digest() != hashlib.sha256(data).digest():
                    raise RegressionError(
                        "artifact.cas.collision",
                        str(destination),
                        "concurrent CAS entry does not match its digest path",
                    )
            _fsync_directory(object_directory)
        finally:
            try:
                temporary.unlink()
            except FileNotFoundError:
                pass
        return destination

    def _store_receipt(self, digest: Digest, value: Any) -> Path:
        receipt_directory = _secure_child_directory(
            self.run_directory,
            ("receipts", "artifacts"),
            "artifact.receipt.invalid_directory",
        )
        destination = receipt_directory / (str(digest)[7:] + ".json")
        encoded = canonical_bytes(value) + b"\n"
        if destination.is_symlink():
            raise RegressionError(
                "artifact.receipt.conflict",
                str(destination),
                "existing receipt cannot be a symlink",
            )
        if destination.exists():
            if destination.read_bytes() != encoded:
                raise RegressionError(
                    "artifact.receipt.conflict",
                    str(destination),
                    "existing receipt does not match its content digest",
                )
            return destination

        descriptor, temporary_name = tempfile.mkstemp(
            prefix=".receipt-", dir=str(receipt_directory)
        )
        temporary = Path(temporary_name)
        try:
            with os.fdopen(descriptor, "wb") as output:
                output.write(encoded)
                output.flush()
                os.fsync(output.fileno())
            try:
                os.link(str(temporary), str(destination))
            except FileExistsError:
                if destination.is_symlink() or destination.read_bytes() != encoded:
                    raise RegressionError(
                        "artifact.receipt.conflict",
                        str(destination),
                        "concurrent receipt does not match its content digest",
                    )
            _fsync_directory(receipt_directory)
        finally:
            try:
                temporary.unlink()
            except FileNotFoundError:
                pass
        return destination


def _safe_relative_parts(relative_path: Union[str, Path]) -> Tuple[str, ...]:
    if not isinstance(relative_path, (str, Path)):
        raise RegressionError(
            "artifact.path.invalid",
            "relativePath",
            "artifact path must be a string or Path",
        )
    text = str(relative_path)
    if not text or "\\" in text or "\x00" in text:
        raise RegressionError(
            "artifact.path.invalid",
            "relativePath",
            "artifact path must be a non-empty POSIX relative path",
        )
    path = PurePosixPath(text)
    if path.is_absolute():
        raise RegressionError(
            "artifact.path.absolute", text, "artifact path must be relative"
        )
    if any(component == ".." for component in path.parts):
        raise RegressionError(
            "artifact.path.traversal", text, "artifact path cannot contain '..'"
        )
    parts = tuple(component for component in path.parts if component != ".")
    if not parts or any(component in ("", ".", "..") for component in parts):
        raise RegressionError(
            "artifact.path.invalid", text, "artifact path does not name a file"
        )
    return parts


def _fsync_directory(directory: Path) -> None:
    descriptor = os.open(str(directory), os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def _secure_child_directory(
    root: Path, parts: Tuple[str, ...], error_code: str
) -> Path:
    current = root
    current.mkdir(parents=True, exist_ok=True)
    for part in parts:
        current = current / part
        try:
            current.mkdir()
        except FileExistsError:
            pass
        if current.is_symlink() or not current.is_dir():
            raise RegressionError(
                error_code,
                str(current),
                "storage directory must be a real directory, not a symlink",
            )
    return current


def ingest_artifact(
    run_directory: Path,
    lease_id: LeaseID,
    evidence_schema: EvidenceSchema,
    relative_path: Union[str, Path],
    byte_length: int,
    digest: Digest,
) -> ArtifactReceipt:
    return ArtifactStore(run_directory).ingest(
        lease_id, evidence_schema, relative_path, byte_length, digest
    )


__all__ = (
    "ArtifactInput",
    "ArtifactReceipt",
    "ArtifactStore",
    "ingest_artifact",
)
