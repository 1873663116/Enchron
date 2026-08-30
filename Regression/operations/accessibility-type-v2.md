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
    "digest": "sha256:13c255d379a9552cf4249b3ac27a69c016115c2cacd6f5ef3783480ca7bc9335"
  }
}
---
# Accessibility Type

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
