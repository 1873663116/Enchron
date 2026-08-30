---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:issue-surface-behavior.typed-single-slot-contract.o01@1",
  "title": "Typed single-slot issues",
  "criteria": [
    "The bound inspect relatedResults include the first hierarchy captured after source-file-missing: title Playback Error, PlayerUI-loadFailure-primary (Retry) and PlayerUI-loadFailure-secondary (Close) at mainWindow, and PlayerUI-playbackIssue-confirm absent.",
    "The bound inspect hierarchy is the replacement after server-certificate-changed on the same attempt without dismissing the first alert or relaunching: title Server Certificate Changed, PlayerUI-loadFailure-secondary (Close) present, and PlayerUI-loadFailure-primary plus the prior Playback Error title absent."
  ],
  "negativeControls": [
    "Dismissing the first alert, using two attempts, observing both surfaces simultaneously, accepting a stale first hierarchy as the replacement state, or falling back to a generic category violates the single-slot contract."
  ]
}
---
# Typed single-slot issues

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
