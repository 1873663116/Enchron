#!/usr/bin/env python3

"""The presentation model, mirrored from Swift for the device scripts.

Modules/PlaybackPresentation/Model/PlaybackPresentation.swift owns this. The
device scripts cannot import it, and when they wrote the answers out as string
literals instead, the literals kept saying a panoramic clip lands in panorama
long after the product started landing it in portal. Whole matrix paths then
asked for a button that portal does not have.

test_presentation_model.py reads the Swift and fails if this file disagrees, so
the next change to the model breaks the mirror instead of the device run.
"""

from __future__ import annotations

FLAT = "flat"
PANORAMIC = "panoramic"

CONTENT_FAMILY = {
    "window": FLAT,
    "portal": PANORAMIC,
    "docked": FLAT,
    "panorama": PANORAMIC,
}

MAIN_WINDOW_PRESENTATION = {FLAT: "window", PANORAMIC: "portal"}
IMMERSIVE_PRESENTATION = {FLAT: "docked", PANORAMIC: "panorama"}

PRESENTATIONS = tuple(CONTENT_FAMILY)


def uses_immersive_space(presentation: str) -> bool:
    return presentation in ("docked", "panorama")


def lands_in_main_window(family: str) -> str:
    """Where content of this family settles when it is not in the immersive space.

    Both a cold open and an applied projection land here. Entering the immersive
    space is always a separate, explicit act by the wearer.
    """
    return MAIN_WINDOW_PRESENTATION[family]


def lands_in_immersive_space(family: str) -> str:
    return IMMERSIVE_PRESENTATION[family]


def edge(source: str, target: str) -> str:
    same_family = CONTENT_FAMILY[source] == CONTENT_FAMILY[target]
    leaving = uses_immersive_space(source)
    arriving = uses_immersive_space(target)
    if not same_family:
        return "projection-swap" if not leaving and not arriving else "illegal"
    if leaving == arriving:
        return "in-place"
    return "enter-immersive" if arriving else "exit-immersive"


def legal_targets(source: str) -> tuple[str, ...]:
    return tuple(
        target for target in PRESENTATIONS if edge(source, target) != "illegal"
    )
