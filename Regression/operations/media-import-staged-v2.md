---
{
  "schema": "enchron.regression.operation",
  "schemaVersion": 1,
  "id": "operation:media.import-staged@2",
  "title": "Media Import Staged",
  "role": "product-behavior",
  "lanes": [
    "device",
    "simulator"
  ],
  "argumentSchema": {
    "fields": [
      {
        "name": "fileName",
        "type": "string",
        "required": true
      }
    ],
    "additionalProperties": false
  },
  "invalidatesTags": [
    "library.contents"
  ],
  "evidenceSchemas": [
    {
      "evidenceType": "library.command",
      "evidenceSchema": "library-command@1"
    }
  ],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:466edc12da9c3126cc7ba845bb2ad3dda158905c5a143133d8e647efc71593b7"
  }
}
---
# Media Import Staged

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
