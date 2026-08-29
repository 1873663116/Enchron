---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:viewing-state-and-storage.storage-rows-report-and-clear.o01@1",
  "title": "Storage Rows Report And Clear",
  "criteria": [
    "After explicit empty artwork and container-index baselines, real local playback and Back produce positive artwork entryCount and totalBytes, and real Enchron Regression WebDAV playback and Back produce positive containerIndex entryCount and totalBytes in the seeded snapshot.",
    "The first Settings-StoragePrivacy-group inspection matches the group and exposes separate Artwork Cache and Container Index Cache value rows with non-zero usage plus Settings-action-clear-artwork-cache and Settings-action-clear-container-index-cache controls.",
    "After clearing only artwork-cache, the between snapshot reaches zero artwork entries and bytes with the same artwork storeIdentity, while containerIndex, viewingState, and protectedState are byte-for-byte unchanged from the seeded snapshot; the second group inspection reports zero Artwork Cache usage and unchanged non-zero Container Index Cache usage.",
    "After clearing only container-index-cache, the after and final snapshots keep artwork empty, reach zero container-index entries and bytes with the same cacheIdentity, and preserve viewingState and protectedState from the seeded snapshot; the third group inspection reports both usage rows at zero and retains both separate clear controls.",
    "The seeded, between, after, and final observations have stable viewing, artwork, and container store identities and zero invalid counts, and each observation plus the final producer binds all chronologically prior viewing-storage digests without using playback-progress clear."
  ],
  "negativeControls": [
    "Synthetic cache seeding, a Playback Progress clear, a clear receipt without the three matched Settings hierarchies and four bound structured snapshots, or a missing required field is inadmissible.",
    "Clearing both caches at once, changing the adjacent cache during the first clear, changing viewing or protected state during either clear, losing a clear control, or reporting a non-zero value after the corresponding empty snapshot violates the isolation contract.",
    "The transient Cleared feedback is neither required nor used for judgment; its absence cannot make an otherwise complete result fail or pause the Agent."
  ]
}
---
# Storage Rows Report And Clear

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
