#!/usr/bin/env python3

"""Microphone evidence for regression journeys (P9). Captures from a Mac
audio input placed beside the headset speaker, then reports structured facts:
dominant frequency, RMS level, silence verdict, and power at the fixture pulse
frequencies (AAC 880, FLAC 660, E-AC-3 550, AC-3 440 Hz). The agent reads the
JSON; this script never judges pass or fail."""

import argparse
import json
import subprocess
import sys
import wave
from pathlib import Path

import numpy as np

PULSE_FREQUENCIES_HZ = (440.0, 550.0, 660.0, 880.0)
# A microphone a short distance from the headset speaker lands near -55 dBFS
# with a clearly resolved tone, so a threshold at that level reports a real
# capture as silence. This sits below the quietest capture that still carried a
# 25x peak, and `dominantPeakRatio` is what actually separates tone from floor.
SILENCE_RMS_DBFS = -75.0


def capture(device: str, seconds: float, wav_path: Path) -> None:
    command = [
        "ffmpeg",
        "-hide_banner",
        "-loglevel",
        "error",
        "-f",
        "avfoundation",
        "-i",
        f":{device}",
        "-t",
        f"{seconds:.1f}",
        "-ac",
        "1",
        "-ar",
        "48000",
        "-y",
        str(wav_path),
    ]
    subprocess.run(command, check=True, timeout=seconds + 30)


def analyze(wav_path: Path) -> dict:
    with wave.open(str(wav_path), "rb") as reader:
        rate = reader.getframerate()
        width = reader.getsampwidth()
        raw = reader.readframes(reader.getnframes())
        channels = reader.getnchannels()
    dtype = {1: np.int8, 2: np.int16, 4: np.int32}[width]
    samples = np.frombuffer(raw, dtype=dtype).astype(np.float64)
    if channels > 1:
        samples = samples.reshape(-1, channels).mean(axis=1)
    full_scale = float(2 ** (8 * width - 1))
    samples /= full_scale

    rms = float(np.sqrt(np.mean(samples**2)))
    rms_dbfs = float(20 * np.log10(rms)) if rms > 0 else -200.0

    window = np.hanning(samples.size)
    spectrum = np.abs(np.fft.rfft(samples * window))
    frequencies = np.fft.rfftfreq(samples.size, d=1.0 / rate)
    band = (frequencies >= 80.0) & (frequencies <= 4000.0)
    band_spectrum = spectrum[band]
    band_frequencies = frequencies[band]
    dominant_hz = float(band_frequencies[int(np.argmax(band_spectrum))])

    def power_near(target: float) -> float:
        nearby = (band_frequencies >= target - 10.0) & (
            band_frequencies <= target + 10.0
        )
        return float(np.sqrt(np.mean(band_spectrum[nearby] ** 2)))

    median_power = float(np.median(band_spectrum)) or 1e-12
    pulse_powers = {
        f"{int(freq)}": round(power_near(freq) / median_power, 1)
        for freq in PULSE_FREQUENCIES_HZ
    }
    # Room noise below 200 Hz can outweigh the tone, so the loudest bin in the
    # band names the room rather than the track. Ranking the fixture pulse
    # frequencies against each other is what survives that.
    ranked = sorted(pulse_powers.items(), key=lambda kv: kv[1], reverse=True)
    leader, runner_up = ranked[0], ranked[1]

    return {
        "wav": str(wav_path),
        "seconds": round(samples.size / rate, 2),
        "rmsDbfs": round(rms_dbfs, 1),
        "silent": rms_dbfs < SILENCE_RMS_DBFS,
        "dominantHz": round(dominant_hz, 1),
        "dominantPeakRatio": round(
            float(band_spectrum.max()) / median_power, 1
        ),
        "dominantPulseHz": int(leader[0]),
        "pulseMarginOverRunnerUp": round(leader[1] / max(runner_up[1], 0.1), 1),
        "pulsePowerOverMedian": pulse_powers,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", default="Steinberg UR12")
    parser.add_argument("--seconds", type=float, default=6.0)
    parser.add_argument("--output", required=True, help="capture WAV path")
    parser.add_argument(
        "--analyze-only",
        action="store_true",
        help="skip capture and analyze an existing WAV",
    )
    arguments = parser.parse_args()
    wav_path = Path(arguments.output)
    if not arguments.analyze_only:
        wav_path.parent.mkdir(parents=True, exist_ok=True)
        capture(arguments.device, arguments.seconds, wav_path)
    print(json.dumps(analyze(wav_path), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
