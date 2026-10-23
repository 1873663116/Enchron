---
{
  "schema": "enchron.regression.operation",
  "schemaVersion": 1,
  "id": "operation:evidence.structural-test@1",
  "title": "Evidence Structural Test",
  "role": "evidence",
  "lanes": [
    "device",
    "simulator"
  ],
  "argumentSchema": {
    "fields": [
      {
        "name": "check",
        "type": "string",
        "required": true
      }
    ],
    "rules": [],
    "additionalProperties": false
  },
  "invalidatesTags": [],
  "evidenceSchemas": [
    {
      "evidenceType": "structural.test",
      "evidenceSchema": "structural-test@2"
    }
  ],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:2202f9fcb28c1f28cebdc70eec2435c09a2f49f882a581861f2b42590330f2c5"
  }
}
---
# Evidence Structural Test

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
