---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:local-media-lifecycle.audio-track-switch-same-session.o01@1",
  "title": "Audio Track Switch Same Session",
  "criteria": [
    "The bound stable case selects the requested track identity, including the requested index for a duplicate label, while session identity remains unchanged.",
    "The structured audio measurement changes to the requested fixture frequency and lifecycle remains Playing."
  ],
  "negativeControls": [
    "An absent, clipped, or noise-floor-only capture is Indeterminate and never Satisfied.",
    "Renderer state alone cannot prove audibility, dominant frequency, channel delivery, or a requested track change.",
    "Matching only the label when duplicate tracks exist, retaining the prior dominant frequency, or reopening the session violates the rubric."
  ]
}
---
# Audio Track Switch Same Session

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
