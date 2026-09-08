---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:dynamic-range-interpretation.docked-hlg-audio-integrity.o02@1",
  "title": "Docked HLG Audio Is Audible",
  "criteria": [
    "The five-second capture on Steinberg UR12, bound to call 05's session, is not silent and measurement.dominantPulseHz is close to 660 Hz, matching the HLG fixture's registered audio (Tests/Fixtures/fixture-registry.json, generated-hlg-hevc10-avsync-10s-v1: \"AAC LC 48 kHz stereo; 660 Hz 80 ms pulses aligned with a white video flash every second\").",
    "The capture is taken while docked and lifecycle remains Playing for its duration, proving the audible signal survives the docked entry rather than predating it."
  ],
  "negativeControls": [
    "An absent capture, measurement.silent true, rmsDbfs below the silence floor, or a missing measurement.dominantPulseHz is Indeterminate and never Satisfied.",
    "A dominantPulseHz far from 660 Hz, a mismatched session, or a non-Playing lifecycle during the capture violates the rubric."
  ]
}
---
# Docked HLG Audio Is Audible

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
