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
    "digest": "sha256:2456975e7b80869247c08ee37872968ffb324753f564485eb1a1ce523e1bc083"
  }
}
---
# Navigation Select Tab

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
