---
{
  "schema": "enchron.regression.operation",
  "schemaVersion": 1,
  "id": "operation:presentation.enter-docked-skybox@1",
  "title": "Presentation Enter Docked Skybox",
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
  "evidenceSchemas": [],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:2aca7cf32430446cf0e8e30832a2fbe3fc9653e8f05004679721c834e0b99e58"
  }
}
---
# Presentation Enter Docked Skybox

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
