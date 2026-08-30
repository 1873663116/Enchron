---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:local-media-lifecycle.audio-track-switch-same-session.o01@1",
  "title": "Audio Track Switch Same Session",
  "criteria": [
    "The bound stable case selects the requested track identity, including the requested index for a duplicate label, while session identity remains unchanged: unique-label expectedAudioTrackID=1, duplicate-label-index-0 expectedAudioTrackID=2, duplicate-label-index-1 expectedAudioTrackID=3.",
    "measurement.dominantPulseHz equals the fixture-registry.json:503-505 pulse for the bound caseKey (unique-label=880, duplicate-label-index-0=440, duplicate-label-index-1=660) and lifecycle remains Playing."
  ],
  "negativeControls": [
    "An absent capture, measurement.silent true, rmsDbfs below SILENCE_RMS_DBFS=-75 from journey_audio_probe.py:18-23, or a missing measurement.dominantPulseHz is Indeterminate and never Satisfied.",
    "Renderer state alone cannot prove audibility, dominant frequency, channel delivery, or a requested track change.",
    "Matching only the label when duplicate tracks exist, retaining the prior dominantPulseHz, or reopening the session violates the rubric."
  ]
}
---
# Audio Track Switch Same Session

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
