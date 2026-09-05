"""Readings taken from an Operation call's recorded outputs.

The L0 field predicates, the known-defect exemptions and the replay-side
check of an exemption all read the same outputs document through the same
lookup, so one call's outputs answer every question the same way.
"""

from __future__ import annotations

from collections.abc import Mapping
from typing import Any, Optional, Tuple

ABSENT = object()

SCREENSHOT_KEYS = ("localScreenshotPath", "screenshotPath", "screenshot")


def field_value(value: Any, field: str) -> Any:
    if isinstance(value, Mapping):
        if field in value:
            return value[field]
        for nested in value.values():
            found = field_value(nested, field)
            if found is not ABSENT:
                return found
    elif isinstance(value, (list, tuple)):
        for item in value:
            found = field_value(item, field)
            if found is not ABSENT:
                return found
    return ABSENT


def reads_equal(read: Any, expected: Any) -> bool:
    """A boolean reading and an integer reading are different facts even
    where Python's ``==`` calls them equal."""
    return type(read) is type(expected) and read == expected


def screenshot_paths(value: Any) -> Tuple[str, ...]:
    found = []
    if isinstance(value, Mapping):
        for key, item in value.items():
            if key in SCREENSHOT_KEYS and isinstance(item, str) and item:
                found.append(item)
            else:
                found.extend(screenshot_paths(item))
    elif isinstance(value, (list, tuple)):
        for item in value:
            found.extend(screenshot_paths(item))
    return tuple(found)


def last_completed_outputs(invocations) -> Optional[Mapping[str, Any]]:
    completed = [
        item for item in invocations if item.completed and item.outputs is not None
    ]
    if not completed:
        return None
    return dict(completed[-1].outputs.payload())


__all__ = (
    "ABSENT",
    "SCREENSHOT_KEYS",
    "field_value",
    "last_completed_outputs",
    "reads_equal",
    "screenshot_paths",
)
