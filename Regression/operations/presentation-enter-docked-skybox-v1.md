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
    "digest": "sha256:78779485939b33b8395464f6e417d5f426b5638ee7ae8d760db5ee479c2eef23"
  }
}
---
# Presentation Enter Docked Skybox

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
