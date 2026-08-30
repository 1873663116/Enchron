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
    "digest": "sha256:bc027ea194114a53d77ceefcab18f000ec037dda33bd5c633ef5eb8360036399"
  }
}
---
# Transition Trace Arm

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
