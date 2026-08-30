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
    "digest": "sha256:c3cdd54218485b9d0e37162bbbc5976fc1f7c0a1bec2cdd908e729cddd832c86"
  }
}
---
# Evidence Capture Audio

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
