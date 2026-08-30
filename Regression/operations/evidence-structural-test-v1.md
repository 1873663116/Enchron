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
    "digest": "sha256:22d56aa15e83f3d15b0b21f5fdc17691ec14fd913bf60001d341479ef22e32c8"
  }
}
---
# Evidence Structural Test

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
