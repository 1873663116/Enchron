---
{
  "schema": "enchron.regression.operation",
  "schemaVersion": 1,
  "id": "operation:format.apply@2",
  "title": "Format Apply",
  "role": "product-behavior",
  "lanes": [
    "device",
    "simulator"
  ],
  "argumentSchema": {
    "fields": [
      {
        "name": "projection",
        "type": "string",
        "required": true
      },
      {
        "name": "horizontalCoverageDegrees",
        "type": "integer",
        "required": false
      },
      {
        "name": "stereoLayout",
        "type": "string",
        "required": true
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
    "media.format",
    "playback.session",
    "presentation.mode",
    "presentation.state",
    "renderer.graph",
    "ui.state"
  ],
  "evidenceSchemas": [],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:78779485939b33b8395464f6e417d5f426b5638ee7ae8d760db5ee479c2eef23"
  }
}
---
# Format Apply

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
