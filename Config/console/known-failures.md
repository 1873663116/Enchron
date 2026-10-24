---
{
  "schema": "enchron.console.known-failures",
  "schemaVersion": 1,
  "failures": []
}
---

Known failures let a defect that predates the console stay declared until it is fixed. A run that matches reports the verdict `known` and does not turn the tier red. Remove an entry when its defect is gone.

Each entry names one failure and a phrase the failure detail must contain:

- `checker` and `match` declare a static-tier checker by its identifier. `match` is a phrase in the checker's log or detail.
- `test` and `match` declare a Swift unit test. `test` is the test identifier xcodebuild prints; `match` is optional.
- `unit` and `match` declare an end-to-end unit by its identifier and a phrase in the failing step's detail.

`reason` says why the defect is accepted. `expires` is an ISO date; an entry past it no longer makes a failure known. The merge gate reads declarations from main only, so a declaration added on a branch protects nothing until it lands on main.
