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
    "additionalProperties": false
  },
  "invalidatesTags": [
    "ui.navigation",
    "ui.state"
  ],
  "evidenceSchemas": [],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:bc027ea194114a53d77ceefcab18f000ec037dda33bd5c633ef5eb8360036399"
  }
}
---
# Navigation Select Tab

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
