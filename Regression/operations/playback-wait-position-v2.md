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
    "additionalProperties": false
  },
  "invalidatesTags": [],
  "evidenceSchemas": [],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:0c453b44779d223dd50352df488c324651a3cad019b894c0b4226ad34f3440a3"
  }
}
---
# Playback Wait Position

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
