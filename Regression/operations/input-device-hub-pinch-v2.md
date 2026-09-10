---
{
  "schema": "enchron.regression.operation",
  "schemaVersion": 1,
  "id": "operation:input.device-hub-pinch@2",
  "title": "Input Device Hub Pinch",
  "role": "product-behavior",
  "lanes": [
    "simulator"
  ],
  "argumentSchema": {
    "fields": [
      {
        "name": "targetDomain",
        "type": "string",
        "required": true
      },
      {
        "name": "systemControl",
        "type": "string",
        "required": false
      },
      {
        "name": "shotX",
        "type": "integer",
        "required": false
      },
      {
        "name": "shotY",
        "type": "integer",
        "required": false
      },
      {
        "name": "shotWidth",
        "type": "integer",
        "required": false
      },
      {
        "name": "shotHeight",
        "type": "integer",
        "required": false
      },
      {
        "name": "allowSmall",
        "type": "boolean",
        "required": false
      }
    ],
    "rules": [
      {
        "kind": "when-equals",
        "discriminator": "targetDomain",
        "cases": [
          {
            "value": "canvas",
            "required": [
              "shotX",
              "shotY",
              "shotWidth",
              "shotHeight"
            ],
            "forbidden": [
              "systemControl"
            ]
          },
          {
            "value": "system-toolbar",
            "required": [
              "systemControl"
            ],
            "forbidden": [
              "shotX",
              "shotY",
              "shotWidth",
              "shotHeight",
              "allowSmall"
            ]
          }
        ]
      }
    ],
    "additionalProperties": false
  },
  "invalidatesTags": [
    "presentation.state",
    "ui.state"
  ],
  "evidenceSchemas": [],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:37ba14f884fd28af7a36604ee01f71bd8505bafd0ae498ea5ed5648b3c314691"
  }
}
---
# Input Device Hub Pinch

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
