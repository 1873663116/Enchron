#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
SOURCE_PATH="${2:-}"
OUTPUT_PATH="${3:-/tmp/enchron-l2-core.json}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="EnchronMacOS"
BUILD_ROOT="${ENCHRON_MACOS_DERIVED_DATA:-/tmp/EnchronMacOS-DD}"
APP_BUNDLE="$BUILD_ROOT/Build/Products/Debug/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

xcodebuild \
  -project "$ROOT_DIR/XrPlayer.xcodeproj" \
  -scheme "$APP_NAME" \
  -destination 'platform=macOS' \
  -derivedDataPath "$BUILD_ROOT" \
  CODE_SIGNING_ALLOWED=NO \
  build

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate 'subsystem == "app.enchron"'
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  --l2-core|l2-core|--l2-app|l2-app)
    if [[ -z "$SOURCE_PATH" || ! -f "$SOURCE_PATH" ]]; then
      echo "$MODE requires an existing media file path" >&2
      exit 2
    fi
    SCENARIO="core"
    if [[ "$MODE" == "--l2-app" || "$MODE" == "l2-app" ]]; then
      SCENARIO="app-adapter"
    fi
    rm -f "$OUTPUT_PATH"
    ENCHRON_L2_SCENARIO="$SCENARIO" \
    ENCHRON_L2_SOURCE="$SOURCE_PATH" \
    ENCHRON_L2_FIXTURE_ID="${ENCHRON_L2_FIXTURE_ID:-local-hdr10-pq-hevc-aac-001}" \
    ENCHRON_L2_FIXTURE_REGISTRY="${ENCHRON_L2_FIXTURE_REGISTRY:-$ROOT_DIR/../PlaybackCore/docs/acceptance/fixture-registry.json}" \
    ENCHRON_L2_OUTPUT="$OUTPUT_PATH" \
    ENCHRON_PLAYBACKCORE_REVISION="$(git -C "$ROOT_DIR/../PlaybackCore" rev-parse HEAD)" \
    ENCHRON_REVISION="$(git -C "$ROOT_DIR" rev-parse HEAD)" \
    "$APP_BINARY"
    test -f "$OUTPUT_PATH"
    if [[ "$(/usr/bin/plutil -extract passed raw -expect bool "$OUTPUT_PATH")" != "true" ]]; then
      echo "L2 Core scenario failed; inspect $OUTPUT_PATH" >&2
      exit 1
    fi
    echo "$OUTPUT_PATH"
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--l2-core MEDIA [OUTPUT]|--l2-app MEDIA [OUTPUT]]" >&2
    exit 2
    ;;
esac
