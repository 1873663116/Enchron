from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Dict, FrozenSet, Iterable, Optional, Sequence, Tuple, Type, TypeVar

from .digest import canonical_digest
from .errors import RegressionError
from .ids import Digest, ReviewPacketID, parse_identifier


class ReviewClass(str, Enum):
    HUMAN_COVERAGE = "human-coverage"
    AGENT_OPERABILITY = "agent-operability"
    DETERMINISTIC = "deterministic"


class ReviewUnitKind(str, Enum):
    PROMISE = "promise"
    FACT = "fact"
    PREPARATION = "preparation"
    OPERATION = "operation"
    ORACLE = "oracle"
    RUBRIC = "rubric"
    JOURNEY = "journey"
    SCENARIO = "scenario"


class BudgetUnit(str, Enum):
    INPUT_TOKENS = "inputTokens"
    OUTPUT_TOKENS = "outputTokens"
    WALL_SECONDS = "wallSeconds"
    COST_MICROS = "costMicros"
    REVIEW_ITEMS = "reviewItems"


def _error(code: str, location: str, detail: str) -> RegressionError:
    return RegressionError(code, location, detail)


def _require_non_empty(value: object, location: str, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise _error("review.empty.value", location, f"{label} must not be empty.")
    return value


@dataclass(frozen=True)
class ReviewActorIdentity:
    actor_id: str
    environment_digest: Digest

    def __post_init__(self) -> None:
        _require_non_empty(
            self.actor_id,
            "review_actor_identity.actor_id",
            "Review actor identifier",
        )
        parse_identifier(
            "digest",
            self.environment_digest,
            "review_actor_identity.environment_digest",
        )


@dataclass(frozen=True)
class BudgetAmount:
    unit: BudgetUnit
    amount: int

    def __post_init__(self) -> None:
        if not isinstance(self.unit, BudgetUnit):
            raise _error(
                "review.invalid.budget.unit",
                "budget.unit",
                f"Unknown budget unit {self.unit!r}.",
            )
        if isinstance(self.amount, bool) or not isinstance(self.amount, int):
            raise _error(
                "review.invalid.budget.amount",
                f"budget.{self.unit.value}",
                "Budget amounts must be integers.",
            )
        if self.amount < 0:
            raise _error(
                "review.negative.budget.amount",
                f"budget.{self.unit.value}",
                "Budget amounts must not be negative.",
            )


_Amounts = TypeVar("_Amounts", bound="_AmountCollection")


@dataclass(frozen=True)
class _AmountCollection:
    amounts: Tuple[BudgetAmount, ...]

    def __post_init__(self) -> None:
        amounts = tuple(self.amounts)
        if not amounts:
            raise _error(
                "review.empty.budget.units",
                "budget",
                "A budget or usage value must declare at least one unit.",
            )
        seen = set()
        for index, amount in enumerate(amounts):
            if not isinstance(amount, BudgetAmount):
                raise _error(
                    "review.invalid.budget.amount",
                    f"budget[{index}]",
                    "Expected a BudgetAmount.",
                )
            if amount.unit in seen:
                raise _error(
                    "review.duplicate.budget.unit",
                    f"budget.{amount.unit.value}",
                    f"Budget unit {amount.unit.value!r} is declared more than once.",
                )
            seen.add(amount.unit)
        object.__setattr__(
            self,
            "amounts",
            tuple(sorted(amounts, key=lambda item: item.unit.value)),
        )

    def amount_for(self, unit: BudgetUnit) -> Optional[int]:
        for amount in self.amounts:
            if amount.unit is unit:
                return amount.amount
        return None

    def as_dict(self) -> Dict[str, int]:
        return {amount.unit.value: amount.amount for amount in self.amounts}

    @classmethod
    def _from_totals(
        cls: Type[_Amounts], totals: Dict[BudgetUnit, int]
    ) -> _Amounts:
        return cls(
            tuple(
                BudgetAmount(unit, amount)
                for unit, amount in sorted(
                    totals.items(), key=lambda item: item[0].value
                )
            )
        )


@dataclass(frozen=True)
class ReviewBudget(_AmountCollection):
    pass


@dataclass(frozen=True)
class ReviewUsage(_AmountCollection):
    pass


def _sum_amounts(
    values: Iterable[_AmountCollection], result_type: Type[_Amounts]
) -> _Amounts:
    totals: Dict[BudgetUnit, int] = {}
    found = False
    for value in values:
        found = True
        for amount in value.amounts:
            totals[amount.unit] = totals.get(amount.unit, 0) + amount.amount
    if not found or not totals:
        raise _error(
            "review.empty.budget.units",
            "budget",
            "Cannot sum an empty collection of budget values.",
        )
    return result_type._from_totals(totals)


def _within(actual: _AmountCollection, limit: ReviewBudget) -> bool:
    for amount in actual.amounts:
        maximum = limit.amount_for(amount.unit)
        if maximum is None or amount.amount > maximum:
            return False
    return True


def _require_within(
    actual: _AmountCollection,
    limit: ReviewBudget,
    code: str,
    location: str,
    subject: str,
) -> None:
    for amount in actual.amounts:
        maximum = limit.amount_for(amount.unit)
        if maximum is None:
            raise _error(
                code,
                location,
                f"{subject} uses undeclared budget unit {amount.unit.value!r}.",
            )
        if amount.amount > maximum:
            raise _error(
                code,
                location,
                f"{subject} needs {amount.amount} {amount.unit.value}, "
                f"but the limit is {maximum}.",
            )


@dataclass(frozen=True)
class ReviewUnit:
    kind: ReviewUnitKind
    ref: str
    content_digest: Digest
    scope: str
    required_reviewers: FrozenSet[ReviewClass]
    estimated_usage: ReviewUsage

    def __post_init__(self) -> None:
        if not isinstance(self.kind, ReviewUnitKind):
            raise _error(
                "review.invalid.unit.kind",
                "review_unit.kind",
                f"Unknown review unit kind {self.kind!r}.",
            )
        _require_non_empty(self.ref, "review_unit.ref", "Review unit reference")
        _require_non_empty(self.scope, "review_unit.scope", "Review unit scope")
        parse_identifier("digest", self.content_digest, "review_unit.content_digest")
        reviewers = frozenset(self.required_reviewers)
        if not reviewers:
            raise _error(
                "review.empty.reviewers",
                f"review_unit[{self.kind.value}:{self.ref}]",
                "A review unit must require at least one review class.",
            )
        for reviewer in reviewers:
            if not isinstance(reviewer, ReviewClass):
                raise _error(
                    "review.invalid.reviewer",
                    f"review_unit[{self.kind.value}:{self.ref}]",
                    f"Unknown review class {reviewer!r}.",
                )
        if not isinstance(self.estimated_usage, ReviewUsage):
            raise _error(
                "review.invalid.usage",
                f"review_unit[{self.kind.value}:{self.ref}].estimated_usage",
                "Expected ReviewUsage.",
            )
        object.__setattr__(self, "required_reviewers", reviewers)

    @property
    def identity(self) -> Tuple[str, str]:
        return (self.kind.value, self.ref)


@dataclass(frozen=True)
class ReviewPolicy:
    per_packet_limit: ReviewBudget
    total_budget: ReviewBudget
    policy_digest: Digest = field(init=False)

    def __post_init__(self) -> None:
        if not isinstance(self.per_packet_limit, ReviewBudget):
            raise _error(
                "review.invalid.policy",
                "review_policy.per_packet_limit",
                "Expected ReviewBudget.",
            )
        if not isinstance(self.total_budget, ReviewBudget):
            raise _error(
                "review.invalid.policy",
                "review_policy.total_budget",
                "Expected ReviewBudget.",
            )
        _require_within(
            self.per_packet_limit,
            self.total_budget,
            "review.policy.limit.exceeds.total",
            "review_policy",
            "Per-packet limit",
        )
        object.__setattr__(
            self,
            "policy_digest",
            canonical_digest(
                {
                    "perPacketLimit": self.per_packet_limit.as_dict(),
                    "totalBudget": self.total_budget.as_dict(),
                }
            ),
        )

    @property
    def digest(self) -> Digest:
        return self.policy_digest


def _unit_payload(unit: ReviewUnit) -> Dict[str, str]:
    return {
        "kind": unit.kind.value,
        "ref": unit.ref,
        "contentDigest": str(unit.content_digest),
    }


@dataclass(frozen=True)
class ReviewPacket:
    reviewer: ReviewClass
    scope: str
    units: Tuple[ReviewUnit, ...]
    approved_budget: ReviewBudget
    policy_digest: Digest
    packet_id: ReviewPacketID = field(init=False)
    packet_digest: Digest = field(init=False)

    def __post_init__(self) -> None:
        if not isinstance(self.reviewer, ReviewClass):
            raise _error(
                "review.invalid.reviewer",
                "review_packet.reviewer",
                f"Unknown review class {self.reviewer!r}.",
            )
        _require_non_empty(self.scope, "review_packet.scope", "Review packet scope")
        parse_identifier("digest", self.policy_digest, "review_packet.policy_digest")
        units = tuple(self.units)
        if not units:
            raise _error(
                "review.empty.packet",
                "review_packet.units",
                "A review packet must contain at least one review unit.",
            )
        units = tuple(sorted(units, key=lambda unit: (unit.kind.value, unit.ref)))
        identities = set()
        for unit in units:
            if not isinstance(unit, ReviewUnit):
                raise _error(
                    "review.invalid.unit",
                    "review_packet.units",
                    "Expected ReviewUnit.",
                )
            if unit.identity in identities:
                raise _error(
                    "review.duplicate.unit",
                    "review_packet.units",
                    f"Duplicate review unit {unit.kind.value}:{unit.ref}.",
                )
            identities.add(unit.identity)
            if unit.scope != self.scope or self.reviewer not in unit.required_reviewers:
                raise _error(
                    "review.packet.unit.mismatch",
                    f"review_packet[{self.reviewer.value}:{self.scope}]",
                    f"Unit {unit.kind.value}:{unit.ref} does not belong in "
                    "this packet.",
                )
        if not isinstance(self.approved_budget, ReviewBudget):
            raise _error(
                "review.invalid.budget",
                "review_packet.approved_budget",
                "Expected ReviewBudget.",
            )
        packet_digest = canonical_digest(
            {
                "reviewer": self.reviewer.value,
                "scope": self.scope,
                "leaves": [_unit_payload(unit) for unit in units],
                "approvedBudget": self.approved_budget.as_dict(),
                "policyDigest": str(self.policy_digest),
            }
        )
        packet_id = parse_identifier(
            "review_packet",
            f"review-packet:{self.reviewer.value}-{str(packet_digest)[7:23]}",
            "review_packet.packet_id",
        )
        object.__setattr__(self, "units", units)
        object.__setattr__(self, "packet_digest", packet_digest)
        object.__setattr__(self, "packet_id", packet_id)

    @property
    def digest(self) -> Digest:
        return self.packet_digest

    @property
    def budget(self) -> ReviewBudget:
        return self.approved_budget


@dataclass(frozen=True)
class PlannedReview:
    units: Tuple[ReviewUnit, ...]
    policy: ReviewPolicy
    packets: Tuple[ReviewPacket, ...]
    plan_digest: Digest = field(init=False)

    def __post_init__(self) -> None:
        units = tuple(self.units)
        packets = tuple(self.packets)
        object.__setattr__(self, "units", units)
        object.__setattr__(self, "packets", packets)
        object.__setattr__(
            self,
            "plan_digest",
            canonical_digest(
                {
                    "policyDigest": str(self.policy.policy_digest),
                    "packetDigests": [
                        str(packet.packet_digest)
                        for packet in sorted(packets, key=_packet_sort_key)
                    ],
                }
            ),
        )

    @property
    def digest(self) -> Digest:
        return self.plan_digest


@dataclass(frozen=True)
class BudgetApproval:
    packet_id: ReviewPacketID
    approved_budget: ReviewBudget

    def __post_init__(self) -> None:
        parse_identifier("review_packet", self.packet_id, "budget_approval.packet_id")
        if not isinstance(self.approved_budget, ReviewBudget):
            raise _error(
                "review.invalid.budget",
                "budget_approval.approved_budget",
                "Expected ReviewBudget.",
            )


@dataclass(frozen=True)
class BudgetApprovedReview:
    planned_review_digest: Digest
    policy: ReviewPolicy
    packets: Tuple[ReviewPacket, ...]
    approval_digest: Digest = field(init=False)

    def __post_init__(self) -> None:
        parse_identifier(
            "digest",
            self.planned_review_digest,
            "approved_review.planned_review_digest",
        )
        packets = tuple(self.packets)
        if not packets:
            raise _error(
                "review.empty.packet.partition",
                "approved_review.packets",
                "An approved review must contain at least one packet.",
            )
        object.__setattr__(self, "packets", packets)
        object.__setattr__(
            self,
            "approval_digest",
            canonical_digest(
                {
                    "plannedReviewDigest": str(self.planned_review_digest),
                    "packetDigests": [
                        str(packet.packet_digest)
                        for packet in sorted(packets, key=_packet_sort_key)
                    ],
                }
            ),
        )

    @property
    def digest(self) -> Digest:
        return self.approval_digest


@dataclass(frozen=True)
class ReviewReceipt:
    packet_digest: Digest
    reviewer: ReviewClass
    actor: ReviewActorIdentity
    report_digest: Digest
    accepted: bool
    usage: ReviewUsage
    issued_at: str
    assessment_digest: Optional[Digest] = None
    receipt_digest: Digest = field(init=False)

    def __post_init__(self) -> None:
        parse_identifier("digest", self.packet_digest, "review_receipt.packet_digest")
        if not isinstance(self.reviewer, ReviewClass):
            raise _error(
                "review.invalid.reviewer",
                "review_receipt.reviewer",
                f"Unknown review class {self.reviewer!r}.",
            )
        if not isinstance(self.actor, ReviewActorIdentity):
            raise _error(
                "review.invalid.actor",
                "review_receipt.actor",
                "Expected ReviewActorIdentity.",
            )
        parse_identifier(
            "digest",
            self.report_digest,
            "review_receipt.report_digest",
        )
        if not isinstance(self.accepted, bool):
            raise _error(
                "review.invalid.receipt.decision",
                "review_receipt.accepted",
                "Receipt acceptance must be a boolean.",
            )
        if not isinstance(self.usage, ReviewUsage):
            raise _error(
                "review.invalid.usage",
                "review_receipt.usage",
                "Expected ReviewUsage.",
            )
        _require_non_empty(
            self.issued_at,
            "review_receipt.issued_at",
            "Receipt issue time",
        )
        # AgentOperability is the only class whose verdict comes from outside
        # and cannot be recomputed at status time, so its receipt has to name
        # the assessment bytes it was issued from.
        if self.reviewer is ReviewClass.AGENT_OPERABILITY:
            if self.assessment_digest is None:
                raise _error(
                    "review.invalid.receipt.assessment",
                    "review_receipt.assessment_digest",
                    "An AgentOperability receipt must name its assessment.",
                )
            parse_identifier(
                "digest",
                self.assessment_digest,
                "review_receipt.assessment_digest",
            )
        elif self.assessment_digest is not None:
            raise _error(
                "review.invalid.receipt.assessment",
                "review_receipt.assessment_digest",
                "Only an AgentOperability receipt names an assessment.",
            )
        object.__setattr__(
            self,
            "receipt_digest",
            canonical_digest(
                {
                    "packetDigest": str(self.packet_digest),
                    "reviewer": self.reviewer.value,
                    "actor": {
                        "actorId": self.actor.actor_id,
                        "environmentDigest": str(
                            self.actor.environment_digest
                        ),
                    },
                    "reportDigest": str(self.report_digest),
                    "accepted": self.accepted,
                    "usage": self.usage.as_dict(),
                    "issuedAt": self.issued_at,
                    "assessmentDigest": (
                        None
                        if self.assessment_digest is None
                        else str(self.assessment_digest)
                    ),
                }
            ),
        )

    @property
    def digest(self) -> Digest:
        return self.receipt_digest


@dataclass(frozen=True)
class CompletedReview:
    catalog_root: Digest
    packets: Tuple[ReviewPacket, ...]
    receipts: Tuple[ReviewReceipt, ...]
    completion_digest: Digest = field(init=False)

    def __post_init__(self) -> None:
        parse_identifier("digest", self.catalog_root, "completed_review.catalog_root")
        packets = tuple(self.packets)
        receipts = tuple(self.receipts)
        for index, packet in enumerate(packets):
            if not isinstance(packet, ReviewPacket):
                raise _error(
                    "review.invalid.packet",
                    f"completed_review.packets[{index}]",
                    "Expected ReviewPacket.",
                )
        for index, receipt in enumerate(receipts):
            if not isinstance(receipt, ReviewReceipt):
                raise _error(
                    "review.invalid.receipt",
                    f"completed_review.receipts[{index}]",
                    "Expected ReviewReceipt.",
                )
        object.__setattr__(self, "packets", packets)
        object.__setattr__(self, "receipts", receipts)
        object.__setattr__(
            self,
            "completion_digest",
            canonical_digest(
                {
                    "catalogDigest": str(self.catalog_root),
                    "packetPartition": [
                        str(packet.packet_digest)
                        for packet in sorted(packets, key=_packet_sort_key)
                    ],
                    "receiptDigests": sorted(
                        str(receipt.receipt_digest) for receipt in receipts
                    ),
                }
            ),
        )

    @property
    def digest(self) -> Digest:
        return self.completion_digest

    @property
    def catalog_digest(self) -> Digest:
        return self.catalog_root


def _packet_sort_key(packet: ReviewPacket) -> Tuple[str, str, str]:
    first = packet.units[0]
    return (packet.reviewer.value, packet.scope, f"{first.kind.value}:{first.ref}")


def _validate_units(units: Iterable[ReviewUnit]) -> Tuple[ReviewUnit, ...]:
    frozen = tuple(units)
    if not frozen:
        raise _error(
            "review.empty.units",
            "review_units",
            "At least one review unit is required.",
        )
    identities = set()
    for index, unit in enumerate(frozen):
        if not isinstance(unit, ReviewUnit):
            raise _error(
                "review.invalid.unit",
                f"review_units[{index}]",
                "Expected ReviewUnit.",
            )
        if unit.identity in identities:
            raise _error(
                "review.duplicate.unit",
                f"review_units[{index}]",
                f"Duplicate review unit {unit.kind.value}:{unit.ref}.",
            )
        identities.add(unit.identity)
    return tuple(sorted(frozen, key=lambda unit: (unit.kind.value, unit.ref)))


def _packet_usage(units: Sequence[ReviewUnit]) -> ReviewUsage:
    return _sum_amounts(
        (unit.estimated_usage for unit in units), ReviewUsage
    )


def _budget_from_usage(usage: ReviewUsage) -> ReviewBudget:
    return ReviewBudget(tuple(usage.amounts))


def plan_reviews(
    units: Iterable[ReviewUnit], policy: ReviewPolicy
) -> PlannedReview:
    if not isinstance(policy, ReviewPolicy):
        raise _error(
            "review.invalid.policy", "review_policy", "Expected ReviewPolicy."
        )
    frozen_units = _validate_units(units)
    grouped: Dict[Tuple[ReviewClass, str], list] = {}
    for unit in frozen_units:
        _require_within(
            unit.estimated_usage,
            policy.per_packet_limit,
            "review.unit.exceeds.packet.limit",
            f"review_unit[{unit.kind.value}:{unit.ref}]",
            f"Unit {unit.kind.value}:{unit.ref}",
        )
        for reviewer in sorted(unit.required_reviewers, key=lambda item: item.value):
            grouped.setdefault((reviewer, unit.scope), []).append(unit)

    packets = []
    for reviewer, scope in sorted(grouped, key=lambda item: (item[0].value, item[1])):
        current = []
        for unit in grouped[(reviewer, scope)]:
            candidate = current + [unit]
            if current and not _within(
                _packet_usage(candidate), policy.per_packet_limit
            ):
                usage = _packet_usage(current)
                packets.append(
                    ReviewPacket(
                        reviewer,
                        scope,
                        tuple(current),
                        _budget_from_usage(usage),
                        policy.policy_digest,
                    )
                )
                current = [unit]
            else:
                current = candidate
        if current:
            usage = _packet_usage(current)
            packets.append(
                ReviewPacket(
                    reviewer,
                    scope,
                    tuple(current),
                    _budget_from_usage(usage),
                    policy.policy_digest,
                )
            )

    total_usage = _sum_amounts(
        (_packet_usage(packet.units) for packet in packets), ReviewUsage
    )
    _require_within(
        total_usage,
        policy.total_budget,
        "review.total.budget.insufficient",
        "review_policy.total_budget",
        "Required review work",
    )
    return PlannedReview(frozen_units, policy, tuple(packets))


def approve_review_budgets(
    planned: PlannedReview,
    approvals: Optional[Iterable[BudgetApproval]] = None,
) -> BudgetApprovedReview:
    if not isinstance(planned, PlannedReview):
        raise _error(
            "review.invalid.plan", "planned_review", "Expected PlannedReview."
        )
    if approvals is None:
        frozen_approvals = tuple(
            BudgetApproval(packet.packet_id, packet.approved_budget)
            for packet in planned.packets
        )
    else:
        frozen_approvals = tuple(approvals)

    by_id: Dict[ReviewPacketID, BudgetApproval] = {}
    planned_ids = {packet.packet_id for packet in planned.packets}
    for index, approval in enumerate(frozen_approvals):
        if not isinstance(approval, BudgetApproval):
            raise _error(
                "review.invalid.approval",
                f"budget_approvals[{index}]",
                "Expected BudgetApproval.",
            )
        if approval.packet_id in by_id:
            raise _error(
                "review.duplicate.approval",
                f"budget_approvals[{index}]",
                f"Packet {approval.packet_id} was approved more than once.",
            )
        if approval.packet_id not in planned_ids:
            raise _error(
                "review.unknown.approval",
                f"budget_approvals[{index}]",
                f"Approval refers to unknown packet {approval.packet_id}.",
            )
        by_id[approval.packet_id] = approval
    missing = planned_ids - set(by_id)
    if missing:
        raise _error(
            "review.missing.approval",
            "budget_approvals",
            "Missing approval for packet "
            f"{sorted(str(value) for value in missing)[0]}.",
        )

    approved_packets = []
    for packet in planned.packets:
        approved_budget = by_id[packet.packet_id].approved_budget
        needed = _packet_usage(packet.units)
        _require_within(
            needed,
            approved_budget,
            "review.approved.budget.insufficient",
            f"budget_approval[{packet.packet_id}]",
            f"Packet {packet.packet_id}",
        )
        _require_within(
            approved_budget,
            planned.policy.per_packet_limit,
            "review.approval.exceeds.packet.limit",
            f"budget_approval[{packet.packet_id}]",
            f"Approved budget for packet {packet.packet_id}",
        )
        approved_packets.append(
            ReviewPacket(
                packet.reviewer,
                packet.scope,
                packet.units,
                approved_budget,
                planned.policy.policy_digest,
            )
        )
    approved_total = _sum_amounts(
        (packet.approved_budget for packet in approved_packets), ReviewBudget
    )
    _require_within(
        approved_total,
        planned.policy.total_budget,
        "review.approval.exceeds.total.budget",
        "budget_approvals",
        "Approved review work",
    )
    return BudgetApprovedReview(
        planned.plan_digest, planned.policy, tuple(approved_packets)
    )


def _coverage_key(
    reviewer: ReviewClass, unit: ReviewUnit
) -> Tuple[str, str, str, str, str]:
    return (
        reviewer.value,
        unit.scope,
        unit.kind.value,
        unit.ref,
        str(unit.content_digest),
    )


def _partition_key(packet: ReviewPacket) -> Tuple[
    str, str, Tuple[Tuple[str, str, str], ...]
]:
    return (
        packet.reviewer.value,
        packet.scope,
        tuple(
            (unit.kind.value, unit.ref, str(unit.content_digest))
            for unit in packet.units
        ),
    )


def complete_reviews(
    current_units: Iterable[ReviewUnit],
    approved: BudgetApprovedReview,
    receipts: Iterable[ReviewReceipt],
    catalog_root: Digest,
) -> CompletedReview:
    units = _validate_units(current_units)
    if not isinstance(approved, BudgetApprovedReview):
        raise _error(
            "review.not.budget.approved",
            "approved_review",
            "Reviews can complete only from BudgetApprovedReview.",
        )
    parse_identifier("digest", catalog_root, "catalog_root")
    frozen_receipts = tuple(receipts)

    current_plan = plan_reviews(units, approved.policy)
    if approved.planned_review_digest != current_plan.plan_digest:
        raise _error(
            "review.stale.plan",
            "approved_review.planned_review_digest",
            "The approved review was not planned from the current review "
            "units and policy.",
        )
    expected_partition = {_partition_key(packet) for packet in current_plan.packets}
    actual_partition = {_partition_key(packet) for packet in approved.packets}
    if len(actual_partition) != len(approved.packets):
        raise _error(
            "review.duplicate.packet.partition",
            "approved_review.packets",
            "The approved review repeats a packet partition member.",
        )
    if actual_partition != expected_partition:
        raise _error(
            "review.packet.partition.mismatch",
            "approved_review.packets",
            "The approved packets do not match the current complete packet partition.",
        )

    reviewers_present = {packet.reviewer for packet in approved.packets}
    missing_review_classes = set(ReviewClass) - reviewers_present
    if missing_review_classes:
        missing = sorted(item.value for item in missing_review_classes)[0]
        raise _error(
            "review.class.incomplete",
            "approved_review.packets",
            f"The packet partition has no {missing} review packet.",
        )

    expected_coverage = {
        _coverage_key(reviewer, unit)
        for unit in units
        for reviewer in unit.required_reviewers
    }
    actual_coverage = set()
    packet_digests = set()
    for packet in approved.packets:
        if packet.packet_digest in packet_digests:
            raise _error(
                "review.duplicate.packet",
                "approved_review.packets",
                f"Packet digest {packet.packet_digest} occurs more than once.",
            )
        packet_digests.add(packet.packet_digest)
        if packet.policy_digest != approved.policy.policy_digest:
            raise _error(
                "review.packet.policy.mismatch",
                f"approved_review.packet[{packet.packet_id}]",
                "Packet policy digest does not match the approved policy.",
            )
        _require_within(
            _packet_usage(packet.units),
            packet.approved_budget,
            "review.approved.budget.insufficient",
            f"approved_review.packet[{packet.packet_id}]",
            f"Packet {packet.packet_id}",
        )
        _require_within(
            packet.approved_budget,
            approved.policy.per_packet_limit,
            "review.approval.exceeds.packet.limit",
            f"approved_review.packet[{packet.packet_id}]",
            f"Approved budget for packet {packet.packet_id}",
        )
        for unit in packet.units:
            key = _coverage_key(packet.reviewer, unit)
            if key in actual_coverage:
                raise _error(
                    "review.packet.overlap",
                    "approved_review.packets",
                    f"Review coverage overlaps at {unit.kind.value}:{unit.ref} "
                    f"for {packet.reviewer.value}.",
                )
            actual_coverage.add(key)
    approved_total = _sum_amounts(
        (packet.approved_budget for packet in approved.packets), ReviewBudget
    )
    _require_within(
        approved_total,
        approved.policy.total_budget,
        "review.approval.exceeds.total.budget",
        "approved_review.packets",
        "Approved review work",
    )
    if actual_coverage != expected_coverage:
        missing = expected_coverage - actual_coverage
        extra = actual_coverage - expected_coverage
        if missing:
            item = sorted(missing)[0]
            raise _error(
                "review.packet.coverage.missing",
                "approved_review.packets",
                f"Packet partition does not cover {item[2]}:{item[3]} for {item[0]}.",
            )
        item = sorted(extra)[0]
        raise _error(
            "review.packet.coverage.extra",
            "approved_review.packets",
            f"Packet partition contains stale or unknown {item[2]}:{item[3]} "
            f"for {item[0]}.",
        )

    receipts_by_digest: Dict[Digest, ReviewReceipt] = {}
    packets_by_digest = {packet.packet_digest: packet for packet in approved.packets}
    for index, receipt in enumerate(frozen_receipts):
        if not isinstance(receipt, ReviewReceipt):
            raise _error(
                "review.invalid.receipt",
                f"review_receipts[{index}]",
                "Expected ReviewReceipt.",
            )
        if receipt.packet_digest in receipts_by_digest:
            raise _error(
                "review.duplicate.receipt",
                f"review_receipts[{index}]",
                f"Packet {receipt.packet_digest} has more than one receipt.",
            )
        packet = packets_by_digest.get(receipt.packet_digest)
        if packet is None:
            raise _error(
                "review.receipt.packet.mismatch",
                f"review_receipts[{index}]",
                f"Receipt refers to unknown packet digest {receipt.packet_digest}.",
            )
        if receipt.reviewer is not packet.reviewer:
            raise _error(
                "review.receipt.reviewer.mismatch",
                f"review_receipts[{index}]",
                f"Receipt reviewer does not match packet {packet.packet_id}.",
            )
        if not receipt.accepted:
            raise _error(
                "review.receipt.rejected",
                f"review_receipts[{index}]",
                f"Packet {packet.packet_id} was not accepted.",
            )
        _require_within(
            receipt.usage,
            packet.approved_budget,
            "review.receipt.usage.exceeds.budget",
            f"review_receipts[{index}].usage",
            f"Receipt for packet {packet.packet_id}",
        )
        receipts_by_digest[receipt.packet_digest] = receipt
    missing_receipts = packet_digests - set(receipts_by_digest)
    if missing_receipts:
        raise _error(
            "review.missing.receipt",
            "review_receipts",
            "Missing receipt for packet digest "
            f"{sorted(str(value) for value in missing_receipts)[0]}.",
        )
    return CompletedReview(
        catalog_root,
        tuple(sorted(approved.packets, key=_packet_sort_key)),
        tuple(sorted(frozen_receipts, key=lambda item: str(item.packet_digest))),
    )


__all__ = (
    "BudgetAmount",
    "BudgetApproval",
    "BudgetApprovedReview",
    "BudgetUnit",
    "CompletedReview",
    "PlannedReview",
    "ReviewActorIdentity",
    "ReviewBudget",
    "ReviewClass",
    "ReviewPacket",
    "ReviewPolicy",
    "ReviewReceipt",
    "ReviewUnit",
    "ReviewUnitKind",
    "ReviewUsage",
    "approve_review_budgets",
    "complete_reviews",
    "plan_reviews",
)
