#!/usr/bin/env python3
"""Analyze wall-clock-aligned UR12 recordings from Vision Pro XCTest attachments."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import statistics
import subprocess
import sys
import tempfile
import wave


MARKER_NAME = re.compile(r"^acoustic-(.+-(?:start|end))_\d+_")
TONE_MANIFEST_NAME = re.compile(r"^acoustic-tone-manifest_\d+_.*\.txt$")
TONE_MANIFEST_HASH_NAME = re.compile(r"^acoustic-tone-manifest-sha256_\d+_.*\.txt$")
SOURCE_ENVELOPE_NAME = re.compile(r"^acoustic-source-envelope_\d+_.*\.txt$")
RUNTIME_TIMELINE_NAME = re.compile(r"^acoustic-runtime-timeline_\d+_.*\.txt$")
MIXER_TAP_ENVELOPE_NAME = re.compile(r"^acoustic-mixer-tap-envelope_\d+_.*\.txt$")
MIXER_TAP_HASH_NAME = re.compile(r"^acoustic-mixer-tap-envelope-sha256_\d+_.*\.txt$")
PLAY_INTERVALS = ("initial-play", "resume", "seek-play")
PAUSE_INTERVALS = ("pause", "final-pause")
CALIBRATION_INTERVAL = "sample-buffer-calibration"
CALIBRATION_FREQUENCIES = (997.0, 1499.0)
CALIBRATION_PERIOD_SECONDS = 1.5
CALIBRATION_PHASES = (
    (997.0, 0.0, 0.5),
    (1499.0, 0.75, 1.25),
)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Measure Vision Pro XCUITest acoustic markers in a wall-clock-aligned "
            "PCM WAV recording. The default timeline mode preserves the existing "
            "play-versus-pause analysis."
        )
    )
    parser.add_argument(
        "--mode",
        choices=("timeline", "sample-buffer-calibration"),
        default="timeline",
    )
    parser.add_argument("--xcresult", type=Path)
    parser.add_argument("--wav", type=Path, required=True)
    parser.add_argument("--recording-start-wall-clock", type=float)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--minimum-play-over-pause-db", type=float, default=6.0)
    parser.add_argument("--edge-trim-seconds", type=float, default=0.25)
    parser.add_argument("--calibration-start-seconds", type=float)
    parser.add_argument("--calibration-end-seconds", type=float)
    parser.add_argument(
        "--calibration-marker-prefix",
        default=CALIBRATION_INTERVAL,
        help=(
            "Marker prefix for calibration start/end attachments "
            f"(default: {CALIBRATION_INTERVAL})"
        ),
    )
    parser.add_argument(
        "--calibration-statistic",
        choices=("whole-interval", "phase-aware"),
        default="whole-interval",
    )
    parser.add_argument("--phase-offset-step-seconds", type=float, default=0.025)
    parser.add_argument("--phase-tone-edge-trim-seconds", type=float, default=0.075)
    parser.add_argument("--phase-minimum-window-count", type=int, default=3)
    parser.add_argument("--phase-minimum-pass-fraction", type=float, default=0.8)
    parser.add_argument("--neighbor-offset-hz", type=float, default=25.0)
    parser.add_argument("--minimum-tone-over-neighbor-db", type=float, default=12.0)
    parser.add_argument(
        "--maximum-observed-period-deviation-fraction", type=float, default=0.02
    )
    parser.add_argument("--tone-manifest", type=Path)
    return parser.parse_args()


def export_attachments(result_bundle: Path, destination: Path) -> None:
    command = [
        "xcrun",
        "xcresulttool",
        "export",
        "attachments",
        "--path",
        str(result_bundle),
        "--output-path",
        str(destination),
    ]
    subprocess.run(command, check=True, stdout=subprocess.DEVNULL)


def load_acoustic_evidence(
    result_bundle: Path,
) -> tuple[
    dict[str, dict[str, object]],
    dict[str, object] | None,
    str | None,
    dict[str, object] | None,
    dict[str, object] | None,
    dict[str, object] | None,
    str | None,
]:
    with tempfile.TemporaryDirectory(prefix="enchron-acoustic-markers-") as directory:
        exported = Path(directory)
        export_attachments(result_bundle, exported)
        manifest = json.loads((exported / "manifest.json").read_text())
        markers: dict[str, dict[str, object]] = {}
        tone_manifests: list[dict[str, object]] = []
        tone_manifest_hashes: list[str] = []
        source_envelopes: list[dict[str, object]] = []
        runtime_timelines: list[dict[str, object]] = []
        mixer_tap_envelopes: list[dict[str, object]] = []
        mixer_tap_hashes: list[str] = []
        for test in manifest:
            for attachment in test.get("attachments", []):
                suggested = attachment.get("suggestedHumanReadableName", "")
                if TONE_MANIFEST_HASH_NAME.fullmatch(suggested):
                    content = (exported / attachment["exportedFileName"]).read_text()
                    tone_manifest_hashes.append(content.strip())
                    continue
                if TONE_MANIFEST_NAME.fullmatch(suggested):
                    content = (exported / attachment["exportedFileName"]).read_text()
                    decoded = json.loads(content)
                    if not isinstance(decoded, dict):
                        raise ValueError("AcousticToneManifest attachment is not a JSON object")
                    tone_manifests.append(decoded)
                    continue
                if SOURCE_ENVELOPE_NAME.fullmatch(suggested):
                    decoded = json.loads(
                        (exported / attachment["exportedFileName"]).read_text()
                    )
                    if not isinstance(decoded, dict):
                        raise ValueError("Acoustic source envelope is not a JSON object")
                    source_envelopes.append(decoded)
                    continue
                if RUNTIME_TIMELINE_NAME.fullmatch(suggested):
                    decoded = json.loads(
                        (exported / attachment["exportedFileName"]).read_text()
                    )
                    if not isinstance(decoded, dict):
                        raise ValueError("Acoustic runtime timeline is not a JSON object")
                    runtime_timelines.append(decoded)
                    continue
                if MIXER_TAP_HASH_NAME.fullmatch(suggested):
                    mixer_tap_hashes.append(
                        (exported / attachment["exportedFileName"]).read_text().strip()
                    )
                    continue
                if MIXER_TAP_ENVELOPE_NAME.fullmatch(suggested):
                    decoded = json.loads(
                        (exported / attachment["exportedFileName"]).read_text()
                    )
                    if not isinstance(decoded, dict):
                        raise ValueError("Acoustic mixer-tap envelope is not a JSON object")
                    mixer_tap_envelopes.append(decoded)
                    continue
                match = MARKER_NAME.match(suggested)
                if match is None:
                    continue
                marker_name = match.group(1)
                content = (exported / attachment["exportedFileName"]).read_text()
                wall_clock_text, separator, state = content.partition(";state=")
                if separator == "" or not wall_clock_text.startswith("wallClock="):
                    raise ValueError(f"Malformed acoustic marker: {suggested}")
                markers[marker_name] = {
                    "wallClock": float(wall_clock_text.removeprefix("wallClock=")),
                    "state": parse_state(state),
                }
        if len(tone_manifests) > 1:
            raise ValueError("Duplicate AcousticToneManifest attachments")
        if len(tone_manifest_hashes) > 1:
            raise ValueError("Duplicate AcousticToneManifest hash attachments")
        if len(source_envelopes) > 1:
            raise ValueError("Duplicate acoustic source-envelope attachments")
        if len(runtime_timelines) > 1:
            raise ValueError("Duplicate acoustic runtime-timeline attachments")
        if len(mixer_tap_envelopes) > 1:
            raise ValueError("Duplicate acoustic mixer-tap envelope attachments")
        if len(mixer_tap_hashes) > 1:
            raise ValueError("Duplicate acoustic mixer-tap hash attachments")
        return (
            markers,
            tone_manifests[0] if tone_manifests else None,
            tone_manifest_hashes[0] if tone_manifest_hashes else None,
            source_envelopes[0] if source_envelopes else None,
            runtime_timelines[0] if runtime_timelines else None,
            mixer_tap_envelopes[0] if mixer_tap_envelopes else None,
            mixer_tap_hashes[0] if mixer_tap_hashes else None,
        )


def load_markers(result_bundle: Path) -> dict[str, dict[str, object]]:
    return load_acoustic_evidence(result_bundle)[0]


def validate_tone_manifest(
    manifest: dict[str, object] | None,
    attached_hash: str | None,
    require_attached_hash: bool = True,
) -> dict[str, object]:
    if manifest is None:
        raise ValueError("Missing AcousticToneManifest attachment")
    source = manifest.get("sourceContract")
    if not isinstance(source, dict):
        raise ValueError("AcousticToneManifest has no sourceContract")
    canonical = json.dumps(source, sort_keys=True, separators=(",", ":")).encode()
    computed_hash = hashlib.sha256(canonical).hexdigest()
    declared_hash = manifest.get("sourceHash")
    if manifest.get("sourceHashAlgorithm") != "sha256-json-sorted-keys":
        raise ValueError("AcousticToneManifest hash algorithm is unsupported")
    if require_attached_hash and attached_hash is None:
        raise ValueError("Missing AcousticToneManifest hash attachment")
    if declared_hash != computed_hash or (
        attached_hash is not None and attached_hash != computed_hash
    ):
        raise ValueError("AcousticToneManifest source hash mismatch")
    required = {
        "schemaVersion": 1,
        "generatorID": "com.enchron.acoustic.dual-tone-cycle.v1",
        "sampleRate": 48_000,
        "totalFrames": 384_000,
        "cycleFrames": 72_000,
        "rampFrames": 480,
        "requestedPlaybackRate": "1.0",
    }
    for key, expected in required.items():
        if source.get(key) != expected:
            raise ValueError(
                f"AcousticToneManifest {key} mismatch: {source.get(key)!r} != {expected!r}"
            )
    phases = source.get("phases")
    expected_phases = [
        {"frequencyHz": 997, "startFrame": 0, "endFrame": 24_000},
        {"frequencyHz": 1_499, "startFrame": 36_000, "endFrame": 60_000},
    ]
    if phases != expected_phases:
        raise ValueError("AcousticToneManifest phase frame contract mismatch")
    runtime = manifest.get("runtime")
    if not isinstance(runtime, dict):
        raise ValueError("AcousticToneManifest has no runtime sample-rate observation")
    for key in ("engineOutputSampleRate", "mainMixerSampleRate"):
        value = runtime.get(key)
        if not isinstance(value, (int, float)) or not math.isfinite(value) or value <= 0:
            raise ValueError(f"AcousticToneManifest runtime {key} is invalid")
    return manifest


def validate_source_runtime_evidence(
    manifest: dict[str, object],
    source_envelope: dict[str, object] | None,
    runtime_timeline: dict[str, object] | None,
) -> dict[str, object] | None:
    scheduled = manifest.get("scheduledBufferEvidence")
    if scheduled is None:
        return None
    if not isinstance(scheduled, dict):
        raise ValueError("AcousticToneManifest scheduledBufferEvidence is malformed")
    if source_envelope is None:
        raise ValueError("Missing acoustic source-envelope attachment")
    if runtime_timeline is None:
        raise ValueError("Missing acoustic runtime-timeline attachment")
    if source_envelope != scheduled:
        raise ValueError("Source-envelope attachment does not match manifest evidence")
    if source_envelope.get("frameLength") != 384_000:
        raise ValueError("Scheduled source PCM frameLength mismatch")
    if source_envelope.get("formatSampleRate") != 48_000:
        raise ValueError("Scheduled source PCM sample rate mismatch")
    pcm_hash = source_envelope.get("sourcePCMHash")
    if not isinstance(pcm_hash, str) or not re.fullmatch(r"[0-9a-f]{64}", pcm_hash):
        raise ValueError("Scheduled source PCM hash is malformed")
    bursts = source_envelope.get("scannedBursts")
    if not isinstance(bursts, list) or not bursts:
        raise ValueError("Scheduled source PCM has no scanned burst evidence")
    by_frequency: dict[int, list[int]] = {997: [], 1499: []}
    for burst in bursts:
        if not isinstance(burst, dict):
            raise ValueError("Scheduled source burst is malformed")
        frequency = burst.get("frequencyHz")
        if frequency not in by_frequency:
            raise ValueError("Scheduled source burst has an unexpected frequency")
        start_frame = burst.get("startFrame")
        end_frame = burst.get("endFrame")
        if not isinstance(start_frame, int) or not isinstance(end_frame, int):
            raise ValueError("Scheduled source burst frame is malformed")
        if not 0 <= start_frame < end_frame <= 384_000:
            raise ValueError("Scheduled source burst frame range is invalid")
        by_frequency[frequency].append(start_frame)
    source_periods = {
        str(frequency): [
            later - earlier for earlier, later in zip(starts, starts[1:])
        ]
        for frequency, starts in by_frequency.items()
    }
    source_period_matches = all(
        periods and all(abs(period - 72_000) <= 480 for period in periods)
        for periods in source_periods.values()
    )

    session_id = runtime_timeline.get("calibrationSessionID")
    if session_id != manifest.get("calibrationSessionID"):
        raise ValueError("Runtime timeline calibrationSessionID mismatch")
    samples = runtime_timeline.get("samples")
    if not isinstance(samples, list) or len(samples) < 2:
        raise ValueError("Runtime timeline has too few samples")
    player_points = []
    for sample in samples:
        if not isinstance(sample, dict):
            raise ValueError("Runtime timeline sample is malformed")
        wall_clock = sample.get("wallClock")
        sample_time = sample.get("playerSampleTime")
        sample_rate = sample.get("playerSampleRate")
        if isinstance(wall_clock, (int, float)) and isinstance(
            sample_time, (int, float)
        ) and isinstance(sample_rate, (int, float)) and sample_rate > 0:
            player_points.append((float(wall_clock), float(sample_time), float(sample_rate)))
    if len(player_points) < 2:
        raise ValueError("Runtime timeline has too few playerTime observations")
    wall_mean = statistics.mean(point[0] for point in player_points)
    sample_mean = statistics.mean(point[1] for point in player_points)
    covariance = sum(
        (wall - wall_mean) * (sample - sample_mean)
        for wall, sample, _ in player_points
    )
    variance = sum((wall - wall_mean) ** 2 for wall, _, _ in player_points)
    slope = covariance / variance
    declared_runtime_rate = statistics.median(point[2] for point in player_points)
    slope_ratio = slope / declared_runtime_rate
    return {
        "sourcePCM": source_envelope,
        "sourceSameFrequencyPeriodsFrames": source_periods,
        "sourcePeriodMatchesManifest": source_period_matches,
        "runtimeTimeline": runtime_timeline,
        "playerTimeWallClockSlopeFramesPerSecond": slope,
        "playerTimeDeclaredSampleRate": declared_runtime_rate,
        "playerTimeWallClockRateRatio": slope_ratio,
        "playerTimeClockWithinTwoPercent": abs(slope_ratio - 1.0) <= 0.02,
    }


def validate_mixer_tap_evidence(
    manifest: dict[str, object],
    envelope: dict[str, object] | None,
    attached_hash: str | None,
) -> dict[str, object]:
    if envelope is None or attached_hash is None:
        return {"status": "infra", "reason": "missing mixer tap envelope or hash"}
    canonical = json.dumps(envelope, sort_keys=True, separators=(",", ":")).encode()
    if not re.fullmatch(r"[0-9a-f]{64}", attached_hash) or (
        hashlib.sha256(canonical).hexdigest() != attached_hash
    ):
        return {"status": "infra", "reason": "mixer tap envelope hash mismatch"}
    if envelope.get("schemaVersion") != 1:
        return {"status": "infra", "reason": "unsupported mixer tap schema"}
    if envelope.get("calibrationSessionID") != manifest.get("calibrationSessionID"):
        return {"status": "infra", "reason": "mixer tap session mismatch"}
    if envelope.get("finished") is not True or envelope.get("callbackCount", 0) <= 0:
        return {"status": "infra", "reason": "mixer tap did not complete"}
    callbacks = envelope.get("callbacks")
    if not isinstance(callbacks, list) or not callbacks:
        return {"status": "infra", "reason": "mixer tap callbacks are missing"}
    buffer_rates = {callback.get("bufferSampleRate") for callback in callbacks}
    channel_counts = {callback.get("bufferChannelCount") for callback in callbacks}
    audio_time_rates = {callback.get("audioTimeSampleRate") for callback in callbacks}
    if len(buffer_rates) != 1 or len(channel_counts) != 1:
        return {"status": "infra", "reason": "mixer callback format changed within session"}
    sample_rate = next(iter(buffer_rates))
    channels = next(iter(channel_counts))
    if not isinstance(sample_rate, (int, float)) or sample_rate <= 0:
        return {"status": "infra", "reason": "mixer callback sample rate is invalid"}
    if not isinstance(channels, int) or channels <= 0:
        return {"status": "infra", "reason": "mixer callback channel count is invalid"}
    if audio_time_rates != {sample_rate}:
        return {"status": "infra", "reason": "AVAudioTime and buffer sample rates disagree"}
    callback_frames = [callback.get("bufferFrameLength") for callback in callbacks]
    if not all(isinstance(value, int) and value > 0 for value in callback_frames):
        return {"status": "infra", "reason": "mixer callback frameLength is invalid"}
    if sum(callback_frames) != envelope.get("totalFrames"):
        return {"status": "infra", "reason": "mixer callback frame total mismatch"}
    if envelope.get("discontinuityCount") != 0 or envelope.get("overrunCount") != 0:
        return {"status": "infra", "reason": "mixer callback continuity gate failed"}
    clock_points = [
        (callback.get("hostTimeSeconds"), callback.get("sampleTime"))
        for callback in callbacks
        if isinstance(callback.get("hostTimeSeconds"), (int, float))
        and isinstance(callback.get("sampleTime"), int)
    ]
    if len(clock_points) < 2:
        return {"status": "infra", "reason": "mixer callback clock evidence is missing"}
    host_mean = statistics.mean(point[0] for point in clock_points)
    sample_mean = statistics.mean(point[1] for point in clock_points)
    covariance = sum(
        (host - host_mean) * (sample - sample_mean)
        for host, sample in clock_points
    )
    variance = sum((host - host_mean) ** 2 for host, _ in clock_points)
    frame_host_slope = covariance / variance
    frame_host_ratio = frame_host_slope / float(sample_rate)
    if abs(frame_host_ratio - 1.0) > 0.02:
        return {"status": "infra", "reason": "mixer frames and host clock disagree"}
    bursts = envelope.get("bursts")
    if not isinstance(bursts, list) or len(bursts) < 4:
        return {"status": "infra", "reason": "mixer tap has too few bursts"}
    starts: dict[int, list[int]] = {997: [], 1499: []}
    host_starts: dict[int, list[float]] = {997: [], 1499: []}
    for burst in bursts:
        if not isinstance(burst, dict):
            return {"status": "infra", "reason": "malformed mixer tap burst"}
        label = burst.get("frequencyHz")
        sample_time = burst.get("startSampleTime")
        host_seconds = burst.get("startHostTimeSeconds")
        if label not in (997, 1499):
            return {"status": "infra", "reason": "mixer tap burst frequency is invalid"}
        if not isinstance(sample_time, int):
            return {"status": "infra", "reason": "mixer tap burst lacks sample time"}
        if not isinstance(host_seconds, (int, float)):
            return {"status": "infra", "reason": "mixer tap burst lacks host time"}
        starts[label].append(sample_time)
        host_starts[label].append(float(host_seconds))
    periods = {
        str(frequency): [later - earlier for earlier, later in zip(values, values[1:])]
        for frequency, values in starts.items()
    }
    period_values = [period for values in periods.values() for period in values]
    host_periods = {
        str(frequency): [later - earlier for earlier, later in zip(values, values[1:])]
        for frequency, values in host_starts.items()
    }
    host_period_values = [period for values in host_periods.values() for period in values]
    if not period_values:
        return {"status": "infra", "reason": "mixer tap has no repeated bursts"}
    observed_frames = statistics.median(period_values)
    observed_seconds = observed_frames / float(sample_rate)
    observed_host_seconds = statistics.median(host_period_values)
    if abs(observed_seconds - observed_host_seconds) / CALIBRATION_PERIOD_SECONDS > 0.02:
        return {"status": "infra", "reason": "mixer burst sample and host periods disagree"}
    deviation = abs(observed_seconds / CALIBRATION_PERIOD_SECONDS - 1.0)
    pre_start = envelope.get("preStartBusFormat")
    pre_start_rate = pre_start.get("sampleRate") if isinstance(pre_start, dict) else None
    return {
        "status": "measured",
        "sampleRate": sample_rate,
        "channelCount": channels,
        "preStartBusFormat": pre_start,
        "runtimeFormatTransition": pre_start_rate != sample_rate,
        "callbackCount": envelope.get("callbackCount"),
        "totalFrames": envelope.get("totalFrames"),
        "discontinuityCount": envelope.get("discontinuityCount"),
        "overrunCount": envelope.get("overrunCount"),
        "sameFrequencyPeriodsFrames": periods,
        "sameFrequencyPeriodsHostSeconds": host_periods,
        "observedPeriodSeconds": observed_seconds,
        "observedHostPeriodSeconds": observed_host_seconds,
        "frameHostSlopeFramesPerSecond": frame_host_slope,
        "frameHostRateRatio": frame_host_ratio,
        "periodDeviationFraction": deviation,
        "periodWithinTwoPercent": deviation <= 0.02,
    }


def parse_state(raw_value: str) -> dict[str, str]:
    state: dict[str, str] = {}
    for item in raw_value.strip().split(";"):
        key, separator, value = item.partition("=")
        if separator:
            state[key] = value
    return state


def decode_sample(sample: bytes, sample_width: int) -> int:
    if sample_width == 1:
        return sample[0] - 128
    return int.from_bytes(sample, byteorder="little", signed=True)


def read_window(
    audio: wave.Wave_read,
    start_seconds: float,
    end_seconds: float,
) -> tuple[list[float], int, int, int, int, int]:
    frame_rate = audio.getframerate()
    channels = audio.getnchannels()
    sample_width = audio.getsampwidth()
    frame_count = audio.getnframes()
    start_frame = max(0, min(frame_count, round(start_seconds * frame_rate)))
    end_frame = max(start_frame, min(frame_count, round(end_seconds * frame_rate)))
    audio.setpos(start_frame)
    raw = audio.readframes(end_frame - start_frame)
    frame_stride = sample_width * channels
    available_frames = len(raw) // frame_stride
    if available_frames == 0:
        raise ValueError("Acoustic interval contains no recorded samples")
    full_scale = float(1 << (sample_width * 8 - 1))
    samples: list[float] = []
    for frame in range(available_frames):
        offset = frame * frame_stride
        mixed = sum(
            decode_sample(
                raw[offset + channel * sample_width : offset + (channel + 1) * sample_width],
                sample_width,
            )
            for channel in range(channels)
        ) / channels
        samples.append(mixed / full_scale)
    return samples, frame_rate, channels, start_frame, start_frame + available_frames, sample_width


def summarize_window(
    samples: list[float],
    frame_rate: int,
    channels: int,
    start_frame: int,
    end_frame: int,
) -> dict[str, float]:
    rms = math.sqrt(sum(sample * sample for sample in samples) / len(samples))
    peak = max(abs(sample) for sample in samples)
    return {
        "startSeconds": start_frame / frame_rate,
        "endSeconds": end_frame / frame_rate,
        "durationSeconds": (end_frame - start_frame) / frame_rate,
        "rmsDBFS": decibels(rms),
        "peakDBFS": decibels(peak),
        "channels": channels,
    }


def measure_window(
    audio: wave.Wave_read,
    start_seconds: float,
    end_seconds: float,
) -> dict[str, float]:
    samples, frame_rate, channels, start_frame, end_frame, _ = read_window(
        audio, start_seconds, end_seconds
    )
    return summarize_window(samples, frame_rate, channels, start_frame, end_frame)


def decibels(value: float) -> float:
    return 20 * math.log10(max(value, 1e-12))


def spectral_energy_dbfs(
    samples: list[float], sample_rate: int, frequency_hz: float
) -> float:
    if frequency_hz <= 0 or frequency_hz >= sample_rate / 2:
        raise ValueError(f"Frequency {frequency_hz} Hz is outside the WAV Nyquist range")
    coefficient = 2 * math.cos(2 * math.pi * frequency_hz / sample_rate)
    previous = 0.0
    previous_previous = 0.0
    for sample in samples:
        current = sample + coefficient * previous - previous_previous
        previous_previous = previous
        previous = current
    power = previous_previous * previous_previous + previous * previous - coefficient * previous * previous_previous
    coherent_power = max(power, 0.0) / (len(samples) * len(samples))
    return 10 * math.log10(max(coherent_power, 1e-24))


def measure_calibration_frequencies(
    samples: list[float],
    sample_rate: int,
    neighbor_offset_hz: float,
    minimum_tone_over_neighbor_db: float,
) -> tuple[list[dict[str, object]], list[str]]:
    if neighbor_offset_hz <= 0:
        raise ValueError("neighbor offset must be greater than zero")
    measurements: list[dict[str, object]] = []
    failures: list[str] = []
    for frequency_hz in CALIBRATION_FREQUENCIES:
        measurement = measure_calibration_frequency(
            samples,
            sample_rate,
            frequency_hz,
            neighbor_offset_hz,
        )
        measurements.append(measurement)
        if measurement["toneOverNeighborDB"] < minimum_tone_over_neighbor_db:
            failures.append(
                f"{frequency_hz:g} Hz is only "
                f"{measurement['toneOverNeighborDB']:.2f} dB above its neighboring references"
            )
    return measurements, failures


def measure_calibration_frequency(
    samples: list[float],
    sample_rate: int,
    frequency_hz: float,
    neighbor_offset_hz: float,
) -> dict[str, object]:
    tone_energy = spectral_energy_dbfs(samples, sample_rate, frequency_hz)
    neighbor_frequencies = (
        frequency_hz - neighbor_offset_hz,
        frequency_hz + neighbor_offset_hz,
    )
    neighbor_energies = [
        spectral_energy_dbfs(samples, sample_rate, neighbor)
        for neighbor in neighbor_frequencies
    ]
    neighbor_reference = max(neighbor_energies)
    return {
        "frequencyHz": frequency_hz,
        "toneEnergyDBFS": tone_energy,
        "neighborFrequenciesHz": list(neighbor_frequencies),
        "neighborEnergiesDBFS": neighbor_energies,
        "neighborReferenceDBFS": neighbor_reference,
        "toneOverNeighborDB": tone_energy - neighbor_reference,
    }


def interval(
    markers: dict[str, dict[str, object]],
    name: str,
    recording_start: float,
    edge_trim: float,
) -> tuple[float, float, dict[str, str]]:
    start_marker = markers[f"{name}-start"]
    end_marker = markers[f"{name}-end"]
    start = float(start_marker["wallClock"]) - recording_start + edge_trim
    end = float(end_marker["wallClock"]) - recording_start - edge_trim
    if end <= start:
        raise ValueError(f"Acoustic interval {name} is empty after edge trimming")
    return start, end, start_marker["state"]  # type: ignore[return-value]


def require_timeline_inputs(arguments: argparse.Namespace) -> None:
    if arguments.xcresult is None or arguments.recording_start_wall_clock is None:
        raise ValueError(
            "timeline mode requires --xcresult and --recording-start-wall-clock"
        )


def analyze_timeline(arguments: argparse.Namespace) -> dict[str, object]:
    require_timeline_inputs(arguments)
    assert arguments.xcresult is not None
    assert arguments.recording_start_wall_clock is not None
    markers = load_markers(arguments.xcresult)
    required = {
        f"{name}-{boundary}"
        for name in PLAY_INTERVALS + PAUSE_INTERVALS
        for boundary in ("start", "end")
    }
    missing = sorted(required - markers.keys())
    if missing:
        raise ValueError(f"Missing acoustic markers: {', '.join(missing)}")

    measurements: dict[str, dict[str, object]] = {}
    with wave.open(str(arguments.wav), "rb") as audio:
        if audio.getcomptype() != "NONE":
            raise ValueError(f"WAV must contain PCM audio, found {audio.getcomptype()}")
        for name in PLAY_INTERVALS + PAUSE_INTERVALS:
            start, end, state = interval(
                markers,
                name,
                arguments.recording_start_wall_clock,
                arguments.edge_trim_seconds,
            )
            measurement: dict[str, object] = measure_window(audio, start, end)
            measurement["state"] = state
            measurements[name] = measurement

    pause_levels = sorted(
        float(measurements[name]["rmsDBFS"]) for name in PAUSE_INTERVALS
    )
    pause_reference = sum(pause_levels) / len(pause_levels)
    failures: list[str] = []
    for name in PLAY_INTERVALS:
        play_level = float(measurements[name]["rmsDBFS"])
        delta = play_level - pause_reference
        measurements[name]["playOverPauseDB"] = delta
        if delta < arguments.minimum_play_over_pause_db:
            failures.append(
                f"{name} is only {delta:.2f} dB above the pause reference"
            )

    return {
        "schemaVersion": 1,
        "xcresult": str(arguments.xcresult.resolve()),
        "wav": str(arguments.wav.resolve()),
        "recordingStartWallClock": arguments.recording_start_wall_clock,
        "pauseReferenceDBFS": pause_reference,
        "minimumPlayOverPauseDB": arguments.minimum_play_over_pause_db,
        "intervals": measurements,
        "outcome": "passed" if not failures else "failed",
        "failures": failures,
    }


def calibration_window(
    arguments: argparse.Namespace,
) -> tuple[float, float, dict[str, object], str, dict[str, object] | None]:
    explicit_start = arguments.calibration_start_seconds
    explicit_end = arguments.calibration_end_seconds
    if (explicit_start is None) != (explicit_end is None):
        raise ValueError(
            "provide both --calibration-start-seconds and --calibration-end-seconds"
        )
    if explicit_start is not None and explicit_end is not None:
        start = explicit_start + arguments.edge_trim_seconds
        end = explicit_end - arguments.edge_trim_seconds
        if end <= start:
            raise ValueError("Explicit calibration interval is empty after edge trimming")
        manifest_path = getattr(arguments, "tone_manifest", None)
        manifest = json.loads(manifest_path.read_text()) if manifest_path else None
        return start, end, {}, "explicit-seconds", manifest

    if arguments.xcresult is None or arguments.recording_start_wall_clock is None:
        raise ValueError(
            "sample-buffer-calibration mode needs either explicit interval seconds or "
            "--xcresult with --recording-start-wall-clock"
        )
    (
        markers,
        manifest,
        attached_hash,
        source_envelope,
        runtime_timeline,
        mixer_tap_envelope,
        mixer_tap_hash,
    ) = (
        load_acoustic_evidence(arguments.xcresult)
    )
    if manifest is not None:
        manifest["_attachedHash"] = attached_hash
        manifest["_sourceEnvelope"] = source_envelope
        manifest["_runtimeTimeline"] = runtime_timeline
        manifest["_mixerTapEnvelope"] = mixer_tap_envelope
        manifest["_mixerTapHash"] = mixer_tap_hash
    marker_prefix = arguments.calibration_marker_prefix
    required = {f"{marker_prefix}-{boundary}" for boundary in ("start", "end")}
    missing = sorted(required - markers.keys())
    if missing:
        raise ValueError(
            "Missing sample-buffer calibration markers; provide explicit interval seconds "
            f"or attach {', '.join(missing)}"
        )
    start, end, state = interval(
        markers,
        marker_prefix,
        arguments.recording_start_wall_clock,
        arguments.edge_trim_seconds,
    )
    return start, end, state, "xcresult-markers", manifest


def analyze_whole_interval_calibration(
    arguments: argparse.Namespace,
) -> dict[str, object]:
    start, end, state, alignment, _ = calibration_window(arguments)
    with wave.open(str(arguments.wav), "rb") as audio:
        if audio.getcomptype() != "NONE":
            raise ValueError(f"WAV must contain PCM audio, found {audio.getcomptype()}")
        samples, sample_rate, channels, start_frame, end_frame, _ = read_window(
            audio, start, end
        )
    interval_measurement: dict[str, object] = summarize_window(
        samples, sample_rate, channels, start_frame, end_frame
    )
    interval_measurement["state"] = state
    frequency_measurements, failures = measure_calibration_frequencies(
        samples,
        sample_rate,
        arguments.neighbor_offset_hz,
        arguments.minimum_tone_over_neighbor_db,
    )
    return {
        "schemaVersion": 1,
        "analysisMode": "sample-buffer-calibration",
        "xcresult": str(arguments.xcresult.resolve()) if arguments.xcresult else None,
        "wav": str(arguments.wav.resolve()),
        "recordingStartWallClock": arguments.recording_start_wall_clock,
        "alignment": alignment,
        "edgeTrimSeconds": arguments.edge_trim_seconds,
        "interval": interval_measurement,
        "frequencies": frequency_measurements,
        "minimumToneOverNeighborDB": arguments.minimum_tone_over_neighbor_db,
        "neighborOffsetHz": arguments.neighbor_offset_hz,
        "outcome": "passed" if not failures else "failed",
        "failures": failures,
    }


def observed_envelope_affine_fit(
    samples: list[float],
    sample_rate: int,
    interval_start: float,
    period_seconds: float,
    phases: list[tuple[float, float, float]],
    neighbor_offset_hz: float,
) -> dict[str, object]:
    window_frames = max(1, round(sample_rate * 0.10))
    hop_frames = max(1, round(sample_rate * 0.02))
    phase_by_frequency = {frequency: phase_start for frequency, phase_start, _ in phases}
    frequencies = list(phase_by_frequency)
    candidates = []
    for start_frame in range(0, max(1, len(samples) - window_frames + 1), hop_frames):
        window = samples[start_frame : start_frame + window_frames]
        band_peaks = {}
        for frequency in frequencies:
            peak_frequency, peak_energy = max(
                (
                    (candidate, spectral_energy_dbfs(window, sample_rate, candidate))
                    for candidate in range(round(frequency - 20), round(frequency + 21))
                ),
                key=lambda item: item[1],
            )
            side_reference = max(
                spectral_energy_dbfs(window, sample_rate, frequency - neighbor_offset_hz),
                spectral_energy_dbfs(window, sample_rate, frequency + neighbor_offset_hz),
            )
            band_peaks[frequency] = (peak_frequency, peak_energy, side_reference)
        winner = max(frequencies, key=lambda frequency: band_peaks[frequency][1])
        other_peak = max(
            band_peaks[frequency][1] for frequency in frequencies if frequency != winner
        )
        peak_frequency, peak_energy, side_reference = band_peaks[winner]
        label = winner if (
            peak_energy - other_peak >= 3.0
            and peak_energy - side_reference >= 3.0
        ) else None
        candidates.append(
            {
                "time": start_frame / sample_rate,
                "label": label,
                "peakFrequencyHz": float(peak_frequency),
                "peakEnergyDBFS": peak_energy,
            }
        )

    detected: dict[float, list[dict[str, float]]] = {frequency: [] for frequency in frequencies}
    for frequency in frequencies:
        run_start = None
        last_same = None
        peak_frequencies = []
        for candidate in candidates + [{"time": len(samples) / sample_rate, "label": -1}]:
            label = candidate["label"]
            time = float(candidate["time"])
            if label == frequency:
                if run_start is None:
                    run_start = time
                last_same = time
                peak_frequencies.append(float(candidate["peakFrequencyHz"]))
                continue
            if run_start is None:
                continue
            # Only an unlabeled dropout may be bridged. Seeing the competing tone
            # always terminates this frequency's burst.
            if label is None and last_same is not None and time - last_same <= 0.16:
                continue
            assert last_same is not None
            offset = last_same + 0.10
            if offset - run_start >= 0.18:
                start_index = round(run_start * sample_rate)
                end_index = round(offset * sample_rate)
                interior = samples[start_index:end_index]
                detected[frequency].append(
                    {
                        "onsetSeconds": interval_start + run_start,
                        "offsetSeconds": interval_start + offset,
                        "durationSeconds": offset - run_start,
                        "mainPeakFrequencyHz": statistics.median(peak_frequencies),
                        "targetEnergyDBFS": spectral_energy_dbfs(
                            interior, sample_rate, frequency
                        ),
                        "rmsDBFS": decibels(
                            math.sqrt(sum(value * value for value in interior) / len(interior))
                        ),
                        "peakDBFS": decibels(max(abs(value) for value in interior)),
                    }
                )
            run_start = None
            last_same = None
            peak_frequencies = []

    observed_events = sorted(
        (
            float(burst["onsetSeconds"]),
            frequency,
            burst,
        )
        for frequency in frequencies
        for burst in detected[frequency]
    )
    if len(observed_events) < 4:
        return {
            "method": "competing local-peak envelope detection followed by penalized RANSAC sequence matching",
            "status": "insufficient_bursts",
            "periodDeviationFraction": None,
            "bursts": [
                {"frequencyHz": frequency, "observations": detected[frequency]}
                for frequency, _, _ in phases
            ],
        }
    expected_events = [
        (phase_start + cycle * period_seconds, frequency)
        for cycle in range(10)
        for frequency, phase_start, _ in phases
    ]
    hypotheses = []
    for first_index, first in enumerate(observed_events):
        for second in observed_events[first_index + 1 :]:
            for expected_first_index, expected_first in enumerate(expected_events):
                if expected_first[1] != first[1]:
                    continue
                for expected_second in expected_events[expected_first_index + 1 :]:
                    if expected_second[1] != second[1]:
                        continue
                    expected_delta = expected_second[0] - expected_first[0]
                    if expected_delta <= 0:
                        continue
                    scale = (second[0] - first[0]) / expected_delta
                    if not 0.5 <= scale <= 1.5:
                        continue
                    offset = first[0] - scale * expected_first[0]
                    transformed = [
                        (offset + scale * expected, frequency, expected)
                        for expected, frequency in expected_events
                    ]
                    minimum = observed_events[0][0] - 0.30
                    maximum = observed_events[-1][0] + 0.30
                    transformed = [
                        event for event in transformed if minimum <= event[0] <= maximum
                    ]
                    matches = []
                    used = set()
                    for observed_time, observed_frequency, _ in observed_events:
                        choices = [
                            (abs(observed_time - expected_time), index, expected_phase)
                            for index, (expected_time, expected_frequency, expected_phase)
                            in enumerate(transformed)
                            if index not in used and expected_frequency == observed_frequency
                        ]
                        if not choices:
                            continue
                        residual, index, expected_phase = min(choices)
                        if residual <= 0.22:
                            used.add(index)
                            matches.append((expected_phase, observed_time, residual))
                    missing = len(transformed) - len(used)
                    extra = len(observed_events) - len(matches)
                    penalty = 0.30 * (missing + extra)
                    cost = sum(match[2] for match in matches) + penalty
                    hypotheses.append((cost, -len(matches), scale, offset, matches, missing, extra))
    if not hypotheses:
        raise ValueError("Observed envelope RANSAC found no labeled sequence hypothesis")
    _, _, _, _, seed_matches, missing, extra = min(hypotheses)
    expected_mean = statistics.mean(match[0] for match in seed_matches)
    observed_mean = statistics.mean(match[1] for match in seed_matches)
    covariance = sum(
        (expected - expected_mean) * (observed - observed_mean)
        for expected, observed, _ in seed_matches
    )
    variance = sum((expected - expected_mean) ** 2 for expected, _, _ in seed_matches)
    scale = covariance / variance
    offset = observed_mean - scale * expected_mean
    residuals = [
        observed - (offset + scale * expected)
        for expected, observed, _ in seed_matches
    ]
    return {
        "method": "competing local-peak envelope detection followed by penalized RANSAC sequence matching",
        "offsetSeconds": offset,
        "scale": scale,
        "observedPeriodSeconds": period_seconds * scale,
        "periodDeviationFraction": abs(scale - 1.0),
        "residualRMSSeconds": math.sqrt(
            sum(residual * residual for residual in residuals) / len(residuals)
        ),
        "matchedBurstCount": len(seed_matches),
        "missingBurstPenaltyCount": missing,
        "extraBurstPenaltyCount": extra,
        "bursts": [
            {"frequencyHz": frequency, "observations": detected[frequency]}
            for frequency, _, _ in phases
        ],
    }


def analyze_phase_aware_calibration(
    arguments: argparse.Namespace,
) -> dict[str, object]:
    start, end, state, alignment, raw_manifest = calibration_window(arguments)
    attached_hash = None
    source_envelope = None
    runtime_timeline = None
    mixer_tap_envelope = None
    mixer_tap_hash = None
    if raw_manifest is not None:
        attached_hash = raw_manifest.pop("_attachedHash", None)
        source_envelope = raw_manifest.pop("_sourceEnvelope", None)
        runtime_timeline = raw_manifest.pop("_runtimeTimeline", None)
        mixer_tap_envelope = raw_manifest.pop("_mixerTapEnvelope", None)
        mixer_tap_hash = raw_manifest.pop("_mixerTapHash", None)
    manifest = validate_tone_manifest(
        raw_manifest,
        attached_hash,
        require_attached_hash=alignment == "xcresult-markers",
    )
    source_runtime = validate_source_runtime_evidence(
        manifest, source_envelope, runtime_timeline
    )
    mixer_tap = validate_mixer_tap_evidence(
        manifest, mixer_tap_envelope, mixer_tap_hash
    ) if alignment == "xcresult-markers" else None
    source_contract = manifest["sourceContract"]
    assert isinstance(source_contract, dict)
    declared_sample_rate = float(source_contract["sampleRate"])
    declared_period = float(source_contract["cycleFrames"]) / declared_sample_rate
    declared_phases = [
        (
            float(phase["frequencyHz"]),
            float(phase["startFrame"]) / declared_sample_rate,
            float(phase["endFrame"]) / declared_sample_rate,
        )
        for phase in source_contract["phases"]
    ]
    if arguments.phase_offset_step_seconds <= 0:
        raise ValueError("phase offset step must be greater than zero")
    if not 0 < arguments.phase_tone_edge_trim_seconds < 0.25:
        raise ValueError("phase tone edge trim must be between zero and 0.25 seconds")
    if arguments.phase_minimum_window_count <= 0:
        raise ValueError("phase minimum window count must be greater than zero")
    if not 0 < arguments.phase_minimum_pass_fraction <= 1:
        raise ValueError("phase minimum pass fraction must be in (0, 1]")

    with wave.open(str(arguments.wav), "rb") as audio:
        if audio.getcomptype() != "NONE":
            raise ValueError(f"WAV must contain PCM audio, found {audio.getcomptype()}")
        samples, sample_rate, channels, start_frame, end_frame, _ = read_window(
            audio, start, end
        )

    interval_measurement: dict[str, object] = summarize_window(
        samples, sample_rate, channels, start_frame, end_frame
    )
    interval_measurement["state"] = state
    actual_start = start_frame / sample_rate
    actual_end = end_frame / sample_rate
    candidates: list[dict[str, object]] = []
    offset_index = 0
    while True:
        offset = offset_index * arguments.phase_offset_step_seconds
        if offset >= declared_period - 1e-12:
            break
        frequency_results: list[dict[str, object]] = []
        for frequency_hz, phase_start, phase_end in declared_phases:
            windows: list[dict[str, object]] = []
            cycle_index = 0
            while True:
                window_start = (
                    actual_start
                    + offset
                    + cycle_index * declared_period
                    + phase_start
                    + arguments.phase_tone_edge_trim_seconds
                )
                window_end = (
                    actual_start
                    + offset
                    + cycle_index * CALIBRATION_PERIOD_SECONDS
                    + phase_end
                    - arguments.phase_tone_edge_trim_seconds
                )
                if window_end > actual_end + 1e-12:
                    break
                relative_start = round(window_start * sample_rate) - start_frame
                relative_end = round(window_end * sample_rate) - start_frame
                window_samples = samples[relative_start:relative_end]
                measurement = measure_calibration_frequency(
                    window_samples,
                    sample_rate,
                    frequency_hz,
                    arguments.neighbor_offset_hz,
                )
                windows.append(
                    {
                        "cycleIndex": cycle_index,
                        "startSeconds": window_start,
                        "endSeconds": window_end,
                        **measurement,
                        "passed": measurement["toneOverNeighborDB"]
                        >= arguments.minimum_tone_over_neighbor_db,
                    }
                )
                cycle_index += 1
            ratios = [float(window["toneOverNeighborDB"]) for window in windows]
            passing_count = sum(bool(window["passed"]) for window in windows)
            frequency_results.append(
                {
                    "frequencyHz": frequency_hz,
                    "windowCount": len(windows),
                    "passingWindowCount": passing_count,
                    "passFraction": passing_count / len(windows) if windows else 0.0,
                    "medianToneOverNeighborDB": (
                        statistics.median(ratios) if ratios else None
                    ),
                    "minimumToneOverNeighborDB": min(ratios) if ratios else None,
                    "windows": windows,
                }
            )
        eligible = all(
            result["windowCount"] >= arguments.phase_minimum_window_count
            for result in frequency_results
        )
        candidates.append(
            {
                "offsetSeconds": offset,
                "eligible": eligible,
                "frequencies": frequency_results,
            }
        )
        offset_index += 1

    eligible_candidates = [candidate for candidate in candidates if candidate["eligible"]]
    if not eligible_candidates:
        raise ValueError(
            "No phase offset produced enough complete repeated tone windows"
        )

    def candidate_score(candidate: dict[str, object]) -> tuple[float, float, float]:
        frequency_results = candidate["frequencies"]
        assert isinstance(frequency_results, list)
        pass_floor = min(float(result["passFraction"]) for result in frequency_results)
        median_floor = min(
            float(result["medianToneOverNeighborDB"])
            for result in frequency_results
        )
        return pass_floor, median_floor, -float(candidate["offsetSeconds"])

    selected = max(eligible_candidates, key=candidate_score)
    selected_frequencies = selected["frequencies"]
    assert isinstance(selected_frequencies, list)
    failures: list[str] = []
    for result in selected_frequencies:
        if result["passFraction"] < arguments.phase_minimum_pass_fraction:
            failures.append(
                f"{result['frequencyHz']:g} Hz passed "
                f"{result['passingWindowCount']}/{result['windowCount']} repeated windows "
                f"({result['passFraction']:.1%}), below the required "
                f"{arguments.phase_minimum_pass_fraction:.1%}"
            )

    observed_fit = observed_envelope_affine_fit(
        samples,
        sample_rate,
        actual_start,
        declared_period,
        declared_phases,
        arguments.neighbor_offset_hz,
    )
    observed_deviation = observed_fit["periodDeviationFraction"]
    contract_mismatch = observed_deviation is not None and (
        observed_deviation > arguments.maximum_observed_period_deviation_fraction
    )
    if contract_mismatch:
        failures.insert(
            0,
            "Observed envelope period differs from AcousticToneManifest by "
            f"{observed_fit['periodDeviationFraction']:.2%}, above the allowed "
            f"{arguments.maximum_observed_period_deviation_fraction:.2%}",
        )

    candidate_summaries = []
    for candidate in candidates:
        summaries = []
        for result in candidate["frequencies"]:
            summaries.append(
                {
                    "frequencyHz": result["frequencyHz"],
                    "windowCount": result["windowCount"],
                    "passingWindowCount": result["passingWindowCount"],
                    "passFraction": result["passFraction"],
                    "medianToneOverNeighborDB": result["medianToneOverNeighborDB"],
                }
            )
        candidate_summaries.append(
            {
                "offsetSeconds": candidate["offsetSeconds"],
                "eligible": candidate["eligible"],
                "frequencies": summaries,
            }
        )

    return {
        "schemaVersion": 1,
        "analysisMode": "sample-buffer-calibration",
        "calibrationStatistic": "phase-aware",
        "xcresult": str(arguments.xcresult.resolve()) if arguments.xcresult else None,
        "wav": str(arguments.wav.resolve()),
        "recordingStartWallClock": arguments.recording_start_wall_clock,
        "alignment": alignment,
        "edgeTrimSeconds": arguments.edge_trim_seconds,
        "interval": interval_measurement,
        "acousticToneManifest": manifest,
        "sourceRuntimeEvidence": source_runtime,
        "mixerTapEvidence": mixer_tap,
        "observedEnvelopeAffineFit": observed_fit,
        "maximumObservedPeriodDeviationFraction": (
            arguments.maximum_observed_period_deviation_fraction
        ),
        "phaseModel": {
            "periodSeconds": declared_period,
            "toneEdgeTrimSeconds": arguments.phase_tone_edge_trim_seconds,
            "phases": [
                {
                    "frequencyHz": frequency_hz,
                    "startSeconds": phase_start,
                    "endSeconds": phase_end,
                }
                for frequency_hz, phase_start, phase_end in declared_phases
            ],
        },
        "offsetSearch": {
            "rangeStartSeconds": 0.0,
            "rangeEndExclusiveSeconds": declared_period,
            "stepSeconds": arguments.phase_offset_step_seconds,
            "candidateCount": len(candidates),
            "selectionRule": (
                "maximize the lower per-frequency pass fraction, then the lower "
                "per-frequency median tone-over-neighbor, then choose the earliest offset"
            ),
            "candidates": candidate_summaries,
            "selectedOffsetSeconds": selected["offsetSeconds"],
        },
        "minimumWindowCountPerFrequency": arguments.phase_minimum_window_count,
        "minimumPassFractionPerFrequency": arguments.phase_minimum_pass_fraction,
        "minimumToneOverNeighborDB": arguments.minimum_tone_over_neighbor_db,
        "neighborOffsetHz": arguments.neighbor_offset_hz,
        "frequencies": selected_frequencies,
        "outcome": (
            "contract_mismatch"
            if contract_mismatch
            else ("passed" if not failures else "acoustic_failed")
        ),
        "failures": failures,
    }


def analyze_sample_buffer_calibration(arguments: argparse.Namespace) -> dict[str, object]:
    if arguments.calibration_statistic == "phase-aware":
        return analyze_phase_aware_calibration(arguments)
    return analyze_whole_interval_calibration(arguments)


def analyze(arguments: argparse.Namespace) -> dict[str, object]:
    if arguments.mode == "timeline":
        return analyze_timeline(arguments)
    return analyze_sample_buffer_calibration(arguments)


def main() -> int:
    arguments = parse_arguments()
    try:
        result = analyze(arguments)
    except (OSError, subprocess.CalledProcessError, ValueError, wave.Error) as error:
        print(f"acoustic analysis error: {error}", file=sys.stderr)
        return 2
    serialized = json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True)
    if arguments.output:
        arguments.output.parent.mkdir(parents=True, exist_ok=True)
        arguments.output.write_text(serialized + "\n")
    print(serialized)
    return 0 if result["outcome"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
