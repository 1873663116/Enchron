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
    "digest": "sha256:62e8b68e2824de74f8b2e2bf5c30dcffb0d4faf88ffe8cba81d325e202e6ed7c"
  }
}
---
# Harness Assert Channels

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
