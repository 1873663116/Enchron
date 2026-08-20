#!/usr/bin/env python3

from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import time
from urllib.parse import quote

sys.path.insert(0, str(Path(__file__).resolve().parent))
from verify_media_discovery_admission import canonical_suffixes, production_arrays


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_MATRIX = REPOSITORY_ROOT / "Config/media_discovery_capability_matrix.json"
DEFAULT_TEST_MEDIA = REPOSITORY_ROOT.parent / "TestMedia"
DEFAULT_SCRATCH = Path(
    "/Volumes/Cortisol/DevSpace/Xcode/Enchron/VerificationGauntlet/PlaybackCore"
)
RANGE_SERVER = REPOSITORY_ROOT / "Scripts/fixtures/range-http-server.py"
PROBE_PRODUCT = "PlaybackCoreRemoteMediaProbe"
VIDEO_STAGES = (
    ("streams", "tracks"),
    ("open", "video-reader"),
    ("firstFrame", "decode"),
)
AUDIO_ONLY_STAGES = (
    ("streams", "tracks"),
    ("open", "audio-reader"),
)


def stages_for(media_kind: str) -> tuple[tuple[str, str], ...]:
    return AUDIO_ONLY_STAGES if media_kind == "audioOnly" else VIDEO_STAGES


@dataclass(frozen=True)
class ProbeResult:
    exit_code: int
    stdout: str
    stderr: str


