---
{
  "schema": "enchron.regression.operation",
  "schemaVersion": 1,
  "id": "operation:issue.present@1",
  "title": "Issue Present",
  "role": "diagnostic-bypass",
  "lanes": [
    "device",
    "simulator"
  ],
  "argumentSchema": {
    "fields": [
      {
        "name": "category",
        "type": "string",
        "required": true
      }
    ],
    "additionalProperties": false
  },
  "invalidatesTags": [
    "issue.surface",
    "ui.state"
  ],
  "evidenceSchemas": [],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:79f83f952a05dbb3f6c32c6f94fc0fe702193f3e36a51a034fba0f8b18d3a95e"
  }
}
---
# Issue Present

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
