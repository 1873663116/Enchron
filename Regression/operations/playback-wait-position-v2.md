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
    "digest": "sha256:22d56aa15e83f3d15b0b21f5fdc17691ec14fd913bf60001d341479ef22e32c8"
  }
}
---
# Playback Wait Position

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
