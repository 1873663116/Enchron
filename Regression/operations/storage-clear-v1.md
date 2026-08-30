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
    "digest": "sha256:73eaf072dcc85c8e674eba9bb6fe90af23f4f5038497d50144bef3002d3b46d7"
  }
}
---
# Storage Clear

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
