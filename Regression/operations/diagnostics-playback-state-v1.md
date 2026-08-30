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
    "digest": "sha256:c60cdd654e41002b2cf848afac7c4dc9c7743660f4596c97f195a4d9ba63bc26"
  }
}
---
# Diagnostics Playback State

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
