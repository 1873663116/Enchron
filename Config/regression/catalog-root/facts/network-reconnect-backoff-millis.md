---
{
  "schema": "enchron.regression.fact",
  "schemaVersion": 1,
  "id": "fact:network.reconnect-backoff-millis",
  "title": "Network reconnect backoff millis",
  "statement": "Demux reconnection has three finite backoff delays.",
  "valueType": "string",
  "value": "[\"250\",\"500\",\"1000\"]",
  "provenance": {
    "kind": "product-constant",
    "path": "Packages/PlaybackCore/Sources/PlaybackFFmpegBridge/PlaybackFFmpegBridge.c",
    "pattern": "PB_DEMUX_RECONNECT_BACKOFF_MILLISECONDS\\[\\]\\s*=\\s*\\{([^}]*)\\}",
    "transform": "number-list"
  }
}
---
# Network reconnect backoff millis

The blueprint recorded design-time status `reviewed` and value `["250","500","1000"]`.

Catalog v1 Facts admit boolean, integer, or string values. This list is therefore supplied to a compile request as the canonical JSON string `["250","500","1000"]`.

The declaration does not certify a value for a run. A compile request must supply the reviewed value and its review provenance.
