---
{
  "schema": "enchron.regression.operation",
  "schemaVersion": 1,
  "id": "operation:playback.select-subtitle@1",
  "title": "Playback Select Subtitle",
  "role": "product-behavior",
  "lanes": [
    "device",
    "simulator"
  ],
  "argumentSchema": {
    "fields": [
      {
        "name": "host",
        "type": "string",
        "required": true
      },
      {
        "name": "sourceKind",
        "type": "string",
        "required": true
      },
      {
        "name": "trackLabel",
        "type": "string",
        "required": false
      },
      {
        "name": "deadlineSeconds",
        "type": "integer",
        "required": true
      }
    ],
    "additionalProperties": false
  },
  "invalidatesTags": [
    "playback.selection",
    "ui.state"
  ],
  "evidenceSchemas": [
    {
      "evidenceType": "window.control-plane",
      "evidenceSchema": "window-control-plane@1"
    }
  ],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:62e8b68e2824de74f8b2e2bf5c30dcffb0d4faf88ffe8cba81d325e202e6ed7c"
  }
}
---
# Playback Select Subtitle

The runtime Operation adapter selects one external subtitle through the public playback surface, More, Subtitles, and dynamic menu-item Accessibility identifiers in one controller transaction, then verifies the same playback identity and selected track in product state.
