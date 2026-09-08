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
    "digest": "sha256:8fe746de8de0d96e7ab0c9fbd04c7ed2e429cb80095c529115b87c0b832eea7c"
  }
}
---
# Presentation Enter Panorama

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
