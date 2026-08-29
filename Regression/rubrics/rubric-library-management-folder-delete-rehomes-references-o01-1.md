---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:library-management.folder-delete-rehomes-references.o01@1",
  "title": "Folder deletion rehomes references",
  "criteria": [
    "After deleting Regression Parent, both Regression Parent and its Regression Child subtree are absent and the imported reference ID remains exactly once at Media Library root, the deleted root folder parent.",
    "The comparison preserves the exact source identity, source path, and source digest, while the staged fixture remains present with the same byte digest."
  ],
  "negativeControls": [
    "Deleting contained media references or source files violates HC-015."
  ]
}
---
# Folder deletion rehomes references

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
