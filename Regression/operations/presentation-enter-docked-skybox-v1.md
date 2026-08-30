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
    "digest": "sha256:1e1838a745dc041bfedc0757cff320e764ad2c3fbce111231533df13267b8a78"
  }
}
---
# Presentation Enter Docked Skybox

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
