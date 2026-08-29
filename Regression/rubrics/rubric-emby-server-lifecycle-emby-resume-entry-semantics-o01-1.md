---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:emby-server-lifecycle.emby-resume-entry-semantics.o01@1",
  "title": "Emby Resume Entry Semantics",
  "criteria": [
    "For a server item with reviewed progress, Resume starts within tolerance of that server position.",
    "Play from Beginning starts within zero tolerance without deleting or overwriting the server's saved progress solely because it was chosen."
  ],
  "negativeControls": [
    "An action return value without the post-action application state cannot satisfy the rubric.",
    "A missing required field, changed session identity where preservation is required, or stale snapshot produces a non-passing result.",
    "Reading local state, reversing the two actions, or erasing server progress on start violates the rubric."
  ]
}
---
# Emby Resume Entry Semantics

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
