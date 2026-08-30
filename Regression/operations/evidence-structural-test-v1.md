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
    "digest": "sha256:0c453b44779d223dd50352df488c324651a3cad019b894c0b4226ad34f3440a3"
  }
}
---
# Evidence Structural Test

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
