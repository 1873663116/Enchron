---
{
  "schema": "enchron.regression.operation",
  "schemaVersion": 1,
  "id": "operation:media.stage-fixture@2",
  "title": "Media Stage Fixture",
  "role": "setup",
  "lanes": [
    "device",
    "simulator"
  ],
  "argumentSchema": {
    "fields": [
      {
        "name": "fixtureID",
        "type": "string",
        "required": true
      },
      {
        "name": "sourceRoot",
        "type": "string",
        "required": true
      }
    ],
    "rules": [],
    "additionalProperties": false
  },
  "invalidatesTags": [
    "fixture.corpus"
  ],
  "evidenceSchemas": [],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:2aca7cf32430446cf0e8e30832a2fbe3fc9653e8f05004679721c834e0b99e58"
  }
}
---
# Media Stage Fixture

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
