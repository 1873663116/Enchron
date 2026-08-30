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
    "digest": "sha256:9e4e0948320959d33bbac7b080512683344fed1031fb75a17fa384b1f937b5e0"
  }
}
---
# Evidence Capture Audio

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
