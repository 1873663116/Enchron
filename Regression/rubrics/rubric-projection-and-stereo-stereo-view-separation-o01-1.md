---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:projection-and-stereo.stereo-view-separation.o01@1",
  "title": "Stereo View Separation",
  "criteria": [
    "The bound artifact uses the media identity and capture request registered for its case: side-by-side uses MediaLibrary-grid-video-180_3D.mp4 and {context: portal, count: 3, minimumIntervalMillis: 1000}; top-bottom uses MediaLibrary-grid-video-180_3D_TB.mp4 with the same request; and mv-hevc-two-view uses MediaLibrary-grid-video-spatial_lighthouse_flowers_waves_short.mov with {context: window, count: 3, minimumIntervalMillis: 500}.",
    "The bound media segment has the format transaction registered for its case. If the bound case is side-by-side or top-bottom, its segment contains exactly one format.apply after media.open with requested values {deadlineSeconds: 30, projection: equirectangular180, stereoLayout: sideBySide} or {deadlineSeconds: 30, projection: equirectangular180, stereoLayout: topBottom} respectively, and observed values portal/equirectangular180/180/sideBySide or portal/equirectangular180/180/topBottom respectively. If the bound case is mv-hevc-two-view, its segment contains no format.apply after media.open and retains the source format.",
    "Every frame in the bound artifact has index 0, 1, or 2 exactly once, playbackState.available and controlPlane.available true, a content-bound screenshot record, and controlPlane.fields matching the registered case: side-by-side is userOverride/portal/equirectangular180/180/sideBySide with rendererProjectionKind HalfEquirectangular, rendererViewPackingKind SideBySide, windowComponentContentType halfEquirectangular, and actualViewingMode stereo; top-bottom has the same state with topBottom and OverUnder; mv-hevc-two-view is source/window/flat/multiview with mvHEVC true, rendererViewPackingKind none, windowComponentContentType stereo, actualViewingMode stereo, and actualSpatialVideoMode spatial.",
    "Within the bound three-frame sequence the session and streamEpoch are non-none and unchanged, lifecycle is Playing, displayedPixel is true, error is none, presentationObservation.observed equals the requested context, adjacent capturedAtMonotonicMillis values differ by at least the requested minimum interval, and the screenshots are nonblank changing images that show one unpacked view rather than a side-by-side or stacked packed source image."
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
