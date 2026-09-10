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
    "digest": "sha256:37ba14f884fd28af7a36604ee01f71bd8505bafd0ae498ea5ed5648b3c314691"
  }
}
---
# Harness Assert Channels

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
