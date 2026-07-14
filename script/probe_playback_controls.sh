#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
OUTPUT="${1:-$ROOT/docs/acceptance/runs/playback-controls-$RUN_ID.json}"
APP="$ROOT/.derivedData/Build/Products/Debug/PlaybackLab.app/Contents/MacOS/PlaybackLab"
LOCK_DIR="/tmp/playbacklab-controls-probe.lock"
WORK_DIR="$(mktemp -d /tmp/playbacklab-controls-probe.XXXXXX)"
PROBE_PID=""

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    rm -rf "$WORK_DIR"
    echo "A PlaybackLab controls probe is already active: $LOCK_DIR" >&2
    exit 73
fi

cleanup() {
    if [[ "$PROBE_PID" =~ ^[0-9]+$ ]]; then
        kill "$PROBE_PID" >/dev/null 2>&1 || true
        wait "$PROBE_PID" >/dev/null 2>&1 || true
    fi
    rm -rf "$WORK_DIR"
    rmdir "$LOCK_DIR" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

"$ROOT/script/build_and_run.sh" build

"$ROOT/script/generate_multiaudio_fixture.sh" "$WORK_DIR/two-audio-tracks.mp4" >/dev/null
ffmpeg -hide_banner -loglevel error -y \
    -f lavfi -i 'testsrc2=size=640x360:rate=30' \
    -t 8 -c:v libx264 -preset veryfast -pix_fmt yuv420p \
    -movflags +faststart -an "$WORK_DIR/video-only.mp4"
printf '%s\n%s\n' \
    "$WORK_DIR/two-audio-tracks.mp4" \
    "$WORK_DIR/video-only.mp4" > "$WORK_DIR/manifest.txt"

mkdir -p "$(dirname "$OUTPUT")"
PLAYBACKLAB_PROBE_MANIFEST="$WORK_DIR/manifest.txt" \
PLAYBACKLAB_PROBE_EXERCISE_CONTROLS=1 \
PLAYBACKLAB_PROBE_RUN_ID="$RUN_ID" \
PLAYBACKLAB_PROBE_OUTPUT="$OUTPUT" \
"$APP" --route-playback-probe &
PROBE_PID=$!
wait "$PROBE_PID"
PROBE_PID=""

test "$(/usr/bin/plutil -extract runID raw -o - "$OUTPUT")" = "$RUN_ID"
test "$(/usr/bin/plutil -extract completed raw -o - "$OUTPUT")" = "true"
test "$(/usr/bin/plutil -extract passed raw -o - "$OUTPUT")" = "true"
test "$(/usr/bin/plutil -extract completedCount raw -o - "$OUTPUT")" = "20"
test "$(/usr/bin/plutil -extract expectedCount raw -o - "$OUTPUT")" = "20"
echo "$OUTPUT"
