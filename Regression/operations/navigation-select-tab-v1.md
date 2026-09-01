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
    "digest": "sha256:ad0562e4a35b7077290d5fd11c50817cda086fa9f1438cf2d9ca80ca005050a7"
  }
}
---
# Navigation Select Tab

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
