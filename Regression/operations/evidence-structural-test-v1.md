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
    "digest": "sha256:1e1838a745dc041bfedc0757cff320e764ad2c3fbce111231533df13267b8a78"
  }
}
---
# Evidence Structural Test

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
