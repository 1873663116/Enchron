#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APMP_FIXTURE="${1:-/Users/xiongzhipeng/Desktop/test/_derived/APMP/equirect_grid_hevc_mono_30s_apmp.mov}"
DEVICE="$(xcrun simctl list devices | sed -n 's/.*Apple Vision Pro (\([^)]*\)) (Booted).*/\1/p' | head -1)"
if [[ -z "$DEVICE" ]]; then
  echo "No booted Apple Vision Pro Simulator." >&2
  exit 2
fi

DERIVED="$ROOT/.derivedData-vision-probe"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
BUNDLE_ID="com.xiongzhipeng.PlaybackLabVision"
CONTAINER=""
TEMP_DIR=""
CONTROL_FIXTURE=""

cleanup() {
  xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
  [[ -n "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR"
}
trap cleanup EXIT INT TERM

command -v ffmpeg >/dev/null
test -f "$APMP_FIXTURE"
TEMP_DIR="$(mktemp -d /tmp/playbacklab-vision-controls.XXXXXX)"
CONTROL_FIXTURE="$TEMP_DIR/presentation-probe-controls.mp4"
ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i "testsrc2=size=640x360:rate=30:duration=18" \
  -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=18" \
  -f lavfi -i "sine=frequency=880:sample_rate=48000:duration=18" \
  -map 0:v:0 -map 1:a:0 -map 2:a:0 \
  -c:v libx264 -preset veryfast -profile:v high -pix_fmt yuv420p -g 30 \
  -c:a aac -b:a 128k \
  -metadata:s:a:0 language=eng -metadata:s:a:1 language=jpn \
  -disposition:a:0 default -disposition:a:1 0 \
  -movflags +faststart -shortest "$CONTROL_FIXTURE"

xcodebuild \
  -project "$ROOT/PlaybackCore.xcodeproj" \
  -scheme PlaybackLabVision \
  -configuration Debug \
  -destination "platform=visionOS Simulator,id=$DEVICE" \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO build

APP="$DERIVED/Build/Products/Debug-xrsimulator/PlaybackLab.app"
xcrun simctl install "$DEVICE" "$APP"
CONTAINER="$(xcrun simctl get_app_container "$DEVICE" "$BUNDLE_ID" data)"
cp "$CONTROL_FIXTURE" "$CONTAINER/Documents/presentation-probe-controls.mp4"
cp "$APMP_FIXTURE" "$CONTAINER/Documents/presentation-probe-apmp.mov"
RESULT="$CONTAINER/Documents/presentation-probe-$RUN_ID.json"
rm -f "$RESULT"
SIMCTL_CHILD_PLAYBACKLAB_PRESENTATION_PROBE_RUN_ID="$RUN_ID" \
  xcrun simctl launch --terminate-running-process "$DEVICE" \
  "$BUNDLE_ID" --presentation-probe

for _ in {1..600}; do
  [[ -f "$RESULT" ]] && break
  sleep 1
done

if [[ ! -f "$RESULT" ]]; then
  echo "Presentation probe timed out." >&2
  xcrun simctl terminate "$DEVICE" com.xiongzhipeng.PlaybackLabVision || true
  exit 1
fi

cp "$RESULT" /tmp/playbacklab-vision-presentation-probe.json
test "$(/usr/bin/plutil -extract runID raw -o - "$RESULT")" = "$RUN_ID"
test "$(/usr/bin/plutil -extract completed raw -o - "$RESULT")" = "true"
if [[ "$(/usr/bin/plutil -extract passed raw -o - "$RESULT")" != "true" ]]; then
  cat /tmp/playbacklab-vision-presentation-probe.json
  exit 1
fi
echo /tmp/playbacklab-vision-presentation-probe.json
