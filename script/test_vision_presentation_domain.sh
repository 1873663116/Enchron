#!/bin/zsh

set -euo pipefail

ROOT="${0:A:h:h}"
BINARY="${TMPDIR:-/tmp}/playbackcore-vision-presentation-domain-$$"
trap 'rm -f "$BINARY"' EXIT

xcrun swiftc \
  "$ROOT/Sources/PlaybackLabVision/VisionPresentationMode.swift" \
  "$ROOT/Sources/PlaybackLabVision/VisionPresentationCoordinator.swift" \
  "$ROOT/Sources/PlaybackLabVision/VisionRegressionPlan.swift" \
  "$ROOT/Sources/PlaybackLabVision/VisionRegressionEvidence.swift" \
  "$ROOT/Tests/VisionPresentationDomainTests.swift" \
  "$ROOT/Tests/VisionPresentationCoordinatorTests.swift" \
  "$ROOT/Tests/VisionRegressionPlanTests.swift" \
  "$ROOT/Tests/VisionRegressionEvidenceTests.swift" \
  -o "$BINARY"
"$BINARY"
