---
{
  "schema": "enchron.regression.operation",
  "schemaVersion": 1,
  "id": "operation:transition-trace.disarm@1",
  "title": "Transition Trace Disarm",
  "role": "setup",
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
  "evidenceSchemas": [],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:c60cdd654e41002b2cf848afac7c4dc9c7743660f4596c97f195a4d9ba63bc26"
  }
}
---
# Transition Trace Disarm

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
