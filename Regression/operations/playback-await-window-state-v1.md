---
{
  "schema": "enchron.regression.operation",
  "schemaVersion": 1,
  "id": "operation:playback.await-window-state@1",
  "title": "Playback Await Window State",
  "role": "product-behavior",
  "lanes": [
    "device",
    "simulator"
  ],
  "argumentSchema": {
    "fields": [
      {
        "name": "presentation",
        "type": "string",
        "required": true
      },
      {
        "name": "lifecycle",
        "type": "string",
        "required": true
      },
      {
        "name": "controls",
        "type": "string",
        "required": true
      },
      {
        "name": "deadlineSeconds",
        "type": "integer",
        "required": true
      }
    ],
    "additionalProperties": false
  },
  "invalidatesTags": [],
  "evidenceSchemas": [
    {
      "evidenceType": "window.control-plane",
      "evidenceSchema": "window-control-plane@1"
    }
  ],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:c60cdd654e41002b2cf848afac7c4dc9c7743660f4596c97f195a4d9ba63bc26"
  }
}
---
# Playback Await Window State

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
