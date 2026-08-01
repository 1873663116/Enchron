#!/usr/bin/env python3
"""Audit a retained stereo capture and both predetermined channel derivations."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import subprocess
import sys

import numpy as np

import analyze_acoustic_timeline as acoustic


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--stereo-wav", type=Path, required=True)
    parser.add_argument("--channel-1-wav", type=Path, required=True)
    parser.add_argument("--channel-2-wav", type=Path, required=True)
    parser.add_argument("--xcresult", type=Path, required=True)
    parser.add_argument("--recording-start-wall-clock", type=float, required=True)
    parser.add_argument("--calibration-marker-prefix", required=True)
    parser.add_argument(
        "--channel-selection",
        choices=("unknown-report-both", "channel-1", "channel-2"),
        required=True,
    )
    parser.add_argument("--capture-argv", type=Path, required=True)
    parser.add_argument("--ffmpeg-version-file", type=Path, required=True)
    parser.add_argument("--capture-log", type=Path, required=True)
    parser.add_argument("--ffprobe-file", type=Path, required=True)
    parser.add_argument("--frame-zero-file", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def decode_stereo(path: Path) -> np.ndarray:
    process = subprocess.run(
        [
            "ffmpeg", "-hide_banner", "-loglevel", "error", "-i", str(path),
            "-f", "f32le", "-acodec", "pcm_f32le", "-ac", "2", "-",
        ],
        check=True,
        stdout=subprocess.PIPE,
    )
    samples = np.frombuffer(process.stdout, dtype="<f4")
    if len(samples) % 2:
        raise ValueError("Stereo decode returned an odd number of samples")
    return samples.reshape(-1, 2).astype(np.float64)


def channel_relationship(stereo: np.ndarray) -> dict[str, object]:
    left = stereo[:, 0]
    right = stereo[:, 1]
    left_rms = math.sqrt(float(np.mean(left * left)))
    right_rms = math.sqrt(float(np.mean(right * right)))
    correlation = float(np.corrcoef(left, right)[0, 1])
    polarity = "positive" if correlation >= 0.5 else (
        "negative" if correlation <= -0.5 else "uncorrelated"
    )
    return {
        "channel1RMSDBFS": acoustic.decibels(left_rms),
        "channel2RMSDBFS": acoustic.decibels(right_rms),
        "correlationCoefficient": correlation,
        "polarityRelationship": polarity,
    }


def analyze_channel(path: Path, args: argparse.Namespace) -> dict[str, object]:
    namespace = argparse.Namespace(
        wav=path,
        xcresult=args.xcresult,
        recording_start_wall_clock=args.recording_start_wall_clock,
        calibration_start_seconds=None,
        calibration_end_seconds=None,
        calibration_marker_prefix=args.calibration_marker_prefix,
        edge_trim_seconds=0.0,
        neighbor_offset_hz=25.0,
        minimum_tone_over_neighbor_db=12.0,
        phase_offset_step_seconds=0.025,
        phase_tone_edge_trim_seconds=0.075,
        phase_minimum_window_count=3,
        phase_minimum_pass_fraction=0.8,
        maximum_observed_period_deviation_fraction=0.02,
        tone_manifest=None,
    )
    return acoustic.analyze_phase_aware_calibration(namespace)


def main() -> int:
    args = arguments()
    required_evidence = (
        args.stereo_wav,
        args.channel_1_wav,
        args.channel_2_wav,
        args.capture_argv,
        args.ffmpeg_version_file,
        args.capture_log,
        args.ffprobe_file,
        args.frame_zero_file,
    )
    missing = [str(path) for path in required_evidence if not path.is_file()]
    if missing:
        raise ValueError(f"Missing capture-contract evidence: {', '.join(missing)}")
    probe = json.loads(args.ffprobe_file.read_text())
    streams = probe.get("streams", [])
    if len(streams) != 1 or streams[0].get("channels") != 2:
        raise ValueError("Primary capture is not a single stereo stream")
    if streams[0].get("codec_name") != "pcm_f32le":
        raise ValueError("Primary capture is not retained pcm_f32le")

    stereo = decode_stereo(args.stereo_wav)
    channel_results = {
        "channel-1": analyze_channel(args.channel_1_wav, args),
        "channel-2": analyze_channel(args.channel_2_wav, args),
    }
    if args.channel_selection == "unknown-report-both":
        outcome = "capture_contract_unknown"
        reason = (
            "No pre-capture physical wiring fact identifies the effective UR12 channel; "
            "both channels are reported and neither may be selected post hoc."
        )
    else:
        selected = channel_results[args.channel_selection]["outcome"]
        outcome = selected
        reason = f"Predeclared physical channel: {args.channel_selection}"

    localization = "capture_contract_unknown"
    if args.channel_selection != "unknown-report-both":
        selected_result = channel_results[args.channel_selection]
        source_runtime = selected_result.get("sourceRuntimeEvidence")
        if not isinstance(source_runtime, dict):
            localization = "source_runtime_evidence_missing"
        elif source_runtime.get("sourcePeriodMatchesManifest") is not True:
            localization = "generator_bug"
        elif source_runtime.get("playerTimeClockWithinTwoPercent") is not True:
            localization = "engine_clock"
        elif selected_result.get("outcome") == "contract_mismatch":
            mixer = selected_result.get("mixerTapEvidence")
            if not isinstance(mixer, dict) or mixer.get("status") != "measured":
                localization = "infra"
            elif mixer.get("periodWithinTwoPercent") is True:
                localization = "post_mixer_or_acoustic_capture"
            else:
                localization = "engine_graph"
        else:
            localization = "acoustic_result"

    result = {
        "schemaVersion": 1,
        "outcome": outcome,
        "channelSelectionRule": args.channel_selection,
        "channelSelectionReason": reason,
        "diagnosticLocalization": localization,
        "primaryCapture": {
            "path": str(args.stereo_wav.resolve()),
            "sha256": sha256(args.stereo_wav),
            "ffprobe": probe,
            "captureArgv": args.capture_argv.read_text().strip(),
            "ffmpegVersionSHA256": sha256(args.ffmpeg_version_file),
            "captureLogSHA256": sha256(args.capture_log),
            "frameZeroSHA256": sha256(args.frame_zero_file),
        },
        "derivedChannels": {
            "channel-1": {
                "path": str(args.channel_1_wav.resolve()),
                "sha256": sha256(args.channel_1_wav),
            },
            "channel-2": {
                "path": str(args.channel_2_wav.resolve()),
                "sha256": sha256(args.channel_2_wav),
            },
        },
        "channelRelationship": channel_relationship(stereo),
        "channelAnalyses": channel_results,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps(result, indent=2, sort_keys=True))
    return {
        "passed": 0,
        "acoustic_failed": 1,
        "contract_mismatch": 3,
        "capture_contract_unknown": 4,
    }.get(outcome, 2)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"stereo acoustic contract error: {error}", file=sys.stderr)
        raise SystemExit(2)
