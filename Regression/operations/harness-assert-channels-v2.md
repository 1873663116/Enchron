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
    "additionalProperties": false
  },
  "invalidatesTags": [],
  "evidenceSchemas": [],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:65e1419b109ee9171294e01fb5f49ae6acfbbca612dc63764bd1bbc686df0622"
  }
}
---
# Harness Assert Channels

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
