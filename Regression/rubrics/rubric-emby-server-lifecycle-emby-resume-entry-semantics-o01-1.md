---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:emby-server-lifecycle.emby-resume-entry-semantics.o01@1",
  "title": "Emby Resume Entry Semantics",
  "criteria": [
    "For a server item with reviewed progress, Resume starts within the five-second observed-position bound of receipt.catalog.progressTicks from the inlined host report, as witnessed by the inlined playback.probe fields after Play followed by the Resume choice in the Resume Playback? alert.",
    "Play followed by the Play from Start choice in the same alert starts from 0 through 5 seconds inclusive under the observed-position bound decided by HC-021, as witnessed by the inlined second playback.probe fields."
  ],
  "negativeControls": [
    "An action return value without the post-action application state cannot satisfy the rubric.",
    "A missing required field, changed session identity where preservation is required, or stale snapshot produces a non-passing result.",
    "Reading local viewing storage, reversing the two choices, or reaching playback without the alert from a series-page episode card violates the rubric."
  ]
}
---
# Emby Resume Entry Semantics

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
