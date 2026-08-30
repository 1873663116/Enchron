---
{
  "schema": "enchron.regression.operation",
  "schemaVersion": 1,
  "id": "operation:storage.clear@1",
  "title": "Storage Clear",
  "role": "product-behavior",
  "lanes": [
    "device",
    "simulator"
  ],
  "argumentSchema": {
    "fields": [
      {
        "name": "target",
        "type": "string",
        "required": true
      }
    ],
    "additionalProperties": false
  },
  "invalidatesTags": [
    "cache.state",
    "library.contents",
    "settings.state",
    "ui.state",
    "viewing.progress",
    "viewing.state"
  ],
  "evidenceSchemas": [],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:46beec247e912597e51e4f21f22b426c17c2d8a1ab7fbd84018fd4f3b24b83fd"
  }
}
---
# Storage Clear

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
