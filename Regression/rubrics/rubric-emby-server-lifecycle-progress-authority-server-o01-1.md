---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:emby-server-lifecycle.progress-authority-server.o01@1",
  "title": "Progress Authority Server",
  "criteria": [
    "The server reports an active session and advancing position for the opened item, then records the exit position within the five-second observed-position bound decided by HC-021.",
    "After exit, operation:diagnostics.surface-probe@1 runs with includeViewingStorage=true and viewingStorageObservation.snapshot.viewingState.entries contains no record for the Emby media identity derived from the bound playback session's serverID, itemID, and mediaSourceID."
  ],
  "negativeControls": [
    "An action return value without the post-action application state cannot satisfy the rubric.",
    "Missing playbackSessions[].serverID, userID, or itemID produces Indeterminate rather than Satisfied; a serverID or userID that does not match account, or an itemID that does not match the prepared Emby fixture item, is mixed-provenance evidence and violates the rubric.",
    "Product-only progress without server state, server progress for another user or item, or a local fallback record violates the rubric."
  ]
}
---
# Progress Authority Server

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
