#!/usr/bin/env python3

from __future__ import annotations

import ast
import json
from pathlib import Path
import sys
from tempfile import TemporaryDirectory
import unittest


SCRIPTS = Path(__file__).resolve().parents[1]
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

from regression.core.digest import (
    canonical_bytes,
    canonical_digest,
    digest_bytes,
)
from regression.core.errors import RegressionError
from regression.core.events import EventType, payload_value
from regression.core.ids import Digest, EvidenceSchema, LeaseID, RunID
from regression.core.ledger import LedgerWriter
from regression.core.replay import read_event_log
from regression.core.store import ArtifactInput, ArtifactStore


RUN_ID = RunID("run:20260828t140501z-a7f2")
PLAN_DIGEST = Digest("sha256:" + "a" * 64)
RECORDED_AT = "2026-08-28T14:05:01.000Z"
EVIDENCE_SCHEMA = EvidenceSchema("fake.frame@1")


def any_events(events) -> None:
    return None


class LedgerTests(unittest.TestCase):
    def test_expanded_evidence_and_oracle_payloads_round_trip_without_shape_loss(self) -> None:
        accepted = {
            "leaseId": "lease:node-first-01",
            "envelopeDigest": "sha256:" + "b" * 64,
            "artifacts": [
                {
                    "obligationId": "obligation:runtime:frame",
                    "evidenceType": "fake.frame",
                    "evidenceSchema": "fake.frame@1",
                    "caseKey": "default",
                    "producedByCall": "call:runtime:capture",
                    "capturedAt": RECORDED_AT,
                    "producerContractDigest": "sha256:" + "c" * 64,
                    "relativePath": "frame.bin",
                    "byteLength": 5,
                    "digest": "sha256:" + "d" * 64,
                    "objectPath": "objects/sha256/" + "d" * 64,
                    "receiptDigest": "sha256:" + "e" * 64,
                }
            ],
        }
        evaluated = {
            "leaseId": "lease:node-first-01",
            "obligationId": "obligation:runtime:frame",
            "overall": "satisfied",
            "criteria": [{"criterion": "frame is visible", "result": "satisfied"}],
            "negativeControls": [
                {"negativeControl": "blank frame", "result": "satisfied"}
            ],
            "evidenceRefs": [{"receiptDigest": "sha256:" + "e" * 64}],
            "detail": [{"code": "fixture", "detail": "exact result"}],
        }
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            with LedgerWriter(directory, RUN_ID, PLAN_DIGEST, any_events) as writer:
                writer.append(EventType.EVIDENCE_ACCEPTED, accepted, RECORDED_AT)
                writer.append(EventType.ORACLE_EVALUATED, evaluated, RECORDED_AT)

            events = read_event_log(directory).events
            self.assertEqual(accepted, payload_value(events[0].payload))
            self.assertEqual(evaluated, payload_value(events[1].payload))

    def test_event_type_is_closed_over_the_runtime_protocol(self) -> None:
        self.assertEqual(
            {
                "RunOpened",
                "LaneBootstrapped",
                "NodeClaimed",
                "OperationAuthorized",
                "OperationInvoked",
                "OperationCompleted",
                "EnvelopeReceived",
                "EvidenceAccepted",
                "OracleEvaluated",
                "VerdictRecorded",
                "LaneInterrupted",
                "RunClosed",
            },
            {event_type.value for event_type in EventType},
        )

    def test_complete_round_trip_has_canonical_payload_and_hash_chain(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            with LedgerWriter(directory, RUN_ID, PLAN_DIGEST, any_events) as writer:
                first = writer.append(
                    EventType.RUN_OPENED,
                    {"z": 2, "a": ["播放", True]},
                    RECORDED_AT,
                    "open-run",
                )
                second = writer.append(
                    EventType.LANE_BOOTSTRAPPED,
                    {"lane": "simulator"},
                    RECORDED_AT,
                )

            event_log = read_event_log(directory)
            self.assertEqual((first, second), event_log.events)
            self.assertEqual(first.event_digest, second.previous_digest)
            self.assertEqual(
                b'{"a":["\xe6\x92\xad\xe6\x94\xbe",true],"z":2}', first.payload
            )
            self.assertFalse((directory / "current.json").exists())
            self.assertFalse((directory / "snapshot.json").exists())
            for line in (directory / "ledger.jsonl").read_bytes().splitlines():
                self.assertEqual(line, canonical_bytes(json.loads(line)))

    def test_payload_tamper_is_rejected(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            with LedgerWriter(directory, RUN_ID, PLAN_DIGEST, any_events) as writer:
                writer.append(EventType.RUN_OPENED, {"value": 1}, RECORDED_AT)
            path = directory / "ledger.jsonl"
            value = json.loads(path.read_text(encoding="utf-8"))
            value["payload"]["value"] = 2
            path.write_bytes(canonical_bytes(value) + b"\n")

            with self.assertRaises(RegressionError) as raised:
                read_event_log(directory)
            self.assertEqual("ledger.event_digest_mismatch", raised.exception.code)

    def test_previous_digest_chain_tamper_is_rejected(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            with LedgerWriter(directory, RUN_ID, PLAN_DIGEST, any_events) as writer:
                writer.append(EventType.RUN_OPENED, {}, RECORDED_AT)
                writer.append(EventType.RUN_CLOSED, {}, RECORDED_AT)
            path = directory / "ledger.jsonl"
            values = [
                json.loads(line)
                for line in path.read_text(encoding="utf-8").splitlines()
            ]
            values[1]["previousDigest"] = "sha256:" + "b" * 64
            fields = dict(values[1])
            del fields["eventDigest"]
            values[1]["eventDigest"] = str(canonical_digest(fields))
            path.write_bytes(
                b"".join(canonical_bytes(value) + b"\n" for value in values)
            )

            with self.assertRaises(RegressionError) as raised:
                read_event_log(directory)
            self.assertEqual(
                "ledger.previous_digest_mismatch", raised.exception.code
            )

    def test_duplicate_json_field_is_rejected(self) -> None:
        with TemporaryDirectory() as temporary:
            path = Path(temporary) / "ledger.jsonl"
            path.write_bytes(b'{"sequence":1,"sequence":1}\n')

            with self.assertRaises(RegressionError) as raised:
                read_event_log(path.parent)
            self.assertEqual("ledger.duplicate_field", raised.exception.code)

    def test_truncated_tail_is_rejected_even_when_json_is_complete(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            with LedgerWriter(directory, RUN_ID, PLAN_DIGEST, any_events) as writer:
                writer.append(EventType.RUN_OPENED, {}, RECORDED_AT)
            path = directory / "ledger.jsonl"
            path.write_bytes(path.read_bytes().removesuffix(b"\n"))

            with self.assertRaises(RegressionError) as raised:
                read_event_log(directory)
            self.assertEqual("ledger.truncated_tail", raised.exception.code)

    def test_sequence_gap_is_rejected_before_chain_can_be_used(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            with LedgerWriter(directory, RUN_ID, PLAN_DIGEST, any_events) as writer:
                writer.append(EventType.RUN_OPENED, {}, RECORDED_AT)
            path = directory / "ledger.jsonl"
            value = json.loads(path.read_text(encoding="utf-8"))
            value["sequence"] = 2
            fields = dict(value)
            del fields["eventDigest"]
            value["eventDigest"] = str(canonical_digest(fields))
            path.write_bytes(canonical_bytes(value) + b"\n")

            with self.assertRaises(RegressionError) as raised:
                read_event_log(directory)
            self.assertEqual("ledger.sequence_gap", raised.exception.code)

    def test_unknown_wire_field_is_rejected(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            with LedgerWriter(directory, RUN_ID, PLAN_DIGEST, any_events) as writer:
                writer.append(EventType.RUN_OPENED, {}, RECORDED_AT)
            path = directory / "ledger.jsonl"
            value = json.loads(path.read_text(encoding="utf-8"))
            value["currentState"] = "forbidden"
            path.write_bytes(canonical_bytes(value) + b"\n")

            with self.assertRaises(RegressionError) as raised:
                read_event_log(directory)
            self.assertEqual("ledger.unknown_field", raised.exception.code)

    def test_second_writer_is_rejected_until_first_closes(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            first = LedgerWriter(directory, RUN_ID, PLAN_DIGEST, any_events)
            try:
                with self.assertRaises(RegressionError) as raised:
                    LedgerWriter(directory, RUN_ID, PLAN_DIGEST, any_events)
                self.assertEqual("ledger.writer_locked", raised.exception.code)
            finally:
                first.close()
            with LedgerWriter(directory, RUN_ID, PLAN_DIGEST, any_events):
                pass

    def test_idempotency_survives_writer_restart_and_conflicts_fail(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            with LedgerWriter(directory, RUN_ID, PLAN_DIGEST, any_events) as writer:
                first = writer.append(
                    EventType.NODE_CLAIMED,
                    {"nodeId": "node:first"},
                    RECORDED_AT,
                    "claim:first",
                )
                repeated = writer.append(
                    EventType.NODE_CLAIMED,
                    {"nodeId": "node:first"},
                    "a different retry timestamp is ignored",
                    "claim:first",
                )
                self.assertIs(first, repeated)
            with LedgerWriter(directory, RUN_ID, PLAN_DIGEST, any_events) as reopened:
                repeated = reopened.append(
                    EventType.NODE_CLAIMED,
                    {"nodeId": "node:first"},
                    RECORDED_AT,
                    "claim:first",
                )
                self.assertEqual(first, repeated)
                with self.assertRaises(RegressionError) as raised:
                    reopened.append(
                        EventType.NODE_CLAIMED,
                        {"nodeId": "node:other"},
                        RECORDED_AT,
                        "claim:first",
                    )
                self.assertEqual("ledger.idempotency_conflict", raised.exception.code)
            self.assertEqual(1, len(read_event_log(directory).events))


class ArtifactStoreTests(unittest.TestCase):
    def _stage(
        self, root: Path, lease: LeaseID, relative_path: str, data: bytes
    ) -> Path:
        path = root / "assignments" / str(lease) / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return path

    def test_ingest_verifies_and_atomically_reuses_cas_object(self) -> None:
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            lease = LeaseID("lease:node-first-01")
            data = b"evidence-bytes"
            self._stage(root, lease, "captures/frame.bin", data)
            digest = digest_bytes(data)
            store = ArtifactStore(root)

            first = store.ingest(
                lease, EVIDENCE_SCHEMA, "captures/frame.bin", len(data), digest
            )
            second = store.ingest(
                lease, EVIDENCE_SCHEMA, "captures/frame.bin", len(data), digest
            )

            self.assertEqual(first, second)
            self.assertEqual(data, first.object_path.read_bytes())
            self.assertEqual(root / "objects" / "sha256", first.object_path.parent)
            self.assertFalse(
                first.receipt_path.is_relative_to(first.object_path.parent)
            )
            self.assertEqual(
                "fake.frame@1",
                json.loads(first.receipt_path.read_text())["evidenceSchema"],
            )
            self.assertEqual(1, len(tuple((root / "objects" / "sha256").iterdir())))

    def test_wrong_hash_and_length_are_rejected_before_cas_write(self) -> None:
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            lease = LeaseID("lease:node-first-01")
            data = b"evidence-bytes"
            self._stage(root, lease, "frame.bin", data)
            store = ArtifactStore(root)

            with self.assertRaises(RegressionError) as wrong_hash:
                store.ingest(
                    lease,
                    EVIDENCE_SCHEMA,
                    "frame.bin",
                    len(data),
                    Digest("sha256:" + "b" * 64),
                )
            self.assertEqual("artifact.sha256_mismatch", wrong_hash.exception.code)
            with self.assertRaises(RegressionError) as wrong_length:
                store.ingest(
                    lease,
                    EVIDENCE_SCHEMA,
                    "frame.bin",
                    len(data) + 1,
                    digest_bytes(data),
                )
            self.assertEqual(
                "artifact.byte_length_mismatch", wrong_length.exception.code
            )
            self.assertFalse((root / "objects").exists())

    def test_zero_byte_artifact_is_rejected_before_cas_write(self) -> None:
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            lease = LeaseID("lease:node-first-01")
            self._stage(root, lease, "empty.bin", b"")
            store = ArtifactStore(root)

            with self.assertRaises(RegressionError) as raised:
                store.ingest(
                    lease,
                    EVIDENCE_SCHEMA,
                    "empty.bin",
                    0,
                    digest_bytes(b""),
                )

            self.assertEqual("artifact.invalid_byte_length", raised.exception.code)
            self.assertFalse((root / "objects").exists())

    def test_batch_validates_every_artifact_before_any_cas_write(self) -> None:
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            lease = LeaseID("lease:node-first-01")
            first = b"first"
            second = b"second"
            self._stage(root, lease, "first.bin", first)
            self._stage(root, lease, "second.bin", second)
            store = ArtifactStore(root)

            with self.assertRaises(RegressionError) as raised:
                store.ingest_many(
                    lease,
                    (
                        ArtifactInput(
                            EVIDENCE_SCHEMA,
                            "first.bin",
                            len(first),
                            digest_bytes(first),
                        ),
                        ArtifactInput(
                            EVIDENCE_SCHEMA,
                            "second.bin",
                            len(second),
                            Digest("sha256:" + "0" * 64),
                        ),
                    ),
                )

            self.assertEqual("artifact.sha256_mismatch", raised.exception.code)
            self.assertFalse((root / "objects").exists())

    def test_absolute_parent_and_backslash_paths_are_rejected(self) -> None:
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            store = ArtifactStore(root)
            lease = LeaseID("lease:node-first-01")
            digest = Digest("sha256:" + "c" * 64)
            fixtures = (
                ("/tmp/frame.bin", "artifact.path.absolute"),
                ("../frame.bin", "artifact.path.traversal"),
                ("captures/../../frame.bin", "artifact.path.traversal"),
                ("captures\\frame.bin", "artifact.path.invalid"),
            )
            for path, code in fixtures:
                with self.subTest(path=path), self.assertRaises(
                    RegressionError
                ) as raised:
                    store.ingest(lease, EVIDENCE_SCHEMA, path, 1, digest)
                self.assertEqual(code, raised.exception.code)

    def test_symlink_file_and_symlink_directory_are_rejected(self) -> None:
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            lease = LeaseID("lease:node-first-01")
            staging = root / "assignments" / str(lease)
            staging.mkdir(parents=True)
            outside = root / "outside"
            outside.mkdir()
            (outside / "frame.bin").write_bytes(b"outside")
            (staging / "file-link").symlink_to(outside / "frame.bin")
            (staging / "directory-link").symlink_to(outside, target_is_directory=True)
            store = ArtifactStore(root)
            digest = digest_bytes(b"outside")

            for path in ("file-link", "directory-link/frame.bin"):
                with self.subTest(path=path), self.assertRaises(RegressionError):
                    store.ingest(lease, EVIDENCE_SCHEMA, path, 7, digest)
            self.assertFalse((root / "objects").exists())


class CompatibilityTests(unittest.TestCase):
    def test_sources_parse_with_python_39_grammar(self) -> None:
        for filename in ("events.py", "ledger.py", "replay.py", "store.py"):
            path = SCRIPTS / "regression" / "core" / filename
            with self.subTest(path=path):
                ast.parse(path.read_text(encoding="utf-8"), feature_version=(3, 9))


if __name__ == "__main__":
    unittest.main()
