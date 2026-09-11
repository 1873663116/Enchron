---
{
  "schema": "enchron.regression.operation",
  "schemaVersion": 1,
  "id": "operation:harness.assert-channels@2",
  "title": "Harness Assert Channels",
  "role": "setup",
  "lanes": [
    "device",
    "simulator"
  ],
  "argumentSchema": {
    "fields": [],
    "rules": [],
    "additionalProperties": false
  },
  "invalidatesTags": [],
  "evidenceSchemas": [],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:5b6b092840aef8fddbc62e40f3d22652ce7eae27239629567d7f9da66e198fec"
  }
}
---
# Harness Assert Channels

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
