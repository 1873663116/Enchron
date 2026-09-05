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
    "digest": "sha256:3c1fe7eecc5a1d752b086e109d55959e59ee7db0be3b2564d535351fb8101919"
  }
}
---
# Host Preflight

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
