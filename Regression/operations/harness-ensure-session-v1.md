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
    "digest": "sha256:cdf09b29d702c42555a10665dddb2389ab0d290fbb3e4599e7a1bcb276352599"
  }
}
---
# Harness Ensure Session

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
