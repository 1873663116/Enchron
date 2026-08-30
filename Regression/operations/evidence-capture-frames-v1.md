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
    "digest": "sha256:0ae2b78c4e24ddd6cd6c5d419c08e006eaf90c24381486b735244b8806d12beb"
  }
}
---
# Evidence Capture Frames

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
