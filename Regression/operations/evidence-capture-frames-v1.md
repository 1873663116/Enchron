---
{
  "schema": "enchron.regression.operation",
  "schemaVersion": 1,
  "id": "operation:evidence.capture-frames@1",
  "title": "Evidence Capture Frames",
  "role": "evidence",
  "lanes": [
    "device",
    "simulator"
  ],
  "argumentSchema": {
    "fields": [
      {
        "name": "count",
        "type": "integer",
        "required": true
      },
      {
        "name": "minimumIntervalMillis",
        "type": "integer",
        "required": true
      },
      {
        "name": "context",
        "type": "string",
        "required": true
      },
      {
        "name": "remoteExpectation",
        "type": "string",
        "required": false
      },
      {
        "name": "remoteGenerationToken",
        "type": "string",
        "required": false
      },
      {
        "name": "productBindingDigest",
        "type": "string",
        "required": false
      },
      {
        "name": "artworkExpectation",
        "type": "string",
        "required": false
      },
      {
        "name": "includeHDRFallback",
        "type": "boolean",
        "required": false
      }
    ],
    "additionalProperties": false
  },
  "invalidatesTags": [],
  "evidenceSchemas": [
    {
      "evidenceType": "visual.frames",
      "evidenceSchema": "frame-sequence@2"
    },
    {
      "evidenceType": "window.control-plane",
      "evidenceSchema": "window-control-plane@1"
    }
  ],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:46beec247e912597e51e4f21f22b426c17c2d8a1ab7fbd84018fd4f3b24b83fd"
  }
}
---
# Evidence Capture Frames

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
