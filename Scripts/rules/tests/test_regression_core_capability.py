#!/usr/bin/env python3

from __future__ import annotations

import ast
from dataclasses import replace
from pathlib import Path
import sys
import unittest

SCRIPTS = Path(__file__).resolve().parents[2]
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

from regression.core.capability import AllowedOperationCall, AssignmentCapability, InvocationCounts, OperationRequest, authorize_operation
from regression.core.contracts import BoundLane
from regression.core.digest import digest_bytes
from regression.core.errors import RegressionError
from regression.core.ids import CallID, Digest, LeaseID, NodeID, OperationID, RunID, StateTag


def digest(character: str) -> Digest:
    return Digest("sha256:" + character * 64)


ARGUMENT_TEMPLATE = b'{"input":"fixed"}'
RESOLVED_ARGUMENTS = b'{"input":"resolved"}'


class CapabilityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.allowed = AllowedOperationCall(
            call_id=CallID("call:scenario-j01-open:step-01"),
            operation=OperationID("operation:playback.open@1"),
            contract_digest=digest("a"),
            arguments_bytes=ARGUMENT_TEMPLATE,
            arguments_digest=digest_bytes(ARGUMENT_TEMPLATE),
            implementation_locator="adapter://playback/open",
            implementation_digest=digest("b"),
            max_invocations=2,
            invalidates_tags=(
                StateTag("playback.session"),
                StateTag("renderer.graph"),
            ),
        )
        self.capability = AssignmentCapability(
            RunID("run:test"),
            digest("c"),
            NodeID("node:test"),
            LeaseID("lease:test"),
            BoundLane.SIMULATOR,
            (self.allowed,),
            100,
        )
        self.request = OperationRequest(
            self.allowed.call_id,
            self.allowed.operation,
            self.allowed.contract_digest,
            self.allowed.arguments_digest,
            self.allowed.implementation_locator,
            self.allowed.implementation_digest,
        )

    def test_exact_call_is_authorized_and_counted(self) -> None:
        first = authorize_operation(
            self.capability,
            self.request,
            InvocationCounts(),
            50,
            RESOLVED_ARGUMENTS,
        )
        second = authorize_operation(
            self.capability,
            self.request,
            first.counts,
            60,
            RESOLVED_ARGUMENTS,
        )
        self.assertEqual(1, first.grant.invocation_index)
        self.assertEqual(2, second.grant.invocation_index)
        self.assertNotEqual(first.grant.id, second.grant.id)
        self.assertEqual(2, second.counts.count(self.allowed.call_id))
        self.assertEqual(self.allowed.invalidates_tags, first.grant.invalidates_tags)
        self.assertEqual(
            self.allowed.arguments_digest,
            first.grant.arguments_template_digest,
        )
        self.assertEqual(RESOLVED_ARGUMENTS, first.grant.arguments_bytes)
        self.assertEqual(
            digest_bytes(RESOLVED_ARGUMENTS), first.grant.arguments_digest
        )
        self.assertEqual(
            self.allowed.implementation_locator,
            first.grant.implementation_locator,
        )
        self.assertEqual(
            self.allowed.implementation_digest,
            first.grant.implementation_digest,
        )

    def test_unknown_call_is_rejected_before_execution(self) -> None:
        request = replace(self.request, call_id=CallID("call:other"))
        with self.assertRaises(RegressionError) as found:
            authorize_operation(
                self.capability,
                request,
                InvocationCounts(),
                50,
                RESOLVED_ARGUMENTS,
            )
        self.assertEqual("capability.call_not_allowed", found.exception.code)

    def test_operation_contract_and_argument_drift_are_rejected(self) -> None:
        for field, value in (
            ("operation", OperationID("operation:playback.seek@1")),
            ("contract_digest", digest("d")),
            ("arguments_digest", digest("e")),
            ("implementation_locator", "adapter://playback/seek"),
            ("implementation_digest", digest("f")),
        ):
            with self.subTest(field=field), self.assertRaises(RegressionError) as found:
                authorize_operation(
                    self.capability,
                    replace(self.request, **{field: value}),
                    InvocationCounts(),
                    50,
                    RESOLVED_ARGUMENTS,
                )
            self.assertEqual("capability.call_mismatch", found.exception.code)

    def test_expired_and_exhausted_leases_are_rejected(self) -> None:
        with self.assertRaises(RegressionError) as expired:
            authorize_operation(
                self.capability,
                self.request,
                InvocationCounts(),
                101,
                RESOLVED_ARGUMENTS,
            )
        self.assertEqual("capability.expired_lease", expired.exception.code)
        counts = InvocationCounts()
        counts = authorize_operation(
            self.capability, self.request, counts, 1, RESOLVED_ARGUMENTS
        ).counts
        counts = authorize_operation(
            self.capability, self.request, counts, 2, RESOLVED_ARGUMENTS
        ).counts
        with self.assertRaises(RegressionError) as exhausted:
            authorize_operation(
                self.capability,
                self.request,
                counts,
                3,
                RESOLVED_ARGUMENTS,
            )
        self.assertEqual("capability.invocation_limit", exhausted.exception.code)

    def test_empty_duplicate_and_invalid_limits_are_rejected(self) -> None:
        with self.assertRaises(RegressionError) as empty:
            replace(self.capability, calls=())
        self.assertEqual("capability.empty_allowlist", empty.exception.code)
        with self.assertRaises(RegressionError) as duplicate:
            replace(self.capability, calls=(self.allowed, self.allowed))
        self.assertEqual("capability.duplicate_call", duplicate.exception.code)
        with self.assertRaises(RegressionError) as limit:
            replace(self.allowed, max_invocations=0)
        self.assertEqual("capability.invalid_invocation_limit", limit.exception.code)

    def test_capability_rejects_malformed_nominal_values(self) -> None:
        replacements = (
            ("run_id", RunID("test")),
            ("plan_digest", Digest("bad")),
            ("node_id", NodeID("node")),
            ("lease_id", LeaseID("lease")),
            ("lane", "simulator"),
        )
        for field, value in replacements:
            with self.subTest(field=field), self.assertRaises(RegressionError):
                replace(self.capability, **{field: value})

    def test_allowlist_and_request_validate_every_bound_identifier(self) -> None:
        for field, value in (
            ("call_id", CallID("call:Bad")),
            ("operation", OperationID("operation:playback.open")),
            ("contract_digest", Digest("bad")),
            ("arguments_digest", Digest("bad")),
            ("implementation_locator", ""),
            ("implementation_digest", Digest("bad")),
        ):
            with self.subTest(field=field), self.assertRaises(RegressionError):
                replace(self.allowed, **{field: value})
            with self.subTest(request_field=field), self.assertRaises(RegressionError):
                replace(self.request, **{field: value})

    def test_argument_bytes_and_digest_must_be_exact_canonical_json(self) -> None:
        noncanonical_bytes = b'{"input": "fixed"}'
        with self.assertRaises(RegressionError) as noncanonical:
            replace(
                self.allowed,
                arguments_bytes=noncanonical_bytes,
                arguments_digest=digest_bytes(noncanonical_bytes),
            )
        self.assertEqual(
            "capability.noncanonical_arguments", noncanonical.exception.code
        )

        with self.assertRaises(RegressionError) as mismatch:
            replace(self.allowed, arguments_digest=digest("f"))
        self.assertEqual(
            "capability.arguments_digest_mismatch", mismatch.exception.code
        )

        with self.assertRaises(RegressionError) as not_object:
            replace(
                self.allowed,
                arguments_bytes=b"[]",
                arguments_digest=digest_bytes(b"[]"),
            )
        self.assertEqual(
            "capability.arguments_not_object", not_object.exception.code
        )

    def test_grant_id_binds_resolved_arguments_and_implementation(self) -> None:
        granted = authorize_operation(
            self.capability,
            self.request,
            InvocationCounts(),
            50,
            RESOLVED_ARGUMENTS,
        ).grant
        changed = b'{"input":"different"}'
        with self.assertRaises(RegressionError) as arguments:
            replace(
                granted,
                arguments_bytes=changed,
                arguments_digest=digest_bytes(changed),
            )
        self.assertEqual(
            "capability.grant_id_mismatch", arguments.exception.code
        )

        with self.assertRaises(RegressionError) as implementation:
            replace(granted, implementation_locator="adapter://playback/other")
        self.assertEqual(
            "capability.grant_id_mismatch", implementation.exception.code
        )

    def test_invocation_counts_validate_call_ids(self) -> None:
        with self.assertRaises(RegressionError):
            InvocationCounts().increment(CallID("not-a-call"))

    def test_invalidation_tags_are_nominal_sorted_and_unique(self) -> None:
        self.assertEqual(
            (StateTag("playback.session"), StateTag("renderer.graph")),
            self.allowed.invalidates_tags,
        )
        with self.assertRaises(RegressionError) as duplicate:
            replace(
                self.allowed,
                invalidates_tags=(
                    StateTag("playback.session"),
                    StateTag("playback.session"),
                ),
            )
        self.assertEqual("capability.duplicate_state_tag", duplicate.exception.code)
        with self.assertRaises(RegressionError):
            replace(self.allowed, invalidates_tags=(StateTag("Invalid"),))

    def test_capability_module_parses_as_python_39(self) -> None:
        path = SCRIPTS / "regression/core/capability.py"
        ast.parse(path.read_text(encoding="utf-8"), feature_version=(3, 9))


if __name__ == "__main__":
    unittest.main()
