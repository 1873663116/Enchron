---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:dynamic-range-interpretation.dolby-vision-profile-matrix.o01@1",
  "title": "Dolby Vision Profile Matrix",
  "criteria": [
    "The bound frame sequence exposes the exact (dolbyVisionProfile, dolbyVisionCrossCompatibilityID, dolbyVisionHasEnhancementLayer) tuple registered for its case: P5=(5,0,false), P7 FEL=(7,6,true), P8.1=(8,1,false), P8.4=(8,4,false), and P10=(10,0,false). Its sourcePixelFormat and destinationPixelFormat are non-none.",
    "sourceHasDvcC/sourceHasDvvC identify the real source configuration atoms and rendererHasDvcC/rendererHasDvvC preserve the delivered Dolby Vision configuration, each justified by the same profile's real fallback/delivery branch rather than a Catalog constant. The single-layer cases dv-profile-5, dv-profile-8-hdr10, dv-profile-8-hlg and dv-profile-10 each carry at least one true source atom. dv-profile-7-dual is the reviewed dual-layer exception: its FEL declaration is classified as HEVC dual layer, excluded from the Format Description, and only its HDR10 base layer is delivered, so sourceHasDvcC and sourceHasDvvC are both none and neither renderer atom is true, while criterion 1's (7, 6, true) tuple still reads from the source declaration.",
    "The bound frame sequence matches the color and fallback expectations registered for its case: P8.1 uses smpte2084/PQ with BT.2020 primaries, bt2020nc matrix, and video range; P8.4 uses arib-std-b67/HLG with the same primaries, matrix, and range; P7 uses the reviewed HDR10/PQ fallback without claiming enhancement-layer delivery; and P5 and P10 retain their exact source tuple and real renderer configuration. dv-profile-10 carries sourceYCbCrMatrix and rendererYCbCrMatrix both exactly IPT_C2, the private string the bridge maps the P10.0 base layer's IPT-C2 declaration to, and a different reading on either field fails the case. Its colour is judged on the same terms as every other case.",
    "The bound producer returns exactly three ordered frames separated by at least 1000 ms with stable session/stream epoch, strictly increasing position, pairwise-distinct content attachments, displayed pixels, and no active issue."
  ],
  "negativeControls": [
    "A profile/compatibility/enhancement tuple mismatch, missing dvcC/dvvC facts on a single-layer case, a true source or renderer atom on dv-profile-7-dual, source Format Description mutation, invented profile fixture, a dv-profile-10 source or renderer YCbCr matrix reading other than IPT_C2, or treating P7 FEL presence as proof that the renderer consumed the enhancement layer fails the structured matrix.",
    "Missing canonical fields, repeated/blank/pure-color frames, changed session/stream epoch, or non-advancing playback is Indeterminate or failing as specified."
  ]
}
---
# Dolby Vision Profile Matrix

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
