---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:network-resilience.buffered-reconnect-has-no-indicator.o01@1",
  "title": "Buffered Reconnect Has No Indicator",
  "criteria": [
    "Every frame in the bound three-frame window capture of the registered WebDAV card has playbackState.available true, playbackState.fields.lifecycle=Playing, strictly increasing playbackState.fields.position, playbackState.fields.error=none, controlPlane.available true, and controlPlane.fields.loadingSpinner=off after the bound case's exact host receipt is restored.",
    "operationOutput.remoteObservation matches the registered case: paired-control={expectation: webdav-playback-range, recipe: healthy, restoredGeneration equals the producer remoteGenerationToken}; buffer-absorbed-interruption={expectation: buffer-absorbed-interruption, recipe: buffer-absorbed-interruption, remoteReceiptID restored, expectationObservation.triggeredRequests nonempty with injected Range status 503, expectationObservation.recoveredRequests nonempty with subsequent Range status 206 for those same ranges, and every frame playbackState.fields.demuxForwardBytes a positive integer}."
  ],
  "negativeControls": [
    "A remoteObservation.expectation, recipe, or restored generation/receipt that differs from the bound case's registered row, fewer than three frames, unavailable playbackState or controlPlane, loadingSpinner=on, error other than none, or a non-increasing position violates the bound case.",
    "Empty triggeredRequests, empty recoveredRequests, missing Range 503 then 206 pairing, or a non-positive demuxForwardBytes on a buffer-absorbed-interruption bound capture violates the absorbed-reconnect contract.",
    "If any required modality of the bound capture is invalid or missing, the result is Indeterminate rather than inferred from the remaining modality."
  ]
}
---
# Buffered Reconnect Has No Indicator

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
