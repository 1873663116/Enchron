#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="${1:?usage: probe_media_coverage.sh MANIFEST_OR_DIRECTORY [OUTPUT]}"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
OUTPUT="${2:-$ROOT_DIR/docs/acceptance/runs/media-coverage-$RUN_ID.json}"
FIXTURE_EXPECTATIONS="$ROOT_DIR/docs/acceptance/fixtures/ffmpeg-compressed-coverage-expectations.json"
LOCK_DIR="/tmp/playbacklab-media-coverage.lock"
APP="$ROOT_DIR/.derivedData/Build/Products/Debug/PlaybackLab.app/Contents/MacOS/PlaybackLab"
PROBE_PID=""

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "A PlaybackLab media coverage probe is already active: $LOCK_DIR" >&2
    exit 73
fi
cleanup() {
    if [[ "$PROBE_PID" =~ ^[0-9]+$ ]]; then
        kill "$PROBE_PID" >/dev/null 2>&1 || true
        wait "$PROBE_PID" >/dev/null 2>&1 || true
    fi
    rmdir "$LOCK_DIR" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

"$ROOT_DIR/script/build_and_run.sh" build

mkdir -p "$(dirname "$OUTPUT")"
PLAYBACKLAB_PROBE_ROUTE=ffmpegCompressed \
PLAYBACKLAB_PROBE_MANIFEST="$MANIFEST" \
PLAYBACKLAB_PROBE_FIXTURE_EXPECTATIONS="$FIXTURE_EXPECTATIONS" \
PLAYBACKLAB_PROBE_RUN_ID="$RUN_ID" \
PLAYBACKLAB_PROBE_OUTPUT="$OUTPUT" \
"$APP" --route-playback-probe &
PROBE_PID=$!
wait "$PROBE_PID"
PROBE_PID=""

if [[ "$(/usr/bin/plutil -extract runID raw -o - "$OUTPUT")" != "$RUN_ID" ]] || \
   [[ "$(/usr/bin/plutil -extract completed raw -o - "$OUTPUT")" != "true" ]] || \
   [[ "$(/usr/bin/plutil -extract passed raw -o - "$OUTPUT")" != "true" ]]; then
    echo "Coverage probe did not complete cleanly: $OUTPUT" >&2
    exit 74
fi

echo "$OUTPUT"
