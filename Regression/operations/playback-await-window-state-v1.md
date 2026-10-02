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
    "digest": "sha256:9cdf39efe61cfee50aa993ffc885140091b0f5447fcfb47732e146c957af129f"
  }
}
---
# Playback Await Window State

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
