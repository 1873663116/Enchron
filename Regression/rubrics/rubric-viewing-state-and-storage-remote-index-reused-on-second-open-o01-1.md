---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:viewing-state-and-storage.remote-index-reused-on-second-open.o01@1",
  "title": "Remote Index Reused On Second Open",
  "criteria": [
    "The ordered transcript clears container-index-cache only before either open, selects Enchron Regression WebDAV, and opens the same FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv card twice without a cache clear, source mutation, different media open, or Preparation boundary between the two attempts.",
    "The baseline call:viewing-state-and-storage:remote-index-reused-on-second-open:02 has an empty containerIndex and null values for all six containerIndexOpen result fields. After the first open reaches playing and position 3 seconds, call:viewing-state-and-storage:remote-index-reused-on-second-open:09 has a non-null media-byte-stream scope, canonical content revision, containerIndexFinished true, no cache-hit ranges, and nonempty source-read and recorded ranges with positive bounds-consistent bytes; every recorded range is present in the first source-read ranges.",
    "After Back, call:viewing-state-and-storage:remote-index-reused-on-second-open:11 has null containerIndexOpen fields but retains a positive persisted containerIndex entry for the first-open content revision, proving that the handle was released without clearing the cache.",
    "The second-open producer call:viewing-state-and-storage:remote-index-reused-on-second-open:17 has containerIndexFinished true, a media-byte-stream scope different from call 09, and exactly the same canonical content revision. The union of its cacheHitRanges fully covers every half-open interval in call 09 recordedRanges, and no byte in a cache-hit interval appears in its sourceReadRanges; source reads wholly outside the cache-hit intervals remain admissible ordinary playback reads.",
    "Calls 02, 09, 11, and 17 retain one cacheIdentity, call 17 binds the preceding three viewingStorageDigest results in chronological order, and both active snapshots identify the same content revision with viewingStateAuthority enchron-persistence."
  ],
  "negativeControls": [
    "Controller success, a nonempty persisted cache, or two opens of the same label without both complete call 09 and call 17 containerIndexOpen snapshots is inadmissible; a missing scope, revision, finished flag, or range list is Indeterminate.",
    "An unfinished first or second index, an empty first source-read or recorded set, any first-open cache hit after the explicit empty baseline, a reused scope, or a changed content revision violates the first-write and second-open identity contract.",
    "A first recorded interval not fully covered by second-open cache hits, or any overlap between a second-open cache-hit interval and second-open source reads, proves that the recorded index bytes were read from the source again and violates reuse.",
    "Clearing the cache, changing the source, crossing an attempt or lane, or replacing the registered WebDAV fixture between the probes invalidates the comparison."
  ]
}
---
# Remote Index Reused On Second Open

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
