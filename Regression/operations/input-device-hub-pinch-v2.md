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
        "required": false
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
    "additionalProperties": false
  },
  "invalidatesTags": [
    "presentation.state",
    "ui.state"
  ],
  "evidenceSchemas": [],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:13c255d379a9552cf4249b3ac27a69c016115c2cacd6f5ef3783480ca7bc9335"
  }
}
---
# Input Device Hub Pinch

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
