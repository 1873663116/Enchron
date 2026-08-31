---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:format-coverage.signalled-media-classification.o01@1",
  "title": "Signalled Media Classification",
  "criteria": [
    "Every frame in the bound artifact has playbackState.available and controlPlane.available true, and its controlPlane.fields report formatProvenance source together with the classification registered for the case, so no override is in play and the presentation follows the source declaration. For caseKey apple-apmp-180 the fields are sourceContentKind halfEquirectangular, projection equirectangular180, horizontalFieldOfViewDegrees 180, effectiveContentIsPanoramic true, stereoLayout multiview, mvHEVC true, rendererViewPackingKind none, presentation portal and attached portal, with windowComponentContentType halfEquirectangular and actualViewingMode stereo -- the settled surface a source-provenance half-equirectangular multiview media requires (Modules/Playback/Model/SpatialPlaybackSurfaceSettlementPolicy.swift:13 and :39-45). For caseKey mv-hevc-stereo they are projection flat, effectiveContentIsPanoramic false, stereoLayout multiview, mvHEVC true, rendererViewPackingKind none, presentation window and attached window, with windowComponentContentType stereo, actualViewingMode stereo and actualSpatialVideoMode spatial. These are the declarations Tests/Fixtures/fixture-registry.json registers for the two fixtures -- internal-apple-apmp-180-v1 projection equirectangular180, stereoLayout multiview, 180 degrees; internal-apple-mvhevc-short-v1 projection rectilinear, stereoLayout multiview -- restated here as the field values the bound artifact carries, because the registry itself is not bound evidence. Neither case's tuple may be the other's.",
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
