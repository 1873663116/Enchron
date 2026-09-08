---
{
  "schema": "enchron.regression.operation",
  "schemaVersion": 1,
  "id": "operation:transition-trace.disarm@1",
  "title": "Transition Trace Disarm",
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
    "rules": [],
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
    "digest": "sha256:8fe746de8de0d96e7ab0c9fbd04c7ed2e429cb80095c529115b87c0b832eea7c"
  }
}
---
# Transition Trace Disarm

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
