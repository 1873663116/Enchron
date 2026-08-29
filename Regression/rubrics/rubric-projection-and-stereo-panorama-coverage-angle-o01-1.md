---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:projection-and-stereo.panorama-coverage-angle.o01@1",
  "title": "Panorama Coverage Angle",
  "criteria": [
    "In the current media segment, defined as the latest media.open call through the bound capture producer, equirectangular-180 requests {deadlineSeconds: 30, projection: equirectangular180, stereoLayout: sideBySide}; equirectangular-360 requests {deadlineSeconds: 30, projection: equirectangular360, stereoLayout: mono}; custom-angle-200 and custom-angle-240 request {deadlineSeconds: 30, projection: customAngle, horizontalCoverageDegrees: 200 or 240, stereoLayout: mono}. In every case operationOutput.requested equals the format.apply arguments.",
    "The format.apply formatObservation.observed tuple is exactly portal/equirectangular180/180/sideBySide, portal/equirectangular360/360/mono, portal/customAngle/200/mono, or portal/customAngle/240/mono for the corresponding case, and the capture producer request is exactly {context: portal, count: 3, minimumIntervalMillis: 1000}.",
    "Every frame has playbackState.available and controlPlane.available true and controlPlane.fields with formatProvenance userOverride, presentation portal, effectiveContentIsPanoramic true, and the case's observed projection, horizontalFieldOfViewDegrees, and stereoLayout. The 180 case additionally has rendererProjectionKind HalfEquirectangular, rendererViewPackingKind SideBySide, windowComponentContentType halfEquirectangular, and actualViewingMode stereo; the 360 and both custom-angle cases have rendererProjectionKind Equirectangular, rendererViewPackingKind none, windowComponentContentType equirectangular, and actualViewingMode mono; all four have actualImmersiveMode portal.",
    "The frame indices are exactly 0, 1, and 2, adjacent capturedAtMonotonicMillis values differ by at least 1000, session and streamEpoch remain non-none and unchanged, lifecycle is Playing, displayedPixel is true, error is none, and each content-bound screenshot is nonblank and changing while retaining the wrapped geometry declared by the structured state."
  ],
  "negativeControls": [
    "A format request, formatObservation.observed tuple, or per-frame product-state tuple that differs from the bound case violates the coverage contract, including a custom angle rounded or replaced by 180 or 360.",
    "A flat projection, non-panoramic state, wrong RealityKit content type or viewing mode, missing renderer projection, or packed stereo in a mono case violates the geometry contract.",
    "Unavailable structured state, missing frame records or attachments, insufficient timestamp separation, or a contradiction between transcript output and frame state is Indeterminate rather than inferred from the remaining modality."
  ]
}
---
# Panorama Coverage Angle

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
