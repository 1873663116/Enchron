---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:projection-and-stereo.apple-immersive-projection.o01@1",
  "title": "Apple Immersive Projection",
  "criteria": [
    "The media is opened without a later format.apply or seek, presentation.enter-panorama requests deadlineSeconds 45, and the bound producer requests exactly context panorama, count 3, and minimumIntervalMillis 1000.",
    "The producer returns exactly three indexed frames; every playbackState is available, presentationObservation is expected and observed panorama, each record has a content-bound screenshot attachment, and adjacent capture times differ by at least 1000 ms.",
    "In every frame playbackState.fields reports source format provenance, Apple Immersive content and projection signals, multiview stereo, MV-HEVC, hvc1 with hvcC and lhvC configuration, and multiview renderer input.",
    "Across all frames session and stream epoch are stable, lifecycle is Playing, presentation is panorama, the immersive geometry is stereo progressive with displayed pixels, no error is active, and screenshots contain nonblank changing Beach imagery."
  ],
  "negativeControls": [
    "A user format override or seek, short capture interval, non-Apple projection signal, packed stereo, missing lhvC or multiview facts, mono geometry, changed session or epoch, zero displayed pixels, an active issue, or blank, identical, pure-color, or undecodable screenshots fails or makes the claim indeterminate according to the missing evidence."
  ]
}
---
# Apple Immersive Projection

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
