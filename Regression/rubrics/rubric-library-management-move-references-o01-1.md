---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:library-management.move-references.o01@1",
  "title": "Move references",
  "criteria": [
    "The selected reference ID appears exactly once in Regression Destination after the Move To action.",
    "Its source identity, source path, and source digest equal the import baseline; no second reference or source copy is created."
  ],
  "negativeControls": [
    "Copying, duplicating, or modifying a source file violates the move contract."
  ]
}
---
# Move references

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
