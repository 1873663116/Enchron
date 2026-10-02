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
    "digest": "sha256:9cdf39efe61cfee50aa993ffc885140091b0f5447fcfb47732e146c957af129f"
  }
}
---
# Harness Assert Channels

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
