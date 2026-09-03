from __future__ import annotations

from typing import Iterable, Mapping

SIMULATOR = "simulator"
DEVICE = "device"

BROWSE_SURFACE_HOST_PREFIX = "browserWindowSurface"
PLAYBACK_OPENING_TOKENS = frozenset(
    {"MediaLibrary-grid-video", "FileBrowsing-grid-video", "Resume", "PlayFromBeginning"}
)


def _host(operation: Mapping[str, object]) -> str:
    derivation = operation.get("proofContextDerivation") or {}
    host = derivation.get("host") if isinstance(derivation, Mapping) else None
    return host if isinstance(host, str) else ""


def opens_playback(operation: Mapping[str, object]) -> bool:
    if operation.get("kind") != "activate":
        return False
    template = operation.get("identifierTemplate") or ""
    return any(token in template for token in PLAYBACK_OPENING_TOKENS)


def simulator_drivable(operation: Mapping[str, object]) -> bool:
    if not _host(operation).startswith(BROWSE_SURFACE_HOST_PREFIX):
        return False
    return not opens_playback(operation)


def lane_for(operation: Mapping[str, object]) -> str:
    return SIMULATOR if simulator_drivable(operation) else DEVICE


def partition(operations: Iterable[Mapping[str, object]]) -> dict[str, list[str]]:
    lanes: dict[str, list[str]] = {SIMULATOR: [], DEVICE: []}
    for operation in operations:
        lanes[lane_for(operation)].append(str(operation["id"]))
    return lanes
