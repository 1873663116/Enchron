---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:emby-server-lifecycle.artwork-by-image-tag.o01@1",
  "title": "Artwork By Image Tag",
  "criteria": [
    "The bound emby.evidence carries an artworkLoads entry whose itemID is the inlined host report's receipt.catalog.seriesID and whose imageTag is that report's receipt.catalog.imageTag; its sanitizedRequestURL is the server image endpoint /Items/<that seriesID>/Images/Primary carrying Tag=<that imageTag>; and its persistedCache is observed with artworkKey equal to that same entry's cacheKey, a 64-character lowercase hex digest. The stored entry is keyed by the tag-bearing request rather than by the item; that the tag itself participates in the key is the separate alternateTagCacheKey criterion, because the evidence never exposes the digest's preimage.",
    "The bound emby.evidence inlines viewingStorageObservation; directory content and viewing progress remain absent from that snapshot (viewingRecordCount 0 and no viewingState entries).",
    "The same artworkLoads entry carries alternateTagCacheKey different from its cacheKey, which establishes that the image tag participates in the persisted key without reading the tag back out of a SHA-256 whose preimage carries the api_key."
  ],
  "negativeControls": [
    "A command exit code or test name without the structured assertion payload cannot satisfy the rubric.",
    "Missing artworkLoads[].itemID produces Indeterminate rather than Satisfied; an observed itemID that does not equal receipt.catalog.episodeID or seriesID from the inlined host report is mixed-provenance evidence and violates the rubric.",
    "A loopback media endpoint request violates the rubric, and so does an item-id-only cache key: a cacheKey equal to that entry's itemID, a cacheKey that is not a 64-character lowercase hex digest, an alternateTagCacheKey that is absent or equal to the cacheKey - the image tag is then outside the key - or a persistedCache artworkKey that differs from that cacheKey. Viewing-storage entries or progress present in the inlined snapshot also violate the rubric."
  ]
}
---
# Artwork By Image Tag

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
