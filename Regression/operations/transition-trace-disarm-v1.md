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
    "digest": "sha256:fce56ed57e5f8746c6c1f82cb3a1d9059d17503968af9e21472c0d05c2758627"
  }
}
---
# Transition Trace Disarm

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
