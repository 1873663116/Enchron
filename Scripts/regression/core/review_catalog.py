from __future__ import annotations

from collections.abc import Mapping as MappingABC
from dataclasses import fields, is_dataclass
from enum import Enum
from types import MappingProxyType
from typing import Any, Dict, FrozenSet, Mapping, Tuple, Type

from .contracts import (
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
from .errors import RegressionError
from .review import (
    BudgetAmount,
    BudgetUnit,
    CompletedReview,
    PlannedReview,
    ReviewBudget,
    ReviewClass,
    ReviewPacket,
    ReviewPolicy,
    ReviewReceipt,
    ReviewUnit,
    ReviewUnitKind,
    ReviewUsage,
    plan_reviews as _plan_reviews,
)


_SHARED_REGISTRY_SCOPE = "shared"
_DERIVED_DIGEST_FIELDS = frozenset(("catalog_digest", "leaf_digest", "source_digest"))

_REVIEWERS_BY_KIND: Mapping[ReviewUnitKind, FrozenSet[ReviewClass]] = (
    MappingProxyType(
        {
            ReviewUnitKind.PROMISE: frozenset(
                (ReviewClass.HUMAN_COVERAGE, ReviewClass.DETERMINISTIC)
            ),
            ReviewUnitKind.FACT: frozenset(
                (ReviewClass.HUMAN_COVERAGE, ReviewClass.DETERMINISTIC)
            ),
            ReviewUnitKind.PREPARATION: frozenset(
                (ReviewClass.AGENT_OPERABILITY, ReviewClass.DETERMINISTIC)
            ),
            ReviewUnitKind.OPERATION: frozenset(
                (ReviewClass.AGENT_OPERABILITY, ReviewClass.DETERMINISTIC)
            ),
            ReviewUnitKind.ORACLE: frozenset(
                (ReviewClass.AGENT_OPERABILITY, ReviewClass.DETERMINISTIC)
            ),
            ReviewUnitKind.RUBRIC: frozenset(
                (
                    ReviewClass.HUMAN_COVERAGE,
                    ReviewClass.AGENT_OPERABILITY,
                    ReviewClass.DETERMINISTIC,
                )
            ),
            ReviewUnitKind.JOURNEY: frozenset(ReviewClass),
            ReviewUnitKind.SCENARIO: frozenset(ReviewClass),
        }
    )
)

_CONTRACT_FIELDS: Tuple[Tuple[ReviewUnitKind, Type[Any], str], ...] = (
    (ReviewUnitKind.PROMISE, PromiseContract, "promises"),
    (ReviewUnitKind.FACT, FactDeclaration, "facts"),
    (ReviewUnitKind.PREPARATION, PreparationContract, "preparations"),
    (ReviewUnitKind.OPERATION, OperationContract, "operations"),
    (ReviewUnitKind.ORACLE, OracleContract, "oracles"),
    (ReviewUnitKind.RUBRIC, RubricContract, "rubrics"),
    (ReviewUnitKind.JOURNEY, JourneyContract, "journeys"),
    (ReviewUnitKind.SCENARIO, ScenarioContract, "scenarios"),
)


def _error(code: str, location: str, detail: str) -> RegressionError:
    return RegressionError(code, location, detail)


def _scope_for(kind: ReviewUnitKind, contract: Any) -> str:
    if kind is ReviewUnitKind.PROMISE:
        feature = str(contract.id).split(":", 2)[1]
        return f"feature:{feature}"
    if kind is ReviewUnitKind.PREPARATION:
        return f"lane:{contract.lane.value}"
    if kind is ReviewUnitKind.JOURNEY:
        return str(contract.id)
    if kind is ReviewUnitKind.SCENARIO:
        return str(contract.journey)
    return _SHARED_REGISTRY_SCOPE


def _estimate_value(value: Any) -> Tuple[int, int]:
    if is_dataclass(value) and not isinstance(value, type):
        readable_bytes = 0
        review_items = 1
        for item in fields(value):
            if item.name in _DERIVED_DIGEST_FIELDS:
                continue
            child_bytes, child_items = _estimate_value(getattr(value, item.name))
            readable_bytes += len(item.name.encode("utf-8")) + child_bytes
            review_items += 1 + child_items
        return readable_bytes, review_items
    if isinstance(value, Enum):
        return len(str(value.value).encode("utf-8")), 1
    if isinstance(value, str):
        return len(value.encode("utf-8")), 1
    if isinstance(value, bytes):
        return len(value), 1
    if isinstance(value, MappingABC):
        readable_bytes = 0
        review_items = 1
        for key, item in value.items():
            key_bytes, key_items = _estimate_value(key)
            item_bytes, item_items = _estimate_value(item)
            readable_bytes += key_bytes + item_bytes
            review_items += key_items + item_items
        return readable_bytes, review_items
    if isinstance(value, (tuple, list, set, frozenset)):
        readable_bytes = 0
        review_items = 1
        for item in value:
            child_bytes, child_items = _estimate_value(item)
            readable_bytes += child_bytes
            review_items += child_items
        return readable_bytes, review_items
    if value is None:
        return len(b"null"), 1
    if type(value) is bool:
        return len(b"true") if value else len(b"false"), 1
    if type(value) is int:
        return len(str(value).encode("ascii")), 1
    raise _error(
        "review.catalog.estimate.unsupported",
        "catalog",
        f"Cannot estimate review usage for {type(value).__name__}.",
    )


def _estimate_usage(contract: Any) -> ReviewUsage:
    readable_bytes, _ = _estimate_value(contract)
    input_tokens = max(1, (readable_bytes + 3) // 4)
    return ReviewUsage(
        (
            BudgetAmount(BudgetUnit.INPUT_TOKENS, input_tokens),
            BudgetAmount(BudgetUnit.REVIEW_ITEMS, 1),
        )
    )


def _require_catalog(catalog: object) -> DraftCatalog:
    if not isinstance(catalog, DraftCatalog):
        raise _error(
            "review.catalog.invalid",
            "catalog",
            "Expected DraftCatalog.",
        )
    for _, contract_type, field_name in _CONTRACT_FIELDS:
        values = getattr(catalog, field_name)
        if not isinstance(values, tuple):
            raise _error(
                "review.catalog.contract.collection.invalid",
                f"catalog.{field_name}",
                "Catalog contract collections must be tuples.",
            )
        for index, contract in enumerate(values):
            if not isinstance(contract, contract_type):
                raise _error(
                    "review.catalog.contract.invalid",
                    f"catalog.{field_name}[{index}]",
                    f"Expected {contract_type.__name__}.",
                )
    rebuilt = DraftCatalog(
        catalog.promises,
        catalog.facts,
        catalog.operations,
        catalog.oracles,
        catalog.rubrics,
        catalog.preparations,
        catalog.journeys,
        catalog.scenarios,
    )
    if rebuilt.catalog_digest != catalog.catalog_digest:
        raise _error(
            "review.catalog.digest.invalid",
            "catalog.catalog_digest",
            "Catalog digest does not match its current contract leaves.",
        )
    return catalog


def build_catalog_review_units(catalog: DraftCatalog) -> Tuple[ReviewUnit, ...]:
    current = _require_catalog(catalog)
    units = []
    for kind, _, field_name in _CONTRACT_FIELDS:
        for contract in getattr(current, field_name):
            units.append(
                ReviewUnit(
                    kind=kind,
                    ref=str(contract.id),
                    content_digest=contract.leaf_digest,
                    scope=_scope_for(kind, contract),
                    required_reviewers=_REVIEWERS_BY_KIND[kind],
                    estimated_usage=_estimate_usage(contract),
                )
            )
    frozen = tuple(sorted(units, key=lambda unit: (unit.kind.value, unit.ref)))
    identities = tuple(unit.identity for unit in frozen)
    if len(identities) != len(set(identities)):
        raise _error(
            "review.catalog.unit.duplicate",
            "catalog",
            "Catalog contains duplicate review unit identities.",
        )
    return frozen


def plan_catalog_reviews(
    catalog: DraftCatalog, policy: ReviewPolicy
) -> PlannedReview:
    return _plan_reviews(build_catalog_review_units(catalog), policy)


def _require_amounts_within(
    actual: ReviewUsage,
    limit: ReviewBudget,
    code: str,
    location: str,
    subject: str,
) -> None:
    for amount in actual.amounts:
        maximum = limit.amount_for(amount.unit)
        if maximum is None or amount.amount > maximum:
            raise _error(
                code,
                location,
                f"{subject} exceeds its approved {amount.unit.value} budget.",
            )


def _required_packet_usage(units: Tuple[ReviewUnit, ...]) -> ReviewUsage:
    totals: Dict[BudgetUnit, int] = {}
    for unit in units:
        for amount in unit.estimated_usage.amounts:
            totals[amount.unit] = totals.get(amount.unit, 0) + amount.amount
    return ReviewUsage(
        tuple(
            BudgetAmount(unit, amount)
            for unit, amount in sorted(
                totals.items(), key=lambda item: item[0].value
            )
        )
    )


def _verify_packet_digest(packet: ReviewPacket, index: int) -> None:
    rebuilt = ReviewPacket(
        reviewer=packet.reviewer,
        scope=packet.scope,
        units=packet.units,
        approved_budget=packet.approved_budget,
        policy_digest=packet.policy_digest,
    )
    if (
        rebuilt.packet_id != packet.packet_id
        or rebuilt.packet_digest != packet.packet_digest
    ):
        raise _error(
            "review.catalog.packet.digest.invalid",
            f"completed_review.packets[{index}]",
            "Packet identity or digest does not match its current fields.",
        )


def _verify_receipt_digest(receipt: ReviewReceipt, index: int) -> None:
    rebuilt = ReviewReceipt(
        packet_digest=receipt.packet_digest,
        reviewer=receipt.reviewer,
        actor=receipt.actor,
        report_digest=receipt.report_digest,
        accepted=receipt.accepted,
        usage=receipt.usage,
        issued_at=receipt.issued_at,
        assessment_digest=receipt.assessment_digest,
    )
    if rebuilt.receipt_digest != receipt.receipt_digest:
        raise _error(
            "review.catalog.receipt.digest.invalid",
            f"completed_review.receipts[{index}]",
            "Receipt digest does not match its current fields.",
        )


def verify_completed_catalog_reviews(
    catalog: DraftCatalog, completed: CompletedReview
) -> None:
    current = _require_catalog(catalog)
    if not isinstance(completed, CompletedReview):
        raise _error(
            "review.catalog.completion.invalid",
            "completed_review",
            "Expected CompletedReview.",
        )
    if completed.catalog_root != current.catalog_digest:
        raise _error(
            "review.catalog.digest.mismatch",
            "completed_review.catalog_root",
            "Completed review does not bind the current Catalog digest.",
        )
    if not isinstance(completed.packets, tuple):
        raise _error(
            "review.catalog.packet.collection.invalid",
            "completed_review.packets",
            "Completed review packets must be a tuple.",
        )
    if not isinstance(completed.receipts, tuple):
        raise _error(
            "review.catalog.receipt.collection.invalid",
            "completed_review.receipts",
            "Completed review receipts must be a tuple.",
        )

    units = build_catalog_review_units(current)
    expected_by_identity = {unit.identity: unit for unit in units}
    expected_coverage = {
        (reviewer, unit.kind.value, unit.ref)
        for unit in units
        for reviewer in unit.required_reviewers
    }
    actual_coverage = set()
    packets_by_digest = {}
    packet_ids = set()
    policy_digests = set()

    for index, packet in enumerate(completed.packets):
        if not isinstance(packet, ReviewPacket):
            raise _error(
                "review.catalog.packet.invalid",
                f"completed_review.packets[{index}]",
                "Expected ReviewPacket.",
            )
        _verify_packet_digest(packet, index)
        if packet.packet_digest in packets_by_digest or packet.packet_id in packet_ids:
            raise _error(
                "review.catalog.packet.duplicate",
                f"completed_review.packets[{index}]",
                "Completed review repeats a packet.",
            )
        packets_by_digest[packet.packet_digest] = packet
        packet_ids.add(packet.packet_id)
        policy_digests.add(packet.policy_digest)

        for unit in packet.units:
            expected = expected_by_identity.get(unit.identity)
            if expected is None:
                raise _error(
                    "review.catalog.coverage.extra",
                    f"completed_review.packets[{index}]",
                    f"Packet contains unknown unit {unit.kind.value}:{unit.ref}.",
                )
            if unit != expected:
                raise _error(
                    "review.catalog.unit.mismatch",
                    f"completed_review.packets[{index}]",
                    f"Unit {unit.kind.value}:{unit.ref} does not match the current "
                    "Catalog leaf, scope, reviewers, or usage.",
                )
            coverage = (packet.reviewer, unit.kind.value, unit.ref)
            if coverage in actual_coverage:
                raise _error(
                    "review.catalog.coverage.duplicate",
                    f"completed_review.packets[{index}]",
                    f"Review coverage repeats {unit.kind.value}:{unit.ref} for "
                    f"{packet.reviewer.value}.",
                )
            actual_coverage.add(coverage)

        _require_amounts_within(
            _required_packet_usage(packet.units),
            packet.approved_budget,
            "review.catalog.packet.budget.insufficient",
            f"completed_review.packets[{index}].approved_budget",
            f"Packet {packet.packet_id}",
        )

    if len(policy_digests) > 1:
        raise _error(
            "review.catalog.packet.policy.mismatch",
            "completed_review.packets",
            "All completed packets must use one review policy.",
        )
    if actual_coverage != expected_coverage:
        missing = expected_coverage - actual_coverage
        if missing:
            reviewer, kind, ref = sorted(
                missing, key=lambda item: (item[0].value, item[1], item[2])
            )[0]
            raise _error(
                "review.catalog.coverage.missing",
                "completed_review.packets",
                f"Missing {reviewer.value} coverage for {kind}:{ref}.",
            )
        reviewer, kind, ref = sorted(
            actual_coverage - expected_coverage,
            key=lambda item: (item[0].value, item[1], item[2]),
        )[0]
        raise _error(
            "review.catalog.coverage.extra",
            "completed_review.packets",
            f"Unexpected {reviewer.value} coverage for {kind}:{ref}.",
        )

    receipts_by_packet = {}
    for index, receipt in enumerate(completed.receipts):
        if not isinstance(receipt, ReviewReceipt):
            raise _error(
                "review.catalog.receipt.invalid",
                f"completed_review.receipts[{index}]",
                "Expected ReviewReceipt.",
            )
        _verify_receipt_digest(receipt, index)
        if receipt.packet_digest in receipts_by_packet:
            raise _error(
                "review.catalog.receipt.duplicate",
                f"completed_review.receipts[{index}]",
                f"Packet {receipt.packet_digest} has more than one receipt.",
            )
        packet = packets_by_digest.get(receipt.packet_digest)
        if packet is None:
            raise _error(
                "review.catalog.receipt.extra",
                f"completed_review.receipts[{index}]",
                f"Receipt refers to unknown packet {receipt.packet_digest}.",
            )
        if receipt.reviewer is not packet.reviewer:
            raise _error(
                "review.catalog.receipt.reviewer.mismatch",
                f"completed_review.receipts[{index}]",
                f"Receipt reviewer does not match packet {packet.packet_id}.",
            )
        if not receipt.accepted:
            raise _error(
                "review.catalog.receipt.rejected",
                f"completed_review.receipts[{index}]",
                f"Receipt rejected packet {packet.packet_id}.",
            )
        _require_amounts_within(
            receipt.usage,
            packet.approved_budget,
            "review.catalog.receipt.budget.exceeded",
            f"completed_review.receipts[{index}].usage",
            f"Receipt for packet {packet.packet_id}",
        )
        receipts_by_packet[receipt.packet_digest] = receipt

    packet_digests = set(packets_by_digest)
    receipt_packet_digests = set(receipts_by_packet)
    missing_receipts = packet_digests - receipt_packet_digests
    if missing_receipts:
        raise _error(
            "review.catalog.receipt.missing",
            "completed_review.receipts",
            f"Missing receipt for packet {sorted(map(str, missing_receipts))[0]}.",
        )
    extra_receipts = receipt_packet_digests - packet_digests
    if extra_receipts:
        raise _error(
            "review.catalog.receipt.extra",
            "completed_review.receipts",
            f"Unexpected receipt for packet {sorted(map(str, extra_receipts))[0]}.",
        )

    rebuilt = CompletedReview(
        current.catalog_digest,
        completed.packets,
        completed.receipts,
    )
    if rebuilt.completion_digest != completed.completion_digest:
        raise _error(
            "review.catalog.completion.digest.invalid",
            "completed_review.completion_digest",
            "Completed review digest does not match the current packets and receipts.",
        )


__all__ = (
    "build_catalog_review_units",
    "plan_catalog_reviews",
    "verify_completed_catalog_reviews",
)
