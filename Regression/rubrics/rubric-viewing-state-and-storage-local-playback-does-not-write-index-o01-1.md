---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:viewing-state-and-storage.local-playback-does-not-write-index.o01@1",
  "title": "Local Playback Does Not Write Index",
  "criteria": [
    "The same registered file, sdr-bframe-aggregate-30s.mkv, is used for both controls: the local library snapshot contains exactly one readable file-backed reference with sourceDigest sha256:e290e5c8a9b10a06795b081b476ff84f55374a8266929a21dde6b895034bd133, and the remote open uses FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv from Enchron Regression WebDAV.",
    "The baseline-empty, local-active-empty, and local-after-empty containerIndexObservation records are present in order; all three have zero entries and bytes and the same containerIndexDigest, while the active local observation reports playbackAddressKind local-file and the post-exit observation returns to no active source.",
    "The final remote-positive-control observation reports playbackAddressKind loopback, positive entryCount, totalBytes, byteStreamScope, and byteStreamRequestCount, a canonical sourceIdentity and contentRevision, an entry key for that contentRevision, and a container digest different from the local baseline.",
    "The final viewingStorageObservation binds all three earlier viewing-storage snapshot digests; its containerIndex has the same cacheIdentity as baseline, positive bytes, and at least one canonical entry for the observed contentRevision whose digest is canonical, invalidFileCount is zero, and ordered ranges are nonempty with positive bounds-consistent bytes."
  ],
  "negativeControls": [
    "Different local and remote files, a missing exact source digest, or absence of the structured remote positive control makes the comparison Indeterminate rather than satisfying it by local emptiness alone.",
    "Any local index entry or byte, a changed local empty digest, a non-loopback remote address, an empty remote cache, a noncanonical revision, missing range or byte evidence, or an invalid cache file violates the contract."
  ]
}
---
# Local Playback Does Not Write Index

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
