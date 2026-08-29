---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:projection-and-stereo.stereo-view-separation.o01@1",
  "title": "Stereo View Separation",
  "criteria": [
    "In the current media segment, defined as the latest media.open call through the bound capture producer, side-by-side opens MediaLibrary-grid-video-180_3D.mp4 and requests capture {context: portal, count: 3, minimumIntervalMillis: 1000}; top-bottom opens MediaLibrary-grid-video-180_3D_TB.mp4 with the same capture request; mv-hevc-two-view opens MediaLibrary-grid-video-spatial_lighthouse_flowers_waves_short.mov and requests {context: window, count: 3, minimumIntervalMillis: 500}.",
    "The side-by-side and top-bottom segments each contain exactly one format.apply after media.open: its arguments and operationOutput.requested are respectively {deadlineSeconds: 30, projection: equirectangular180, stereoLayout: sideBySide} and {deadlineSeconds: 30, projection: equirectangular180, stereoLayout: topBottom}; formatObservation.observed is respectively {presentation: portal, projection: equirectangular180, horizontalFieldOfViewDegrees: 180, stereoLayout: sideBySide} and the same tuple with topBottom. The mv-hevc-two-view segment contains no format.apply after media.open and therefore retains the source format.",
    "Every frame has index 0, 1, or 2 exactly once, playbackState.available and controlPlane.available true, a content-bound screenshot record, and controlPlane.fields matching its case: side-by-side is userOverride/portal/equirectangular180/180/sideBySide with rendererProjectionKind HalfEquirectangular, rendererViewPackingKind SideBySide, windowComponentContentType halfEquirectangular, and actualViewingMode stereo; top-bottom has the same state with topBottom and OverUnder; mv-hevc-two-view is source/window/flat/multiview with mvHEVC true, rendererViewPackingKind none, windowComponentContentType stereo, actualViewingMode stereo, and actualSpatialVideoMode spatial.",
    "Within each three-frame sequence the session and streamEpoch are non-none and unchanged, lifecycle is Playing, displayedPixel is true, error is none, presentationObservation.observed equals the requested context, adjacent capturedAtMonotonicMillis values differ by at least the requested minimum interval, and the screenshots are nonblank changing images that show one unpacked view rather than a side-by-side or stacked packed source image."
  ],
  "negativeControls": [
    "A missing or extra current-segment format.apply, a request/output mismatch, a wrong capture context or interval, or a product format tuple that differs from the case mapping violates the transcript and product-state contract.",
    "A frame with unavailable structured state, a missing screenshot attachment, a changed session or stream epoch, no displayed pixel, or an undecidable packing or geometry field is Indeterminate; an image alone cannot replace the structured fields.",
    "A corrupt, blank, pure-color, repeated-identical, side-by-side-packed, or over-under-packed output frame violates the visual separation contract once capture validity is established."
  ]
}
---
# Stereo View Separation

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
