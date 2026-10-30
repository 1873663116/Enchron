---
{
  "schema": "enchron.regression.operation",
  "schemaVersion": 1,
  "id": "operation:accessibility.type@2",
  "title": "Accessibility Type",
  "role": "product-behavior",
  "lanes": [
    "device",
    "simulator"
  ],
  "argumentSchema": {
    "fields": [
      {
        "name": "context",
        "type": "string",
        "required": true
      },
      {
        "name": "identifier",
        "type": "string",
        "required": false
      },
      {
        "name": "label",
        "type": "string",
        "required": false
      },
      {
        "name": "index",
        "type": "integer",
        "required": false
      },
      {
        "name": "mode",
        "type": "string",
        "required": true
      },
      {
        "name": "text",
        "type": "string",
        "required": false
      },
      {
        "name": "textFile",
        "type": "string",
        "required": false
      },
      {
        "name": "textJSONKey",
        "type": "string",
        "required": false
      },
      {
        "name": "secret",
        "type": "boolean",
        "required": true
      }
    ],
    "rules": [
      {
        "kind": "exactly-one-group",
        "groups": [
          [
            "identifier"
          ],
          [
            "label"
          ]
        ]
      },
      {
        "kind": "exactly-one-group",
        "groups": [
          [
            "text"
          ],
          [
            "textFile",
            "textJSONKey"
          ]
        ]
      }
    ],
    "additionalProperties": false
  },
  "invalidatesTags": [
    "settings.state",
    "source.connection",
    "ui.state"
  ],
  "evidenceSchemas": [],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:62531e988a9e70e62e672faaf49818793b6fff7936a62ac2a4fbdaf657e4a527"
  }
}
---
# Accessibility Type

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
