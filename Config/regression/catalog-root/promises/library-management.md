---
{
  "schema": "enchron.regression.promises",
  "schemaVersion": 1,
  "feature": "library-management",
  "title": "Library management",
  "promises": [
    {
      "id": "promise:library-management:c01",
      "title": "Folder naming",
      "statement": "Library folders use the reviewed naming and uniqueness rules.",
      "automation": {
        "scope": "included"
      }
    },
    {
      "id": "promise:library-management:c02",
      "title": "Folder deletion rehomes references",
      "statement": "Deleting a folder removes its hierarchy, rehomes contained media references to its parent, and leaves source files untouched.",
      "automation": {
        "scope": "included"
      }
    },
    {
      "id": "promise:library-management:c03",
      "title": "Move references",
      "statement": "Media references can move between library folders without modifying source files.",
      "automation": {
        "scope": "included"
      }
    },
    {
      "id": "promise:library-management:c04",
      "title": "Confirmed batch deletion",
      "statement": "Batch deletion requires confirmation and removes only the selected library references.",
      "automation": {
        "scope": "included"
      }
    },
    {
      "id": "promise:library-management:c05",
      "title": "Current-folder search and counts",
      "statement": "Search results and counts are scoped to the current library folder.",
      "automation": {
        "scope": "included"
      }
    }
  ]
}
---
# Library management

These commitments are included in unattended Regression Catalog v2 coverage.
