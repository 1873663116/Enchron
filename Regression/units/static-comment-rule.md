---
{
  "schema": "enchron.console.unit",
  "schemaVersion": 1,
  "id": "unit:static.comment-rule@1",
  "layer": 2,
  "role": "verification",
  "requires": [],
  "actions": [
    {"verb": "static.check", "args": {"checker": "verify_product_source_comments.py"}}
  ],
  "terminal": {"kind": "artifact", "path": "static-check.json"}
}
---

Runs the source comment rule as a single console unit.
