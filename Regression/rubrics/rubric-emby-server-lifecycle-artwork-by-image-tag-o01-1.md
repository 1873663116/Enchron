---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:emby-server-lifecycle.artwork-by-image-tag.o01@1",
  "title": "Artwork By Image Tag",
  "criteria": [
    "The image request uses the server image endpoint and the persisted cache key includes the server-provided image tag.",
    "The bound emby.evidence inlines viewingStorageObservation; directory content and viewing progress remain absent from that snapshot (viewingRecordCount 0 and no viewingState entries)."
  ],
  "negativeControls": [
    "A command exit code or test name without the structured assertion payload cannot satisfy the rubric.",
    "Missing artworkLoads[].itemID produces Indeterminate rather than Satisfied; an observed itemID that does not equal receipt.catalog.episodeID or seriesID from the inlined host report is mixed-provenance evidence and violates the rubric.",
    "A loopback media endpoint request, an item-id-only cache key, or viewing-storage entries/progress present in the inlined snapshot violates the rubric."
  ]
}
---
# Artwork By Image Tag

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
