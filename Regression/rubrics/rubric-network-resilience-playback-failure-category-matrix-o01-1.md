---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:network-resilience.playback-failure-category-matrix.o01@1",
  "title": "Playback Failure Category Matrix",
  "criteria": [
    "Against the registered WebDAV media identity, the bound playback-state snapshot exposes the category registered for its case: recoverable-read-interruption→connection-interrupted, missing-object→source-file-missing, access-denied→source-access-denied, and corrupt-media→media-data-corrupt.",
    "The bound case's issue snapshot preserves the active session identity and causal position, exposes exactly Retry and Close in the main window, and contains its matching host activation receipt and triggered request evidence.",
    "After the bound case's exact receipt is restored, Retry returns the same media attempt to Playing and advances beyond the causal position within 5000 ms; the healthy control receipt is restored before the case completes."
  ],
  "negativeControls": [
    "A fabricated basename, generic playbackFailed category, mismatched recipe/category, missing host trigger, changed media session on Retry, or failure to restore either receipt is inadmissible.",
    "Missing Retry or Close, loss of causal position, or resume later than the explicit 5000 ms HC-021 bound fails the rubric."
  ]
}
---
# Playback Failure Category Matrix

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
