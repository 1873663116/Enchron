from __future__ import annotations

import os
import subprocess
import sys
import threading
import uuid
from pathlib import Path
from typing import Callable, Mapping, Sequence

from harness import parallel
from harness.parallel import CAMPAIGN_TOKEN_ENV

Spawn = Callable[[str, str, str], int]


class CampaignNotParallelizable(RuntimeError):
    pass


def segment_command(
    matrix_path: Path,
    segment_plan: Path,
    execution_input: Path,
    output: Path,
    segment: str,
    extra_args: Sequence[str] = (),
) -> list[str]:
    return [
        sys.executable,
        str(matrix_path),
        "--execution-input",
        str(execution_input),
        "--segment-plan",
        str(segment_plan),
        "--segment",
        segment,
        "--output-directory",
        str(output),
        *[str(argument) for argument in extra_args],
    ]


def default_spawn(
    target_devices: Mapping[str, str],
    matrix_path: Path,
    segment_plan: Path,
    execution_input: Path,
    output_root: Path,
    extra_args_by_segment: Mapping[str, Sequence[str]] | None = None,
) -> Spawn:
    extra = dict(extra_args_by_segment or {})

    def spawn(target: str, segment: str, token: str) -> int:
        environment = dict(os.environ)
        environment["ENCHRON_TARGET_DEVICE"] = target_devices[target]
        environment[CAMPAIGN_TOKEN_ENV] = token
        command = segment_command(
            matrix_path,
            segment_plan,
            execution_input,
            output_root / f"{target}-{segment}",
            segment,
            extra.get(segment, ()),
        )
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
