---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:issue-surface-behavior.typed-single-slot-contract.o01@1",
  "title": "Typed single-slot issues",
  "criteria": [
    "The bound artifact's own inspect hierarchy is the post-state its obligation names, on one attempt with no relaunch between them and no dismissal of the first alert. For obligation o01:first-post-state the producer is call 03, taken while source-file-missing held the slot: matchedElement is PlayerUI-loadFailure-primary labelled Retry at mainWindow, the hierarchy carries title Playback Error and PlayerUI-loadFailure-secondary labelled Close, and PlayerUI-playbackIssue-confirm is absent. For obligation o01:replacement-post-state the producer is call 06, taken after server-certificate-changed replaced that slot: matchedElement is PlayerUI-loadFailure-secondary labelled Close, the hierarchy carries title Server Certificate Changed, and PlayerUI-loadFailure-primary and the Playback Error title are gone; its relatedResults hold that same attempt's call 03 response and matched Retry, so the replacement is decided against the hierarchy it replaced, and call 05's observations record PlayerUI-playbackIssue-confirm unmatched in between.",
    "Exactly one typed issue surface is open in the bound hierarchy: one alert title drawn from the registered category vocabulary and matching the category that produced it, no second issue surface stacked beside it, no generic playbackFailed category, and no PlayerUI-playbackIssue-confirm. The other category's surface -- its title and, where the categories differ in actions, its actions -- is absent from that same hierarchy, so the slot replaced rather than accumulated."
  ],
  "negativeControls": [
    "Dismissing the first alert, using two attempts, observing both surfaces simultaneously, accepting a stale first hierarchy as the replacement state, a producer whose own hierarchy is not the post-state its obligation names, two obligations resolved from one reading, or falling back to a generic category violates the single-slot contract."
  ]
}
---
# Typed single-slot issues

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
