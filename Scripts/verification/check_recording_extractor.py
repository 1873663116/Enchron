#!/usr/bin/env python3

"""Asserts that recording recovery accepts a screen recording and rejects the
runner stdout log that sits beside it in a staged xcresult.

The extractor offers every file staged in an unsealed result bundle to ffprobe,
and ffmpeg demuxes plain text as ANSI art video with a width, a frame rate and a
plausible duration. The runner's stdout is staged beside the attachments, so five
consecutive sessions reported a 575 KB recording that was in fact that log.

Four checks, because the container predicate that closed it is only one of the
ways this can come back:

  fixtures   both fixtures are present, since a negative that has been deleted
             is indistinguishable from a negative that was correctly rejected;
  predicate  probe_video accepts the recording and rejects the log;
  trap       the log still misparses as video under the predicate this one
             replaced, so its rejection is a decision and not an accident of
             whichever ffmpeg is installed;
  selection  find_recording_sources, which is what actually offers staged files
             to the predicate, returns the movie and not the log.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import types

sys.path.insert(0, str(Path(__file__).parent))

from enchron_artifact_paths import scratch_directory

EXTRACTOR = Path(__file__).parent / "extract_visionpro_ui_recording.py"
EVIDENCE = Path("/Volumes/Cortisol/DevSpace/Xcode/Enchron/TestEvidence")

RECORDING = (
    EVIDENCE
    / "exit-cutover-20260813/before-docked/session.xcresult/Data"
    / "data.0~c0ocuAnb6WhCbEfBTPv-wTbYVtBPb2zirhHCSfRhxPjMaf7oI2lf0wAuzIbe6lh0spg9S-tOwAg7zMccwPY2ow=="
)

STDOUT_LOG = (
    EVIDENCE
    / "recording-repro-20260814/session.xcresult/Staging/1_Test/Diagnostics"
    / "EnchronAppUITests-27098CE2-376E-4B1A-B4D1-BBF57774646D-Configuration-Default-Iteration-1"
    / "EnchronAppUITests-4790BF50-22C1-4DC1-8B46-070F6C276B77"
    / "StandardOutputAndStandardError-com.xiongzhipeng.XrPlayer.txt"
)


def load_extractor(path: Path) -> types.ModuleType:
    specification = importlib.util.spec_from_file_location(f"extractor_{id(path)}", path)
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


def parses_as_video_without_a_container_check(path: Path) -> dict[str, object] | None:
    """The predicate the extractor used before it required a movie container: a
    video stream and a duration were enough. Restated here so the fixture can be
    shown to still spring the trap that predicate fell into."""
    completed = subprocess.run(
        [
            "ffprobe",
            "-v",
            "error",
            "-show_entries",
            "format=duration:stream=codec_name,codec_type,width,height,avg_frame_rate",
            "-of",
            "json",
            str(path),
        ],
        check=False,
        text=True,
        capture_output=True,
    )
    if completed.returncode != 0:
        return None
    try:
        payload = json.loads(completed.stdout)
        stream = next(
            entry for entry in payload["streams"] if entry.get("codec_type") == "video"
        )
        duration = float(payload["format"]["duration"])
    except (KeyError, StopIteration, TypeError, ValueError, json.JSONDecodeError):
        return None
    return {
        "codec": stream.get("codec_name"),
        "width": stream.get("width"),
        "height": stream.get("height"),
        "averageFrameRate": stream.get("avg_frame_rate"),
        "duration": duration,
    }


def staged_bundle(log: Path) -> tuple[Path, Path, Path]:
    """A result bundle shaped like the unsealed ones: a Staging tree holding the
    runner's stdout beside a real movie, and no exported attachments."""
    scratch = scratch_directory("recording-extractor-selection")
    bundle = scratch / "session.xcresult"
    if bundle.exists():
        shutil.rmtree(bundle)
    staging = bundle / "Staging/1_Test/Diagnostics"
    staging.mkdir(parents=True)
    exports = scratch / "attachments"
    exports.mkdir(exist_ok=True)

    movie = staging / "screen-recording.mp4"
    completed = subprocess.run(
        [
            "ffmpeg", "-y", "-v", "error",
            "-f", "lavfi",
            "-i", "testsrc=size=320x240:rate=10:duration=1",
            "-c:v", "libx264",
            "-pix_fmt", "yuv420p",
            str(movie),
        ],
        check=False,
        text=True,
        capture_output=True,
    )
    if completed.returncode != 0 or not movie.is_file():
        raise SystemExit(
            f"could not build the movie this check stages:\n{completed.stderr}"
        )
    shutil.copy(log, staging / log.name)
    return bundle, exports, movie


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--extractor",
        type=Path,
        default=EXTRACTOR,
        help="The recording extractor to check. Point this at an older copy to "
        "confirm the check still fails on the state it was written for.",
    )
    arguments = parser.parse_args()
    extractor = arguments.extractor.resolve()
    if not extractor.is_file():
        raise SystemExit(f"no extractor to check at {extractor}")
    print(f"checking {extractor}")
    module = load_extractor(extractor)

    failures: list[str] = []

    print("\nfixtures")
    for label, path in (("recording", RECORDING), ("runner stdout log", STDOUT_LOG)):
        if path.is_file():
            print(f"  ok   the {label} fixture is present")
            continue
        print(f"  FAIL the {label} fixture is gone: {path}")
        failures.append(
            f"the {label} fixture is missing, so this check proves nothing about it: {path}"
        )
    if failures:
        for failure in failures:
            print(f"FAIL {failure}", file=sys.stderr)
        raise SystemExit(1)

    print("\npredicate")
    recording = module.probe_video(RECORDING)
    if recording is None:
        print(f"  FAIL a real screen recording was rejected")
        failures.append(f"a real screen recording was rejected: {RECORDING}")
    else:
        print(f"  ok   accepted recording: {recording}")
    log = module.probe_video(STDOUT_LOG)
    if log is not None:
        print(f"  FAIL the runner stdout log was accepted as video: {log}")
        failures.append(f"the runner stdout log was accepted as video: {log}")
    else:
        print("  ok   rejected the runner stdout log")

    print("\ntrap")
    misparse = parses_as_video_without_a_container_check(STDOUT_LOG)
    if misparse is None:
        print("  FAIL the log no longer parses as video at all")
        failures.append(
            "the runner stdout log no longer misparses as video, so rejecting it no "
            "longer demonstrates anything and the container predicate is being credited "
            "for a rejection this ffmpeg would make anyway. Find a negative fixture that "
            "does reproduce it before trusting this check again."
        )
    else:
        print(f"  ok   the log still misparses as video: {misparse}")

    print("\nselection")
    bundle, exports, movie = staged_bundle(STDOUT_LOG)
    sources = module.find_recording_sources(bundle, exports, [])
    chosen = sorted(Path(source.path).name for source in sources)
    if chosen == [movie.name]:
        print(f"  ok   the staged movie was the only source recovered: {chosen}")
    else:
        print(f"  FAIL recovered {chosen} from a staging tree holding one movie and one log")
        failures.append(
            f"find_recording_sources recovered {chosen} from a staging tree whose only "
            f"movie is {movie.name}"
        )

    print()
    for failure in failures:
        print(f"FAIL {failure}", file=sys.stderr)
    raise SystemExit(1 if failures else 0)


if __name__ == "__main__":
    main()
