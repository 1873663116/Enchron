---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:emby-server-lifecycle.emby-resume-entry-semantics.o01@1",
  "title": "Emby Resume Entry Semantics",
  "criteria": [
    "For a server item with reviewed progress, Resume starts within the five-second observed-position bound of receipt.catalog.progressTicks from the inlined host report, as witnessed by the inlined playback.probe fields after Resume.",
    "Play from Beginning starts from 0 through 5 seconds inclusive under the observed-position bound decided by HC-021, as witnessed by the inlined second playback.probe fields."
  ],
  "negativeControls": [
    "An action return value without the post-action application state cannot satisfy the rubric.",
    "A missing required field, changed session identity where preservation is required, or stale snapshot produces a non-passing result.",
    "Reading local viewing storage, reversing the two actions, or opening PlayFromBeginning from a series-page episode card that starts playback immediately violates the rubric."
  ]
}
---
# Emby Resume Entry Semantics

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
