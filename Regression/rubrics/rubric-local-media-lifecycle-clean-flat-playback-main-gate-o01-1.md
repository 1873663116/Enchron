---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:local-media-lifecycle.clean-flat-playback-main-gate.o01@1",
  "title": "Clean Flat Playback Main Gate",
  "criteria": [
    "After reset, relaunch, import, and open, lifecycle=Playing, presentation=window, attached=window, videoVisible=true, and position is from 0 through 5 seconds inclusive under the observed-position bound decided by HC-021.",
    "The one bound artifact carries both readings, taken by the same call: operationOutput.fields is the PlayerUI-window-control-plane state the wait settled on, and operationOutput.playbackObservation is the PlayerUI-playback-state probe the same handler takes immediately after it (Scripts/verification/regression_operation_adapter.py:6939-6944). Their session values are equal and neither is none, their mediaName values are equal and both read sdr-bframe-multiaudio-avsync-30s.mp4, and playbackObservation.missingIdentityFields is empty. Both readings belong to the one archive whose build identity the manifest records, so no second artifact is needed and none may be opened."
  ],
  "negativeControls": [
    "An action return value without the post-action application state cannot satisfy the rubric.",
    "A missing required field, changed session identity where preservation is required, or stale snapshot produces a non-passing result.",
    "A non-window landing, stale progress, missing session identity, or lifecycle other than Playing violates the state gate."
  ]
}
---
# Clean Flat Playback Main Gate

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
