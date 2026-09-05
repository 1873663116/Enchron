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
    "digest": "sha256:3c1fe7eecc5a1d752b086e109d55959e59ee7db0be3b2564d535351fb8101919"
  }
}
---
# Media Stage Fixture

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
