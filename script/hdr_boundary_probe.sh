#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/.derivedData"

xcodegen generate --spec "$ROOT_DIR/project.yml" --project "$ROOT_DIR" >/dev/null
xcodebuild \
  -quiet \
  -project "$ROOT_DIR/PlaybackCore.xcodeproj" \
  -scheme HDRBoundaryProbe \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build

"$DERIVED_DATA/Build/Products/Debug/HDRBoundaryProbe"
