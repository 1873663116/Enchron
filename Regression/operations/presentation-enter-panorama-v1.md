---
{
  "schema": "enchron.regression.operation",
  "schemaVersion": 1,
  "id": "operation:presentation.enter-panorama@1",
  "title": "Presentation Enter Panorama",
  "role": "product-behavior",
  "lanes": [
    "device",
    "simulator"
  ],
  "argumentSchema": {
    "fields": [
      {
        "name": "deadlineSeconds",
        "type": "integer",
        "required": true
      },
      {
        "name": "expectedResult",
        "type": "string",
        "required": false
      },
      {
        "name": "summonControls",
        "type": "boolean",
        "required": false
      }
    ],
    "rules": [],
    "additionalProperties": false
  },
  "invalidatesTags": [
    "presentation.mode",
    "presentation.state",
    "renderer.graph",
    "ui.state"
  ],
  "evidenceSchemas": [
    {
      "evidenceType": "transition.trace",
      "evidenceSchema": "transition-trace@1"
    }
  ],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:d71725e8567bc710b16a8c0ac9304c09571bc4df01df1a1799500c4d49dd04a5"
  }
}
---
# Presentation Enter Panorama

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
