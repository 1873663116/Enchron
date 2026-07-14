#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "${1:-}" != "--confirm-device-ready" ]]; then
    echo "Refusing device work without this-run confirmation." >&2
    echo "usage: probe_vision_device.sh --confirm-device-ready DEVICE_ID TEAM_ID [APMP_FIXTURE] [OUTPUT]" >&2
    exit 64
fi
shift
DEVICE="${1:?usage: probe_vision_device.sh --confirm-device-ready DEVICE_ID TEAM_ID [APMP_FIXTURE] [OUTPUT]}"
TEAM="${2:?usage: probe_vision_device.sh --confirm-device-ready DEVICE_ID TEAM_ID [APMP_FIXTURE] [OUTPUT]}"
FIXTURE="${3:-/Users/xiongzhipeng/Desktop/test/_derived/APMP/equirect_grid_hevc_mono_30s_apmp.mov}"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
OUTPUT="${4:-$ROOT/docs/acceptance/runs/vision-device-presentation-$RUN_ID.json}"
DERIVED="$ROOT/.derivedData-vision-device-probe"
APP="$DERIVED/Build/Products/Debug-xros/PlaybackLab.app"
REMOTE_RESULT="Documents/presentation-probe-$RUN_ID.json"
LOCK_DIR="/tmp/playbacklab-vision-device-probe.lock"
BUNDLE_ID="com.xiongzhipeng.PlaybackLabVision"
LAUNCH_JSON="/tmp/playbacklab-vision-device-launch-$RUN_ID.json"
TEMP_DIR=""
CONTROL_FIXTURE=""
REALITY_ASSET="$ROOT/Sources/PlaybackLabVision/Fixtures/Immersive_Space.reality"

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "A Vision Pro presentation probe is already active: $LOCK_DIR" >&2
    exit 73
fi
cleanup() {
    local pid
    pid=""
    if [[ -f "$LAUNCH_JSON" ]]; then
        pid="$(/usr/bin/plutil -p "$LAUNCH_JSON" 2>/dev/null \
            | sed -n 's/.*"processIdentifier" => \([0-9][0-9]*\).*/\1/p' \
            | head -1 || true)"
    fi
    if [[ ! "$pid" =~ ^[0-9]+$ ]]; then
        pid="$(xcrun devicectl device info processes \
            --device "$DEVICE" \
            --search PlaybackLab \
            --hide-headers 2>/dev/null \
            | awk '$1 ~ /^[0-9]+$/ { print $1; exit }' || true)"
    fi
    if [[ "$pid" =~ ^[0-9]+$ ]]; then
        xcrun devicectl device process terminate \
            --device "$DEVICE" \
            --pid "$pid" >/dev/null 2>&1 || true
    fi
    rm -f "$LAUNCH_JSON"
    [[ -n "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR"
    rmdir "$LOCK_DIR" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

test -f "$FIXTURE"
test -f "$REALITY_ASSET"
command -v ffmpeg >/dev/null
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

xcodegen generate --spec "$ROOT/project.yml" --project "$ROOT"
WORKTREE_STATUS="$(git -C "$ROOT" status --porcelain=v1 -uall)"
export PLAYBACKLAB_PROVENANCE_GIT_HEAD="$(git -C "$ROOT" rev-parse HEAD)"
export PLAYBACKLAB_PROVENANCE_WORKTREE_DIRTY=false
[[ -n "$WORKTREE_STATUS" ]] && export PLAYBACKLAB_PROVENANCE_WORKTREE_DIRTY=true
export PLAYBACKLAB_PROVENANCE_WORKTREE_STATUS_SHA256="$(printf '%s' "$WORKTREE_STATUS" | shasum -a 256 | awk '{print $1}')"
export PLAYBACKLAB_PROVENANCE_WORKTREE_CONTENT_SHA256="$(git -C "$ROOT" ls-files -co --exclude-standard -z | while IFS= read -r -d '' FILE; do [[ -f "$ROOT/$FILE" ]] || continue; shasum -a 256 "$ROOT/$FILE" | awk -v file="$FILE" '{print $1 "  " file}'; done | LC_ALL=C sort | shasum -a 256 | awk '{print $1}')"
export PLAYBACKLAB_PROVENANCE_XCODE_VERSION="$(xcodebuild -version | paste -sd ' ' -)"
export PLAYBACKLAB_PROVENANCE_VISIONOS_SDK_VERSION="$(xcrun --sdk xros --show-sdk-version)"
export PLAYBACKLAB_PROVENANCE_DEVICE_IDENTIFIER="$DEVICE"
export PLAYBACKLAB_PROVENANCE_FLAT_FIXTURE_SHA256="$(shasum -a 256 "$CONTROL_FIXTURE" | awk '{print $1}')"
export PLAYBACKLAB_PROVENANCE_PANORAMA_FIXTURE_SHA256="$(shasum -a 256 "$FIXTURE" | awk '{print $1}')"
export PLAYBACKLAB_PROVENANCE_REALITY_ASSET_SHA256="$(shasum -a 256 "$REALITY_ASSET" | awk '{print $1}')"
LAUNCH_ENV="$(RUN_ID="$RUN_ID" /usr/bin/python3 -c 'import json, os; keys = [key for key in os.environ if key.startswith("PLAYBACKLAB_PROVENANCE_")]; values = {key: os.environ[key] for key in keys}; values["PLAYBACKLAB_PRESENTATION_PROBE_RUN_ID"] = os.environ["RUN_ID"]; print(json.dumps(values, separators=(",", ":")))')"
xcodebuild \
    -project "$ROOT/PlaybackCore.xcodeproj" \
    -scheme PlaybackLabVision \
    -configuration Debug \
    -destination "id=$DEVICE" \
    -derivedDataPath "$DERIVED" \
    DEVELOPMENT_TEAM="$TEAM" \
    -allowProvisioningUpdates \
    build

xcrun devicectl device install app \
    --device "$DEVICE" \
    "$APP"
xcrun devicectl device copy to \
    --device "$DEVICE" \
    --source "$FIXTURE" \
    --destination Documents/presentation-probe-apmp.mov \
    --domain-type appDataContainer \
    --domain-identifier "$BUNDLE_ID"
xcrun devicectl device copy to \
    --device "$DEVICE" \
    --source "$CONTROL_FIXTURE" \
    --destination Documents/presentation-probe-controls.mp4 \
    --domain-type appDataContainer \
    --domain-identifier "$BUNDLE_ID"

set +e
xcrun devicectl device process launch \
    --timeout 900 \
    --device "$DEVICE" \
    --terminate-existing \
    --console \
    --json-output "$LAUNCH_JSON" \
    --environment-variables "$LAUNCH_ENV" \
    "$BUNDLE_ID" \
    --presentation-probe
LAUNCH_STATUS=$?
set -e

mkdir -p "$(dirname "$OUTPUT")"
xcrun devicectl device copy from \
    --device "$DEVICE" \
    --source "$REMOTE_RESULT" \
    --destination "$OUTPUT" \
    --domain-type appDataContainer \
    --domain-identifier "$BUNDLE_ID"

test "$(/usr/bin/plutil -extract runID raw -o - "$OUTPUT")" = "$RUN_ID"
test "$(/usr/bin/plutil -extract completed raw -o - "$OUTPUT")" = "true"
test "$(/usr/bin/plutil -extract passed raw -o - "$OUTPUT")" = "true"
test "$LAUNCH_STATUS" -eq 0
echo "$OUTPUT"
