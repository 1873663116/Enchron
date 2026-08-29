---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:issue-surface-behavior.typed-single-slot-contract.o01@1",
  "title": "Typed single-slot issues",
  "criteria": [
    "After mediaOpeningFailed is presented, the first bound hierarchy exposes title Failed to Load, Retry and Close at mainWindow, and no confirm-only action; this policy interrupts playback.",
    "Without closing the first issue or relaunching, presenting playbackControlFailed replaces the same slot: the second bound hierarchy exposes title Playback Error and only PlayerUI-playbackIssue-confirm; the prior title, PlayerUI-loadFailure-primary, and PlayerUI-loadFailure-secondary are absent, and this policy does not interrupt playback."
  ],
  "negativeControls": [
    "Dismissing the first alert, using two attempts, observing both surfaces simultaneously, accepting a stale first hierarchy as the replacement state, or falling back to a generic category violates the single-slot contract."
  ]
}
---
# Typed single-slot issues

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
