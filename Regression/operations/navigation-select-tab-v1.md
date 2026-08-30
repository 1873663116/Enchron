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
    "digest": "sha256:79f83f952a05dbb3f6c32c6f94fc0fe702193f3e36a51a034fba0f8b18d3a95e"
  }
}
---
# Navigation Select Tab

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
