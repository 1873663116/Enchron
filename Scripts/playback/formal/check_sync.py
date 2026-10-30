#!/usr/bin/env python3
"""Checks that the C source still has the guards the TLA+ model assumes.

The model in PlaybackLanes.tla reproduces the subscription protocol of
PBFFmpegDemuxSource. It is only honest while the C code keeps the guards
listed below. When one disappears, this script fails and the model must be
read again before the model's verdict is trusted.
"""

import re
import sys
from pathlib import Path

SOURCE = Path(__file__).resolve().parents[3] / (
    "Packages/PlaybackCore/Sources/PlaybackFFmpegBridge/PlaybackFFmpegBridge.c"
)

GUARDS = (
    (
        "take-over marks the stream subscribed",
        r"PBFFmpegDemuxSourceTakeOverStream[\s\S]{0,2000}?subscribers\s*=\s*1",
    ),
    (
        "release compares the owner token before releasing",
        r"queue->ownerToken\s*==\s*token",
    ),
    (
        "seek clears every queue",
        r"PBFFmpegDemuxSourceSeek[\s\S]{0,2000}?clear_packet_queue",
    ),
    (
        "history replay keeps only packets at or after the requested time",
        r"replay_stream_history_locked\([\s\S]{0,400}?threshold",
    ),
)

FINDINGS = (
    (
        "attach does not trim packets older than the playhead",
        r"PBFFmpegDemuxSourceTakeOverStream[\s\S]{0,2000}?time_base[\s\S]{0,400}?clear_packet_queue",
    ),
)


def main() -> int:
    text = SOURCE.read_text(encoding="utf-8")
    failed = False
    for description, pattern in GUARDS:
        if re.search(pattern, text):
            print(f"guard present: {description}")
        else:
            print(f"guard missing: {description}")
            failed = True
    for description, pattern in FINDINGS:
        if re.search(pattern, text):
            print(f"finding absent: {description}")
        else:
            print(f"finding open: {description}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
