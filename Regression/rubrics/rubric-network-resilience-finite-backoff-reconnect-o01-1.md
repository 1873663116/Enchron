---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:network-resilience.finite-backoff-reconnect.o01@1",
  "title": "Finite Backoff Reconnect",
  "criteria": [
    "The reconnect run is finite and ordered, decided inside the one bound artifact. relatedResults[0] is call 09's playback-state fields and relatedResults[1] its expectationObservation, and both report demuxReconnects equal to 3, the whole of PB_DEMUX_RECONNECT_ATTEMPT_LIMIT (Packages/PlaybackCore/Sources/PlaybackFFmpegBridge/PlaybackFFmpegBridge.c:107-110), so the engine stopped retrying at the declared limit. remoteObservation.expectationObservation.reconnectAttempts holds exactly three entries with ordinal 1, 2 and 3, whose declaredBackoffMillis read 250, 500 and 1000 in that order and whose recovered is true, and observedDelayMillis -- the host's monotonic gap from the read it refused to the client's next request, so it contains that attempt's wait -- is at least its own declaredBackoffMillis and strictly greater than the preceding attempt's. No upper tolerance is applied and none may be invented: HC-021 still lists version-reconnect-sampling as required work, so only the exact limit, the declared table and these lower-bound and ordering comparisons decide the claim.",
    "Source-side connection closure is attributable to the injected upstream fault or exhausted recovery, never an unsolicited playback-engine disconnect."
  ],
  "negativeControls": [
    "Controller success without the application-side delivery event is not evidence of product behavior.",
    "Missing sequence numbers, mismatched revisions, reversed order, or a truncated timing window cannot satisfy the rubric.",
    "Unlimited retries, missing a declared backoff, a byte-stream retry layer, or engine-originated disconnect violates the rubric."
  ]
}
---
# Finite Backoff Reconnect

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
