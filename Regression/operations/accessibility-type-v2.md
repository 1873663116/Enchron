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
        "required": true
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
    "digest": "sha256:0c453b44779d223dd50352df488c324651a3cad019b894c0b4226ad34f3440a3"
  }
}
---
# Accessibility Type

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
