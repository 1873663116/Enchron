#!/usr/bin/env python3

from __future__ import annotations

import ast
from dataclasses import replace
from concurrent.futures import ThreadPoolExecutor
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import sys
from tempfile import TemporaryDirectory
import threading
import unittest
from unittest import mock


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCRIPTS_ROOT = REPOSITORY_ROOT / "Scripts"
if str(SCRIPTS_ROOT) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_ROOT))

from regression.core.catalog import load_catalog
from regression.core.contracts import BoundLane
from regression.core.digest import canonical_bytes, canonical_digest
from regression.core.errors import RegressionError
from regression.core.plan import ToolchainIdentity
from regression.core.review import (
    ReviewActorIdentity,
    ReviewClass,
    ReviewReceipt,
    ReviewUsage,
    approve_review_budgets,
)
from regression.core.review_catalog import plan_catalog_reviews
import regression.review_stage as review_stage
from regression.review_io import (
    load_review_policy,
    load_review_report,
    receipt_path,
    review_receipt_payload,
    write_review_receipt,
    write_review_report,
)
from regression.review_stage import (
    AGENT_ASSESSMENT_SCHEMA,
    DERIVED_HUMAN_ACTOR_ID,
    PACKET_MANIFEST_SCHEMA,
    REVIEW_REPORT_SCHEMA,
    accept_agent_assessment,
    agent_review_environment_digest,
    derive_human_coverage_reviews,
    prepare_review_packets,
    review_status,
    run_deterministic_reviews,
)


CATALOG_ROOT = Path("Regression")
POLICY_PATH = Path("Regression/review-policy.md")
ISSUED_AT = "2026-08-29T00:00:00Z"
SEMANTIC_AUTHORITY_SOURCE = (
    REPOSITORY_ROOT / "Config/regression/catalog-root/semantic-authority.json"
)
SEMANTIC_DECISIONS_SOURCE = (
    REPOSITORY_ROOT / "Config/regression/semantic-authority-decisions.tsv"
)


class ReviewStageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.catalog = load_catalog(REPOSITORY_ROOT / CATALOG_ROOT)
        cls.policy = load_review_policy(REPOSITORY_ROOT / POLICY_PATH)
        cls.approved = approve_review_budgets(
            plan_catalog_reviews(cls.catalog, cls.policy)
        )
        cls.agent_packets = tuple(
            packet
            for packet in cls.approved.packets
            if packet.reviewer is ReviewClass.AGENT_OPERABILITY
        )
        cls.human_packet = next(
            packet
            for packet in cls.approved.packets
            if packet.reviewer is ReviewClass.HUMAN_COVERAGE
        )

    def assert_error(self, code: str, call) -> RegressionError:
        with self.assertRaises(RegressionError) as raised:
            call()
        self.assertEqual(raised.exception.code, code)
        return raised.exception

    def assessment(self, packet=None):
        if packet is None:
            packet = self.agent_packets[0]
        return {
            "schema": AGENT_ASSESSMENT_SCHEMA,
            "schemaVersion": 1,
            "packetDigest": str(packet.packet_digest),
            "reviewer": ReviewClass.AGENT_OPERABILITY.value,
            "actor": {
                "actorId": "agent:test-operability-reviewer",
                "environmentDigest": str(
                    agent_review_environment_digest(
                        REPOSITORY_ROOT, packet.packet_digest
                    )
                ),
            },
            "usage": packet.approved_budget.as_dict(),
            "issuedAt": ISSUED_AT,
            "units": [
                {
                    "kind": unit.kind.value,
                    "ref": unit.ref,
                    "contentDigest": str(unit.content_digest),
                    "decision": "accepted",
                    "rationale": (
                        "The declared operation, inputs, and evidence boundary "
                        "are executable without unstated human steps."
                    ),
                }
                for unit in packet.units
            ],
        }

    def write_assessment(self, root: Path, value, name: str = "assessment.json") -> Path:
        path = root / name
        path.write_bytes(canonical_bytes(value) + b"\n")
        return path

    def accept(self, root: Path, value):
        assessment = self.write_assessment(root, value)
        return accept_agent_assessment(
            REPOSITORY_ROOT,
            CATALOG_ROOT,
            POLICY_PATH,
            root / "reviews",
            assessment,
        )

    def complete_non_human_reviews(self, root: Path) -> Path:
        reviews = root / "reviews"
        run_deterministic_reviews(
            REPOSITORY_ROOT,
            CATALOG_ROOT,
            POLICY_PATH,
            reviews,
            ISSUED_AT,
        )
        for index, packet in enumerate(self.agent_packets):
            assessment = self.write_assessment(
                root,
                self.assessment(packet),
                f"agent-{index}.json",
            )
            accept_agent_assessment(
                REPOSITORY_ROOT,
                CATALOG_ROOT,
                POLICY_PATH,
                reviews,
                assessment,
            )
        return reviews

    def semantic_authority_repository(
        self,
        root: Path,
        locator: str = "Evidence/Proof.swift#proofSymbol",
    ) -> Path:
        repository = root / "repository"
        authority_path = repository / "Regression/semantic-authority.json"
        decisions_path = (
            repository / "Config/regression/semantic-authority-decisions.tsv"
        )
        evidence_root = repository / "Evidence"
        authority_path.parent.mkdir(parents=True)
        decisions_path.parent.mkdir(parents=True)
        evidence_root.mkdir(parents=True)

        decisions_source = b"id\tstatus\nHC-000\tdecided\n"
        decisions_path.write_bytes(decisions_source)
        (evidence_root / "Proof.swift").write_text(
            "enum Proof { static let proofSymbol = true }\n",
            encoding="utf-8",
        )
        (evidence_root / "guide.md").write_text(
            "# Permission bootstrap\n\nApproved evidence.\n",
            encoding="utf-8",
        )
        (evidence_root / "records.json").write_text(
            '{"approved":true}\n', encoding="utf-8"
        )
        (evidence_root / "decisions.tsv").write_text(
            "id\tstatus\nHC-015\tdecided\n", encoding="utf-8"
        )

        document = json.loads(
            SEMANTIC_AUTHORITY_SOURCE.read_text(encoding="utf-8")
        )
        document["authority"]["sourceDigest"] = (
            "sha256:" + hashlib.sha256(decisions_source).hexdigest()
        )
        for decision in document["decisions"]:
            decision["evidence"] = ["Evidence/Proof.swift#proofSymbol"]
        document["decisions"][0]["evidence"] = [locator]
        authority_path.write_text(
            json.dumps(document, ensure_ascii=False), encoding="utf-8"
        )
        return repository.resolve()

    def test_catalog_analysis_request_uses_explicit_v2_placeholder(self) -> None:
        scope_fact = next(
            fact
            for fact in self.catalog.facts
            if fact.id == review_stage._CATALOG_SCOPE_FACT
        )
        request = review_stage._analysis_request(self.catalog, scope_fact)
        identity = request.build_identity

        self.assertEqual(
            (BoundLane.SIMULATOR, BoundLane.DEVICE),
            request.requested_lanes,
        )
        self.assertIsInstance(identity.toolchain, ToolchainIdentity)
        self.assertEqual(
            ("catalog-analysis-only",) * 6,
            (
                identity.toolchain.xcode_version,
                identity.toolchain.xcode_build,
                identity.toolchain.visionos_sdk_version,
                identity.toolchain.visionos_sdk_build,
                identity.toolchain.visionos_simulator_sdk_version,
                identity.toolchain.visionos_simulator_sdk_build,
            ),
        )
        artifact_digests = tuple(
            digest
            for artifact in identity.lane_artifacts
            for digest in (
                artifact.xctestrun_digest,
                artifact.test_products_digest,
                artifact.application_code_digest,
            )
        )
        self.assertEqual(6, len(set(artifact_digests)))
        self.assertFalse(hasattr(identity, "worktree_clean"))

    def test_prepared_manifests_are_stable_canonical_and_source_bound(self) -> None:
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            first = prepare_review_packets(
                REPOSITORY_ROOT,
                CATALOG_ROOT,
                POLICY_PATH,
                root / "stage",
            )
            before = tuple(path.read_bytes() for path in first.manifest_paths)
            second = prepare_review_packets(
                REPOSITORY_ROOT,
                CATALOG_ROOT,
                POLICY_PATH,
                root / "stage",
            )

            self.assertEqual(len(self.approved.packets), len(first.manifest_paths))
            self.assertEqual(first, second)
            self.assertEqual(before, tuple(path.read_bytes() for path in second.manifest_paths))
            for path, source in zip(first.manifest_paths, before):
                self.assertTrue(source.endswith(b"\n"))
                value = json.loads(source)
                self.assertEqual(source, canonical_bytes(value) + b"\n")
                self.assertEqual(value["schema"], PACKET_MANIFEST_SCHEMA)
                self.assertEqual(value["catalogDigest"], str(self.catalog.catalog_digest))
                self.assertIn(value["reviewer"], {item.value for item in ReviewClass})
                self.assertTrue(value["units"])
                for unit in value["units"]:
                    source_path = REPOSITORY_ROOT / unit["sourcePath"]
                    self.assertTrue(source_path.is_file(), source_path)
                    self.assertEqual(source_path.suffix, ".md")
                self.assertIn(value["reviewer"], path.parts)

    def test_deterministic_review_receipts_cover_exact_partition(self) -> None:
        with TemporaryDirectory() as temporary:
            reviews = Path(temporary) / "reviews"
            result = run_deterministic_reviews(
                REPOSITORY_ROOT,
                CATALOG_ROOT,
                POLICY_PATH,
                reviews,
                ISSUED_AT,
            )
            expected = {
                packet.packet_digest
                for packet in self.approved.packets
                if packet.reviewer is ReviewClass.DETERMINISTIC
            }
            actual = {item.receipt.packet_digest for item in result.issued}

            self.assertEqual(actual, expected)
            self.assertEqual(len(result.issued), len(expected))
            for item in result.issued:
                self.assertIs(item.receipt.reviewer, ReviewClass.DETERMINISTIC)
                self.assertEqual(item.receipt.actor.actor_id, "checker:regression-review-stage")
                self.assertEqual(item.receipt.actor.environment_digest, result.environment_digest)
                report = load_review_report(reviews, item.receipt.report_digest)
                self.assertIn(str(item.receipt.packet_digest), report)
            status = review_status(
                REPOSITORY_ROOT, CATALOG_ROOT, POLICY_PATH, reviews
            )
            self.assertEqual(status.pending[ReviewClass.DETERMINISTIC], 0)
            self.assertEqual(
                status.pending[ReviewClass.AGENT_OPERABILITY],
                len(self.agent_packets),
            )
            self.assertEqual(
                status.pending[ReviewClass.HUMAN_COVERAGE],
                sum(
                    packet.reviewer is ReviewClass.HUMAN_COVERAGE
                    for packet in self.approved.packets
                ),
            )

    def test_deterministic_and_agent_reviews_publish_concurrently_without_shared_writes(
        self,
    ) -> None:
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            reviews = root / "reviews"
            packet = self.agent_packets[0]
            assessment = self.write_assessment(
                root,
                self.assessment(packet),
                "concurrent-agent.json",
            )
            original_write_report = review_stage.write_review_report
            first_report_by_reviewer = set()
            first_report_lock = threading.Lock()
            both_reviewers_writing = threading.Barrier(2)

            def synchronized_write_report(target, report):
                reviewer = next(
                    value
                    for value in (
                        ReviewClass.DETERMINISTIC.value,
                        ReviewClass.AGENT_OPERABILITY.value,
                    )
                    if f'"reviewer":"{value}"' in report
                )
                with first_report_lock:
                    first_for_reviewer = reviewer not in first_report_by_reviewer
                    first_report_by_reviewer.add(reviewer)
                if first_for_reviewer:
                    both_reviewers_writing.wait(timeout=10)
                return original_write_report(target, report)

            with (
                mock.patch.object(
                    review_stage, "_implementation_locators", return_value=()
                ),
                mock.patch.object(
                    review_stage,
                    "write_review_report",
                    side_effect=synchronized_write_report,
                ),
                ThreadPoolExecutor(max_workers=2) as executor,
            ):
                deterministic_future = executor.submit(
                    run_deterministic_reviews,
                    REPOSITORY_ROOT,
                    CATALOG_ROOT,
                    POLICY_PATH,
                    reviews,
                    ISSUED_AT,
                )
                agent_future = executor.submit(
                    accept_agent_assessment,
                    REPOSITORY_ROOT,
                    CATALOG_ROOT,
                    POLICY_PATH,
                    reviews,
                    assessment,
                )
                deterministic_result = deterministic_future.result(timeout=30)
                agent_result = agent_future.result(timeout=30)
                status = review_status(
                    REPOSITORY_ROOT, CATALOG_ROOT, POLICY_PATH, reviews
                )

            self.assertEqual(
                deterministic_result.catalog_digest,
                self.catalog.catalog_digest,
            )
            self.assertEqual(
                deterministic_result.plan_digest,
                self.approved.planned_review_digest,
            )
            self.assertEqual(status.catalog_digest, self.catalog.catalog_digest)
            self.assertEqual(
                status.plan_digest, self.approved.planned_review_digest
            )
            self.assertEqual(
                agent_result.receipt.packet_digest, packet.packet_digest
            )
            self.assertEqual(
                first_report_by_reviewer,
                {
                    ReviewClass.DETERMINISTIC.value,
                    ReviewClass.AGENT_OPERABILITY.value,
                },
            )
            deterministic_paths = {
                item.receipt_path for item in deterministic_result.issued
            }
            deterministic_reports = {
                item.report_path for item in deterministic_result.issued
            }
            agent_paths = {agent_result.receipt_path}
            self.assertTrue(deterministic_paths.isdisjoint(agent_paths))
            self.assertTrue(
                deterministic_reports.isdisjoint({agent_result.report_path})
            )
            self.assertTrue(
                all(
                    path.parent.name == ReviewClass.DETERMINISTIC.value
                    for path in deterministic_paths
                )
            )
            self.assertEqual(
                agent_result.receipt_path.parent.name,
                ReviewClass.AGENT_OPERABILITY.value,
            )
            published_paths = (
                deterministic_paths
                | agent_paths
                | deterministic_reports
                | {agent_result.report_path}
            )
            for path in published_paths:
                path.relative_to(reviews)
                self.assertTrue(path.is_file())
            self.assertEqual(tuple(reviews.rglob(".review-*")), ())
            self.assertEqual(status.pending[ReviewClass.DETERMINISTIC], 0)
            self.assertEqual(
                status.completed[ReviewClass.AGENT_OPERABILITY], 1
            )

    def test_human_coverage_waits_for_atomic_non_human_receipt_publication(
        self,
    ) -> None:
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            reviews = root / "reviews"
            for index, packet in enumerate(self.agent_packets[:-1]):
                assessment = self.write_assessment(
                    root,
                    self.assessment(packet),
                    f"completed-agent-{index}.json",
                )
                accept_agent_assessment(
                    REPOSITORY_ROOT,
                    CATALOG_ROOT,
                    POLICY_PATH,
                    reviews,
                    assessment,
                )

            last_packet = self.agent_packets[-1]
            last_assessment = self.write_assessment(
                root,
                self.assessment(last_packet),
                "last-agent.json",
            )
            original_write_receipt = review_stage.write_review_receipt
            ready_to_publish = {
                ReviewClass.DETERMINISTIC: threading.Event(),
                ReviewClass.AGENT_OPERABILITY: threading.Event(),
            }
            release_publication = threading.Event()

            def paused_non_human_receipt(target, receipt):
                event = ready_to_publish.get(receipt.reviewer)
                if event is not None and not event.is_set():
                    event.set()
                    if not release_publication.wait(timeout=10):
                        raise TimeoutError("receipt publication was not released")
                return original_write_receipt(target, receipt)

            with (
                mock.patch.object(
                    review_stage, "_implementation_locators", return_value=()
                ),
                mock.patch.object(
                    review_stage,
                    "SEMANTIC_AUTHORITY_PATH",
                    Path("Config/regression/catalog-root/semantic-authority.json"),
                ),
                mock.patch.object(
                    review_stage,
                    "write_review_receipt",
                    side_effect=paused_non_human_receipt,
                ),
                ThreadPoolExecutor(max_workers=2) as executor,
            ):
                deterministic_future = executor.submit(
                    run_deterministic_reviews,
                    REPOSITORY_ROOT,
                    CATALOG_ROOT,
                    POLICY_PATH,
                    reviews,
                    ISSUED_AT,
                )
                agent_future = executor.submit(
                    accept_agent_assessment,
                    REPOSITORY_ROOT,
                    CATALOG_ROOT,
                    POLICY_PATH,
                    reviews,
                    last_assessment,
                )
                self.assertTrue(
                    ready_to_publish[ReviewClass.DETERMINISTIC].wait(timeout=10)
                )
                self.assertTrue(
                    ready_to_publish[ReviewClass.AGENT_OPERABILITY].wait(timeout=10)
                )
                reports_before_early_derivation = frozenset(
                    (reviews / "reports").rglob("*.md")
                )
                try:
                    pending_error = self.assert_error(
                        "review.stage.derived_human.non_human_incomplete",
                        lambda: derive_human_coverage_reviews(
                            REPOSITORY_ROOT,
                            CATALOG_ROOT,
                            POLICY_PATH,
                            reviews,
                            ISSUED_AT,
                        ),
                    )
                    self.assertIn("agent-operability=1", pending_error.detail)
                    self.assertRegex(
                        pending_error.detail,
                        r"(?:^|, )deterministic=[1-9][0-9]*(?:,|$)",
                    )
                    self.assertFalse(
                        (reviews / ReviewClass.HUMAN_COVERAGE.value).exists()
                    )
                    self.assertEqual(
                        frozenset((reviews / "reports").rglob("*.md")),
                        reports_before_early_derivation,
                    )
                finally:
                    release_publication.set()
                deterministic_future.result(timeout=30)
                agent_future.result(timeout=30)
                derived = derive_human_coverage_reviews(
                    REPOSITORY_ROOT,
                    CATALOG_ROOT,
                    POLICY_PATH,
                    reviews,
                    ISSUED_AT,
                )
                status = review_status(
                    REPOSITORY_ROOT, CATALOG_ROOT, POLICY_PATH, reviews
                )

            self.assertEqual(
                len(derived.issued),
                sum(
                    packet.reviewer is ReviewClass.HUMAN_COVERAGE
                    for packet in self.approved.packets
                ),
            )
            self.assertEqual(
                {reviewer: 0 for reviewer in ReviewClass},
                dict(status.pending),
            )
            self.assertEqual(tuple(reviews.rglob(".review-*")), ())

    def test_stale_agent_packet_digest_is_rejected_before_writes(self) -> None:
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            value = self.assessment()
            value["packetDigest"] = str(canonical_digest({"stale": "packet"}))
            assessment = self.write_assessment(root, value)

            self.assert_error(
                "review.stage.assessment.stale_packet",
                lambda: accept_agent_assessment(
                    REPOSITORY_ROOT,
                    CATALOG_ROOT,
                    POLICY_PATH,
                    root / "reviews",
                    assessment,
                ),
            )
            self.assertFalse((root / "reviews").exists())

    def test_agent_units_reject_missing_extra_and_duplicate_coverage(self) -> None:
        mutations = []

        missing = self.assessment()
        missing["units"] = missing["units"][1:]
        mutations.append(("review.stage.assessment.unit_missing", missing))

        extra = self.assessment()
        extra["units"].append(
            {
                "kind": "operation",
                "ref": "operation:extra@1",
                "contentDigest": str(canonical_digest({"extra": True})),
                "decision": "accepted",
                "rationale": "This extra entry must not be accepted.",
            }
        )
        mutations.append(("review.stage.assessment.unit_extra", extra))

        duplicate = self.assessment()
        duplicate["units"].append(deepcopy(duplicate["units"][0]))
        mutations.append(("review.stage.assessment.unit_duplicate", duplicate))

        for index, (code, value) in enumerate(mutations):
            with self.subTest(code=code), TemporaryDirectory() as temporary:
                root = Path(temporary)
                assessment = self.write_assessment(root, value, f"{index}.json")
                self.assert_error(
                    code,
                    lambda: accept_agent_assessment(
                        REPOSITORY_ROOT,
                        CATALOG_ROOT,
                        POLICY_PATH,
                        root / "reviews",
                        assessment,
                    ),
                )

    def test_rejected_agent_leaf_cannot_issue_receipt(self) -> None:
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            value = self.assessment()
            value["units"][0]["decision"] = "rejected"
            value["units"][0]["rationale"] = "The operation has an unstated setup step."
            assessment = self.write_assessment(root, value)

            self.assert_error(
                "review.stage.assessment.rejected",
                lambda: accept_agent_assessment(
                    REPOSITORY_ROOT,
                    CATALOG_ROOT,
                    POLICY_PATH,
                    root / "reviews",
                    assessment,
                ),
            )
            self.assertFalse((root / "reviews").exists())

    def test_agent_environment_must_bind_packet_and_current_protocol(self) -> None:
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            value = self.assessment()
            value["actor"]["environmentDigest"] = str(
                canonical_digest({"stale": "agent-review-protocol"})
            )
            assessment = self.write_assessment(root, value)

            self.assert_error(
                "review.stage.assessment.environment_mismatch",
                lambda: accept_agent_assessment(
                    REPOSITORY_ROOT,
                    CATALOG_ROOT,
                    POLICY_PATH,
                    root / "reviews",
                    assessment,
                ),
            )
            self.assertFalse((root / "reviews").exists())

    def test_agent_usage_cannot_exceed_approved_typed_budget(self) -> None:
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            packet = self.agent_packets[0]
            value = self.assessment(packet)
            value["usage"]["reviewItems"] = (
                packet.approved_budget.as_dict()["reviewItems"] + 1
            )
            assessment = self.write_assessment(root, value)

            self.assert_error(
                "review.stage.usage.exceeds_budget",
                lambda: accept_agent_assessment(
                    REPOSITORY_ROOT,
                    CATALOG_ROOT,
                    POLICY_PATH,
                    root / "reviews",
                    assessment,
                ),
            )

    def test_manifest_writes_are_idempotent_and_conflict_safe(self) -> None:
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            first = prepare_review_packets(
                REPOSITORY_ROOT,
                CATALOG_ROOT,
                POLICY_PATH,
                root / "stage",
            )
            second = prepare_review_packets(
                REPOSITORY_ROOT,
                CATALOG_ROOT,
                POLICY_PATH,
                root / "stage",
            )
            self.assertEqual(first, second)

            first.manifest_paths[0].write_text("conflict\n", encoding="utf-8")
            self.assert_error(
                "review.stage.write_conflict",
                lambda: prepare_review_packets(
                    REPOSITORY_ROOT,
                    CATALOG_ROOT,
                    POLICY_PATH,
                    root / "stage",
                ),
            )

    def test_agent_report_and_receipt_are_idempotent(self) -> None:
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            value = self.assessment()
            first = self.accept(root, value)
            second = self.accept(root, value)

            self.assertEqual(first, second)
            self.assertEqual(
                load_review_report(root / "reviews", first.receipt.report_digest),
                first.report_path.read_text(encoding="utf-8"),
            )

            changed = self.assessment()
            changed["units"][0]["rationale"] = (
                "A different rationale cannot replace an issued packet receipt."
            )
            self.assert_error(
                "review.io.write_conflict", lambda: self.accept(root, changed)
            )

    def test_status_rejects_report_that_is_not_bound_to_receipt_packet(self) -> None:
        with TemporaryDirectory() as temporary:
            reviews = Path(temporary) / "reviews"
            packet = self.agent_packets[0]
            actor = ReviewActorIdentity(
                "agent:forged-report-test",
                canonical_digest({"environment": "forged-report-test"}),
            )
            usage = ReviewUsage(tuple(packet.approved_budget.amounts))
            wrong_metadata = {
                "schema": REVIEW_REPORT_SCHEMA,
                "schemaVersion": 1,
                "packetId": str(self.agent_packets[1].packet_id),
                "packetDigest": str(packet.packet_digest),
                "reviewer": packet.reviewer.value,
                "actor": {
                    "actorId": actor.actor_id,
                    "environmentDigest": str(actor.environment_digest),
                },
                "usage": usage.as_dict(),
                "issuedAt": ISSUED_AT,
            }
            report = (
                "---\n"
                + canonical_bytes(wrong_metadata).decode("utf-8")
                + "\n---\n\n# Forged binding\n"
            )
            report_digest, _ = write_review_report(reviews, report)
            receipt = ReviewReceipt(
                packet.packet_digest,
                packet.reviewer,
                actor,
                report_digest,
                True,
                usage,
                ISSUED_AT,
                canonical_digest({"assessment": "forged-report-test"}),
            )
            write_review_receipt(reviews, receipt)

            self.assert_error(
                "review.stage.report.binding_mismatch",
                lambda: review_status(
                    REPOSITORY_ROOT, CATALOG_ROOT, POLICY_PATH, reviews
                ),
            )

    def issue_one_agent_review(self, root: Path):
        """Issue a single AgentOperability receipt and return it with its packet."""
        packet = self.agent_packets[0]
        issued = self.accept(root, self.assessment(packet))
        return packet, issued.receipt

    def status_error_for_one_agent_receipt(self, reviews: Path, code: str) -> None:
        self.assert_error(
            code,
            lambda: review_status(
                REPOSITORY_ROOT, CATALOG_ROOT, POLICY_PATH, reviews
            ),
        )

    def test_status_rejects_an_assessment_whose_bytes_were_replaced(self) -> None:
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            reviews = root / "reviews"
            _, receipt = self.issue_one_agent_review(root)
            stored = (
                reviews
                / "assessments"
                / "sha256"
                / (str(receipt.assessment_digest).removeprefix("sha256:") + ".json")
            )
            stored.write_bytes(canonical_bytes({"schema": "tampered"}) + b"\n")

            self.status_error_for_one_agent_receipt(
                reviews, "review.io.assessment_digest_mismatch"
            )

    def test_status_rejects_a_receipt_whose_assessment_is_absent(self) -> None:
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            reviews = root / "reviews"
            _, receipt = self.issue_one_agent_review(root)
            (
                reviews
                / "assessments"
                / "sha256"
                / (str(receipt.assessment_digest).removeprefix("sha256:") + ".json")
            ).unlink()

            self.status_error_for_one_agent_receipt(
                reviews, "review.io.missing_assessment"
            )

    def test_status_rejects_a_receipt_naming_another_packets_assessment(self) -> None:
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            reviews = root / "reviews"
            first = self.accept(root, self.assessment(self.agent_packets[0]))
            second = self.accept(
                root, self.assessment(self.agent_packets[1])
            ).receipt
            swapped = replace(
                first.receipt, assessment_digest=second.assessment_digest
            )
            receipt_path(reviews, swapped).write_bytes(
                canonical_bytes(review_receipt_payload(swapped)) + b"\n"
            )

            self.status_error_for_one_agent_receipt(
                reviews, "review.stage.assessment.packet_mismatch"
            )

    def test_status_rejects_a_report_that_does_not_follow_from_its_assessment(
        self,
    ) -> None:
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            reviews = root / "reviews"
            packet, receipt = self.issue_one_agent_review(root)
            stored = (
                reviews
                / "reports"
                / "sha256"
                / (str(receipt.report_digest).removeprefix("sha256:") + ".md")
            )
            source = stored.read_text(encoding="utf-8")
            rewritten = source.replace(
                "Every packet unit has an accepted decision",
                "Some packet unit has an accepted decision",
            )
            self.assertNotEqual(source, rewritten)
            stored.write_text(rewritten, encoding="utf-8")

            self.status_error_for_one_agent_receipt(
                reviews, "review.io.report_digest_mismatch"
            )

    def test_status_rejects_a_self_consistent_report_that_contradicts_its_assessment(
        self,
    ) -> None:
        """The forgery the frontmatter check alone cannot see.

        Everything a receipt used to be checked against still lines up: the
        report bytes hash to the receipt digest and its frontmatter binds this
        packet, actor, usage and issue time. Only rebuilding the report from the
        assessment shows that the body claims a verdict nobody assessed.
        """
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            reviews = root / "reviews"
            packet, receipt = self.issue_one_agent_review(root)
            metadata = {
                "schema": REVIEW_REPORT_SCHEMA,
                "schemaVersion": 1,
                "packetId": str(packet.packet_id),
                "packetDigest": str(packet.packet_digest),
                "reviewer": packet.reviewer.value,
                "actor": {
                    "actorId": receipt.actor.actor_id,
                    "environmentDigest": str(receipt.actor.environment_digest),
                },
                "usage": receipt.usage.as_dict(),
                "issuedAt": receipt.issued_at,
            }
            forged = (
                "---\n"
                + canonical_bytes(metadata).decode("utf-8")
                + "\n---\n\n"
                + f"This report accepts `{packet.packet_id}`.\n\n"
                + "## Canonical assessment\n\n    {}\n"
            )
            forged_digest, _ = write_review_report(reviews, forged)
            self.assertNotEqual(forged_digest, receipt.report_digest)
            swapped = replace(receipt, report_digest=forged_digest)
            receipt_path(reviews, swapped).write_bytes(
                canonical_bytes(review_receipt_payload(swapped)) + b"\n"
            )

            self.status_error_for_one_agent_receipt(
                reviews, "review.stage.status.report_not_derived"
            )

    def test_status_rejects_a_receipt_that_renames_the_assessment_actor(self) -> None:
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            reviews = root / "reviews"
            packet, receipt = self.issue_one_agent_review(root)
            renamed = replace(
                receipt,
                actor=ReviewActorIdentity(
                    "agent:someone-else", receipt.actor.environment_digest
                ),
            )
            path = receipt_path(reviews, renamed)
            path.write_bytes(
                canonical_bytes(review_receipt_payload(renamed)) + b"\n"
            )

            self.status_error_for_one_agent_receipt(
                reviews, "review.stage.report.binding_mismatch"
            )

    def test_status_rejects_stale_deterministic_checker_environment(self) -> None:
        with TemporaryDirectory() as temporary:
            reviews = Path(temporary) / "reviews"
            packet = next(
                item
                for item in self.approved.packets
                if item.reviewer is ReviewClass.DETERMINISTIC
            )
            actor = ReviewActorIdentity(
                "checker:regression-review-stage",
                canonical_digest({"stale": "checker-environment"}),
            )
            usage = ReviewUsage(tuple(packet.approved_budget.amounts))
            metadata = {
                "schema": REVIEW_REPORT_SCHEMA,
                "schemaVersion": 1,
                "packetId": str(packet.packet_id),
                "packetDigest": str(packet.packet_digest),
                "reviewer": packet.reviewer.value,
                "actor": {
                    "actorId": actor.actor_id,
                    "environmentDigest": str(actor.environment_digest),
                },
                "usage": usage.as_dict(),
                "issuedAt": ISSUED_AT,
            }
            report = (
                "---\n"
                + canonical_bytes(metadata).decode("utf-8")
                + "\n---\n\n# Stale checker environment\n"
            )
            report_digest, _ = write_review_report(reviews, report)
            write_review_receipt(
                reviews,
                ReviewReceipt(
                    packet.packet_digest,
                    packet.reviewer,
                    actor,
                    report_digest,
                    True,
                    usage,
                    ISSUED_AT,
                ),
            )

            self.assert_error(
                "review.stage.status.environment_mismatch",
                lambda: review_status(
                    REPOSITORY_ROOT, CATALOG_ROOT, POLICY_PATH, reviews
                ),
            )

    def test_agent_api_refuses_human_coverage_issuance(self) -> None:
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            value = self.assessment(self.human_packet)
            value["reviewer"] = ReviewClass.HUMAN_COVERAGE.value
            assessment = self.write_assessment(root, value)

            self.assert_error(
                "review.stage.human_receipt.forbidden",
                lambda: accept_agent_assessment(
                    REPOSITORY_ROOT,
                    CATALOG_ROOT,
                    POLICY_PATH,
                    root / "reviews",
                    assessment,
                ),
            )
            self.assertFalse((root / "reviews").exists())

    def test_derived_human_coverage_requires_complete_non_human_reviews(self) -> None:
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.assert_error(
                "review.stage.derived_human.non_human_incomplete",
                lambda: derive_human_coverage_reviews(
                    REPOSITORY_ROOT,
                    CATALOG_ROOT,
                    POLICY_PATH,
                    root / "reviews",
                    ISSUED_AT,
                ),
            )
            self.assertFalse((root / "reviews").exists())

    def test_semantic_authority_source_digest_tamper_fails_closed(self) -> None:
        with TemporaryDirectory() as temporary:
            repository = self.semantic_authority_repository(Path(temporary))
            authority_path = repository / "Regression/semantic-authority.json"
            decisions_path = (
                repository / "Config/regression/semantic-authority-decisions.tsv"
            )

            authority = review_stage._semantic_authority(repository)
            payload = json.loads(authority_path.read_text(encoding="utf-8"))
            self.assertEqual(
                str(authority.decision_log_digest),
                payload["authority"]["sourceDigest"],
            )

            decisions_path.write_bytes(decisions_path.read_bytes() + b"tampered\n")
            self.assert_error(
                "review.stage.semantic_authority.source_digest",
                lambda: review_stage._semantic_authority(repository),
            )

    def test_semantic_authority_evidence_locator_grammar_is_file_aware(self) -> None:
        locators = (
            "Evidence/Proof.swift",
            "Evidence/Proof.swift#proofSymbol",
            "Evidence/guide.md#Permission bootstrap",
            "Evidence/records.json#approved",
            "Evidence/decisions.tsv#HC-015",
        )
        for locator in locators:
            with self.subTest(locator=locator), TemporaryDirectory() as temporary:
                repository = self.semantic_authority_repository(
                    Path(temporary), locator
                )
                review_stage._semantic_authority(repository)

    def test_semantic_authority_rejects_missing_and_prose_evidence_paths(self) -> None:
        cases = (
            (
                "review.stage.semantic_authority.evidence.locator",
                "approved composite design",
            ),
            (
                "review.stage.semantic_authority.evidence.missing_path",
                "Evidence/Missing.swift#proofSymbol",
            ),
        )
        for code, locator in cases:
            with self.subTest(locator=locator), TemporaryDirectory() as temporary:
                repository = self.semantic_authority_repository(
                    Path(temporary), locator
                )
                self.assert_error(
                    code, lambda: review_stage._semantic_authority(repository)
                )

    def test_semantic_authority_rejects_repository_escape_evidence_paths(self) -> None:
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            for kind in ("parent", "absolute", "symlink"):
                with self.subTest(kind=kind):
                    case_root = root / kind
                    case_root.mkdir()
                    outside = case_root / "outside.swift"
                    outside.write_text(
                        "enum Proof { static let proofSymbol = true }\n",
                        encoding="utf-8",
                    )
                    locator = {
                        "parent": "../outside.swift#proofSymbol",
                        "absolute": f"{outside.resolve()}#proofSymbol",
                        "symlink": "Evidence/escaped.swift#proofSymbol",
                    }[kind]
                    repository = self.semantic_authority_repository(
                        case_root, locator
                    )
                    if kind == "symlink":
                        (repository / "Evidence/escaped.swift").symlink_to(
                            outside
                        )

                    self.assert_error(
                        "review.stage.semantic_authority.evidence.outside_repository",
                        lambda: review_stage._semantic_authority(repository),
                    )

    def test_semantic_authority_rejects_missing_or_stale_evidence_anchors(self) -> None:
        locators = (
            "Evidence/Proof.swift#missingSymbol",
            "Evidence/guide.md#Old permission heading",
            "Evidence/guide.md#Approved evidence.",
            "Evidence/records.json#missingRecord",
            "Evidence/decisions.tsv#HC-999",
        )
        for locator in locators:
            with self.subTest(locator=locator), TemporaryDirectory() as temporary:
                repository = self.semantic_authority_repository(
                    Path(temporary), locator
                )
                self.assert_error(
                    "review.stage.semantic_authority.evidence.anchor",
                    lambda: review_stage._semantic_authority(repository),
                )

    def test_semantic_authority_rejects_unsafe_or_symlinked_source(self) -> None:
        payload = json.loads(SEMANTIC_AUTHORITY_SOURCE.read_text(encoding="utf-8"))
        with TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            for name, source in (
                ("absolute", str(root / "approved.tsv")),
                ("parent", "../approved.tsv"),
            ):
                with self.subTest(source=name):
                    repository = root / name
                    authority_path = repository / "Regression/semantic-authority.json"
                    authority_path.parent.mkdir(parents=True)
                    document = deepcopy(payload)
                    document["authority"]["source"] = source
                    authority_path.write_text(
                        json.dumps(document, ensure_ascii=False), encoding="utf-8"
                    )
                    self.assert_error(
                        "review.stage.semantic_authority.source",
                        lambda repository=repository: review_stage._semantic_authority(
                            repository.resolve()
                        ),
                    )

            repository = root / "symlink"
            authority_path = repository / "Regression/semantic-authority.json"
            decisions_path = (
                repository / "Config/regression/semantic-authority-decisions.tsv"
            )
            actual_source = repository / "approved.tsv"
            authority_path.parent.mkdir(parents=True)
            decisions_path.parent.mkdir(parents=True)
            authority_path.write_bytes(SEMANTIC_AUTHORITY_SOURCE.read_bytes())
            actual_source.write_bytes(SEMANTIC_DECISIONS_SOURCE.read_bytes())
            decisions_path.symlink_to(actual_source)
            self.assert_error(
                "review.stage.semantic_authority.source",
                lambda: review_stage._semantic_authority(repository.resolve()),
            )

    def test_derived_human_coverage_binds_approved_semantic_authority(self) -> None:
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            with (
                mock.patch.object(
                    review_stage, "_implementation_locators", return_value=()
                ),
                mock.patch.object(
                    review_stage,
                    "SEMANTIC_AUTHORITY_PATH",
                    Path("Config/regression/catalog-root/semantic-authority.json"),
                ),
            ):
                reviews = self.complete_non_human_reviews(root)

                first = derive_human_coverage_reviews(
                    REPOSITORY_ROOT,
                    CATALOG_ROOT,
                    POLICY_PATH,
                    reviews,
                    ISSUED_AT,
                )
                second = derive_human_coverage_reviews(
                    REPOSITORY_ROOT,
                    CATALOG_ROOT,
                    POLICY_PATH,
                    reviews,
                    ISSUED_AT,
                )
                status = review_status(
                    REPOSITORY_ROOT, CATALOG_ROOT, POLICY_PATH, reviews
                )

            self.assertEqual(first, second)
            self.assertEqual(
                len(first.issued),
                sum(
                    packet.reviewer is ReviewClass.HUMAN_COVERAGE
                    for packet in self.approved.packets
                ),
            )
            for item in first.issued:
                self.assertEqual(
                    item.receipt.actor.actor_id, DERIVED_HUMAN_ACTOR_ID
                )
                report = load_review_report(
                    reviews, item.receipt.report_digest
                )
                self.assertIn("introduces no runtime human step", report)
                self.assertIn("HC-000", report)
                self.assertIn("HC-023", report)
            self.assertEqual(
                {reviewer: 0 for reviewer in ReviewClass},
                dict(status.pending),
            )

    def test_owned_modules_parse_with_python_39_grammar(self) -> None:
        paths = (
            SCRIPTS_ROOT / "regression/review_stage.py",
            SCRIPTS_ROOT / "regression/reviewctl.py",
            Path(__file__),
        )
        for path in paths:
            with self.subTest(path=path):
                ast.parse(
                    path.read_text(encoding="utf-8"), feature_version=(3, 9)
                )


if __name__ == "__main__":
    unittest.main()
