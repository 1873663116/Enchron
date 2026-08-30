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
    "digest": "sha256:73eaf072dcc85c8e674eba9bb6fe90af23f4f5038497d50144bef3002d3b46d7"
  }
}
---
# Issue Present

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
