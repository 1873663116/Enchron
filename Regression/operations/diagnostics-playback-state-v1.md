---
{
  "schema": "enchron.regression.operation",
  "schemaVersion": 1,
  "id": "operation:diagnostics.playback-state@1",
  "title": "Diagnostics Playback State",
  "role": "evidence",
  "lanes": [
    "device",
    "simulator"
  ],
  "argumentSchema": {
    "fields": [
      {
        "name": "expectation",
        "type": "string",
        "required": false
      },
      {
        "name": "expectedSession",
        "type": "string",
        "required": false
      },
      {
        "name": "expectedSourceIdentity",
        "type": "string",
        "required": false
      },
      {
        "name": "expectedContentRevision",
        "type": "string",
        "required": false
      },
      {
        "name": "expectedTopologyDigest",
        "type": "string",
        "required": false
      },
      {
        "name": "minimumPositionMillis",
        "type": "integer",
        "required": false
      },
      {
        "name": "minimumReconnects",
        "type": "integer",
        "required": false
      }
    ],
    "additionalProperties": false
  },
  "invalidatesTags": [],
  "evidenceSchemas": [
    {
      "evidenceType": "playback.probe",
      "evidenceSchema": "playback-probe@1"
    },
    {
      "evidenceType": "window.control-plane",
      "evidenceSchema": "window-control-plane@1"
    }
  ],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:466edc12da9c3126cc7ba845bb2ad3dda158905c5a143133d8e647efc71593b7"
  }
}
---
# Diagnostics Playback State

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
