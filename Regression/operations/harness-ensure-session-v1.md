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
    "rules": [],
    "additionalProperties": false
  },
  "invalidatesTags": [
    "lane.instance"
  ],
  "evidenceSchemas": [],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:fce56ed57e5f8746c6c1f82cb3a1d9059d17503968af9e21472c0d05c2758627"
  }
}
---
# Harness Ensure Session

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
