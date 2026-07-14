#!/usr/bin/env python3

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image


def metrics(path: Path) -> dict[str, float | int]:
    pixels = np.asarray(Image.open(path).convert("RGB"), dtype=np.float32) / 255.0
    luminance = pixels @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    visible = luminance > 0.01
    if visible.mean() < 0.5:
        raise RuntimeError(f"capture has insufficient visible content: {path}")
    values = luminance[visible]
    return {
        "width": int(pixels.shape[1]),
        "height": int(pixels.shape[0]),
        "mean": float(values.mean()),
        "p50": float(np.percentile(values, 50)),
        "p90": float(np.percentile(values, 90)),
        "p95": float(np.percentile(values, 95)),
        "p99": float(np.percentile(values, 99)),
        "highlightFraction": float((values >= 0.90).mean()),
        "clippedChannelFraction": float((pixels[visible].max(axis=1) >= 254.0 / 255.0).mean()),
    }


def main() -> int:
    directory = Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/playbacklab-hdr-probe")
    reality = metrics(directory / "realitykit.png")
    reality_avplayer = metrics(directory / "realitykit-avplayer.png")
    reference = metrics(directory / "system-reference.png")
    if not (
        (reality["width"], reality["height"])
        == (reality_avplayer["width"], reality_avplayer["height"])
        == (reference["width"], reference["height"])
    ):
        raise RuntimeError("captures have different dimensions")

    def compare(candidate: dict[str, float | int]) -> tuple[dict[str, float], bool]:
        delta = {
            "mean": candidate["mean"] - reference["mean"],
            "p95": candidate["p95"] - reference["p95"],
            "highlightFraction": candidate["highlightFraction"] - reference["highlightFraction"],
            "clippedChannelFraction": candidate["clippedChannelFraction"] - reference["clippedChannelFraction"],
        }
        return delta, (
            delta["mean"] >= 0.04
            or delta["p95"] >= 0.04
            or delta["highlightFraction"] >= 0.02
            or delta["clippedChannelFraction"] >= 0.01
        )

    delta, overexposed = compare(reality)
    avplayer_delta, avplayer_overexposed = compare(reality_avplayer)
    result = {
        "verdict": "RED_OVEREXPOSED" if overexposed else "GREEN_NO_OVEREXPOSURE",
        "localization": (
            "REALITYKIT_PRESENTATION"
            if avplayer_overexposed
            else "SAMPLE_BUFFER_RENDERER_ROUTE"
            if overexposed
            else "NO_REPRO"
        ),
        "realityKit": reality,
        "realityKitAVPlayer": reality_avplayer,
        "systemReference": reference,
        "delta": {
            "sampleBufferRendererVsSystem": delta,
            "avPlayerVsSystem": avplayer_delta,
        },
    }
    print(json.dumps(result, indent=2, sort_keys=True))
    return 1 if overexposed else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(json.dumps({"verdict": "INVALID_CAPTURE", "error": str(error)}, indent=2), file=sys.stderr)
        raise SystemExit(2)
