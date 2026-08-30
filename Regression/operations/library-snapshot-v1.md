---
{
  "schema": "enchron.regression.operation",
  "schemaVersion": 1,
  "id": "operation:library.snapshot@1",
  "title": "Library Snapshot",
  "role": "evidence",
  "lanes": [
    "device",
    "simulator"
  ],
  "argumentSchema": {
    "fields": [
      {
        "name": "baselineReferenceIDs",
        "type": "string-list",
        "required": false
      },
      {
        "name": "baselineFolderIDs",
        "type": "string-list",
        "required": false
      },
      {
        "name": "baselineSourceIdentities",
        "type": "string-list",
        "required": false
      },
      {
        "name": "baselineSourcePaths",
        "type": "string-list",
        "required": false
      },
      {
        "name": "baselineSourceDigests",
        "type": "string-list",
        "required": false
      },
      {
        "name": "baselineFileNames",
        "type": "string-list",
        "required": false
      },
      {
        "name": "systemImportExpectation",
        "type": "string",
        "required": false
      }
    ],
    "additionalProperties": false
  },
  "invalidatesTags": [],
  "evidenceSchemas": [
    {
      "evidenceType": "library.command",
      "evidenceSchema": "library-command@1"
    }
  ],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:13c255d379a9552cf4249b3ac27a69c016115c2cacd6f5ef3783480ca7bc9335"
  }
}
---
# Library Snapshot

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
