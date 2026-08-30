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
    "digest": "sha256:73eaf072dcc85c8e674eba9bb6fe90af23f4f5038497d50144bef3002d3b46d7"
  }
}
---
# Host Preflight

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
