---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:local-media-lifecycle.clean-flat-playback-main-gate.o01@1",
  "title": "Clean Flat Playback Main Gate",
  "criteria": [
    "After reset, relaunch, import, and open, lifecycle=Playing, presentation=window, attached=window, videoVisible=true, and position is from 0 through 5 seconds inclusive under the observed-position bound decided by HC-021.",
    "The playback and diagnostic observations bind to the same BuildIdentity and media session."
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
