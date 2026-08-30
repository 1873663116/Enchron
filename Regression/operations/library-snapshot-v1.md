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
        "name": "priorSnapshot",
        "type": "string",
        "required": false
      },
      {
        "name": "systemImportExpectation",
        "type": "string",
        "required": false
      }
    ],
    "rules": [
      {
        "kind": "all-or-none",
        "fields": [
          "baselineReferenceIDs",
          "baselineFolderIDs",
          "baselineSourceIdentities",
          "baselineSourcePaths",
          "baselineSourceDigests",
          "baselineFileNames"
        ]
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
    "digest": "sha256:00d8e78cf5a88b70b8bf9d6bff760cfc5bae3f9d312e88b31c4feb3389928d56"
  }
}
---
# Library Snapshot

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
