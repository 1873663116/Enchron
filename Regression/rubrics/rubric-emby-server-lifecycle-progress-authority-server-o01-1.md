---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:emby-server-lifecycle.progress-authority-server.o01@1",
  "title": "Progress Authority Server",
  "criteria": [
    "The server reports an active session and advancing position for the opened item, then records the exit position within the five-second observed-position bound decided by HC-021.",
    "After exit, operation:diagnostics.surface-probe@1 runs with includeViewingStorage=true and its viewingStorageObservation inlines the same attempt's pre-playback probe as priorSnapshots[0]. That prior viewingState's viewingRecordCount equals snapshot.viewingState.viewingRecordCount and the two entries lists are element-for-element identical, so the opened and exited Emby session added, removed, or changed no local viewing record. Entries publish only a sha256 mediaIdentity, so the decision is this list comparison, never a decoding of that hash."
  ],
  "negativeControls": [
    "An action return value without the post-action application state cannot satisfy the rubric.",
    "Missing playbackSessions[].serverID, userID, or itemID produces Indeterminate rather than Satisfied; a serverID or userID that does not match account, or an itemID that does not match the prepared Emby fixture item, is mixed-provenance evidence and violates the rubric.",
    "Product-only progress without server state, or server progress for another user or item, violates the rubric. So does a local fallback record: any viewingState entry added, removed, or changed between the pre-playback snapshot and the post-exit snapshot, or a missing priorSnapshots binding that leaves the comparison unmade."
  ]
}
---
# Progress Authority Server

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
