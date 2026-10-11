---
{
  "schema": "enchron.regression.operation",
  "schemaVersion": 1,
  "id": "operation:presentation.enter-docked-default@1",
  "title": "Presentation Enter Docked Default",
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
  "evidenceSchemas": [],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:08e508d2adbffcec266820ab7e91cfba4640b2275ed609e930ee4b4e5055c40d"
  }
}
---
# Presentation Enter Docked Default

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
