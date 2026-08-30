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
    "digest": "sha256:c60cdd654e41002b2cf848afac7c4dc9c7743660f4596c97f195a4d9ba63bc26"
  }
}
---
# Media Import Staged

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
