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
    "digest": "sha256:1e1838a745dc041bfedc0757cff320e764ad2c3fbce111231533df13267b8a78"
  }
}
---
# Harness Ensure Session

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
