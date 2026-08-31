---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:format-coverage.unsupported-codec-guidance.o01@1",
  "title": "Unsupported codec guidance",
  "criteria": [
    "The bound media.open observation includes error=unsupportedVideoCodec, alertMessage containing MPEG-4 Part 2, identifier Emby-Playback-Error, primaryAction.present false for PlayerUI-loadFailure-primary, secondaryAction.present true for PlayerUI-loadFailure-secondary (Close), and closeOnly true.",
    "The bound media.open observation shows rejection before playback start: noActiveSession and noDeliveredSample are true, session and technicalSession are none, and videoSamples and rendererInputs are 0."
  ],
  "negativeControls": [
    "A fabricated basename, generic mediaOpeningFailed/playbackFailed issue, a Retry action (PlayerUI-loadFailure-primary present), steady-state playback, an active session, or any delivered video sample violates the typed preflight rejection."
  ]
}
---
# Unsupported codec guidance

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
