from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import re


PRESENTATIONS = ("window", "docked", "portal", "panorama")
TOLERANCE = 0.001
MAPPING = re.compile(
    r"presentation=(\S+)\s+kind=(\S+)\s+canvas=(\S+)\s+"
    r"content=(\S+)\s+extent=(\S+)\s+pixelAspect=(\S+)"
)


def positive_number(value: str) -> float:
    number = float(value)
    if not math.isfinite(number) or number <= 0:
        raise ValueError(f"expected a positive finite number: {value}")
    return number


def dimensions(value: str) -> tuple[float, float]:
    width, height = value.split("x")
    return positive_number(width), positive_number(height)


def verify_probe(text: str, presentations: list[str]) -> dict[str, object]:
    samples: dict[str, list[float]] = {mode: [] for mode in dict.fromkeys(presentations)}
    failures: list[dict[str, object]] = []
    for line_number, line in enumerate(text.splitlines(), 1):
        _, marker, payload = line.partition("subtitlePixelMapping ")
        if not marker:
            continue
        mode_match = re.search(r"\bpresentation=(\S+)", payload)
        mode = mode_match.group(1) if mode_match else None
        if mode is not None and mode not in samples:
            continue
        record = MAPPING.match(payload)
        if record is None:
            failures.append({"line": line_number, "presentation": mode, "error": "malformed mapping"})
            continue
        _, kind, canvas, content, extent, reported_aspect = record.groups()
        try:
            dimensions(canvas)
            content_width, content_height = dimensions(content)
            extent_width, extent_height = dimensions(extent)
            positive_number(reported_aspect)
            ratio = (extent_width / content_width) / (extent_height / content_height)
            if not math.isfinite(ratio) or ratio <= 0:
                raise ValueError("computed pixel aspect is not positive and finite")
        except (ValueError, ZeroDivisionError, OverflowError) as error:
            failures.append({"line": line_number, "presentation": mode, "kind": kind, "error": str(error)})
            continue
        samples[mode].append(ratio)
        if not 1 - TOLERANCE <= ratio <= 1 + TOLERANCE:
            failures.append({"line": line_number, "presentation": mode, "kind": kind, "pixelAspect": ratio})
    for mode, ratios in samples.items():
        if not ratios:
            failures.append({"presentation": mode, "error": "no valid samples"})
    return {
        "passed": not failures,
        "tolerance": TOLERANCE,
        "presentations": {
            mode: {
                "samples": len(ratios),
                "minPixelAspect": min(ratios) if ratios else None,
                "maxPixelAspect": max(ratios) if ratios else None,
            }
            for mode, ratios in samples.items()
        },
        "failures": failures,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify subtitle pixels have equal horizontal and vertical scale.")
    parser.add_argument("probe", type=Path)
    parser.add_argument("--presentation", action="append", choices=PRESENTATIONS, required=True)
    arguments = parser.parse_args()
    try:
        result = verify_probe(arguments.probe.read_text(encoding="utf-8"), arguments.presentation)
    except (OSError, UnicodeError) as error:
        result = {"passed": False, "failures": [{"error": str(error)}]}
    print(json.dumps(result, ensure_ascii=False, separators=(",", ":"), allow_nan=False))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
