---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:format-coverage.signalled-media-classification.o01@1",
  "title": "Signalled Media Classification",
  "criteria": [
    "The source classification, effective presentation, attachment, projection, and packing agree with the reviewed fixture declaration for the case.",
    "For caseKey apple-apmp-180, whose fixture runs 85 s, the three captured frames have pairwise-different screenshotDigest values and each frame's playbackState.fields shows position, videoSamples and rendererInputs strictly advancing. For caseKey mv-hevc-stereo the frames are required only to be valid and to agree with presentationObservation, because the registered fixture runs 4.05 s while three device-lane frames cost about 23 s, so a correct product would show one frozen final frame."
  ],
  "negativeControls": [
    "If any required modality is invalid or missing, the result is Indeterminate rather than inferred from the remaining modality.",
    "Contradictory valid artifacts produce Indeterminate; no majority vote or best-effort selection is permitted.",
    "Landing in a presentation that contradicts source signalling or treating a 4-second fixture timeout as success violates the rubric."
  ]
}
---
# Signalled Media Classification

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
