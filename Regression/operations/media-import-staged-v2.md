---
{
  "schema": "enchron.regression.operation",
  "schemaVersion": 1,
  "id": "operation:media.import-staged@2",
  "title": "Media Import Staged",
  "role": "setup",
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
    "rules": [],
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
    "digest": "sha256:1d898ed90d6199a310eb518f6000131cb818e57a00be69e15059d5451b9c0b7e"
  }
}
---
# Media Import Staged

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
