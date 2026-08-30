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
    "digest": "sha256:0ae2b78c4e24ddd6cd6c5d419c08e006eaf90c24381486b735244b8806d12beb"
  }
}
---
# Media Import Staged

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
