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
    "digest": "sha256:62e8b68e2824de74f8b2e2bf5c30dcffb0d4faf88ffe8cba81d325e202e6ed7c"
  }
}
---
# Input Device Hub Pinch

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
