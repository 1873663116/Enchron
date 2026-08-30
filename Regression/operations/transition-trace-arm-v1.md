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
    "digest": "sha256:46beec247e912597e51e4f21f22b426c17c2d8a1ab7fbd84018fd4f3b24b83fd"
  }
}
---
# Transition Trace Arm

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
