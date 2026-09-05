from __future__ import annotations

from typing import Mapping

SIMULATOR = "simulator"
DEVICE = "device"
LANES = (SIMULATOR, DEVICE)

PLAYBACK_OPENING_TOKENS = frozenset(
    {"MediaLibrary-grid-video", "FileBrowsing-grid-video", "Emby-Detail-Play"}
)
PLAYBACK_OPENING_IDENTIFIER_PREFIXES = (
    "MediaLibrary-grid-video-",
    "FileBrowsing-grid-video-",
)
PLAYBACK_OPENING_IDENTIFIERS = frozenset(
    {"Emby-Detail-Play"}
)


def opens_playback(operation: Mapping[str, object]) -> bool:
    if operation.get("kind") != "activate":
        return False
    template = str(operation.get("identifierTemplate") or "")
    return any(token in template for token in PLAYBACK_OPENING_TOKENS)


def identifier_opens_playback(identifier: str) -> bool:
    if identifier in PLAYBACK_OPENING_IDENTIFIERS:
        return True
    return any(
        identifier.startswith(prefix)
        for prefix in PLAYBACK_OPENING_IDENTIFIER_PREFIXES
    )


def simulator_refuses_tap(lane: str, identifier: str) -> bool:
    return lane == SIMULATOR and identifier_opens_playback(identifier)
