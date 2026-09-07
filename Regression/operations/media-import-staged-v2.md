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
    "digest": "sha256:ed10e583b4e69fa6fdad2cf7047126cf19166f9c7971ae55eb03cc7ac975ea6e"
  }
}
---
# Media Import Staged

The operation stages and imports one direct TestMediaInbox file. It requires that importMedia requires a direct TestMediaInbox file name, that TestMediaInbox does contain the file and it is not a directory, and that the production media import pipeline did add the file as exactly one new library reference. It validates that the file name is one direct child, checks inbox existence, invokes the production addFiles pipeline, and reports TestMediaInbox does not contain the file or The production media import pipeline did not add the file when those preconditions fail.
