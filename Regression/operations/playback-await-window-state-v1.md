---
{
  "schema": "enchron.regression.operation",
  "schemaVersion": 1,
  "id": "operation:playback.await-window-state@1",
  "title": "Playback Await Window State",
  "role": "evidence",
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
    "rules": [],
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
    "digest": "sha256:cdf09b29d702c42555a10665dddb2389ab0d290fbb3e4599e7a1bcb276352599"
  }
}
---
# Playback Await Window State

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
