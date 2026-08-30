---
{
  "schema": "enchron.regression.operation",
  "schemaVersion": 1,
  "id": "operation:format.apply@2",
  "title": "Format Apply",
  "role": "product-behavior",
  "lanes": [
    "device",
    "simulator"
  ],
  "argumentSchema": {
    "fields": [
      {
        "name": "projection",
        "type": "string",
        "required": true
      },
      {
        "name": "horizontalCoverageDegrees",
        "type": "integer",
        "required": false
      },
      {
        "name": "stereoLayout",
        "type": "string",
        "required": true
      },
      {
        "name": "deadlineSeconds",
        "type": "integer",
        "required": true
      }
    ],
    "rules": [
      {
        "kind": "when-equals",
        "discriminator": "projection",
        "cases": [
          {
            "value": "customAngle",
            "required": [
              "horizontalCoverageDegrees"
            ],
            "forbidden": []
          },
          {
            "value": "flat",
            "required": [],
            "forbidden": [
              "horizontalCoverageDegrees"
            ]
          },
          {
            "value": "equirectangular180",
            "required": [],
            "forbidden": [
              "horizontalCoverageDegrees"
            ]
          },
          {
            "value": "equirectangular360",
            "required": [],
            "forbidden": [
              "horizontalCoverageDegrees"
            ]
          }
        ]
      }
    ],
    "additionalProperties": false
  },
  "invalidatesTags": [
    "media.format",
    "playback.session",
    "presentation.mode",
    "presentation.state",
    "renderer.graph",
    "ui.state"
  ],
  "evidenceSchemas": [
    {
      "evidenceType": "visual.frames",
      "evidenceSchema": "frame-sequence@2"
    },
    {
      "evidenceType": "window.control-plane",
      "evidenceSchema": "window-control-plane@1"
    }
  ],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:2aca7cf32430446cf0e8e30832a2fbe3fc9653e8f05004679721c834e0b99e58"
  }
}
---
# Format Apply

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
