#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="${DOLBY_VISION_TEST_ROOT:-/Users/xiongzhipeng/Desktop/test/DolbyVision/UHD}"
DERIVED_DATA="$ROOT_DIR/.derivedData"
TOOL="$DERIVED_DATA/Build/Products/Debug/DolbyVisionCompressedProbe"

xcodegen generate --spec "$ROOT_DIR/project.yml" --project "$ROOT_DIR"
xcodebuild \
  -project "$ROOT_DIR/PlaybackCore.xcodeproj" \
  -scheme DolbyVisionCompressedProbe \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build

"$TOOL" \
  "5=$TEST_ROOT/Patterns_Of_Nature_DoVi_24_P5_UHD_HEVC-10mbps_DD+JOC-768kbps_iOS.mp4" \
  "8.1=$TEST_ROOT/Patterns_Of_Nature_HDR10-P8.1_UHD_24_H265-10Mbps_DD+JOC-768Kbps.mp4" \
  "8.4=$TEST_ROOT/Patterns_Of_Nature_HLG-P8.4_UHD_24_H265-10Mbps_DD+JOC-768Kbps.mp4"
