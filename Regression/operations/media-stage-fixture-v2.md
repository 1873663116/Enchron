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
    "digest": "sha256:9ad0337ad1486b36ef0a1bc8b0aff866c9a81df1a2a013f2b5edbe3a34d264aa"
  }
}
---
# Media Stage Fixture

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
