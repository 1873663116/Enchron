---
{
  "schema": "enchron.regression.operation",
  "schemaVersion": 1,
  "id": "operation:transition-trace.fetch@1",
  "title": "Transition Trace Fetch",
  "role": "evidence",
  "lanes": [
    "device",
    "simulator"
  ],
  "argumentSchema": {
    "fields": [
      {
        "name": "generationToken",
        "type": "string",
        "required": true
      }
    ],
    "additionalProperties": false
  },
  "invalidatesTags": [],
  "evidenceSchemas": [
    {
      "evidenceType": "transition.trace",
      "evidenceSchema": "transition-trace@1"
    }
  ],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:0ae2b78c4e24ddd6cd6c5d419c08e006eaf90c24381486b735244b8806d12beb"
  }
}
---
# Transition Trace Fetch

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
