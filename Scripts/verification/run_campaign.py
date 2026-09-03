#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Mapping

sys.path.insert(0, str(Path(__file__).resolve().parent))

from harness.campaign import CampaignNotParallelizable, default_spawn, launch
from harness.parallel import assignments_from_plan


def _load(path: str) -> dict[str, object]:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def extra_args_by_segment(
    plan: Mapping[str, object], extra_args_by_context: Mapping[str, object]
) -> dict[str, list[str]]:
    return {
        str(segment["id"]): [
            str(argument)
            for argument in extra_args_by_context.get(str(segment["context"]), [])
        ]
        for segment in plan.get("segments") or []
        if isinstance(segment, Mapping)
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--campaign")
    parser.add_argument("--execution-input", required=True)
    parser.add_argument("--segment-plan", required=True)
    parser.add_argument("--output-root", required=True)
    parser.add_argument("--simulator-target", required=True)
    parser.add_argument("--device-target", required=True)
    arguments = parser.parse_args()

    campaign = _load(arguments.campaign) if arguments.campaign else {}
    if "assignments" in campaign:
        sys.stderr.write(
            "campaign assignments are derived from the segment plan's lanes; "
            f"remove the assignments array from {arguments.campaign}\n"
        )
        return 2
    plan = _load(arguments.segment_plan)
    execution_input = _load(arguments.execution_input)
    assignments = assignments_from_plan(plan)
    reachable = campaign.get("reachable", {"simulator": True, "device": True})
    target_devices = {
        "simulator": arguments.simulator_target,
        "device": arguments.device_target,
    }
    worktrees = {
        str(target): str(Path(str(path)).resolve())
        for target, path in (campaign.get("worktrees") or {}).items()
    }
    spawn = default_spawn(
        target_devices,
        {target: Path(path) for target, path in worktrees.items()},
        Path(arguments.segment_plan),
        Path(arguments.execution_input),
        Path(arguments.output_root),
        extra_args_by_segment(plan, campaign.get("extraArgs") or {}),
    )
    try:
        results = launch(
            assignments, execution_input, reachable, spawn, worktrees=worktrees
        )
    except CampaignNotParallelizable as refusal:
        sys.stderr.write(str(refusal) + "\n")
        return 2
    worst = max((code for codes in results.values() for code in codes), default=0)
    sys.stdout.write(json.dumps(results, sort_keys=True) + "\n")
    return worst


if __name__ == "__main__":
    raise SystemExit(main())
