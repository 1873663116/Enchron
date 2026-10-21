---
{
  "schema": "enchron.regression.operation",
  "schemaVersion": 1,
  "id": "operation:navigation.select-tab@1",
  "title": "Navigation Select Tab",
  "role": "product-behavior",
  "lanes": [
    "device",
    "simulator"
  ],
  "argumentSchema": {
    "fields": [
      {
        "name": "tab",
        "type": "string",
        "required": true
      }
    ],
    "rules": [],
    "additionalProperties": false
  },
  "invalidatesTags": [
    "ui.navigation",
    "ui.state"
  ],
  "evidenceSchemas": [],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:8a50235b0a1ce01dba1b535b457d1779500032d094cf113fdadd3cb77cc8b17e"
  }
}
---
# Navigation Select Tab

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
