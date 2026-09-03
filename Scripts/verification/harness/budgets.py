from __future__ import annotations

import datetime
import json
import math
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

from harness.failures import InstrumentFault

LANES = ("device", "simulator")
TIMING_SAMPLES_FILENAME = "timing-samples.jsonl"
PROVISIONAL_CEILING_VERBS = frozenset({
    "identifier-appearance",
    "any-identifier-appearance",
    "identifier-absence",
    "identifier-value",
    "probe-needle",
    "presentation-settle",
    "presentation",
    "immersive-settlement",
    "wedge",
    "clean-open",
    "panorama-settle",
    "result-bundle",
})
SAMPLE_LIMIT = 40
MINIMUM_SAMPLE_COUNT = 5
BUDGET_MULTIPLIER = 1.5
BUDGET_FLOOR_SECONDS = 5.0
BUDGET_CEILING_SECONDS = 600.0

DEFAULT_TIMINGS_DIRECTORY = Path(__file__).resolve().parent.parent
DEFAULT_PROVISIONAL_PATH = Path(__file__).resolve().parent / "provisional_budgets.json"


@dataclass(frozen=True)
class Budget:
    seconds: float
    provenance: str
    at_floor: bool = False


def percentile_95(values: list[float]) -> float:
    assert values, "p95 of an empty sample set is undefined"
    ordered = sorted(values)
    rank = math.ceil(0.95 * len(ordered))
    return ordered[rank - 1]


class BudgetProvider:
    def __init__(
        self,
        timings_directory: Path = DEFAULT_TIMINGS_DIRECTORY,
        provisional_path: Path = DEFAULT_PROVISIONAL_PATH,
        today: Callable[[], datetime.date] = datetime.date.today,
        now: Callable[[], datetime.datetime] = lambda: datetime.datetime.now(
            datetime.timezone.utc
        ),
        output_directory: Path | None = None,
    ) -> None:
        self.timings_directory = Path(timings_directory)
        self.provisional_path = Path(provisional_path)
        self.today = today
        self.now = now
        self.output_directory = (
            Path(output_directory) if output_directory is not None else None
        )

    def timings_path(self, lane: str) -> Path:
        assert lane in LANES, (
            f"unknown lane {lane!r}; timing samples are split per lane into "
            f"controller_timings.<lane>.json for lanes {LANES}"
        )
        return self.timings_directory / f"controller_timings.{lane}.json"

    def load(self, lane: str) -> dict[str, object]:
        path = self.timings_path(lane)
        if not path.exists():
            return {"verbs": {}, "updatedAt": None}
        return json.loads(path.read_text(encoding="utf-8"))

    def samples(self, lane: str, verb: str) -> list[dict[str, object]]:
        verbs = self.load(lane).get("verbs", {})
        entry = verbs.get(verb, {}) if isinstance(verbs, dict) else {}
        listed = entry.get("samples", []) if isinstance(entry, dict) else []
        return list(listed) if isinstance(listed, list) else []

    def budget(self, lane: str, verb: str) -> Budget:
        recorded = self.samples(lane, verb)
        if len(recorded) < MINIMUM_SAMPLE_COUNT:
            return self.provisional_budget(lane, verb, len(recorded))
        seconds_values = [float(sample["seconds"]) for sample in recorded]
        censored_count = sum(1 for sample in recorded if sample.get("censored"))
        p95 = percentile_95(seconds_values)
        derived = min(
            max(p95 * BUDGET_MULTIPLIER, BUDGET_FLOOR_SECONDS),
            BUDGET_CEILING_SECONDS,
        )
        provenance = (
            f"p95 {p95:.2f}s × {BUDGET_MULTIPLIER}, lane={lane}, "
            f"n={len(recorded)}, censored={censored_count}"
        )
        floor = self.declared_floor(verb)
        at_floor = floor is not None and derived < floor
        if at_floor:
            derived = min(floor, BUDGET_CEILING_SECONDS)
            provenance += f", raised to the declared floor {floor:g}s"
        return Budget(seconds=derived, provenance=provenance, at_floor=at_floor)

    def declared_floor(self, verb: str) -> float | None:
        if not self.provisional_path.exists():
            return None
        table = json.loads(self.provisional_path.read_text(encoding="utf-8"))
        entry = table.get(verb)
        if isinstance(entry, dict) and "floorSeconds" in entry:
            return float(entry["floorSeconds"])
        return None

    def provisional_budget(self, lane: str, verb: str, sample_count: int) -> Budget:
        table: dict[str, object] = {}
        if self.provisional_path.exists():
            table = json.loads(self.provisional_path.read_text(encoding="utf-8"))
        entry = table.get(verb)
        if not isinstance(entry, dict):
            raise InstrumentFault(
                "provisional-budget-expired",
                {
                    "verb": verb,
                    "lane": lane,
                    "sampleCount": sample_count,
                    "diagnosis": (
                        f"verb {verb!r} has {sample_count} samples "
                        f"(< {MINIMUM_SAMPLE_COUNT}) and no provisional budget entry; "
                        "measure the verb or add a dated entry"
                    ),
                },
            )
        expires = datetime.date.fromisoformat(str(entry["expires"]))
        if self.today() >= expires:
            raise InstrumentFault(
                "provisional-budget-expired",
                {
                    "verb": verb,
                    "lane": lane,
                    "sampleCount": sample_count,
                    "expires": str(entry["expires"]),
                    "diagnosis": (
                        f"provisional budget for {verb!r} expired on {entry['expires']} "
                        f"and only {sample_count} measured samples exist; "
                        "the measurement debt is due"
                    ),
                },
            )
        seconds = float(entry["seconds"])
        if verb in PROVISIONAL_CEILING_VERBS:
            provenance = (
                f"provisional ceiling {seconds:g}s, expires {entry['expires']}, "
                f"lane={lane}, n={sample_count}"
            )
        else:
            provenance = (
                f"provisional {seconds:g}s, expires {entry['expires']}, "
                f"lane={lane}, n={sample_count}"
            )
        return Budget(seconds=seconds, provenance=provenance)

    def record_sample(
        self, lane: str, verb: str, seconds: float, censored: bool
    ) -> None:
        if os.environ.get("ENCHRON_EXECUTION_INPUT"):
            if self.output_directory is not None:
                self.output_directory.mkdir(parents=True, exist_ok=True)
                with (
                    self.output_directory / TIMING_SAMPLES_FILENAME
                ).open("a", encoding="utf-8") as handle:
                    handle.write(
                        json.dumps(
                            {
                                "verb": verb,
                                "lane": lane,
                                "seconds": round(float(seconds), 3),
                                "censored": bool(censored),
                                "at": self.now().isoformat(),
                            },
                            sort_keys=True,
                        )
                        + "\n"
                    )
            return
        document = self.load(lane)
        verbs = document.setdefault("verbs", {})
        entry = verbs.setdefault(verb, {"samples": []})
        entry.setdefault("samples", []).append(
            {
                "seconds": round(float(seconds), 3),
                "censored": bool(censored),
                "at": self.now().isoformat(),
            }
        )
        entry["samples"] = entry["samples"][-SAMPLE_LIMIT:]
        document["updatedAt"] = self.now().isoformat()
        path = self.timings_path(lane)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            json.dumps(document, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
