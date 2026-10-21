---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:dynamic-range-interpretation.hdr10-hlg-interpretation.o01@1",
  "title": "Hdr10 Hlg Interpretation",
  "criteria": [
    "The bound frame sequence exposes the transfer-function atom set registered for its case: generated-pq-hevc10-avsync-10s-v1 uses the closed 2084/PQ set, and generated-hlg-hevc10-avsync-10s-v1 uses the closed HLG/B67/2100 set. sourceTransferFunction, sampleTransferFunction, and rendererTransferFunction each match that registered set.",
    "The bound case's sourceColorPrimaries/sampleColorPrimaries/rendererColorPrimaries match the reviewed 2020 atom, sourceYCbCrMatrix/sampleYCbCrMatrix/rendererYCbCrMatrix match the reviewed 2020 matrix atom, and sourceRange/sampleRange/rendererRange match the reviewed video/TV range atom. sourceMasteringDisplayMetadata and sourceContentLightLevelMetadata are preserved unchanged through sample and renderer, and sourcePixelFormat/destinationPixelFormat are non-none.",
    "The producer requests exactly three frames at minimumIntervalMillis=1000; indices are 0, 1 and 2, adjacent capture timestamps differ by at least 1000 ms, and every frame is valid -- its structured playback state available, its screenshot record content-bound, its session and streamEpoch non-none and unchanged across the sequence, and no issue active. The first frame is taken immediately after playback.await-window-state@1 settles on playing, so it reports lifecycle Playing at a position inside the media. The second and third frames are required only to be valid and to hold that same identity; their attachment digests may repeat and their positions need not advance, because both registered fixtures run 10.0 s -- generated-pq-hevc10-avsync-10s-v1 and generated-hlg-hevc10-avsync-10s-v1 in Tests/Fixtures/fixture-registry.json -- while three device-lane frames cost about 23 s, two controller round trips each, so under the default endBehavior, which now ends playback and waits for the ended-state transport affordance instead of auto-repeating, a correct product has reached end of media before they are taken."
  ],
  "negativeControls": [
    "Using sampleTransfer instead of canonical sampleTransferFunction, accepting an unspecified transfer/matrix/range, source→sample→renderer metadata drift, missing structured fields, or fewer than three valid ordered frames is Indeterminate or failing as the criterion states.",
    "A blank or pure-color first frame, a first frame whose lifecycle is not Playing, or a missing or invalid frame at any index fails or leaves Indeterminate the bound visual.frames artifact. Repeated attachment bytes or a non-advancing position in the second and third frames do not, for the duration reason criterion 3 states."
  ]
}
---
# Hdr10 Hlg Interpretation

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
