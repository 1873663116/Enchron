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
    "rules": [],
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
  "evidenceSchemas": [
    {
      "evidenceType": "visual.frames",
      "evidenceSchema": "frame-sequence@2"
    },
    {
      "evidenceType": "window.control-plane",
      "evidenceSchema": "window-control-plane@1"
    }
  ],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:3b3773d1e84f8ddecd3a3a7839b29f3a4f4f4f949d65840d0efcf25c793ac62d"
  }
}
---
# Format Apply

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
