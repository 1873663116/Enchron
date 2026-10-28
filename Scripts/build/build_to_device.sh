#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DERIVED_DATA="${ENCHRON_DEVICE_DERIVED_DATA:-$ROOT_DIR/.scratch/derived-data-device}"
DEVICE_UDID="${ENCHRON_DEVICE_UDID:-}"
CONFIGURATION="${ENCHRON_CONFIGURATION:-Debug}"
XCODE_BIN="${XCODEBIN:-}"
if [[ -z "$XCODE_BIN" ]]; then
  XCODE_BIN="/Volumes/Cortisol/Applications/Xcode27.2RC.app/Contents/Developer/usr/bin/xcodebuild"
fi

if [[ "$#" -ne 0 ]]; then
  echo "usage: ENCHRON_DEVICE_UDID=<udid> $0" >&2
  echo "       ENCHRON_DEVICE_DERIVED_DATA=<path> overrides the fixed cache (default .scratch/derived-data-device)" >&2
  exit 64
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
