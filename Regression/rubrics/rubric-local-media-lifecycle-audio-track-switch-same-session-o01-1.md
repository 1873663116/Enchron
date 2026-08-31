---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:local-media-lifecycle.audio-track-switch-same-session.o01@1",
  "title": "Audio Track Switch Same Session",
  "criteria": [
    "The bound stable case selects the requested track identity, including the requested index for a duplicate label, while session identity remains unchanged: unique-label expectedAudioTrackID=1, duplicate-label-index-0 expectedAudioTrackID=2, duplicate-label-index-1 expectedAudioTrackID=3.",
    "measurement.dominantPulseHz equals the pulse the opened fixture registers for the bound caseKey. The Scenario opens sdr-bframe-duplicate-label-audio-30s.mkv, whose oracle tracks are Tests/Fixtures/fixture-registry.json:697-716: streamIndex 1 is 880, streamIndex 2 is 440, streamIndex 3 is 660, and PlaybackRuntime.swift:621 maps selectedAudioStreamIndex to that same string. So unique-label=880, duplicate-label-index-0=440, duplicate-label-index-1=660, and lifecycle remains Playing."
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
