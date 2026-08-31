---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:emby-server-lifecycle.emby-artwork-bypasses-loopback.o01@1",
  "title": "Emby Artwork Bypasses Loopback",
  "criteria": [
    "The bound emby.evidence carries an artworkLoads entry whose sanitizedRequestURL is present and is the server image endpoint /Items/<that entry's itemID>/Images/<that entry's imageType> carrying Tag=<that entry's imageTag>, and whose host is none of localhost, 127.0.0.1 or ::1. That entry's loopbackHitCount is observed 0, or is notApplicable for no-network-request while its cacheHit is observed true, and no artworkLoads entry in the artifact reports a loopbackHitCount above 0. The route is decided from the sanitized URL and the loopback counter because the product publishes no other reading of where the image came from.",
    "That same artworkLoads entry binds to the prepared item and tag: its itemID equals the inlined host report's receipt.catalog.seriesID and its imageTag equals that report's receipt.catalog.imageTag, and its persistedCache is observed with artworkKey equal to that entry's own cacheKey, a 64-character lowercase hex digest. The binding decided here is that itemID, imageTag and cacheKey equality, never a decoding of the digest: the evidence never exposes the key's preimage, so no field of the persisted entry can be read back as an item or a tag."
  ],
  "negativeControls": [
    "A command exit code or test name without the structured assertion payload cannot satisfy the rubric.",
    "Missing artworkLoads[].itemID produces Indeterminate rather than Satisfied; an observed itemID that does not equal receipt.catalog.episodeID or seriesID from the inlined host report is mixed-provenance evidence and violates the rubric.",
    "Any loopback artwork request, missing tag, or artwork bound to a different item violates the rubric. So does an absent persistedCache observation, a persistedCache artworkKey that differs from that entry's cacheKey, a cacheKey that is not a 64-character lowercase hex digest, and a sanitizedRequestURL that is null, which the product publishes exactly when the request route did not match the item, the image type, and the tag. An empty artworkLoads produces Indeterminate rather than Satisfied."
  ]
}
---
# Emby Artwork Bypasses Loopback

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
