---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:library-management.confirmed-batch-deletion.o01@1",
  "title": "Confirmed batch deletion",
  "criteria": [
    "The pre-confirmation library snapshot still contains both selected reference IDs and the unselected reference ID; only after the destructive confirmation are the two selected IDs absent from the final snapshot.",
    "The unselected reference remains exactly once, and all three staged source files remain present under their exact names and byte digests."
  ],
  "negativeControls": [
    "Deletion before confirmation or source-file deletion violates the contract."
  ]
}
---
# Confirmed batch deletion

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
