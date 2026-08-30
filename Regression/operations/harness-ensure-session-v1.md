---
{
  "schema": "enchron.regression.operation",
  "schemaVersion": 1,
  "id": "operation:harness.ensure-session@1",
  "title": "Harness Ensure Session",
  "role": "setup",
  "lanes": [
    "device",
    "simulator"
  ],
  "argumentSchema": {
    "fields": [
      {
        "name": "controlsAutoHideSeconds",
        "type": "integer",
        "required": false
      }
    ],
    "additionalProperties": false
  },
  "invalidatesTags": [
    "lane.instance"
  ],
  "evidenceSchemas": [],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:466edc12da9c3126cc7ba845bb2ad3dda158905c5a143133d8e647efc71593b7"
  }
}
---
# Harness Ensure Session

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
