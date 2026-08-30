---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:webdav-source-lifecycle.webdav-open-through-loopback.o01@1",
  "title": "Webdav Open Through Loopback",
  "criteria": [
    "The bound capture-frames observation has terminal fields lifecycle=Playing, playbackAddressKind=loopback, and collectionOrigin=sourceDirectory, and remoteObservation.expectation is webdav-playback-range.",
    "At least three valid time-separated PNG frames contain real non-solid content, and time-separated pairs have FFmpeg SSIM no greater than 0.995, the VISUAL_FROZEN_SSIM threshold in Scripts/verification/playback_mode_matrix.py:1329.",
    "remoteObservation.rangeRequests is nonempty and expectationObservation.successfulRangeResponseCount is at least 1, so the host trace records Range traffic rather than a naked URL crossing the playback boundary."
  ],
  "negativeControls": [
    "If any required modality is invalid or missing, the result is Indeterminate rather than inferred from the remaining modality.",
    "Contradictory valid artifacts produce Indeterminate; no majority vote or best-effort selection is permitted.",
    "A 1x1, corrupt, single-frame, or provenance-free capture is Indeterminate and never Satisfied.",
    "playbackAddressKind other than loopback, an empty rangeRequests list, a frame with FFmpeg signalstats YAVG below 18.0 and YMAX below 40.0 (VISUAL_BLACK_YAVG and VISUAL_BLACK_YMAX in Scripts/verification/playback_mode_matrix.py:1327-1328), or time-separated pairs with FFmpeg SSIM greater than 0.995 (VISUAL_FROZEN_SSIM at playback_mode_matrix.py:1329) violates the rubric."
  ]
}
---
# Webdav Open Through Loopback

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
