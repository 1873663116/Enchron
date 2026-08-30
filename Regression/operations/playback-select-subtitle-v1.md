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
  "evidenceSchemas": [],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:0ae2b78c4e24ddd6cd6c5d419c08e006eaf90c24381486b735244b8806d12beb"
  }
}
---
# Playback Select Subtitle

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
