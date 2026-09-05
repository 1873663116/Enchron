---
{
  "schema": "enchron.regression.operation",
  "schemaVersion": 1,
  "id": "operation:playback.wait-position@2",
  "title": "Playback Wait Position",
  "role": "product-behavior",
  "lanes": [
    "device",
    "simulator"
  ],
  "argumentSchema": {
    "fields": [
      {
        "name": "minimumPositionMillis",
        "type": "integer",
        "required": true
      },
      {
        "name": "minimumRemainingMillis",
        "type": "integer",
        "required": true
      },
      {
        "name": "expectedMediaName",
        "type": "string",
        "required": false
      },
      {
        "name": "differentSessionFrom",
        "type": "string",
        "required": false
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
  "evidenceSchemas": [],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:3c1fe7eecc5a1d752b086e109d55959e59ee7db0be3b2564d535351fb8101919"
  }
}
---
# Playback Wait Position

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
