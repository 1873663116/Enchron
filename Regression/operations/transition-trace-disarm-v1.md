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
    "digest": "sha256:37ba14f884fd28af7a36604ee01f71bd8505bafd0ae498ea5ed5648b3c314691"
  }
}
---
# Transition Trace Disarm

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
