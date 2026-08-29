---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:format-coverage.unsupported-codec-guidance.o01@1",
  "title": "Unsupported codec guidance",
  "criteria": [
    "Opening registered fixture internal-fate-mpeg4-part2-packed-bframes-v1 through MediaLibrary-grid-video-packed_bframes.avi yields category unsupportedVideoCodec with codec-specific MPEG-4 Part 2 guidance and only the policy-declared Close action.",
    "The open transcript and bound issue hierarchy show rejection before playback start: no active media session and no delivered video sample are present."
  ],
  "negativeControls": [
    "A fabricated basename, generic mediaOpeningFailed/playbackFailed issue, steady-state playback, an active session, or any delivered video sample violates the typed preflight rejection."
  ]
}
---
# Unsupported codec guidance

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
