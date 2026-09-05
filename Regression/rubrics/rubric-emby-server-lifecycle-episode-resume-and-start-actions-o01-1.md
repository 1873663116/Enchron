---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:emby-server-lifecycle.episode-resume-and-start-actions.o01@1",
  "title": "Episode Resume And Start Actions",
  "criteria": [
    "The bound emby.evidence inlines the inspect matchedElement object from episode detail whose identifier field is Emby-Detail-Play, present before the action is opened, and the Play activate response from call 06 that succeeded, after which the Resume Playback? alert offers PlayerUI-resumeDecision-primary and PlayerUI-resumeDecision-secondary.",
    "The bound document inlines the host emby-aggregate report and two playback.probe fields: the Resume choice's position is within the five-second observed-position bound of receipt.catalog.progressTicks, the Play from Start choice's position is from 0 through 5 seconds inclusive, and both probes share the same Emby item identity as that report.",
    "The bound document inlines the same-attempt Resume choice activate's activatedAtMonotonicMillis from call 07, that same attempt's playback.await-window-state elapsedMillis, and the capture-frames list, and it decides HC-018's 45000 ms bound from the one interval this instrument resolves: frames[0].capturedAtMonotonicMillis minus activatedAtMonotonicMillis is at most 45000 ms, and frame 0 itself reports lifecycle Playing with displayedPixel true, so the bound is read against a frame that already carries a picture. That interval is an upper bound on click-to-first-frame and never an understatement, because frame 0 is the first capture taken after the wait has already observed playing: it contains the product's whole open plus the instrument's share, of which the inlined elapsedMillis is the wait and the remainder is the activate's return and one diagnostics.playback-state@1 snapshot, device median 3.91 s in Scripts/verification/controller_timings.json. The changing half of the claim is decided without a time bound: at least one later frame has a screenshotDigest differing from frame 0's and a strictly greater position. No spacing between adjacent frames is read as a product latency, because each capture iteration costs two controller snapshots at that same median, so the spacing is the instrument's. 90000 ms is only the harness liveness deadline."
  ],
  "negativeControls": [
    "An action return value without the post-action application state cannot satisfy the rubric.",
    "A missing required field, changed session identity where preservation is required, or stale snapshot produces a non-passing result.",
    "One choice aliasing the other, using local progress, changing the item identity, or reaching playback without the alert from a series-page episode card violates the rubric.",
    "Treating the 90000 ms liveness deadline as the product threshold violates HC-018."
  ]
}
---
# Episode Resume And Start Actions

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
