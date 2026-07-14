#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="PlaybackLab"
DERIVED_DATA="$ROOT_DIR/.derivedData"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"
OUTPUT_DIR="/tmp/playbacklab-hdr-probe"

rm -f \
  "$OUTPUT_DIR/realitykit.png" \
  "$OUTPUT_DIR/realitykit-avplayer.png" \
  "$OUTPUT_DIR/system-reference.png" \
  "$OUTPUT_DIR/renderer-boundary.json" \
  "$OUTPUT_DIR/error.txt"

xcodegen generate --spec "$ROOT_DIR/project.yml" --project "$ROOT_DIR"
xcodebuild \
  -project "$ROOT_DIR/PlaybackCore.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build

/usr/bin/open -W -n "$APP_BUNDLE" --args --hdr-visual-probe
python3 "$ROOT_DIR/script/analyze_hdr_captures.py" "$OUTPUT_DIR"
