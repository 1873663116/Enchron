#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import threading
import uuid
from pathlib import Path
from typing import Callable, Mapping, Sequence

sys.path.insert(0, str(Path(__file__).resolve().parent))

from harness import parallel
from harness.parallel import CAMPAIGN_TOKEN_ENV

Spawn = Callable[[str, str, str], int]


class CampaignNotParallelizable(RuntimeError):
    pass


def _default_spawn(
    target_devices: Mapping[str, str],
    matrix_path: Path,
    segment_plan: Path,
    output_root: Path,
) -> Spawn:
    def spawn(target: str, segment: str, token: str) -> int:
        environment = dict(os.environ)
        environment["ENCHRON_TARGET_DEVICE"] = target_devices[target]
        environment[CAMPAIGN_TOKEN_ENV] = token
        output = output_root / f"{target}-{segment}"
        command = [
            sys.executable,
            str(matrix_path),
            "--segment-plan",
            str(segment_plan),
            "--segment",
            segment,
            "--output-directory",
            str(output),
        ]
        completed = subprocess.run(command, env=environment)
        return completed.returncode

    return spawn


def launch(
    assignments: Sequence[Mapping[str, object]],
    execution_input: Mapping[str, object],
    reachable: Mapping[str, bool],
    spawn: Spawn,
    token: str | None = None,
) -> dict[str, list[int]]:
    frozen = parallel.lane_targets(execution_input)
    partitioned = parallel.partition_by_target(assignments)
    targets = parallel.parallelizable_targets(frozen, partitioned, reachable)
    if len(targets) < 2:
        raise CampaignNotParallelizable(
            "the campaign does not partition into two reachable frozen lanes; "
            f"qualifying targets were {targets!r}"
        )
    token = token or uuid.uuid4().hex
    results: dict[str, list[int]] = {}

    def run_target(target: str) -> None:
        codes: list[int] = []
        for segment in partitioned[target]:
            codes.append(spawn(target, segment, token))
        results[target] = codes

    threads = [
        threading.Thread(target=run_target, args=(target,), name=f"lane-{target}")
        for target in targets
    ]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()
    return results


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
    spawn = _default_spawn(
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
