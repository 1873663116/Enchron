---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:dynamic-range-interpretation.dolby-vision-cross-compatibility-switch.o01@1",
  "title": "Dolby Vision Cross Compatibility Switch",
  "criteria": [
    "P8.1 and P8.4 each deliver one surface→videoFormat→HDRFallback→apply transaction. Their source tuples remain (8,1,false) and (8,4,false), source Format Description and source dvcC/dvvC atom pair remain unchanged, while renderer configuration switches to the reviewed HDR10/PQ and HLG/B67 branches respectively and renderer dvcC/dvvC facts reflect that fallback.",
    "P5 remains (5,0,false); after surface→videoFormat, the complete inspect response has matchedElement=null for PlayerUI-VideoFormat-HDRFallback, then cancel is delivered. Its source and renderer Dolby Vision atom facts remain present and no fallback mutation occurs.",
    "The bound producer returns three ordered frameSequences for P8.1, P8.4, and P5. Each sequence contains exactly three Playing frames at 1000 ms minimum intervals with stable session/revision, strictly increasing position, pairwise-distinct content attachments, non-none source/destination pixel formats, and no issue or whole-frame cast."
  ],
  "negativeControls": [
    "Split transient editor actions, fallback offered for P5, changed source tuple/Format Description, renderer transfer unrelated to P8.1/P8.4 compatibility, missing dvcC/dvvC facts, or UI action without renderer-state change fails the contract.",
    "A missing full hierarchy for the P5 absence check, fewer than three valid frames, repeated/blank attachments, or non-advancing playback is Indeterminate or failing as specified."
  ]
}
---
# Dolby Vision Cross Compatibility Switch

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
