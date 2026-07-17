#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
SOURCE_PATH="${2:-}"
OUTPUT_PATH="${3:-/tmp/enchron-l2-core.json}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="EnchronMacOS"
BUILD_ROOT="${ENCHRON_MACOS_DERIVED_DATA:-$HOME/Library/Developer/EnchronMacOS/DerivedData}"
APP_BUNDLE="$BUILD_ROOT/Build/Products/Debug/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
SIGNING_MODE="${ENCHRON_MACOS_SIGNING:-auto}"
SIGNING_ARGS=(CODE_SIGN_STYLE=Automatic)

if [[ -z "${DEVELOPER_DIR:-}" && "$(/usr/bin/xcode-select -p 2>/dev/null || true)" == "/Library/Developer/CommandLineTools" ]]; then
  for xcode_app in \
    /Applications/Xcode.app \
    /Volumes/MacDev/Applications/Xcode.app \
    /Volumes/MacDev/Applications/Xcode-beta3.app; do
    if [[ -d "$xcode_app/Contents/Developer" ]]; then
      export DEVELOPER_DIR="$xcode_app/Contents/Developer"
      break
    fi
  done
fi

case "$SIGNING_MODE" in
  auto)
    if ! /usr/bin/security find-identity -p codesigning -v 2>/dev/null \
      | /usr/bin/grep -q '"Apple Development:'; then
      SIGNING_MODE="adhoc"
    fi
    ;;
  automatic)
    SIGNING_MODE="auto"
    ;;
  adhoc)
    ;;
  none)
    SIGNING_ARGS=(CODE_SIGNING_ALLOWED=NO)
    ;;
  *)
    echo "ENCHRON_MACOS_SIGNING must be auto, automatic, adhoc, or none" >&2
    exit 2
    ;;
esac

if [[ "$SIGNING_MODE" == "adhoc" ]]; then
  SIGNING_ARGS=(
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_IDENTITY=-
    DEVELOPMENT_TEAM=
    PROVISIONING_PROFILE_SPECIFIER=
    AD_HOC_CODE_SIGNING_ALLOWED=YES
  )
  echo "No Apple Development identity is available; using ad-hoc signing." >&2
  echo "macOS privacy grants will not persist across changed builds." >&2
fi

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

xcodebuild \
  -project "$ROOT_DIR/XrPlayer.xcodeproj" \
  -scheme "$APP_NAME" \
  -destination 'platform=macOS' \
  -derivedDataPath "$BUILD_ROOT" \
  "${SIGNING_ARGS[@]}" \
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
    ENCHRON_L2_FIXTURE_REGISTRY="${ENCHRON_L2_FIXTURE_REGISTRY:-$ROOT_DIR/docs/acceptance/fixture-registry.json}" \
    ENCHRON_L2_OUTPUT="$OUTPUT_PATH" \
    ENCHRON_PLAYBACKCORE_REVISION="$(git -C "$ROOT_DIR" rev-parse HEAD)" \
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
