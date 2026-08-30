---
{
  "schema": "enchron.regression.operation",
  "schemaVersion": 1,
  "id": "operation:preparation.local-directory-subtitle-source@1",
  "title": "Prepare Local Directory Subtitle Source",
  "role": "setup",
  "lanes": [
    "device",
    "simulator"
  ],
  "argumentSchema": {
    "fields": [
      {
        "name": "directoryName",
        "type": "string",
        "required": true
      },
      {
        "name": "mediaFileName",
        "type": "string",
        "required": true
      },
      {
        "name": "memberFileNames",
        "type": "string-list",
        "required": true
      }
    ],
    "rules": [],
    "additionalProperties": false
  },
  "invalidatesTags": [
    "library.contents",
    "ui.state"
  ],
  "evidenceSchemas": [
    {
      "evidenceType": "library.command",
      "evidenceSchema": "library-command@1"
    }
  ],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:3b3773d1e84f8ddecd3a3a7839b29f3a4f4f4f949d65840d0efcf25c793ac62d"
  }
}
---
# Prepare Local Directory Subtitle Source

The runtime Operation adapter imports one registered media directory, preserves its bookmark root and nonempty media relative path, and returns the typed directory import receipt required by its Preparation.
