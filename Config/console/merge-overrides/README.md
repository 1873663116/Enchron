# Merge overrides

A merge override lets one red merge gate pass for a failure a human approved. It lives on main as a JSON file in this directory.

Adding an override needs human approval (需请示人类). An agent that meets a red gate stops and asks; it does not write the record itself.

The record:

```json
{
  "schema": "enchron.console.merge-override",
  "schemaVersion": 1,
  "signature": "unit:PlaybackTests/testSeek",
  "reason": "the operator accepted this failing test for this release",
  "approvedBy": "the human who approved it",
  "approvedAt": "2026-10-23",
  "expires": "2026-11-06"
}
```

`signature` is the canonical failure signature the gate prints on a red line. `approvedBy` and `approvedAt` record who approved it and when; a record missing either is inert. `expires` bounds the approval in time; an expired record is inert. The merge gate reads this directory from main, so a record added on a branch protects nothing until it lands on main.
