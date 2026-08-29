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
    "digest": "sha256:7e53f393ef9bd5d549b126c3223be5b993d9ca78ae86d57916da332f126032dc"
  }
}
---
# Playback Select Subtitle

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
