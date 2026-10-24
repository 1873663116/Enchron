#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOPIC="${1:-device-build}"
STAMP="$(date +%F)"
DERIVED_DATA="$ROOT_DIR/.scratch/$STAMP-$TOPIC"
DEVICE_UDID="${ENCHRON_DEVICE_UDID:-}"
CONFIGURATION="${ENCHRON_CONFIGURATION:-Debug}"
XCODE_BIN="${XCODEBIN:-}"
if [[ -z "$XCODE_BIN" ]]; then
  XCODE_BIN="/Volumes/Cortisol/Applications/Xcode27.2RC.app/Contents/Developer/usr/bin/xcodebuild"
fi

if [[ -z "$DEVICE_UDID" ]]; then
  echo "ENCHRON_DEVICE_UDID is not set. Find it with: xcrun devicectl list devices" >&2
  exit 2
fi

mkdir -p "$DERIVED_DATA"

"$XCODE_BIN" \
  -project "$ROOT_DIR/Enchron.xcodeproj" \
  -scheme Enchron \
  -configuration "$CONFIGURATION" \
  -destination "platform=visionOS,id=$DEVICE_UDID" \
  -derivedDataPath "$DERIVED_DATA" \
  -allowProvisioningUpdates \
  build
