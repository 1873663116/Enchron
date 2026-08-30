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
    "additionalProperties": false
  },
  "invalidatesTags": [
    "fixture.corpus"
  ],
  "evidenceSchemas": [],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:0c453b44779d223dd50352df488c324651a3cad019b894c0b4226ad34f3440a3"
  }
}
---
# Media Stage Fixture

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
