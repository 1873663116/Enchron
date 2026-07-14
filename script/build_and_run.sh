#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="PlaybackLab"
PROJECT="$ROOT_DIR/PlaybackCore.xcodeproj"
DERIVED_DATA="$ROOT_DIR/.derivedData"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"
FFMPEG_XCFRAMEWORK="$ROOT_DIR/Vendor/FFmpeg/PlaybackFFmpeg.xcframework"

if [[ ! -d "$FFMPEG_XCFRAMEWORK" ]]; then
  "$ROOT_DIR/script/build_ffmpeg.sh"
fi

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

xcodegen generate --spec "$ROOT_DIR/project.yml" --project "$ROOT_DIR"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$APP_NAME" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  --build|build)
    ;;
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.xiongzhipeng.PlaybackLab"'
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  --route-probe|route-probe)
    rm -f /tmp/playbacklab-route-probe.json
    PLAYBACKLAB_PROBE_OUTPUT=/tmp/playbacklab-route-probe.json \
      "$APP_BUNDLE/Contents/MacOS/$APP_NAME" --route-playback-probe
    [[ "$(/usr/bin/plutil -extract completed raw -o - /tmp/playbacklab-route-probe.json)" == "true" ]]
    [[ "$(/usr/bin/plutil -extract passed raw -o - /tmp/playbacklab-route-probe.json)" == "true" ]]
    echo /tmp/playbacklab-route-probe.json
    ;;
  *)
    echo "usage: $0 [run|--build|--debug|--logs|--telemetry|--verify|--route-probe]" >&2
    exit 2
    ;;
esac
