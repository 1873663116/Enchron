---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:viewing-state-and-storage.local-playback-does-not-write-index.o01@1",
  "title": "Local Playback Does Not Write Index",
  "criteria": [
    "relatedResults inline library.snapshot call 06's snapshot: it contains exactly one readable file-backed reference with sourceDigest sha256:e290e5c8a9b10a06795b081b476ff84f55374a8266929a21dde6b895034bd133. The same registered file is used for the remote open of FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv from Enchron Regression WebDAV.",
    "relatedResults inline the baseline-empty, local-active-empty, and local-after-empty containerIndexObservation records from calls 02, 10, and 12 in that order. All three have zero entries and bytes and the same containerIndexDigest, while the active local observation reports playbackAddressKind local-file and the post-exit observation returns to no active source.",
    "The producer containerIndexObservation is the remote-positive-control: playbackAddressKind loopback, positive entryCount, totalBytes, byteStreamScope, and byteStreamRequestCount, a canonical sourceIdentity and contentRevision, an entry key for that contentRevision, and a container digest different from the inlined local baseline.",
    "relatedResults also inline the three earlier viewingStorageObservation objects. The producer viewingStorageObservation.snapshot.containerIndex has the same cacheIdentity as the inlined baseline, positive bytes, and at least one canonical entry for the observed contentRevision whose digest is canonical, invalidFileCount is zero, and ordered ranges are nonempty with positive bounds-consistent bytes."
  ],
  "negativeControls": [
    "Different local and remote files, a missing exact source digest on the inlined library snapshot, or absence of the structured remote positive control makes the comparison Indeterminate rather than satisfying it by local emptiness alone.",
    "Any local index entry or byte, a changed local empty digest, a non-loopback remote address, an empty remote cache, a noncanonical revision, missing range or byte evidence, or an invalid cache file violates the contract.",
    "priorSnapshotDigests or expected*Digest hashes without the inlined containerIndexObservation objects and library snapshot cannot establish emptiness, address kind, or sourceDigest."
  ]
}
---
# Local Playback Does Not Write Index

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
