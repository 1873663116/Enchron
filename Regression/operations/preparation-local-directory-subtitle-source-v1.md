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
    "digest": "sha256:ed10e583b4e69fa6fdad2cf7047126cf19166f9c7971ae55eb03cc7ac975ea6e"
  }
}
---
# Prepare Local Directory Subtitle Source

The operation imports one registered media directory, preserves its bookmark root and nonempty media relative path, and returns the typed directory import receipt required by its Preparation. It requires that importMediaDirectory requires directory, media, and a files JSON array; The media directory name must be one direct TestMediaInbox child; The media file name must be one direct TestMediaInbox child; The directory member is not one direct TestMediaInbox file; The media directory contains a duplicate member name; The media directory members must include the requested media file; The media directory name conflicts with one of its member files; TestMediaInbox is unavailable; TestMediaInbox does not contain the regular staged file; The requested TestMediaInbox directory name is occupied by a file; The imported media reference does not identify the requested directory media; The production directory import pipeline did not add exactly one requested media reference; and it validates uniqueness, direct-child, member contains media, disjoint directory, atomic staging, and bookmark root verification. It materializes the staging directory atomically, moves it into place, and validates the receipt's bookmark root is a directory and its members exist.
