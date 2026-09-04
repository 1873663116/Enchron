#!/usr/bin/env python3

from __future__ import annotations

from pathlib import Path
import sys
from typing import Any, Callable, Dict, Mapping, Optional


VERIFICATION = Path(__file__).resolve().parents[2] / "verification"
if str(VERIFICATION) not in sys.path:
    sys.path.insert(0, str(VERIFICATION))

from interactive_visionpro_ui import (
    ensure_session,
    halt_session,
    parse_arguments,
)


AGENT_MODE = "agent"
HUMAN_MODE = "human"
SESSION_MODES = (AGENT_MODE, HUMAN_MODE)

ENSURE_STAGE = "ensure"
HALT_STAGE = "halt"
SESSION_STAGES = (ENSURE_STAGE, HALT_STAGE)

ENSURE_SESSION_ACTION = "ensure-session"
HALT_ACTION = "halt"

ENSURE_RESULT_STAGES = (
    "adopted",
    "ready",
    "halt",
    "firstCommand",
    "readyTimeout",
)

CONTROLLER_FAILURES = (OSError, RuntimeError, ValueError)

HUMAN_MODE_REFUSAL = (
    "session --mode human opens the recording, console and timeline poll that "
    "phase 16 builds; this phase forwards the agent-mode ensure and halt stages only"
)


class SessionToolError(ValueError):
    pass


def run(
    mode: str,
    device: str,
    stage: str,
    execution_input: Optional[str] = None,
    output_directory: Optional[str] = None,
) -> Dict[str, Any]:
    if mode not in SESSION_MODES:
        joined = " or ".join(SESSION_MODES)
        raise SessionToolError(f"session runs in {joined} mode, not {mode!r}")
    if mode == HUMAN_MODE:
        raise SessionToolError(HUMAN_MODE_REFUSAL)
    if stage not in SESSION_STAGES:
        joined = " or ".join(SESSION_STAGES)
        raise SessionToolError(f"session drives the {joined} stage, not {stage!r}")
    if not isinstance(device, str) or not device:
        raise SessionToolError("session needs the device it drives")

    argv = [f"--device={device}"]
    if output_directory is not None:
        argv.append(f"--output-directory={output_directory}")
    if stage == ENSURE_STAGE:
        if execution_input is not None:
            argv.append(f"--execution-input={execution_input}")
        return _forward(ensure_session, argv + [ENSURE_SESSION_ACTION])
    return _forward(halt_session, argv + [HALT_ACTION])


def _forward(call: Callable[[Any], Mapping[str, Any]], argv: list) -> Dict[str, Any]:
    try:
        arguments = parse_arguments(argv)
    except SystemExit as error:
        raise SessionToolError(
            f"the controller refused these session arguments: {argv}"
        ) from error
    try:
        return dict(call(arguments))
    except CONTROLLER_FAILURES as error:
        return {"success": False, "error": str(error)}


__all__ = (
    "AGENT_MODE",
    "CONTROLLER_FAILURES",
    "ENSURE_RESULT_STAGES",
    "ENSURE_SESSION_ACTION",
    "ENSURE_STAGE",
    "HALT_ACTION",
    "HALT_STAGE",
    "HUMAN_MODE",
    "HUMAN_MODE_REFUSAL",
    "SESSION_MODES",
    "SESSION_STAGES",
    "SessionToolError",
    "run",
)
