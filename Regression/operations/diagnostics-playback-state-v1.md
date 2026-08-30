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
      },
      {
        "name": "relatedResults",
        "type": "string-list",
        "required": false
      }
    ],
    "rules": [
      {
        "kind": "when-equals",
        "discriminator": "expectation",
        "cases": [
          {
            "value": "webdav-loopback",
            "required": [
              "minimumPositionMillis"
            ],
            "forbidden": [
              "expectedSession",
              "expectedSourceIdentity",
              "expectedContentRevision",
              "expectedTopologyDigest",
              "minimumReconnects"
            ]
          },
          {
            "value": "recoverable-read",
            "required": [
              "expectedSession",
              "expectedSourceIdentity",
              "expectedContentRevision",
              "expectedTopologyDigest",
              "minimumPositionMillis",
              "minimumReconnects"
            ],
            "forbidden": []
          },
          {
            "value": "finite-reconnect",
            "required": [
              "expectedSession",
              "expectedSourceIdentity",
              "expectedContentRevision",
              "expectedTopologyDigest",
              "minimumPositionMillis",
              "minimumReconnects"
            ],
            "forbidden": []
          }
        ]
      }
    ],
    "additionalProperties": false
  },
  "invalidatesTags": [],
  "evidenceSchemas": [
    {
      "evidenceType": "playback.probe",
      "evidenceSchema": "playback-probe@1"
    }
  ],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:00d8e78cf5a88b70b8bf9d6bff760cfc5bae3f9d312e88b31c4feb3389928d56"
  }
}
---
# Diagnostics Playback State

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
