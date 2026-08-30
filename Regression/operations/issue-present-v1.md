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
    "digest": "sha256:466edc12da9c3126cc7ba845bb2ad3dda158905c5a143133d8e647efc71593b7"
  }
}
---
# Issue Present

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
