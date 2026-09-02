---
{
  "schema": "enchron.regression.operation",
  "schemaVersion": 1,
  "id": "operation:host.preflight@1",
  "title": "Host Preflight",
  "role": "setup",
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
      },
      {
        "name": "phase",
        "type": "string",
        "required": false
      },
      {
        "name": "recipe",
        "type": "string",
        "required": false
      },
      {
        "name": "receiptID",
        "type": "string",
        "required": false
      }
    ],
    "rules": [],
    "additionalProperties": false
  },
  "invalidatesTags": [
    "certificate.trust",
    "fixture.corpus",
    "source.connection",
    "source.session"
  ],
  "evidenceSchemas": [],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:d71725e8567bc710b16a8c0ac9304c09571bc4df01df1a1799500c4d49dd04a5"
  }
}
---
# Host Preflight

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
