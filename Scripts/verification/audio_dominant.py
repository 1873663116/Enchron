"""Report whether a captured WAV is audible and which tone dominates it.

P9 judges playback by the frequency that comes out the end of the chain, so this
reads a capture produced by audio_capture.swift and answers two questions the
journey ledger records: is it silent, and does the dominant partial match the
frequency the fixture's chosen track carries.
"""

import argparse
import json
import struct
import sys

import numpy as np

SILENCE_DBFS = -60.0
DEFAULT_TOLERANCE_HZ = 15.0


PCM_INTEGER = 1
PCM_FLOAT = 3
PCM_EXTENSIBLE = 0xFFFE


def read_mono(path):
    with open(path, "rb") as handle:
        blob = handle.read()
    if blob[0:4] != b"RIFF" or blob[8:12] != b"WAVE":
        raise SystemExit(f"{path} is not a RIFF/WAVE file")
    encoding = channels = rate = width = None
    payload = None
    cursor = 12
    while cursor + 8 <= len(blob):
        name = blob[cursor:cursor + 4]
        size = struct.unpack_from("<I", blob, cursor + 4)[0]
        body = blob[cursor + 8:cursor + 8 + size]
        if name == b"fmt ":
            encoding, channels, rate, _, _, bits = struct.unpack_from("<HHIIHH", body, 0)
            if encoding == PCM_EXTENSIBLE and len(body) >= 26:
                encoding = struct.unpack_from("<H", body, 24)[0]
            width = bits // 8
        elif name == b"data":
            payload = body if size else blob[cursor + 8:]
            if not size:
                break
        cursor += 8 + size + (size & 1)
    if payload is None or width is None:
        raise SystemExit(f"{path} has no readable fmt/data chunk pair")
    if encoding == PCM_FLOAT and width == 4:
        samples = np.frombuffer(payload, dtype="<f4").astype(np.float64)
    elif encoding == PCM_FLOAT and width == 8:
        samples = np.frombuffer(payload, dtype="<f8")
    elif encoding == PCM_INTEGER and width == 2:
        samples = np.frombuffer(payload, dtype="<i2").astype(np.float64) / 32768.0
    elif encoding == PCM_INTEGER and width == 4:
        samples = np.frombuffer(payload, dtype="<i4").astype(np.float64) / 2147483648.0
    else:
        raise SystemExit(f"unsupported encoding {encoding} at {width * 8} bits")
    if channels > 1:
        samples = samples[: len(samples) // channels * channels].reshape(-1, channels).mean(axis=1)
    return samples, rate


def dbfs(value):
    return -np.inf if value <= 0 else 20.0 * np.log10(value)


def dominant(samples, rate, floor_hz, ceiling_hz):
    window = samples * np.hanning(len(samples))
    spectrum = np.abs(np.fft.rfft(window))
    freqs = np.fft.rfftfreq(len(window), 1.0 / rate)
    band = (freqs >= floor_hz) & (freqs <= ceiling_hz)
    if not band.any():
        raise SystemExit("analysis band is empty")
    index = np.argmax(np.where(band, spectrum, 0.0))
    if 0 < index < len(spectrum) - 1:
        left, peak, right = spectrum[index - 1], spectrum[index], spectrum[index + 1]
        denominator = left - 2.0 * peak + right
        shift = 0.0 if denominator == 0 else 0.5 * (left - right) / denominator
    else:
        shift = 0.0
    resolution = freqs[1] - freqs[0]
    return float(freqs[index] + shift * resolution), spectrum, freqs, band


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("wav")
    parser.add_argument("--expect", type=float)
    parser.add_argument("--tolerance", type=float, default=DEFAULT_TOLERANCE_HZ)
    parser.add_argument("--skip", type=float, default=0.5)
    parser.add_argument("--floor", type=float, default=60.0)
    parser.add_argument("--ceiling", type=float, default=8000.0)
    args = parser.parse_args()

    samples, rate = read_mono(args.wav)
    offset = int(args.skip * rate)
    if len(samples) - offset < rate // 4:
        raise SystemExit(f"capture is too short: {len(samples)} samples at {rate} Hz")
    samples = samples[offset:]

    rms = dbfs(float(np.sqrt(np.mean(np.square(samples)))))
    peak = dbfs(float(np.max(np.abs(samples))))
    silent = rms < SILENCE_DBFS

    frequency, spectrum, freqs, band = dominant(samples, rate, args.floor, args.ceiling)
    energy = float(np.sum(spectrum[band] ** 2))
    near = band & (np.abs(freqs - frequency) <= max(args.tolerance, freqs[1] - freqs[0]))
    purity = float(np.sum(spectrum[near] ** 2) / energy) if energy > 0 else 0.0

    report = {
        "path": args.wav,
        "sampleRate": rate,
        "seconds": round(len(samples) / rate, 3),
        "rmsDbfs": round(rms, 2),
        "peakDbfs": round(peak, 2),
        "silent": bool(silent),
        "dominantHz": round(frequency, 2),
        "purity": round(purity, 4),
    }
    if args.expect is not None:
        report["expectedHz"] = args.expect
        report["deltaHz"] = round(frequency - args.expect, 2)
        report["matched"] = bool(not silent and abs(frequency - args.expect) <= args.tolerance)

    json.dump(report, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")
    if silent:
        return 1
    if args.expect is not None and not report["matched"]:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
