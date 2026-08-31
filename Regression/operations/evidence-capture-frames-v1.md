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
        "name": "relatedResults",
        "type": "string-list",
        "required": false
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
        "name": "remoteReceiptID",
        "type": "string",
        "required": false
      },
      {
        "name": "restoredGenerationToken",
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
        "name": "artworkKey",
        "type": "string",
        "required": false
      },
      {
        "name": "includeHDRFallback",
        "type": "boolean",
        "required": false
      },
      {
        "name": "relatedFrameManifests",
        "type": "string-list",
        "required": false
      }
    ],
    "rules": [],
    "additionalProperties": false
  },
  "invalidatesTags": [],
  "evidenceSchemas": [
    {
      "evidenceType": "visual.frames",
      "evidenceSchema": "frame-sequence@2"
    }
  ],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:cdf09b29d702c42555a10665dddb2389ab0d290fbb3e4599e7a1bcb276352599"
  }
}
---
# Evidence Capture Frames

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
