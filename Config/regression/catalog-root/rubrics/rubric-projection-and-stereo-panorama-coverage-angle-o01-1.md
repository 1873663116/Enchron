---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:projection-and-stereo.panorama-coverage-angle.o01@1",
  "title": "Panorama Coverage Angle",
  "criteria": [
    "In the current media segment, defined as the latest media.open call through the bound format.apply producer, the request matches the registered case: equirectangular-180={deadlineSeconds: 30, projection: equirectangular180, stereoLayout: sideBySide}; equirectangular-360={deadlineSeconds: 30, projection: equirectangular360, stereoLayout: mono}; custom-angle-200 and custom-angle-240={deadlineSeconds: 30, projection: customAngle, horizontalCoverageDegrees: 200 and 240 respectively, stereoLayout: mono}. operationOutput.requested equals the bound format.apply arguments.",
    "The bound format.apply formatObservation.observed tuple matches its registered case: equirectangular-180=portal/equirectangular180/180/sideBySide, equirectangular-360=portal/equirectangular360/360/mono, custom-angle-200=portal/customAngle/200/mono, and custom-angle-240=portal/customAngle/240/mono. operationOutput.captureRequest is exactly {context: portal, count: 3, minimumIntervalMillis: 1000}. The two custom-angle cases additionally carry the declared route for a slider whose detents SwiftUI gives no identifiers: operationOutput.customAnglePicker is one tapSequence of PlayerUI-TopAction-videoFormat then PlayerUI-VideoFormat-CustomAngle, and operationOutput.customAngleSelection.listing enumerates the playerUI customAngle family and .selection reports the selected id equal to the requested degrees. No PlayerUI-VideoFormat-CustomAngle-<degrees> identifier is addressed anywhere in the bound transcript.",
    "Every frame in the bound artifact has playbackState.available and controlPlane.available true and controlPlane.fields with formatProvenance userOverride, presentation portal, effectiveContentIsPanoramic true, and the registered case's projection, horizontalFieldOfViewDegrees, and stereoLayout. The equirectangular-180 case additionally has rendererProjectionKind HalfEquirectangular, rendererViewPackingKind SideBySide, windowComponentContentType halfEquirectangular, and actualViewingMode stereo; equirectangular-360 and the custom-angle cases have rendererProjectionKind Equirectangular, rendererViewPackingKind none, windowComponentContentType equirectangular, and actualViewingMode mono; the bound case has actualImmersiveMode portal.",
    "The bound frame indices are exactly 0, 1, and 2, adjacent capturedAtMonotonicMillis values differ by at least 1000, session and streamEpoch remain non-none and unchanged, lifecycle is Playing, displayedPixel is true, error is none, and each content-bound screenshot is nonblank and changing while retaining the wrapped geometry declared by the structured state."
  ],
  "negativeControls": [
    "A format request, formatObservation.observed tuple, or per-frame product-state tuple that differs from the bound case violates the coverage contract, including a custom angle rounded or replaced by 180 or 360.",
    "A flat projection, non-panoramic state, wrong RealityKit content type or viewing mode, missing renderer projection, or packed stereo in a mono case violates the geometry contract.",
    "Unavailable structured state, missing frame records or attachments, insufficient timestamp separation, or a contradiction between transcript output and frame state is Indeterminate rather than inferred from the remaining modality.",
    "A custom-angle case whose coverage is not carried by the recorded listMenuItems/selectMenuItem transaction, or whose transcript addresses a per-degree identifier the product does not publish, has no real execution route and is Indeterminate."
  ]
}
---
# Panorama Coverage Angle

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
