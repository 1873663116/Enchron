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
    "rules": [],
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
    "digest": "sha256:ed10e583b4e69fa6fdad2cf7047126cf19166f9c7971ae55eb03cc7ac975ea6e"
  }
}
---
# Evidence Capture Audio

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
