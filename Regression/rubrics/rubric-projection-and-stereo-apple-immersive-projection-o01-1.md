---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:projection-and-stereo.apple-immersive-projection.o01@1",
  "title": "Apple Immersive Projection",
  "criteria": [
    "In the current media segment, MediaLibrary-grid-video-Immersive-Video-example.f99766.mp4 is opened without a later format.apply, presentation.enter-panorama requests {deadlineSeconds: 45}, and the bound producer requests exactly {context: panorama, count: 3, minimumIntervalMillis: 1000}; source format, rather than a user override, remains authoritative.",
    "The producer returns exactly three frames with indices 0, 1, and 2; every playbackState and controlPlane is available, presentationObservation is expected panorama and observed panorama, each record has a content-bound screenshot attachment, and adjacent capturedAtMonotonicMillis values differ by at least 1000.",
    "In every frame controlPlane.fields has formatProvenance source, sourceContentKind appleImmersiveVideo, effective projection flat, effectiveContentIsPanoramic true, stereoLayout multiview, mvHEVC true, providerProjectionKind AppleImmersiveVideo, sampleProjectionKind AppleImmersiveVideo, rendererProjectionKind AppleImmersiveVideo, rendererViewPackingKind none, providerCodecName hevc, providerCodecTag hvc1, providerCodecConfiguration hvcC,lhvC, sampleMediaSubtype hvc1, sampleHasLhvC true, rendererHasLhvC true, and rendererInputIsMultiview true.",
    "Across all three frames session and streamEpoch are non-none and unchanged, lifecycle is Playing, presentation is panorama, windowComponentContentType is immersive, actualViewingMode is stereo, actualImmersiveMode is progressive, displayedPixel is true, error is none, and the screenshots contain nonblank changing Beach imagery. The flat effective projection is the correct domain value for Apple Immersive Video when these Apple-Immersive and immersive-geometry facts co-occur."
  ],
  "negativeControls": [
    "A user format override after media.open, a capture interval below 1000, a non-Apple provider/sample/renderer projection signal, packed stereo, missing lhvC or multiview facts, mono viewing, or a non-immersive content type violates the source-format and geometry contract.",
    "An ordinary flat fallback is established by rectilinear source/signaling or mono window geometry, not by the expected effective projection value flat alone; treating the expected Apple Immersive flat value as a fallback contradicts the structured product model.",
    "Unavailable structured fields or attachments, changed session or stream epoch, zero displayed pixels, an active issue, or insufficient timestamp separation is Indeterminate when the remaining evidence cannot decide the contract.",
    "Identical, blank, pure-color, base-eye-only, or undecodable screenshots violate the visual criterion once the three captures are valid; counters alone do not replace the captured frames."
  ]
}
---
# Apple Immersive Projection

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
