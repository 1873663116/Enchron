#!/usr/bin/env python3

"""Asserts that recording recovery accepts a screen recording and rejects the
runner stdout log that sits beside it in a staged xcresult."""

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).parent))

from extract_visionpro_ui_recording import probe_video

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


def main() -> None:
    failures: list[str] = []

    recording = probe_video(RECORDING)
    if recording is None:
        failures.append(f"a real screen recording was rejected: {RECORDING}")
    else:
        print(f"accepted recording: {recording}")

    log = probe_video(STDOUT_LOG)
    if log is not None:
        failures.append(f"the runner stdout log was accepted as video: {log}")
    else:
        print("rejected the runner stdout log")

    for failure in failures:
        print(f"FAIL {failure}", file=sys.stderr)
    raise SystemExit(1 if failures else 0)


if __name__ == "__main__":
    main()
