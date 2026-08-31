---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:library-management.confirmed-batch-deletion.o01@1",
  "title": "Confirmed batch deletion",
  "criteria": [
    "The bound library.snapshot@1 output names its three baselines by file name and decides the deletion by name, not by count. referenceComparisons holds one entry per import in call order, each pairing a baselineReferenceID with the fileName that import returned: the entry whose baseline.fileName is sdr-bframe-multiaudio-avsync-30s.mp4 and the entry whose baseline.fileName is sdr-bframe-aggregate-30s.mkv -- exactly the two MediaLibrary-grid-video- cards call 08 activated -- each report currentReference null, while the entry whose baseline.fileName is sdr-bframe-multiaudio-subtitles-30s.mkv reports a currentReference whose id equals its own referenceID. priorSnapshot is call 10's pre-confirmation reading, taken after MediaLibrary-MultiSelect-delete and before MediaLibrary-MultiSelect-confirmDelete, and its references still carry all three of those referenceIDs, so the two named files disappear only across the destructive confirmation and a run that deleted the wrong pair fails the criterion.",
    "The unselected reference sdr-bframe-multiaudio-subtitles-30s.mkv appears exactly once in the final snapshot.references, and no source file was touched: every referenceComparisons entry has a non-null stagedFile whose name equals that entry's baseline.fileName, the three names are exactly sdr-bframe-multiaudio-avsync-30s.mp4, sdr-bframe-aggregate-30s.mkv and sdr-bframe-multiaudio-subtitles-30s.mkv, and each stagedFile.digest and sizeInBytes equal the priorSnapshot.stagedFiles entry of the same name. Deleting a library reference is therefore proved not to have deleted or rewritten the bytes behind it."
  ],
  "negativeControls": [
    "Deletion before the confirmation, a currentReference still present for sdr-bframe-multiaudio-avsync-30s.mp4 or sdr-bframe-aggregate-30s.mkv, a currentReference gone for sdr-bframe-multiaudio-subtitles-30s.mkv, or any stagedFile missing or with a changed digest violates the contract."
  ]
}
---
# Confirmed batch deletion

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
