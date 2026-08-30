---
{
  "schema": "enchron.regression.operation",
  "schemaVersion": 1,
  "id": "operation:presentation.exit-spatial@1",
  "title": "Presentation Exit Spatial",
  "role": "product-behavior",
  "lanes": [
    "device",
    "simulator"
  ],
  "argumentSchema": {
    "fields": [
      {
        "name": "from",
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
    "presentation.mode",
    "presentation.state",
    "renderer.graph",
    "ui.state"
  ],
  "evidenceSchemas": [
    {
      "evidenceType": "window.control-plane",
      "evidenceSchema": "window-control-plane@1"
    }
  ],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:c3cdd54218485b9d0e37162bbbc5976fc1f7c0a1bec2cdd908e729cddd832c86"
  }
}
---
# Presentation Exit Spatial

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