def probe_binary(scratch_path: Path) -> Path:
    package = REPOSITORY_ROOT / "Packages/PlaybackCore"
    build = [
        "/usr/bin/xcrun", "swift", "build",
        "--package-path", str(package),
        "--scratch-path", str(scratch_path),
    ]
    subprocess.run([*build, "--product", PROBE_PRODUCT], check=True)
    bin_path = subprocess.run(
        [*build, "--show-bin-path"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    return Path(bin_path) / PROBE_PRODUCT


def parse_fields(output: str) -> dict[str, str]:
    fields: dict[str, str] = {}
    for token in output.split():
        if "=" in token:
            key, value = token.split("=", 1)
            fields[key] = value
    return fields


def run_probe(
    probe: Path,
    stage: str,
    source: str,
    timeout: int,
) -> ProbeResult:
    command = [str(probe), "--stage", stage, "--url", source]
    if stage == "decode":
        command.extend(["--seconds", "1"])
    try:
        completed = subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired as error:
        raise RuntimeError(f"{stage} timed out after {timeout}s") from error
    return ProbeResult(
        exit_code=completed.returncode,
        stdout=completed.stdout.strip(),
        stderr=completed.stderr.strip(),
    )


def last_error_line(stderr: str) -> str:
    lines = stderr.splitlines()
    return lines[-1] if lines else ""


def stage_record(stage: str, result: ProbeResult) -> dict[str, object]:
    record: dict[str, object] = {
        "exitCode": result.exit_code,
        "stdout": result.stdout,
        "stderr": result.stderr if result.exit_code != 0 else "",
    }
    if result.exit_code != 0:
        record["expectation"] = {"error": last_error_line(result.stderr)}
        return record

    fields = parse_fields(result.stdout)
    if stage == "tracks":
        record["expectation"] = {
            key: fields[key]
            for key in ("video_tracks", "audio_tracks", "subtitle_tracks")
        }
    elif stage == "video-reader":
        record["expectation"] = {
            "video_stream": fields["video_stream"],
            "duration": "positive",
        }
    elif stage == "audio-reader":
        record["expectation"] = {"audio_stream": fields["audio_stream"]}
    elif stage == "decode":
        decoded_frames = int(fields["decoded_frames"])
        record["expectation"] = {
            "codec": fields["codec"],
            "decode": fields["decode"],
            "decodedFrames": "positive" if decoded_frames > 0 else "zero",
        }
    else:
        raise ValueError(f"unknown probe stage {stage}")
    return record


def playback_outcome(
    media_kind: str,
    stages: dict[str, dict[str, object]],
) -> str:
    streams = stages["streams"]
    opened = stages["open"]
    if streams["exitCode"] != 0:
        return "stream-information-rejected"
    if opened["exitCode"] != 0:
        return "audio-open-rejected" if media_kind == "audioOnly" else "video-open-rejected"
    if media_kind == "audioOnly":
        return "audio-open"
    first_frame = stages["firstFrame"]
    if first_frame["exitCode"] != 0:
        return "first-frame-rejected"
    fields = parse_fields(str(first_frame["stdout"]))
    return "first-frame" if int(fields.get("decoded_frames", "0")) > 0 else "no-first-frame"


def capture_transport(
    probe: Path,
    source: str,
    source_scope: str,
    media_kind: str,
    timeout: int,
) -> dict[str, object]:
    stages = {
        label: stage_record(stage, run_probe(probe, stage, source, timeout))
        for label, stage in stages_for(media_kind)
    }
    return {
        "evidence": "proven",
        "sourceScope": source_scope,
        "playbackOutcome": playback_outcome(media_kind, stages),
        "stages": stages,
    }


class RangeServer:
    def __init__(self, directory: Path) -> None:
        self.directory = directory
        self.username = "enchron-probe"
        self.password = "media-discovery"

    def __enter__(self) -> "RangeServer":
        self.temporary = tempfile.TemporaryDirectory(
            prefix="Enchron-admission-",
            dir="/Volumes/Cortisol",
        )
        temporary_path = Path(self.temporary.name)
        ready = temporary_path / "port"
        self.process = subprocess.Popen(
            [
                sys.executable,
                str(RANGE_SERVER),
                "--directory", str(self.directory),
                "--port", "0",
                "--username", self.username,
                "--password", self.password,
                "--log-file", str(temporary_path / "server.jsonl"),
                "--ready-file", str(ready),
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
        )
        deadline = time.time() + 30
        while not ready.exists():
            if self.process.poll() is not None:
                raise RuntimeError(self.process.stderr.read())
            if time.time() > deadline:
                raise RuntimeError("range HTTP server did not start")
            time.sleep(0.01)
        self.port = int(ready.read_text(encoding="utf-8"))
        return self

    def url_for(self, filename: str) -> str:
        username = quote(self.username, safe="")
        password = quote(self.password, safe="")
        return (
            f"http://{username}:{password}@127.0.0.1:{self.port}/"
            f"{quote(filename)}"
        )

    def __exit__(self, *_: object) -> None:
        self.process.terminate()
        self.process.wait(timeout=10)
        self.temporary.cleanup()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def expected_source_scope(extension: str, transport: str) -> str:
    if extension == "iso":
        return (
            "local-udf-image"
            if transport == "local"
            else "http-byte-range-without-local-udf-detection"
        )
    return "local-file" if transport == "local" else "http-byte-range"


def validate_matrix(
    matrix: object,
    suffixes: frozenset[str],
    test_media_root: Path,
) -> list[str]:
    if not isinstance(matrix, dict) or matrix.get("version") != 2:
        return ["matrix version must be 2"]
    if matrix.get("probe") != {
        "product": PROBE_PRODUCT,
        "videoStages": ["tracks", "video-reader", "decode --seconds 1"],
        "audioOnlyStages": ["tracks", "audio-reader"],
    }:
        return ["matrix probe contract differs from the verifier"]
    containers = matrix.get("containers")
    if not isinstance(containers, list):
        return ["containers must be a list"]
    extensions = [entry.get("extension") for entry in containers if isinstance(entry, dict)]
    failures: list[str] = []
    if len(extensions) != len(containers) or set(extensions) != suffixes:
        failures.append(
            "matrix extensions differ from media discovery admission: "
            f"matrix={sorted(str(value) for value in extensions)} policy={sorted(suffixes)}"
        )
        return failures
    if len(extensions) != len(set(extensions)):
        failures.append("matrix contains duplicate extensions")
        return failures

    for entry in containers:
        extension = entry["extension"]
        media_kind = entry.get("mediaKind", "video")
        if media_kind not in {"video", "audioOnly"}:
            failures.append(f"{extension}: mediaKind must be video or audioOnly")
            continue
        fixture = entry.get("fixture")
        transports = entry.get("transports")
        if not isinstance(transports, dict) or set(transports) != {"local", "http"}:
            failures.append(f"{extension}: transports must contain local and http")
            continue
        if fixture is None:
            for transport, evidence in transports.items():
                if not isinstance(evidence, dict) or evidence.get("evidence") != "unproven":
                    failures.append(f"{extension}/{transport}: missing fixture must be unproven")
                elif not isinstance(evidence.get("reason"), str) or not evidence["reason"].strip():
                    failures.append(f"{extension}/{transport}: unproven evidence needs a reason")
                elif evidence.get("sourceScope") != expected_source_scope(extension, transport):
                    failures.append(
                        f"{extension}/{transport}: sourceScope must be "
                        f"{expected_source_scope(extension, transport)}"
                    )
            continue
        if not isinstance(fixture, dict):
            failures.append(f"{extension}: fixture must be an object or null")
            continue
        relative_path = fixture.get("path")
        expected_hash = fixture.get("sha256")
        if not isinstance(relative_path, str) or not isinstance(expected_hash, str):
            failures.append(f"{extension}: fixture needs path and sha256 strings")
            continue
        fixture_path = test_media_root / relative_path
        if not fixture_path.is_file():
            failures.append(f"{extension}: fixture is missing: {fixture_path}")
        elif sha256(fixture_path) != expected_hash:
            failures.append(f"{extension}: fixture sha256 differs: {relative_path}")
        for transport, evidence in transports.items():
            expected_scope = expected_source_scope(extension, transport)
            if not isinstance(evidence, dict) or evidence.get("evidence") != "proven":
                failures.append(f"{extension}/{transport}: fixture evidence must be proven")
                continue
            if evidence.get("sourceScope") != expected_scope:
                failures.append(
                    f"{extension}/{transport}: sourceScope must be {expected_scope}"
                )
            stages = evidence.get("stages")
            expected_stage_labels = {label for label, _ in stages_for(media_kind)}
            if not isinstance(stages, dict) or set(stages) != expected_stage_labels:
                failures.append(f"{extension}/{transport}: required stages must be recorded")
                continue
            try:
                recorded_outcome = playback_outcome(media_kind, stages)
            except (KeyError, TypeError, ValueError):
                failures.append(f"{extension}/{transport}: recorded stages are malformed")
                continue
            if evidence.get("playbackOutcome") != recorded_outcome:
                failures.append(
                    f"{extension}/{transport}: playbackOutcome must be {recorded_outcome}"
                )
    return failures


def compare_stage(
    extension: str,
    transport: str,
    label: str,
    stage: str,
    recorded: dict[str, object],
    actual: ProbeResult,
) -> list[str]:
    prefix = f"{extension}/{transport}/{label}"
    expected_exit = recorded.get("exitCode")
    if actual.exit_code != expected_exit:
        return [f"{prefix}: exit {actual.exit_code}, expected {expected_exit}"]
    expectation = recorded.get("expectation")
    if not isinstance(expectation, dict):
        return [f"{prefix}: recorded expectation is missing"]
    if actual.exit_code != 0:
        expected_error = expectation.get("error")
        actual_error = last_error_line(actual.stderr)
        return [] if actual_error == expected_error else [
            f"{prefix}: error {actual_error!r}, expected {expected_error!r}"
        ]

    fields = parse_fields(actual.stdout)
    if stage == "tracks":
        return [
            f"{prefix}: {key}={fields.get(key)!r}, expected {expected!r}"
            for key, expected in expectation.items()
            if fields.get(key) != expected
        ]
    if stage == "video-reader":
        failures = []
        if fields.get("video_stream") != expectation.get("video_stream"):
            failures.append(
                f"{prefix}: video_stream={fields.get('video_stream')!r}, "
                f"expected {expectation.get('video_stream')!r}"
            )
        try:
            duration = float(fields.get("duration_seconds", "nan"))
        except ValueError:
            duration = float("nan")
        if not duration > 0:
            failures.append(f"{prefix}: duration_seconds is not positive")
        return failures
    if stage == "audio-reader":
        return [] if fields.get("audio_stream") == expectation.get("audio_stream") else [
            f"{prefix}: audio_stream={fields.get('audio_stream')!r}, "
            f"expected {expectation.get('audio_stream')!r}"
        ]
    if stage == "decode":
        failures = []
        for key in ("codec", "decode"):
            if fields.get(key) != expectation.get(key):
                failures.append(
                    f"{prefix}: {key}={fields.get(key)!r}, expected {expectation.get(key)!r}"
                )
        decoded_frames = int(fields.get("decoded_frames", "-1"))
        frame_expectation = expectation.get("decodedFrames")
        if frame_expectation == "positive" and decoded_frames <= 0:
            failures.append(f"{prefix}: expected a decoded first frame")
        if frame_expectation == "zero" and decoded_frames != 0:
            failures.append(f"{prefix}: expected zero decoded frames, got {decoded_frames}")
        return failures
    return [f"{prefix}: unknown stage {stage}"]


def replay_transport(
    extension: str,
    transport: str,
    recorded: dict[str, object],
    probe: Path,
    source: str,
    media_kind: str,
    timeout: int,
) -> list[str]:
    failures: list[str] = []
    for label, stage in stages_for(media_kind):
        actual = run_probe(probe, stage, source, timeout)
        failures.extend(
            compare_stage(
                extension,
                transport,
                label,
                stage,
                recorded["stages"][label],
                actual,
            )
        )
    return failures


def capture_matrix(
    matrix: dict[str, object],
    test_media_root: Path,
    probe: Path,
    timeout: int,
    selected_extensions: frozenset[str],
) -> None:
    for entry in matrix["containers"]:
        extension = entry["extension"]
        if selected_extensions and extension not in selected_extensions:
            continue
        media_kind = entry.get("mediaKind", "video")
        fixture = entry.get("fixture")
        if fixture is None:
            reason = f"TestMedia contains no .{extension} fixture."
            entry["transports"] = {
                transport: {
                    "evidence": "unproven",
                    "sourceScope": expected_source_scope(extension, transport),
                    "reason": reason,
                }
                for transport in ("local", "http")
            }
            continue
        path = test_media_root / fixture["path"]
        entry["transports"]["local"] = capture_transport(
            probe,
            str(path),
            expected_source_scope(extension, "local"),
            media_kind,
            timeout,
        )
        with RangeServer(path.parent) as server:
            entry["transports"]["http"] = capture_transport(
                probe,
                server.url_for(path.name),
                expected_source_scope(extension, "http"),
                media_kind,
                timeout,
            )
        print(
            f"captured .{extension}: "
            f"local={entry['transports']['local']['playbackOutcome']} "
            f"http={entry['transports']['http']['playbackOutcome']}"
        )


def replay_matrix(
    matrix: dict[str, object],
    test_media_root: Path,
    probe: Path,
    timeout: int,
) -> list[str]:
    failures: list[str] = []
    for entry in matrix["containers"]:
        fixture = entry.get("fixture")
        if fixture is None:
            continue
        extension = entry["extension"]
        media_kind = entry.get("mediaKind", "video")
        path = test_media_root / fixture["path"]
        print(f"replaying .{extension} local", flush=True)
        failures.extend(
            replay_transport(
                extension,
                "local",
                entry["transports"]["local"],
                probe,
                str(path),
                media_kind,
                timeout,
            )
        )
        print(f"replaying .{extension} HTTP", flush=True)
        with RangeServer(path.parent) as server:
            failures.extend(
                replay_transport(
                    extension,
                    "http",
                    entry["transports"]["http"],
                    probe,
                    server.url_for(path.name),
                    media_kind,
                    timeout,
                )
            )
    return failures


def parse_arguments(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Capture or replay media discovery capability evidence."
    )
    parser.add_argument("--capture", action="store_true")
    parser.add_argument("--matrix", type=Path, default=DEFAULT_MATRIX)
    parser.add_argument("--test-media-root", type=Path, default=DEFAULT_TEST_MEDIA)
    parser.add_argument("--scratch-path", type=Path, default=DEFAULT_SCRATCH)
    parser.add_argument("--timeout", type=int, default=300)
    parser.add_argument("--extension", action="append", default=[])
    arguments = parser.parse_args(argv)
    if arguments.timeout < 1:
        parser.error("--timeout must be positive")
    return arguments


def main(argv: list[str] | None = None) -> int:
    arguments = parse_arguments(argv)
    try:
        matrix = json.loads(arguments.matrix.read_text(encoding="utf-8"))
        suffixes = canonical_suffixes(production_arrays(REPOSITORY_ROOT))
        if arguments.capture:
            probe = probe_binary(arguments.scratch_path)
            capture_matrix(
                matrix,
                arguments.test_media_root,
                probe,
                arguments.timeout,
                frozenset(arguments.extension),
            )
            failures = validate_matrix(matrix, suffixes, arguments.test_media_root)
            if failures:
                for failure in failures:
                    print(f"error: {failure}", file=sys.stderr)
                return 1
            arguments.matrix.write_text(
                json.dumps(matrix, ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8",
            )
            print(f"wrote {arguments.matrix}")
            return 0
        failures = validate_matrix(matrix, suffixes, arguments.test_media_root)
        if failures:
            for failure in failures:
                print(f"error: {failure}", file=sys.stderr)
            return 1
        probe = probe_binary(arguments.scratch_path)
        failures = replay_matrix(matrix, arguments.test_media_root, probe, arguments.timeout)
    except (
        OSError,
        ValueError,
        KeyError,
        TypeError,
        RuntimeError,
        subprocess.SubprocessError,
    ) as error:
        print(f"capability matrix verification failed: {error}", file=sys.stderr)
        return 2
    if failures:
        for failure in failures:
            print(f"error: {failure}", file=sys.stderr)
        return 1
    proven = sum(
        1
        for entry in matrix["containers"]
        for evidence in entry["transports"].values()
        if evidence["evidence"] == "proven"
    )
    print(f"Media discovery capability matrix passed: {proven} proven combinations replayed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
