#!/usr/bin/env bash
set -euo pipefail

FRAMEWORK="Packages/PlaybackCore/Vendor/FFmpeg/PlaybackFFmpeg.xcframework"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DONOR="${1:-${ENCHRON_FFMPEG_DONOR:-}}"

if [[ -n "$DONOR" ]]; then
  if [[ ! -d "$DONOR" ]]; then
    echo "donor clone does not exist: $DONOR" >&2
    exit 1
  fi
  DONOR="$(cd "$DONOR" && pwd)"
fi

if [[ -d "$ROOT/$FRAMEWORK" ]]; then
  echo "$ROOT/$FRAMEWORK"
  exit 0
fi

if [[ -z "$DONOR" ]]; then
  "$ROOT/Packages/PlaybackCore/Scripts/build_ffmpeg.sh"
  echo "$ROOT/$FRAMEWORK"
  exit 0
fi

if [[ ! -d "$DONOR/$FRAMEWORK" ]]; then
  "$DONOR/Packages/PlaybackCore/Scripts/build_ffmpeg.sh"
fi
ln -s "$DONOR/$FRAMEWORK" "$ROOT/$FRAMEWORK"
if [[ ! -d "$ROOT/$FRAMEWORK" ]]; then
  echo "framework link does not resolve: $ROOT/$FRAMEWORK -> $DONOR/$FRAMEWORK" >&2
  exit 1
fi
echo "$ROOT/$FRAMEWORK"
