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
    "digest": "sha256:1e1838a745dc041bfedc0757cff320e764ad2c3fbce111231533df13267b8a78"
  }
}
---
# Transition Trace Fetch

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
