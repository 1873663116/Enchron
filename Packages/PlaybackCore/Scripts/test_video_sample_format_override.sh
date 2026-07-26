#!/bin/zsh

set -euo pipefail

ROOT="${0:A:h:h}"
BINARY="${TMPDIR:-/tmp}/playbackcore-video-sample-format-override-$$"
trap 'rm -f "$BINARY"' EXIT

xcrun --sdk macosx swiftc \
  "$ROOT/Sources/PlaybackCore/VideoSampleFormatOverride.swift" \
  "$ROOT/Tests/Standalone/VideoSampleFormatOverrideTests.swift" \
  -o "$BINARY"
"$BINARY"
