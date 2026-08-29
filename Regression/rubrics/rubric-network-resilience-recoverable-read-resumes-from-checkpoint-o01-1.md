---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:network-resilience.recoverable-read-resumes-from-checkpoint.o01@1",
  "title": "Recoverable Read Resumes From Checkpoint",
  "criteria": [
    "A single injected recoverable read failure increments reconnection state and resumes from the checkpoint without emitting end-of-stream.",
    "Playback position crosses the interruption point and the stream topology after reconnect matches the original topology."
  ],
  "negativeControls": [
    "Controller success without the application-side delivery event is not evidence of product behavior.",
    "Missing sequence numbers, mismatched revisions, reversed order, or a truncated timing window cannot satisfy the rubric.",
    "Restart from zero, lifecycle Ended, duplicate samples across the checkpoint, or a topology mismatch accepted as recovery violates the rubric."
  ]
}
---
# Recoverable Read Resumes From Checkpoint

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
