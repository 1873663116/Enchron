#!/usr/bin/env python3

from __future__ import annotations

import argparse
from pathlib import Path
import sys
from typing import Any, Mapping, Optional, Sequence


if __package__ in (None, ""):
    scripts_root = Path(__file__).resolve().parents[1]
    if str(scripts_root) not in sys.path:
        sys.path.insert(0, str(scripts_root))
    from regression.core.digest import canonical_bytes
    from regression.core.errors import RegressionError
    from regression.review_stage import (
        accept_agent_assessment,
        derive_human_coverage_reviews,
        prepare_review_packets,
        review_status,
        run_deterministic_reviews,
    )
else:
    from .core.digest import canonical_bytes
    from .core.errors import RegressionError
    from .review_stage import (
        accept_agent_assessment,
        derive_human_coverage_reviews,
        prepare_review_packets,
        review_status,
        run_deterministic_reviews,
    )


def _common_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument(
        "--repository-root",
        "--repo-root",
        type=Path,
        default=Path.cwd(),
        help="repository root; defaults to the current directory",
    )
    parser.add_argument(
        "--catalog-root",
        type=Path,
        default=Path("Regression"),
        help="Catalog directory, relative to the repository by default",
    )
    parser.add_argument(
        "--policy",
        type=Path,
        default=Path("Regression/review-policy.md"),
        help="review policy, relative to the repository by default",
    )
    return parser


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Prepare and execute Regression Catalog review packets."
    )
    commands = parser.add_subparsers(dest="operation", required=True)
    common = _common_parser()

    prepare = commands.add_parser(
        "prepare", parents=(common,), help="write canonical packet manifests"
    )
    prepare.add_argument("--staging-root", type=Path, required=True)

    deterministic = commands.add_parser(
        "deterministic",
        parents=(common,),
        help="run the deterministic Catalog review",
    )
    deterministic.add_argument("--reviews-root", type=Path, required=True)
    deterministic.add_argument(
        "--issued-at",
        required=True,
        help="RFC 3339 issue time; repeat the same value for idempotent reruns",
    )

    agent = commands.add_parser(
        "accept-agent",
        parents=(common,),
        help="validate and persist one AgentOperability assessment",
    )
    agent.add_argument("--reviews-root", type=Path, required=True)
    agent.add_argument("--assessment", type=Path, required=True)

    derived_human = commands.add_parser(
        "derive-human",
        parents=(common,),
        help="derive HumanCoverage receipts from approved semantic authority",
    )
    derived_human.add_argument("--reviews-root", type=Path, required=True)
    derived_human.add_argument(
        "--issued-at",
        required=True,
        help="RFC 3339 issue time; repeat the same value for idempotent reruns",
    )

    status = commands.add_parser(
        "status",
        parents=(common,),
        help="verify persisted receipts and report bytes",
    )
    status.add_argument("--reviews-root", type=Path, required=True)
    return parser


def _write(payload: Mapping[str, Any]) -> None:
    sys.stdout.buffer.write(canonical_bytes(payload) + b"\n")


def _run(arguments: argparse.Namespace) -> Mapping[str, Any]:
    common = (
        arguments.repository_root,
        arguments.catalog_root,
        arguments.policy,
    )
    if arguments.operation == "prepare":
        result = prepare_review_packets(*common, arguments.staging_root)
        return {
            "operation": "prepare",
            "catalogDigest": str(result.catalog_digest),
            "planDigest": str(result.plan_digest),
            "policyDigest": str(result.policy_digest),
            "approvalDigest": str(result.approval_digest),
            "packetCount": len(result.manifest_paths),
            "manifests": [str(path) for path in result.manifest_paths],
        }
    if arguments.operation == "deterministic":
        result = run_deterministic_reviews(
            *common, arguments.reviews_root, arguments.issued_at
        )
        return {
            "operation": "deterministic",
            "catalogDigest": str(result.catalog_digest),
            "planDigest": str(result.plan_digest),
            "environmentDigest": str(result.environment_digest),
            "receiptCount": len(result.issued),
            "receipts": [
                {
                    "packetDigest": str(item.receipt.packet_digest),
                    "receiptDigest": str(item.receipt.receipt_digest),
                    "reportDigest": str(item.receipt.report_digest),
                    "receiptPath": str(item.receipt_path),
                    "reportPath": str(item.report_path),
                }
                for item in result.issued
            ],
        }
    if arguments.operation == "accept-agent":
        result = accept_agent_assessment(
            *common, arguments.reviews_root, arguments.assessment
        )
        return {
            "operation": "accept-agent",
            "packetDigest": str(result.receipt.packet_digest),
            "receiptDigest": str(result.receipt.receipt_digest),
            "reportDigest": str(result.receipt.report_digest),
            "receiptPath": str(result.receipt_path),
            "reportPath": str(result.report_path),
        }
    if arguments.operation == "derive-human":
        result = derive_human_coverage_reviews(
            *common, arguments.reviews_root, arguments.issued_at
        )
        return {
            "operation": "derive-human",
            "catalogDigest": str(result.catalog_digest),
            "planDigest": str(result.plan_digest),
            "authorityDigest": str(result.authority_digest),
            "receiptCount": len(result.issued),
            "receipts": [
                {
                    "packetDigest": str(item.receipt.packet_digest),
                    "receiptDigest": str(item.receipt.receipt_digest),
                    "reportDigest": str(item.receipt.report_digest),
                    "receiptPath": str(item.receipt_path),
                    "reportPath": str(item.report_path),
                }
                for item in result.issued
            ],
        }
    result = review_status(*common, arguments.reviews_root)
    payload = dict(result.as_payload())
    payload["operation"] = "status"
    return payload


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = _parser()
    arguments = parser.parse_args(argv)
    try:
        _write(_run(arguments))
    except (OSError, RegressionError) as error:
        parser.exit(2, f"reviewctl: {error}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
