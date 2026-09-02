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
    "digest": "sha256:7a9623efa963e819ae7843e17425c7d16ab3368af04ecc302334b1d160f95240"
  }
}
---
# Presentation Enter Panorama

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
