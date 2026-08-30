"""The shape a transition capture must have, in one place.

The materialiser and the completion checker both decide whether a Scenario's
arm/action/fetch/disarm sequence is well formed. They held separate copies of
the rule until the copies disagreed: one had been taught that a fetch may also
inline earlier observations through relatedResults and the other had not, so a
Catalog that materialised cleanly still failed completion.
"""

from __future__ import annotations

from typing import Iterator, Mapping, Sequence

ARM = "operation:transition-trace.arm@1"
FETCH = "operation:transition-trace.fetch@1"
DISARM = "operation:transition-trace.disarm@1"
CONTROLS = frozenset((ARM, FETCH, DISARM))

FETCH_ARGUMENTS = frozenset(("generationToken", "relatedResults"))


def failures(scenario: Mapping[str, object]) -> Iterator[str]:
    """Yield one message per way this Scenario's transition captures are wrong."""
    identifier = scenario["id"]
    calls: Sequence[Mapping[str, object]] = scenario["operations"]
    index = 0
    while index < len(calls):
        if calls[index]["operation"] != ARM:
            if calls[index]["operation"] in CONTROLS:
                yield (
                    f"{identifier} transition trace control is outside an "
                    "arm/action/fetch/disarm sequence"
                )
            index += 1
            continue
        arm = calls[index]
        fetch_index = next(
            (
                candidate
                for candidate in range(index + 1, len(calls))
                if calls[candidate]["operation"] == FETCH
            ),
            None,
        )
        if fetch_index is None:
            yield f"{identifier} transition trace has no fetch"
            return
        actions = calls[index + 1 : fetch_index]
        if not actions or any(call["operation"] in CONTROLS for call in actions):
            yield f"{identifier} transition trace has no product action"
        if (
            fetch_index + 1 >= len(calls)
            or calls[fetch_index + 1]["operation"] != DISARM
        ):
            yield f"{identifier} transition trace is not fetch then disarm"
            return
        token = f"result://{arm['callId']}/generationToken"
        fetch_arguments = calls[fetch_index]["arguments"]
        if (
            fetch_arguments.get("generationToken") != token
            or not set(fetch_arguments) <= FETCH_ARGUMENTS
            or calls[fetch_index + 1]["arguments"] != {"generationToken": token}
        ):
            yield f"{identifier} transition trace does not bind its arm token"
        index = fetch_index + 2


def count(scenarios: Sequence[Mapping[str, object]]) -> int:
    return sum(
        1
        for scenario in scenarios
        for call in scenario["operations"]
        if call["operation"] == ARM
    )
