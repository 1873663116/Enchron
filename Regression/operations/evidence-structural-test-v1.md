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
    "digest": "sha256:9cdf39efe61cfee50aa993ffc885140091b0f5447fcfb47732e146c957af129f"
  }
}
---
# Evidence Structural Test

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
