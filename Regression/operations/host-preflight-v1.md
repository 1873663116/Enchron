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
    "digest": "sha256:37ba14f884fd28af7a36604ee01f71bd8505bafd0ae498ea5ed5648b3c314691"
  }
}
---
# Host Preflight

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
