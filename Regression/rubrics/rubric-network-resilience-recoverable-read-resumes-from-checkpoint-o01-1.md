---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:network-resilience.recoverable-read-resumes-from-checkpoint.o01@1",
  "title": "Recoverable Read Resumes From Checkpoint",
  "criteria": [
    "The bound interaction.trace inlines the pre-fault playback.probe fields and the post-recovery expectationObservation: demuxReconnects increases by at least one, topologyDigest matches the original topology, lifecycle remains Playing, and positionMillis advances from at least 5000 to at least 8000 without Ended.",
    "The inlined post-recovery fields keep the same session and streamEpoch as the original probe, and videoSamples continues to increase after the injected recoverable read."
  ],
  "negativeControls": [
    "Controller success without the application-side delivery event is not evidence of product behavior.",
    "Restart from zero, lifecycle Ended, a topologyDigest mismatch, a changed session or streamEpoch, or a non-increasing videoSamples count after reconnect cannot Satisfy.",
    "Missing sequence numbers, reversed sample order, or duplicate sample identities are not in the published probe fields and cannot be invented to Satisfy or Violated."
  ]
}
---
# Recoverable Read Resumes From Checkpoint

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
