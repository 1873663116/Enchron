---
{
  "schema": "enchron.regression.fact",
  "schemaVersion": 1,
  "id": "fact:network.prefetch-target-seconds",
  "title": "Network prefetch target seconds",
  "statement": "A subscribed demux queue stops on whichever comes first: the 150 MB forward byte limit, or the non-cache target duration in seconds.",
  "valueType": "integer",
  "value": 1,
  "provenance": {
    "kind": "product-constant",
    "path": "Packages/PlaybackCore/Sources/PlaybackFFmpegBridge/PlaybackFFmpegBridge.c",
    "pattern": "PB_DEMUX_DEFAULT_NON_CACHE_TARGET_SECONDS\\s*=\\s*([0-9.]+)\\s*;",
    "transform": "integer"
  }
}
---
# Network prefetch target seconds

The blueprint recorded design-time status `reviewed` and value `6`.

The declaration does not certify a value for a run. A compile request must supply the reviewed value and its review provenance.
