---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:emby-server-lifecycle.episode-resume-and-start-actions.o01@1",
  "title": "Episode Resume And Start Actions",
  "criteria": [
    "The bound emby.evidence inlines two inspect matchedElement objects from episode detail whose identifier fields are Emby-Detail-Resume and Emby-Detail-PlayFromBeginning, both present before either action is opened.",
    "The bound document inlines the host emby-aggregate report and two playback.probe fields: Resume position is within the five-second observed-position bound of receipt.catalog.progressTicks, Play from Beginning is from 0 through 5 seconds inclusive, and both probes share the same Emby item identity as that report.",
    "The bound document inlines the same-attempt Resume activate's activatedAtMonotonicMillis and the capture-frames list. The first frame whose screenshotDigest differs from the previous frame has capturedAtMonotonicMillis minus that activate timestamp at most 45000 ms; 90000 ms is only the harness liveness deadline."
  ],
  "negativeControls": [
    "An action return value without the post-action application state cannot satisfy the rubric.",
    "A missing required field, changed session identity where preservation is required, or stale snapshot produces a non-passing result.",
    "One action aliasing the other, using local progress, changing the item identity, or opening PlayFromBeginning from a series-page episode card that starts playback immediately violates the rubric.",
    "Treating the 90000 ms liveness deadline as the product threshold violates HC-018."
  ]
}
---
# Episode Resume And Start Actions

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
