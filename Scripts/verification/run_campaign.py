#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from harness.campaign import CampaignNotParallelizable, default_spawn, launch
from harness.parallel import CAMPAIGN_TOKEN_ENV


def _load(path: str) -> dict[str, object]:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--campaign", required=True)
    parser.add_argument("--execution-input", required=True)
    parser.add_argument("--segment-plan", required=True)
    parser.add_argument("--output-root", required=True)
    parser.add_argument("--simulator-target", required=True)
    parser.add_argument("--device-target", required=True)
    arguments = parser.parse_args()

    campaign = _load(arguments.campaign)
    execution_input = _load(arguments.execution_input)
    assignments = campaign["assignments"]
    reachable = campaign.get("reachable", {"simulator": True, "device": True})
    target_devices = {
        "simulator": arguments.simulator_target,
        "device": arguments.device_target,
    }
    spawn = default_spawn(
        target_devices,
        Path(__file__).resolve().parent / "reachability_matrix.py",
        Path(arguments.segment_plan),
        Path(arguments.output_root),
    )
    try:
        results = launch(assignments, execution_input, reachable, spawn)
    except CampaignNotParallelizable as refusal:
        sys.stderr.write(str(refusal) + "\n")
        return 2
    worst = max((code for codes in results.values() for code in codes), default=0)
    sys.stdout.write(json.dumps(results, sort_keys=True) + "\n")
    return worst


if __name__ == "__main__":
    raise SystemExit(main())
