---
{
  "schema": "enchron.regression.operation",
  "schemaVersion": 1,
  "id": "operation:evidence.capture-audio@2",
  "title": "Evidence Capture Audio",
  "role": "evidence",
  "lanes": [
    "device"
  ],
  "argumentSchema": {
    "fields": [
      {
        "name": "durationMillis",
        "type": "integer",
        "required": true
      },
      {
        "name": "inputDevice",
        "type": "string",
        "required": true
      },
      {
        "name": "wavPath",
        "type": "string",
        "required": true
      },
      {
        "name": "expectedSession",
        "type": "string",
        "required": false
      },
      {
        "name": "expectedAudioTrackID",
        "type": "string",
        "required": false
      }
    ],
    "additionalProperties": false
  },
  "invalidatesTags": [],
  "evidenceSchemas": [
    {
      "evidenceType": "audio.measurement",
      "evidenceSchema": "audio-measurement@2"
    }
  ],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:73eaf072dcc85c8e674eba9bb6fe90af23f4f5038497d50144bef3002d3b46d7"
  }
}
---
# Evidence Capture Audio

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
