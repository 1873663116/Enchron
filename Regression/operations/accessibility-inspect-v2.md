---
{
  "schema": "enchron.regression.operation",
  "schemaVersion": 1,
  "id": "operation:accessibility.inspect@2",
  "title": "Accessibility Inspect",
  "role": "evidence",
  "lanes": [
    "device",
    "simulator"
  ],
  "argumentSchema": {
    "fields": [
      {
        "name": "context",
        "type": "string",
        "required": true
      },
      {
        "name": "identifier",
        "type": "string",
        "required": true
      },
      {
        "name": "index",
        "type": "integer",
        "required": false
      },
      {
        "name": "requireMatchedElement",
        "type": "boolean",
        "required": false
      }
    ],
    "additionalProperties": false
  },
  "invalidatesTags": [],
  "evidenceSchemas": [
    {
      "evidenceType": "accessibility.tree",
      "evidenceSchema": "accessibility-tree@1"
    }
  ],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:73eaf072dcc85c8e674eba9bb6fe90af23f4f5038497d50144bef3002d3b46d7"
  }
}
---
# Accessibility Inspect

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
