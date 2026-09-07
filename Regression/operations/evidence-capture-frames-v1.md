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
    "digest": "sha256:ed10e583b4e69fa6fdad2cf7047126cf19166f9c7971ae55eb03cc7ac975ea6e"
  }
}
---
# Evidence Capture Frames

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
