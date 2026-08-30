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
    "digest": "sha256:be8f6611010ac088ec845d293391ef8c8461bafd044d341caca45c9799e6a728"
  }
}
---
# Playback Select Subtitle

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
