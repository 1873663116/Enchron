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
    "digest": "sha256:22d56aa15e83f3d15b0b21f5fdc17691ec14fd913bf60001d341479ef22e32c8"
  }
}
---
# Host Preflight

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
