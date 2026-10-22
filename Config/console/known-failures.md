---
{
  "schema": "enchron.console.known-failures",
  "schemaVersion": 1,
  "failures": []
}
---

Known failures let a defect that predates the console stay declared until it is fixed. Each entry names a unit and a phrase the failing step's detail must contain; a run that matches reports the verdict `known` and does not turn the tier red. Remove an entry when its defect is gone.
