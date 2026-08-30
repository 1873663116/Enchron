---
{
  "schema": "enchron.regression.operation",
  "schemaVersion": 1,
  "id": "operation:transition-trace.arm@1",
  "title": "Transition Trace Arm",
  "role": "setup",
  "lanes": [
    "device",
    "simulator"
  ],
  "argumentSchema": {
    "fields": [
      {
        "name": "fault",
        "type": "string",
        "required": false
      }
    ],
    "additionalProperties": false
  },
  "invalidatesTags": [],
  "evidenceSchemas": [],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:1e1838a745dc041bfedc0757cff320e764ad2c3fbce111231533df13267b8a78"
  }
}
---
# Transition Trace Arm

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
