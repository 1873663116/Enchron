---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:dynamic-range-interpretation.hdr10-hlg-interpretation.o01@1",
  "title": "Hdr10 Hlg Interpretation",
  "criteria": [
    "The bound frame sequence exposes the transfer-function atom set registered for its case: generated-pq-hevc10-avsync-10s-v1 uses the closed 2084/PQ set, and generated-hlg-hevc10-avsync-10s-v1 uses the closed HLG/B67/2100 set. sourceTransferFunction, sampleTransferFunction, and rendererTransferFunction each match that registered set.",
    "The bound case's sourceColorPrimaries/sampleColorPrimaries/rendererColorPrimaries match the reviewed 2020 atom, sourceYCbCrMatrix/sampleYCbCrMatrix/rendererYCbCrMatrix match the reviewed 2020 matrix atom, and sourceRange/sampleRange/rendererRange match the reviewed video/TV range atom. sourceMasteringDisplayMetadata and sourceContentLightLevelMetadata are preserved unchanged through sample and renderer, and sourcePixelFormat/destinationPixelFormat are non-none.",
    "The producer requests exactly three frames at minimumIntervalMillis=1000; indices are 0,1,2, adjacent capture timestamps differ by at least 1000 ms, attachment digests are pairwise distinct, and playback position strictly increases while lifecycle remains Playing and no issue is active."
  ],
  "negativeControls": [
    "Using sampleTransfer instead of canonical sampleTransferFunction, accepting an unspecified transfer/matrix/range, source→sample→renderer metadata drift, missing structured fields, or fewer than three valid ordered frames is Indeterminate or failing as the criterion states.",
    "Blank/pure-color frames, repeated attachment bytes, or non-advancing playback fails the bound visual.frames artifact."
  ]
}
---
# Hdr10 Hlg Interpretation

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
