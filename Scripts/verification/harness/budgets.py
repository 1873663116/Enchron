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
    ) -> None:
        self.timings_directory = Path(timings_directory)
        self.provisional_path = Path(provisional_path)
        self.today = today
        self.now = now

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
        return Budget(seconds=derived, provenance=provenance)

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
        provenance = (
            f"provisional {seconds:g}s, expires {entry['expires']}, "
            f"lane={lane}, n={sample_count}"
        )
        return Budget(seconds=seconds, provenance=provenance)

    def record_sample(
        self, lane: str, verb: str, seconds: float, censored: bool
    ) -> None:
        if os.environ.get("ENCHRON_EXECUTION_INPUT"):
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
