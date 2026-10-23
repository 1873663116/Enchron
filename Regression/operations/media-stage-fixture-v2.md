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
    "digest": "sha256:6d1b99aaf4052d852ba6aabdff288903c7fa95bc26e562dbf8ae055335387f50"
  }
}
---
# Media Stage Fixture

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
