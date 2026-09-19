#!/usr/bin/env bash
set -euo pipefail
#
# Build Enchron for the physical Apple Vision Pro.
#
# Signing uses the team stored in the project with automatic provisioning
# (-allowProvisioningUpdates). Do NOT pass DEVELOPMENT_TEAM on the command
# line: the override breaks Xcode's account resolution for this project
# ("No Account for Team", no provisioning profiles found), while the
# project-stored team resolves fine. This exact failure has recurred
# whenever the override was hand-added to the invocation.
#
# Usage:
#   ENCHRON_DEVICE_UDID=<udid> Scripts/build/build_to_device.sh [scratch-topic]
#
# Environment:
#   ENCHRON_DEVICE_UDID  Vision Pro UDID, required. No default is stored here:
#                        a device identifier committed to the repository
#                        identifies one headset to everyone who reads it.
#                        `xcrun devicectl list devices` prints the identifier.
#   XCODEBIN             xcodebuild to use (default: the Xcode on Cortisol)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOPIC="${1:-device-build}"
STAMP="$(date +%F)"
DERIVED_DATA="$ROOT_DIR/.scratch/$STAMP-$TOPIC"
DEVICE_UDID="${ENCHRON_DEVICE_UDID:-}"
XCODE_BIN="${XCODEBIN:-}"
if [[ -z "$XCODE_BIN" ]]; then
  XCODE_BIN="/Volumes/Cortisol/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild"
fi

if [[ -z "$DEVICE_UDID" ]]; then
  echo "ENCHRON_DEVICE_UDID is not set. Find it with: xcrun devicectl list devices" >&2
  exit 2
fi

mkdir -p "$DERIVED_DATA"

"$XCODE_BIN" \
  -project "$ROOT_DIR/Enchron.xcodeproj" \
  -scheme Enchron \
  -configuration Debug \
  -destination "platform=visionOS,id=$DEVICE_UDID" \
  -derivedDataPath "$DERIVED_DATA" \
  -allowProvisioningUpdates \
  build
