---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:viewing-state-and-storage.storage-rows-report-and-clear.o01@1",
  "title": "Storage Rows Report And Clear",
  "criteria": [
    "relatedResults inline the empty-baseline viewingStorageObservation from call 03 and the seeded snapshot from call 17. After those empty artwork and container-index baselines, real local playback and Back produce positive artwork entryCount and totalBytes, and real Enchron Regression WebDAV playback and Back produce positive containerIndex entryCount and totalBytes in the seeded snapshot.",
    "relatedResults inline the first Settings-StoragePrivacy-group inspect matchedElement and response from call 20. The matched group hierarchy exposes separate Artwork Cache and Container Index Cache value rows with non-zero usage plus Settings-action-clear-artwork-cache and Settings-action-clear-container-index-cache controls.",
    "relatedResults inline the between viewingStorageObservation from call 22 and the second group inspect matchedElement and response from call 23. After clearing only artwork-cache, call 22 reaches zero artwork entries and bytes with the same artwork storeIdentity, while containerIndex, viewingState, and protectedState are byte-for-byte unchanged from the inlined seeded snapshot. Call 23 reports zero Artwork Cache usage and unchanged non-zero Container Index Cache usage.",
    "relatedResults inline the after viewingStorageObservation from call 25 and the third group inspect matchedElement and response from call 26. After clearing only container-index-cache, call 25 keeps artwork empty, reaches zero container-index entries and bytes with the same cacheIdentity, and preserves viewingState and protectedState from the seeded snapshot. Call 26 reports both usage rows at zero and retains both separate clear controls.",
    "The producer snapshot plus the inlined seeded, between, and after observations have stable viewing, artwork, and container store identities and zero invalid counts. The ordered transcript does not invoke playback-progress clear."
  ],
  "negativeControls": [
    "Synthetic cache seeding, a Playback Progress clear, a clear receipt without the three inlined Settings hierarchies and four bound structured snapshots, or a missing required field is inadmissible.",
    "Clearing both caches at once, changing the adjacent cache during the first clear, changing viewing or protected state during either clear, losing a clear control, or reporting a non-zero value after the corresponding empty snapshot violates the isolation contract.",
    "The transient Cleared feedback is neither required nor used for judgment; its absence cannot make an otherwise complete result fail or pause the Agent.",
    "priorSnapshotDigests hashes without the inlined Settings inspect responses and viewingStorageObservation objects cannot establish usage-row text or isolated cache emptiness."
  ]
}
---
# Storage Rows Report And Clear

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
