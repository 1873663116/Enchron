#!/bin/zsh

set -euo pipefail

ROOT="${0:A:h:h}"
APP="$ROOT/Sources/PlaybackLabVision/PlaybackLabVisionApp.swift"
CONTENT="$ROOT/Sources/PlaybackLabVision/VisionContentView.swift"
MODE="$ROOT/Sources/PlaybackLabVision/VisionPresentationMode.swift"
MODEL="$ROOT/Sources/PlaybackLabVision/VisionPlaybackModel.swift"
RUNNER="$ROOT/Sources/PlaybackLabVision/VisionRegressionRunner.swift"
EVIDENCE="$ROOT/Sources/PlaybackLabVision/VisionRegressionEvidence.swift"
DEVICE_PROBE="$ROOT/script/probe_vision_device.sh"

fail() {
  print -u2 -- "RED $1"
  exit 1
}

rg -q 'enum PresentationCommand' "$MODE" \
  || fail 'public PresentationCommand is missing'
rg -q 'case flatWindow' "$MODE" \
  || fail 'Flat Window product shape is missing'
rg -q 'case portalWindow' "$MODE" \
  || fail 'Portal Window product shape is missing'
rg -q 'case docked' "$MODE" \
  || fail 'Docked product shape is missing'
rg -q 'case panorama' "$MODE" \
  || fail 'Panorama product shape is missing'
if rg -q 'case (fixedImmersiveScreen|progressive|full)' "$MODE"; then
  fail 'obsolete surface modes remain in the domain model'
fi
if rg -q 'illegalPresentationTransition|allowsDirectPresentation' "$MODE" "$MODEL"; then
  fail 'the backend still models the obsolete illegal-edge graph'
fi
rg -q 'performPresentationCommand' "$MODEL" \
  || fail 'shared presentation command handler is missing'
rg -q 'performPresentationCommand' "$CONTENT" \
  || fail 'UI and regression input do not use the shared command handler'
rg -q 'performPresentationCommand' "$RUNNER" \
  || fail 'regression input bypasses the shared command handler'
rg -q 'VisionRegressionPlan.cases' "$RUNNER" \
  || fail 'regression runner does not execute the exact manifest'
rg -q 'presentationFailures' "$RUNNER" "$EVIDENCE" \
  || fail 'presentation cases do not enforce fresh attached output evidence'
rg -q 'coldSwitchFailures' "$RUNNER" "$EVIDENCE" \
  || fail 'cold route switch does not enforce new-session output evidence'
rg -q 'cleanupFailures' "$RUNNER" "$EVIDENCE" \
  || fail 'cleanup does not enforce flush and binding invalidation evidence'
rg -q '"provenance": provenance()' "$RUNNER" \
  || fail 'device result does not include run provenance'
rg -q 'validateProvenance' "$RUNNER" \
  || fail 'missing provenance does not fail the run closed'
rg -q 'PLAYBACKLAB_PROVENANCE_REALITY_ASSET_SHA256' "$DEVICE_PROBE" \
  || fail 'device launcher does not identify the bundled Reality asset'
rg -q 'stereoSuiteSessionID' "$RUNNER" \
  || fail 'Stereo cases do not retain one fixed session'
if rg -q 'private func changePresentation' "$CONTENT"; then
  fail 'probe-only presentation orchestration still exists'
fi
if rg -U -q '\.task \{[[:space:][:print:]]*openSurface\(\.window' "$CONTENT"; then
  fail 'launch still opens an unsolicited playback window'
fi
if rg -q '\.windowStyle\(\.plain\)' "$APP"; then
  fail 'playback windows still remove standard movable window chrome'
fi
test "$(rg -c '^[[:space:]]*ImmersiveSpace\(' "$APP")" -eq 1 \
  || fail 'the app must declare exactly one playback ImmersiveSpace'
if rg -q 'PlaybackPortalWindow|PlaybackProgressiveSpace|PlaybackFullSpace|PlaybackFixedImmersiveSpace' "$APP" "$MODE"; then
  fail 'obsolete portal or immersive scene containers remain'
fi
rg -q 'ImmersiveViewingModeDidChange' "$MODEL" \
  || fail 'mode-change acknowledgement is not observed'
rg -q 'screen' "$MODEL" \
  || fail 'RCP screen anchor is not connected'
rg -q -- '--confirm-device-ready' "$DEVICE_PROBE" \
  || fail 'device execution is missing the this-run human confirmation gate'

"$ROOT/script/test_vision_presentation_domain.sh"

print -- 'GREEN vision presentation command contract'
