---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:dynamic-range-interpretation.dolby-vision-profile-matrix.o01@1",
  "title": "Dolby Vision Profile Matrix",
  "criteria": [
    "The bound frame sequence exposes the exact (dolbyVisionProfile, dolbyVisionCrossCompatibilityID, dolbyVisionHasEnhancementLayer) tuple registered for its case: P5=(5,0,false), P7 FEL=(7,6,true), P8.1=(8,1,false), P8.4=(8,4,false), P10=(10,0,false), and P20=(20,0,false). Its sourcePixelFormat and destinationPixelFormat are non-none.",
    "sourceHasDvcC/sourceHasDvvC identify the real source configuration atoms and rendererHasDvcC/rendererHasDvvC preserve the delivered Dolby Vision configuration; at least one source atom is true and the renderer atom pair is justified by the same profile's real fallback/delivery branch rather than a Catalog constant.",
    "The bound frame sequence matches the color and fallback expectations registered for its case: P8.1 uses smpte2084/PQ with BT.2020 primaries, bt2020nc matrix, and video range; P8.4 uses arib-std-b67/HLG with the same primaries, matrix, and range; P7 uses the reviewed HDR10/PQ fallback without claiming enhancement-layer delivery; and P5, P10, and P20 retain their exact source tuple and real renderer configuration.",
    "The bound producer returns exactly three ordered frames separated by at least 1000 ms with stable session/stream epoch, strictly increasing position, pairwise-distinct content attachments, displayed pixels, and no active issue or whole-frame purple/green cast."
  ],
  "negativeControls": [
    "A profile/compatibility/enhancement tuple mismatch, missing dvcC/dvvC facts, source Format Description mutation, invented profile fixture, or treating P7 FEL presence as proof that the renderer consumed the enhancement layer fails the structured matrix.",
    "Missing canonical fields, repeated/blank/pure-color frames, changed session/stream epoch, non-advancing playback, or a whole-frame P5 cast is Indeterminate or failing as specified."
  ]
}
---
# Dolby Vision Profile Matrix

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
