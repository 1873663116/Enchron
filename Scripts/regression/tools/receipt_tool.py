#!/usr/bin/env python3

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict, Optional, Tuple

from regression.core.ids import NodeID
from regression.core.replay import replay
from regression.core.runview import NodeStatus, RunView
from regression.tools.human_receipt import (
    HumanReceipt,
    HumanReceiptError,
    load_receipt,
)

RECEIPT_SCHEMA = "enchron.regression.run-receipt"

CLOSED_WITHOUT_A_HUMAN = (
    NodeStatus.PASSED,
    NodeStatus.FAILED,
    NodeStatus.FAILED_KNOWN,
    NodeStatus.BLOCKED_BY,
)


class ReceiptToolError(ValueError):
    pass


def open_nodes(current: RunView, receipt: Optional[HumanReceipt]) -> Tuple[NodeID, ...]:
    covered = frozenset(() if receipt is None else receipt.covered())
    return tuple(
        node.node_id
        for node in current.nodes
        if node.status not in CLOSED_WITHOUT_A_HUMAN
        and not (
            node.status is NodeStatus.DEFERRED_HUMAN and node.node_id in covered
        )
    )


def run(
    run_directory: Path, human_receipt: Optional[Path] = None
) -> Dict[str, Any]:
    current = replay(Path(run_directory))
    receipt = None
    if human_receipt is not None:
        path = Path(human_receipt)
        if not path.is_file():
            raise ReceiptToolError(f"{path} holds no human receipt")
        try:
            receipt = load_receipt(json.loads(path.read_text(encoding="utf-8")))
        except (json.JSONDecodeError, HumanReceiptError) as error:
            raise ReceiptToolError(str(error)) from error
    remaining = open_nodes(current, receipt)
    if remaining:
        return {
            "refused": (
                "a merge receipt closes when every node is closed; "
                f"{len(remaining)} still open"
            ),
            "openNodes": [str(item) for item in remaining],
        }
    return {
        "schema": RECEIPT_SCHEMA,
        "schemaVersion": 1,
        "runId": None if current.run_id is None else str(current.run_id),
        "planDigest": None
        if current.plan_digest is None
        else str(current.plan_digest),
        "nodes": [
            {"node": str(node.node_id), "status": node.status.value}
            for node in current.nodes
        ],
        "humanReceipt": None if receipt is None else receipt.payload(),
    }


__all__ = (
    "CLOSED_WITHOUT_A_HUMAN",
    "RECEIPT_SCHEMA",
    "ReceiptToolError",
    "open_nodes",
    "run",
)
